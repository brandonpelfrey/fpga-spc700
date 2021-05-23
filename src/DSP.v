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
  output idle,

  output [15:0] voice_states_out [7:0]
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

reg [7:0] VxVOLL  [N_VOICES-1:0];    // $x0 VxVOLL - Left volume for Voice x
reg [7:0] VxVOLR  [N_VOICES-1:0];    // $x1 VxVOLR - Right volume for Voice x
reg [7:0] VxPL    [N_VOICES-1:0];    // $x2 Pitch low byte
reg [7:0] VxPH    [N_VOICES-1:0];    // $x3 Pitch high 6 bits
reg [7:0] VxSRCN  [N_VOICES-1:0];    // $x4 Source number
reg [7:0] VxADSR1 [N_VOICES-1:0];    // $x5 ADSR - part 1
reg [7:0] VxADSR2 [N_VOICES-1:0];    // $x6 ADSR - part 2
reg [7:0] VxGAIN  [N_VOICES-1:0];    // $x7 GAIN
reg [7:0] VxENVX  [N_VOICES-1:0];    // $x8 Current envelope value for Voice X.
reg [7:0] VxOUTX  [N_VOICES-1:0];    // $x8 Value after envelope mult, but before VOL mult

reg [7:0] MVOLL; // $0C Main Volume L
reg [7:0] MVOLR; // $1C Main Volume R
reg [7:0] EVOLL; // $2C Echo Volume L
reg [7:0] EVOLR; // $3C Echo Volume R
reg [7:0] KON;   // $4C Key On 
reg [7:0] KOFF;  // $5C Key Off
reg [7:0] FLG;   // $6C Flags (reset, mute, echo, noise clock)
reg [7:0] ENDX;  // $7C Indicates source end block

reg [7:0] EFB;  // $0D Echo Feedback
/* unused */    // $1D
reg [7:0] PMON; // $2D Pitch Modulation
reg [7:0] NON;  // $3D Noise on/off
reg [7:0] EON;  // $4D Echo on/off
reg [7:0] DIR;  // $5D Offset address for source directory
reg [7:0] ESA;  // $6D Offset address for echo data
reg [7:0] EDL;  // $7D Flags (reset, mute, echo, noise clock)

reg[7:0] Cx [7:0]; // FIR Filter coefficients

/////////////////////////////////////////////
// Register read/write logic
reg [7:0] reg_data_out;
assign dsp_reg_data_out = reg_data_out;

// Read reg
always @(*) begin
  case (dsp_reg_address[3:0])
    4'h0: reg_data_out = VxVOLL[ dsp_reg_address[6:4] ];  
    4'h1: reg_data_out = VxVOLR[ dsp_reg_address[6:4] ];  
    4'h2: reg_data_out = VxPL[ dsp_reg_address[6:4] ];
    4'h3: reg_data_out = VxPH[ dsp_reg_address[6:4] ];
    4'h8: reg_data_out = {1'b0, VxENVX[dsp_reg_address[6:4]][6:0]};  
    default: reg_data_out = 0;
  endcase
end

// Write to Reg
always @(posedge clock) begin
  if(dsp_reg_write_enable) begin
    case (dsp_reg_address[3:0])
      4'h0: VxVOLL[ dsp_reg_address[6:4] ] <= dsp_reg_data_in;  
      4'h1: VxVOLR[ dsp_reg_address[6:4] ] <= dsp_reg_data_in;
      4'h2: VxPL[ dsp_reg_address[6:4] ] <= dsp_reg_data_in;
      4'h3: VxPH[ dsp_reg_address[6:4] ] <= dsp_reg_data_in;
      4'h8: VxENVX[ dsp_reg_address[6:4] ] <= dsp_reg_data_in & 8'b0111_1111;  
      default: begin end
    endcase
  end
end

/////////////////////////////////////////////
// Per-Voice FSM
//   | 0000000000000000111111111111111122222222222222223333333333333333
// t | 0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF
// V0| iHDDDpppp.......................................................
// V1| ....iHDDDpppp...................................................
// V2| ........iHDDDpppp...............................................
// V3| ............iHDDDpppp...........................................
// V4| ................iHDDDpppp.......................................
// V5| ....................iHDDDpppp...................................
// V6| ........................iHDDDpppp...............................
// V7| ............................iHDDDpppp...........................
//  G| .................................EEEEEEEESSSSSS.................
// i - Initialize first read and cleanup voice state
// H - Read next header byte
// D - Read data byte
// p - Process input samples
// E - Read echo buffer
// S - Read Source/loop start address/dir/srcn (cycle across voices each sample)

parameter VSTATE_S0 = 0, VSTATE_S1 = 1, VSTATE_S2 = 2, VSTATE_S3 = 3,
          VSTATE_S4 = 4, VSTATE_S5 = 5, VSTATE_S6 = 6, VSTATE_S7 = 7,
          VSTATE_S8 = 8, VSTATE_S9 = 8, VSTATE_S10 = 10, VSTATE_S11 = 11,
          VSTATE_S12 = 12, VSTATE_S13 = 13, VSTATE_S14 = 14, VSTATE_S15 = 15;

parameter [5:0] VOICE_S0_START [7:0] = '{6'h0, 6'h4, 6'h8, 6'hC, 6'h10, 6'h14, 6'h18, 6'h1C};
reg [15:0] voice_state [N_VOICES-1:0];

generate
for(gi=0; gi<N_VOICES; gi=gi+1)
  assign voice_states_out[gi] = voice_state[gi];
endgenerate

///////////////////////////////////////////////////////////////////////////////
// DSP-global FSM

parameter N_MAJOR_STEPS = 64;
reg [N_MAJOR_STEPS-1:0] major_step;

///////////////////////////////////////////////////////////////////////////////
// BRR Decode logic

reg first_half = 1;
reg [15:0] sample_buffer    [N_VOICES-1:0][1:0];
reg [2:0] sample_buffer_ptr [N_VOICES-1:0];

reg [15:0] cursor [N_VOICES-1:0];
reg [15:0] P [N_VOICES-1:0];

/*
[   c        ][            ][            ][ ...
A ---- B ---- C ---- D ---- E ---- F ---- G ----
|      |      |      |      |      |      |

Pseudocode

Init() {
  ring_buffer[8] = {0};
  
  byte_index = 1;  // Block byte index
  rbi = 0;         // Current ring buffer 
  cursor = 0;

  Sx = {0,0,0}
  
  range, filter, loop, end
  ReadHeader(); 
  ReadByte();
  ReadByte();
}

// TODO : Keep 2 additional bytes beyond the current byte supplied in the buffer

reg [3:0] next_input
void AdvanceNextSample() {
  static int sample_byte_index = 0;
  static int sample_first_half = 1;

  next_input = sample_first_half 
                ? ring_buffer[sample_byte_index][7:4]
                : ring_buffer[sample_byte_index][3:0];
  sample_first_half = !sample_first_half; // Flip which nibble is being read
  sample_byte_index ++;
}

void FeedRingBuffer() {
  // Are we at the end of a BRR block?
  //  - Yes, END + LOOP : Go back to HEADER for loop
  //  - Yes, END        : Done with this sample.
  //  - Yes, !END       : Continue to following block
  //  - No              : Continue with next byte

  static byte_reader_index = 0;
  static ring_buffer_read_address = 0x1234;



}

void genOutputSample() {
  // Step however many whole samples are needed
  while(cursor > 0x1000) {
    AdvanceNextSample();
    R = next_input << range;
    Sx[0] = R + (a * Sx[1] + b * Sx[2]);
    cursor -= 0x1000;
  }

  // Now we are some fraction between the last two computed samples.
  // Resample for output, with simple linear interpolation in this case.
  output = (cursor*Sx[0] + (0x1000 - cursor)*Sx[1]) / 0x1000;

  // Advance the desired position for the next output sample
  cursor += P;
}

////////////////////////////////////////////////
0: Prep
1: Read next header
2: Read data1
3: Read data2
4: Read data3
5: Advance Input 1
6: Advance Input 2
7: Advance Input 3
8: Advance Input 4
15: Idle
*/

// Tracks state for the 'reader' which fills data into the read buffer
reg [7:0]  brr_read_buffer   [N_VOICES-1:0][7:0];  // 8-byte buffer for each voice
reg [15:0] brr_read_mem_addr [N_VOICES-1:0];       // 16-bit read address corresponding to 'index'
reg [2:0]  brr_read_index    [N_VOICES-1:0];       // Points to the index of the buffer to write
                                                   // to for next byte read

// Tracks state for the 'processor' which is reading data from the read buffer
// and producing samples.
reg [2:0]  brr_proc_index     [N_VOICES-1:0];      // Index in the read buffer for the next sample being read
reg [15:0] brr_proc_mem_addr  [N_VOICES-1:0];      // Address of the current byte being processed
reg        brr_proc_hi_nib    [N_VOICES-1:0];      // 1 iff the high nibble is the next to be processed
reg [15:0] brr_output_samples [N_VOICES-1:0][2:0]; // current and last two output samples. newest is @ [0]

reg [7:0]  current_header[N_VOICES-1:0];
reg [15:0] current_header_address[N_VOICES-1:0];
reg [7:0]  next_header[N_VOICES-1:0];
//wire [4:0]  current_range[N_VOICES-1:0];

reg done [N_VOICES-1:0]; // Have we output a sample yet for this voice?

// always @(*)
//   for(i=0; i<N_VOICES; i=i+1) begin
//     P[i] = {2'b00, VxPH[5:0], VxPL};
//     // TODO: Add pmod logic
//     cursor[i] = cursor[i] + P[i];
//   end

///////////////////////////////////////////////////////////////////////////////
// Voice processing / mixing

always @(*)
  for(i=0; i<N_VOICES; i=i+1) begin
    P[i] = {2'b00, VxPH[i][5:0], VxPL[i][7:0]};
  end

reg [15:0] vxoutx_to_l [N_VOICES-1:0];
reg [15:0] vxoutx_to_r [N_VOICES-1:0];
reg [15:0] VxOUTX_full [N_VOICES-1:0];

// Envelope and L/R volume split for each voice
always @(*)
  for(i=0; i<N_VOICES; i=i+1) begin
    VxOUTX_full[i] = $signed(current_sample[i]) * $signed(VxENVX[i]);
    VxOUTX[i][7:0] = VxOUTX_full[i][15:8];
    vxoutx_to_l[i] = $signed(VxVOLL[i]) * $signed(VxOUTX[i]) << 1;
    vxoutx_to_r[i] = $signed(VxVOLR[i]) * $signed(VxOUTX[i]) << 1;
  end

// Sum of individual voices
reg [19:0] sum_of_voices_l;
reg [19:0] sum_of_voices_r;
always @(*) begin
  // TODO : Clamping 
  sum_of_voices_l = $signed({{4{vxoutx_to_l[0][15]}}, vxoutx_to_l[0]}) +
                    $signed({{4{vxoutx_to_l[1][15]}}, vxoutx_to_l[1]}) + 
                    $signed({{4{vxoutx_to_l[2][15]}}, vxoutx_to_l[2]}) + 
                    $signed({{4{vxoutx_to_l[3][15]}}, vxoutx_to_l[3]}) + 
                    $signed({{4{vxoutx_to_l[4][15]}}, vxoutx_to_l[4]}) + 
                    $signed({{4{vxoutx_to_l[5][15]}}, vxoutx_to_l[5]}) + 
                    $signed({{4{vxoutx_to_l[6][15]}}, vxoutx_to_l[6]}) + 
                    $signed({{4{vxoutx_to_l[7][15]}}, vxoutx_to_l[7]});
  
  sum_of_voices_r = $signed({{4{vxoutx_to_r[0][15]}}, vxoutx_to_r[0]}) + 
                    $signed({{4{vxoutx_to_r[1][15]}}, vxoutx_to_r[1]}) + 
                    $signed({{4{vxoutx_to_r[2][15]}}, vxoutx_to_r[2]}) + 
                    $signed({{4{vxoutx_to_r[3][15]}}, vxoutx_to_r[3]}) + 
                    $signed({{4{vxoutx_to_r[4][15]}}, vxoutx_to_r[4]}) + 
                    $signed({{4{vxoutx_to_r[5][15]}}, vxoutx_to_r[5]}) + 
                    $signed({{4{vxoutx_to_r[6][15]}}, vxoutx_to_r[6]}) + 
                    $signed({{4{vxoutx_to_r[7][15]}}, vxoutx_to_r[7]});
end

///////////////////////////////////////////////////////////////////////////////
// State logic

reg [15:0] current_sample [N_VOICES-1:0];
reg [7:0] basic_oscillator [N_VOICES-1:0];

// TODO : For now, no ram writes possible.
reg [15:0] reg_ram_address;
assign ram_address = reg_ram_address;
assign ram_write_enable = 0;

// DSP Sample decoding combinational logic

// Sample decoding is done in a high number of bits for precision
// TODO: These mults can be turned into a number of add/sub/shift.

reg [31:0] sample_decoder [N_VOICES-1:0];
always @(*)
  for(i=0; i<N_VOICES; i=i+1) begin
    // Read nibble, shift by current header range.
    sample_decoder[i] = brr_proc_hi_nib[i]
      ? {28'b0, brr_read_buffer[i][ brr_proc_index[i] ][7:4]}
      : {28'b0, brr_read_buffer[i][ brr_proc_index[i] ][3:0]};
    sample_decoder[i] = sample_decoder[i] << current_header[i][7:4];

    // Filtering
    if(current_header[i][3:2] == 2'b00) begin
      // Direct filter : Nothing to do
    end else if(current_header[i][3:2] == 2'b01) begin
      sample_decoder[i] = 
        $signed(sample_decoder[i])
        + ($signed({16'b0, brr_output_samples[i][0]}) * 15) / 16;
    end else if(current_header[i][3:2] == 2'b10) begin
      sample_decoder[i] = 
        $signed(sample_decoder[i])
        + ($signed({16'b0, brr_output_samples[i][0]}) * 61) / 32
        + ($signed({16'b0, brr_output_samples[i][1]}) * -15) / 16;
    end else begin
      sample_decoder[i] = 
        $signed(sample_decoder[i])
        + ($signed({16'b0, brr_output_samples[i][0]}) * 115) / 64
        + ($signed({16'b0, brr_output_samples[i][1]}) * -13) / 16;
    end

    // TODO : Supposed to clip each of these to 15 bits after decoding
  end

// Clocked logic
always @(posedge clock)
	begin

  //   $monitor("%03t: major %h VS[0] %h VS[1] %h VS[2] %h VS[3] %h VS[4] %h VS[5] %h VS[6] %h VS[7] %h ", 
  // $time, major_step, voice_state[0], voice_state[1], voice_state[2], voice_state[3], voice_state[4], 
  // voice_state[5], voice_state[6], voice_state[7]);

		if (reset == 1'b1) begin

      // FIXME: Ideally, this starts at 0. I'm unsure why this needs to start at 28 
      // in order to get V0 starting on the first output. :\
      major_step <= 1 << 28;

      // Per-voice register initialization
      for(i=0; i<N_VOICES; i=i+1) begin
        basic_oscillator[i] <= 0;
        VxENVX[i] <= 8'b01111111;
        VxVOLL[i] <= 8'b01111111 / 4;
        VxVOLR[i] <= 8'b01111111 / 4;
        brr_proc_mem_addr[i] <= 0;
        brr_proc_index[i] <= 0;
        done[i] <= 0;
        cursor[i] <= 0;
        brr_proc_hi_nib[i] <= 1;
      end
      
      // Initially voice sample generators are in these states.
      voice_state[0] <= 1 << VSTATE_S0;
      voice_state[1] <= 1 << VSTATE_S15;
      voice_state[2] <= 1 << VSTATE_S15;
      voice_state[3] <= 1 << VSTATE_S15;
      voice_state[4] <= 1 << VSTATE_S15;
      voice_state[5] <= 1 << VSTATE_S15;
      voice_state[6] <= 1 << VSTATE_S15;
      voice_state[7] <= 1 << VSTATE_S15;

    end else begin

      // HACK : current_sample driven by a basic oscillator
      if(major_step[0]) begin
        for(i=0; i<N_VOICES; i=i+1) begin
          basic_oscillator[i] <= basic_oscillator[i] + i[7:0] + 1;
          current_sample[i] <= { {8{basic_oscillator[i][7]}} , basic_oscillator[i][7:0] };
        end
      end

      // Advance major steps (which is equal to one clock cycle for now)
      major_step <= {major_step[0], major_step[N_MAJOR_STEPS-1:1]};

      // Per-voice state advance logic
      for(i=0; i<N_VOICES; i=i+1) begin

        // State transitions
        if( voice_state[i][VSTATE_S15] ) begin
          if( major_step[VOICE_S0_START[i]] )
            voice_state[i] <= 1 << VSTATE_S0;
        end else
          voice_state[i] <= {voice_state[i][14:0], voice_state[i][15]};
          
        // TODO: The read_mem_addr advance logic isn't aware of headers or looping at all.

        // 012345678

        // B1        B2        ..
        // HDDDDDDDD HDDDDDDDD
        //        ^ 

        //

        // [Dn          ][Dn+1         ]H       [Dn+2         ]
        // |      |      |      |       ********|       |     |....
        //            ^     



        // State logic
        case (1'b1)
          voice_state[i][VSTATE_S0]: begin // initialize
            reg_ram_address <= current_header_address[i] + 9; // ADDR: Next block's header
          end
          voice_state[i][VSTATE_S1]: begin // H
            next_header[i]  <= ram_data;                      // READ: Next block header
            reg_ram_address <= brr_proc_mem_addr[i] + 1;      // ADDR: BRR Data 0
            brr_read_index[i] <= brr_proc_index[i] + 1;       // Read data into ring buffer after current byte
                                                              // being processed.
          end
          voice_state[i][VSTATE_S2]: begin // D
            brr_read_buffer[i][ brr_read_index[i] ] <= ram_data; // READ: BRR Data 0
            reg_ram_address <= brr_proc_mem_addr[i] + 2;         // ADDR: BRR Data 1
            brr_read_index[i] <= brr_proc_index[i] + 2;          // Advance ring buffer
          end
          voice_state[i][VSTATE_S3]: begin // D
            brr_read_buffer[i][ brr_read_index[i] ] <= ram_data; // READ: BRR Data 1
            reg_ram_address <= brr_proc_mem_addr[i] + 3;         // ADDR: BRR Data 2
            brr_read_index[i] <= brr_proc_index[i] + 3;          // Advance ring buffer
          end
          voice_state[i][VSTATE_S4]: begin // D
            brr_read_buffer[i][ brr_read_index[i] ] <= ram_data; // READ: BRR Data 2
            brr_read_index[i] <= brr_read_index[i] + 1;          // Advance ring buffer
          end
          voice_state[i][VSTATE_S5]: begin // p
            // TODO : 

            if(cursor[i] > 16'h1000) begin
              // process one sample, move last two back
              brr_output_samples[i][0] <= sample_decoder[i][15:0];
              brr_output_samples[i][1] <= brr_output_samples[i][0];
              brr_output_samples[i][2] <= brr_output_samples[i][1];

              // advance proc_index/first_half
              brr_proc_hi_nib[i] <= ! brr_proc_hi_nib[i];
              brr_proc_index[i] <= brr_proc_hi_nib[i] ? brr_proc_index[i] : brr_proc_index[i] + 1;
              
            end else begin
              // interpolate result for later mixing
              done[i] <= 1; // we're done generating an output sample for this voice
            end

          end
          voice_state[i][VSTATE_S6]: begin // p
            // TODO : 
          end
          voice_state[i][VSTATE_S7]: begin // p
            // TODO : 
          end
          voice_state[i][VSTATE_S8]: begin // p
            // TODO : 
          end
          voice_state[i][VSTATE_S9]: begin
            // TODO : 
          end
          voice_state[i][VSTATE_S10]: begin
            // TODO : 
          end
          voice_state[i][VSTATE_S11]: begin
            // TODO : 
          end
          voice_state[i][VSTATE_S12]: begin
            // TODO : 
          end
          voice_state[i][VSTATE_S13]: begin
            // TODO : 
          end
          voice_state[i][VSTATE_S14]: begin
            // TODO : Handle end of sample, looping, etc.
            current_header_address[i] <= current_header_address[i] + 9;
            current_header[i] <= next_header[i];
            done[i] <= 0;
          end
          voice_state[i][VSTATE_S15]: begin
            // This is a idle wait state that we stay in for several cycles until going to S0.
            // Don't do anything here!
          end
        endcase        
      end
    end
    // End of voice state logic

    // TODO: calculate start/loop addresses per-voice
    // n = {DIR, 8'b0} + {6'b0, SRCN, 2'b0}
    // SA(L)  = n+0, SA(H)  = n+1
    // LSA(L) = n+2, LSA(H) = n+3

    // DSP FSM logic
    case (1'b1)
      major_step[N_MAJOR_STEPS-1]: begin
        dac_sample_l <= sum_of_voices_l[15:0];
        dac_sample_r <= sum_of_voices_r[15:0];
      end
    endcase

  end


assign audio_valid = 0;
assign idle = 0;
assign dsp_reg_data_out = 0;
assign dac_out_l = dac_sample_l;
assign dac_out_r = dac_sample_r;
  
endmodule