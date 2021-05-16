// The S-DSP is nominally intended to output samples at 32KhZ, and originally
// had 96 clock cycles per sample (~3MhZ). In this system, we'll be shooting for
// 32 cycles per sample (So a 1.024 MhZ input clock, receiving L/R samples once every
// 32 cycles).



module DSP (
  inout [15:0] ram_address,
  inout [7:0] ram_data,
  output ram_write_enable,

  input  [7:0] dsp_reg_address,
  input  [7:0] dsp_reg_data_in,
  output [7:0] dsp_reg_data_out,
  input        dsp_reg_write_enable,

  input clock,
  input reset,
  output reg audio_valid,
  output signed [15:0] dac_out_l,
  output signed [15:0] dac_out_r,
  output idle
);

reg [4:0] clock_counter;

reg signed [15:0] dac_sample_l;
reg signed [15:0] dac_sample_r;

genvar gi;
integer i;
parameter OUTPUT_AUDIO_RATE = 32000;
parameter CLOCKS_PER_SAMPLE = 32 * 3; // 32 "steps" * 3 clock cycles each

parameter N_VOICES = 8;

///////////////////////////////////////////////////////////////////////////////
// DSP Registers

reg [7:0] VxVOLL [N_VOICES-1:0];    // $x0 rw VxVOLL - Left volume for Voice x
reg [7:0] VxVOLR [N_VOICES-1:0];    // $x1 rw VxVOLR - Right volume for Voice x
reg [7:0] VxENVX [N_VOICES-1:0];    // $x8 rw Current envelope value for Voice X, MSb always zero.

/////////////////////////////////////////////
// Register read/write logic
reg [7:0] reg_data_out;
assign dsp_reg_data_out = reg_data_out;

always @(*) begin
  case (dsp_reg_address[3:0])
    4'h0: reg_data_out = VxVOLL[ dsp_reg_address[6:4] ];  
    4'h1: reg_data_out = VxVOLR[ dsp_reg_address[6:4] ];  
    4'h8: reg_data_out = {1'b0, VxENVX[ dsp_reg_address[6:4] ][6:0] };  
    default: begin end
  endcase
end

always @(posedge clock) begin
  if(dsp_reg_write_enable) begin
    case (dsp_reg_address[3:0])
      4'h0: VxVOLL[ dsp_reg_address[6:4] ] <= dsp_reg_data_in;  
      4'h1: VxVOLR[ dsp_reg_address[6:4] ] <= dsp_reg_data_in;  
      4'h8: VxVOLR[ dsp_reg_address[6:4] ] <= {1'b0, dsp_reg_data_in[6:0]};  
      default: begin end
    endcase
  end
end

/////////////////////////////////////////////
// Per-Voice FSM
parameter VSTATE_S1 = 0,
          VSTATE_S2 = 1,
          VSTATE_S3 = 2,
          VSTATE_S4 = 3,
          VSTATE_S5 = 4,
          VSTATE_S6 = 5,
          VSTATE_S7 = 6,
          VSTATE_S8 = 7,
          VSTATE_S9 = 8;

parameter [4:0] VOICE_S1_START [7:0] = '{5'd17, 5'd20, 5'd31, 5'd2, 5'd5, 5'd8, 5'd11, 5'd14};
reg [8:0] voice_state [N_VOICES-1:0];

///////////////////////////////////////////////////////////////////////////////
// DSP-global FSM

// The entire flow of the DSP occurs in 32 'major' steps, each step consisting of 3 cycles. Every
// 96 cycles, the process repeats. (32KhZ * 96 cyc/sample = 3.072 MhZ input clock rate). 
// Track 32 major steps, each containing 3 minor steps, both as one hot encoding.
parameter N_MAJOR_STEPS = 32;
parameter N_MINOR_STEPS = 3;
reg [N_MAJOR_STEPS-1:0] major_step;
reg [N_MINOR_STEPS-1:0] minor_step;

///////////////////////////////////////////////////////////////////////////////
// Voice processing mixing

reg [15:0] VxOUTX_full [N_VOICES-1:0];
wire [7:0] VxOUTX [N_VOICES-1:0];

generate
for(gi=0; gi<N_VOICES; gi=gi+1)
  assign VxOUTX[gi][7:0] = VxOUTX_full[gi][15:8];
endgenerate

reg [15:0] vxoutx_to_l [N_VOICES-1:0];
reg [15:0] vxoutx_to_r [N_VOICES-1:0];

// Per-voice sample -> envelope -> L/R vol split
always @(*)
  for(i=0; i<N_VOICES; i=i+1) begin
    VxOUTX_full[i] = $signed(current_sample[i]) * $signed(VxENVX[i]);
    vxoutx_to_l[i] = $signed(VxVOLL[i]) * $signed(VxOUTX[i]) << 1;
    vxoutx_to_r[i] = $signed(VxVOLR[i]) * $signed(VxOUTX[i]) << 1;
  end

// Sum of individual voices

reg [19:0] sum_of_voices_l;
reg [19:0] sum_of_voices_r;
always @(*) begin
  sum_of_voices_l = $signed({{4{vxoutx_to_l[0][15]}}, vxoutx_to_l[0]}) +
                    $signed({{4{vxoutx_to_l[1][15]}}, vxoutx_to_l[1]}) + 
                    $signed({{4{vxoutx_to_l[2][15]}}, vxoutx_to_l[2]}) + 
                    $signed({{4{vxoutx_to_l[3][15]}}, vxoutx_to_l[3]}) + 
                    $signed({{4{vxoutx_to_l[4][15]}}, vxoutx_to_l[4]}) + 
                    $signed({{4{vxoutx_to_l[5][15]}}, vxoutx_to_l[5]}) + 
                    $signed({{4{vxoutx_to_l[6][15]}}, vxoutx_to_l[6]}) + 
                    $signed({{4{vxoutx_to_l[7][15]}}, vxoutx_to_l[7]});
  // sum_of_voices_l = sum_of_voices_l > 20'b0000_0111_1111_1111_1111
  //                     ? 20'b0000_0111_1111_1111_1111
  //                     : sum_of_voices_l;
  // sum_of_voices_l = sum_of_voices_l > 20'b1111_1000_0000_0000_0000
  //                     ? 20'b1111_1000_0000_0000_0000
  //                     : sum_of_voices_l;

  sum_of_voices_r = $signed({{4{vxoutx_to_r[0][15]}}, vxoutx_to_r[0]}) + 
                    $signed({{4{vxoutx_to_r[1][15]}}, vxoutx_to_r[1]}) + 
                    $signed({{4{vxoutx_to_r[2][15]}}, vxoutx_to_r[2]}) + 
                    $signed({{4{vxoutx_to_r[3][15]}}, vxoutx_to_r[3]}) + 
                    $signed({{4{vxoutx_to_r[4][15]}}, vxoutx_to_r[4]}) + 
                    $signed({{4{vxoutx_to_r[5][15]}}, vxoutx_to_r[5]}) + 
                    $signed({{4{vxoutx_to_r[6][15]}}, vxoutx_to_r[6]}) + 
                    $signed({{4{vxoutx_to_r[7][15]}}, vxoutx_to_r[7]});
  // sum_of_voices_r = sum_of_voices_r > 20'b0000_0111_1111_1111_1111
  //                     ? 20'b0000_0111_1111_1111_1111
  //                     : sum_of_voices_r;
  // sum_of_voices_r = sum_of_voices_r > 20'b1111_1000_0000_0000_0000
  //                     ? 20'b1111_1000_0000_0000_0000
  //                     : sum_of_voices_r;
end

///////////////////////////////////////////////////////////////////////////////
// State logic

reg [15:0] current_sample [N_VOICES-1:0];
reg [7:0] basic_oscillator [N_VOICES-1:0];

// TODO : For now, no ram writes possible.
assign ram_write_enable = 0;

// Clocked logic
always @(posedge clock)
	begin
		if (reset == 1'b1) begin

      major_step <= 1 << 0;
      minor_step <= 1 << 0;

      // Per-voice register initialization
      for(i=0; i<N_VOICES; i=i+1) begin
        basic_oscillator[i] <= 0;
        VxENVX[i] <= 8'b01111111;
        VxVOLL[i] <= 8'b01111111 / 4;
        VxVOLR[i] <= 8'b01111111 / 4;
      end
      
      // Initially voice sample generators are in these states.
      voice_state[0] <= 1 << VSTATE_S5;
      voice_state[1] <= 1 << VSTATE_S2;
      voice_state[2] <= 1 << VSTATE_S1;
      voice_state[3] <= 1 << VSTATE_S9;
      voice_state[4] <= 1 << VSTATE_S9;
      voice_state[5] <= 1 << VSTATE_S9;
      voice_state[6] <= 1 << VSTATE_S9;
      voice_state[7] <= 1 << VSTATE_S9;

    end else begin

      // HACK : current_sample driven by a basic oscillator
      if(major_step[0]) begin
        for(i=0; i<N_VOICES; i=i+1) begin
          basic_oscillator[i] <= basic_oscillator[i] + i[7:0] + 1;
          current_sample[i] <= { {8{basic_oscillator[i][7]}} , basic_oscillator[i][7:0] };
        end
      end

      // Advance minor every clock cycle, and major step every 3 minor steps
      minor_step <= {minor_step[1:0], minor_step[2]};
      major_step <= minor_step[2] ? {major_step[30:0], major_step[31]} : major_step;

      // Per-voice state advance logic
      for(i=0; i<N_VOICES; i=i+1) begin

        // State transitions
        if(minor_step[2]) begin
          // Handle transition for (S[x] minor 2 -> S[x+1] minor 0) for S1-S8
          if( !voice_state[i][VSTATE_S9] )  
            voice_state[i] <= {voice_state[i][7:0], voice_state[i][8]};
          // In this case, we're in S9. Check if we're scheduled to go to S1 this next major step.
          // TODO : I think the schedule needs to be changed by 1. Think more about this.
          else if(major_step[VOICE_S1_START[i]])
            voice_state[i] <= VSTATE_S1;
        end
        
        // State logic
        case (1'b1)
          voice_state[i][VSTATE_S1]: begin
            // TODO : Load VxSRCN register, if necessary.
          end
          voice_state[i][VSTATE_S2]: begin
            // TODO : 
          end
          voice_state[i][VSTATE_S3]: begin
            // TODO : 
          end
          voice_state[i][VSTATE_S4]: begin
            // Apply VxVOL
            // TODO : 
          end
          voice_state[i][VSTATE_S5]: begin
            // TODO : 
          end
          voice_state[i][VSTATE_S6]: begin
            // TODO : 
          end
          voice_state[i][VSTATE_S7]: begin
            // TODO : 
          end
          voice_state[i][VSTATE_S8]: begin
            // TODO : 
          end
          voice_state[i][VSTATE_S9]: begin
            // TODO : 
          end
        endcase        
      end
    end
    // End of voice state logic

    // DSP FSM logic
    case (1'b1)
      major_step[26]: begin
        // Load and apply MVOLL.
        // Load and apply EVOLL.
        // Output the left sample to the DAC.
        // Load and apply EFB.

        dac_sample_l <= sum_of_voices_l[15:0];

      end
      major_step[27]: begin
        // Load and apply MVOLR.
        // Load and apply EVOLR.
        // Output the right sample to the DAC.

        dac_sample_r <= sum_of_voices_l[15:0];
        // Load PMON
      end
    endcase

  end


assign audio_valid = 0;
assign idle = 0;
assign dsp_reg_data_out = 0;
assign dac_out_l = dac_sample_l;
assign dac_out_r = dac_sample_r;
  
endmodule