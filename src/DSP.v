// The S-DSP is nominally intended to output samples at 32KhZ, and originally
// had 96 clock cycles per sample (~3MhZ). In this system, we'll be shooting for
// 32 cycles per sample (So a 1.024 MhZ input clock, receiving L/R samples once every
// 32 cycles).



module DSP (
  inout [15:0] ram_address,
  inout [7:0] ram_data,
  output ram_write_enable,

  input [7:0]  dsp_reg_address,
  input [7:0]  dsp_reg_data_in,
  output [7:0] dsp_reg_data_out,
  input        dsp_reg_write_enable,

  input clock,
  input reset,
  output reg audio_valid,
  output [15:0] dac_out_l,
  output [15:0] dac_out_r,
  output idle
);

reg [4:0] clock_counter;

integer i;
parameter OUTPUT_AUDIO_RATE = 32000;
parameter CLOCKS_PER_SAMPLE = 32 * 3; // 32 "steps" * 3 clock cycles each

parameter N_VOICES = 8;

/////////////////////////////////////////////
// There are over 200 1-byte registers on the DSP. For simplicity in addressing,
// these are mapped to a range of 256 bytes.
// --------------------------------------------
// x0	| VOL   | (L)	Left channel volume.
// x1	| VOL   | (R)	Right channel volume.
// x2	| P(L)  |	Lower 8 bits of pitch.
// x3	| P(H)  |	Higher 8-bits of pitch.
// x4	| SRCN	| Source number (0-255). (references the source directory)
// x5	| ADSR  | (1)	If bit7 is set, ADSR is enabled. If cleared GAIN is used.
// x6	| ADSR  | (2)	These two registers control the ADSR envelope.
// x7	| GAIN	| This register provides function for software envelopes.
// x8	| -ENVX	| The DSP writes the current value of the envelope to this register. (read it)
// x9	| -OUTX	| The DSP writes the current waveform value after envelope multiplication and before volume multiplication.
// 0C	| MVOL  | (L)	Main Volume (left output)
// 1C	| MVOL  | (R)	Main Volume (right output)
// 2C	| EVOL  | (L)	Echo Volume (left output)
// 3C	| EVOL  | (R)	Echo Volume (right output)
// 4C	| KON	  | Key On (1 bit for each voice)
// 5C	| KOF	  | Key Off (1 bit for each voice)
// 6C	| FLG	  | DSP Flags. (used for MUTE,ECHO,RESET,NOISE CLOCK)
// 7C	| -ENDX	| 1 bit for each voice.
// 0D	| EFB	  | Echo Feedback
// 1D	| ---	  | Not used
// 2D	| PMON	| Pitch modulation
// 3D	| NON	  | Noise enable
// 4D	| EON	  | Echo enable
// 5D	| DIR	  | Offset of source directory (DIR*100h = memory offset)
// 6D	| ESA	  | Echo buffer start offset (ESA*100h = memory offset)
// 7D	| EDL	  | Echo delay, 4-bits, higher values require more memory.
// xF	| COEF	| 8-tap FIR Filter coefficients

reg [7:0] VxVOLL [N_VOICES-1:0];
reg [7:0] VxVOLR [N_VOICES-1:0];



/////////////////////////////////////////////
// Register read/write logic
assign ram_write_enable = 0;

/////////////////////////////////////////////
// Reset logic

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

// The entire flow of the DSP occurs in 32 steps, each step consisting of 3 cycles. Every
// 96 cycles, the process repeats. (32KhZ * 96 cyc/sample = 3.072 MhZ input clock rate). 
// Track each as one hot encoding
parameter N_MAJOR_STEPS = 32;
parameter N_MINOR_STEPS = 3;
reg [N_MAJOR_STEPS-1:0] major_step;
reg [N_MINOR_STEPS-1:0] minor_step;

always @(posedge clock)
	begin
		if (reset == 1'b1) begin

      major_step <= 1 << 0;
      minor_step <= 1 << 0;
      
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
      // End of voice state logic

    end
  end


assign audio_valid = 0;
assign idle = 0;
assign dsp_reg_data_out = 0;
assign dac_out_l = 0;
assign dac_out_r = 0;
  
endmodule