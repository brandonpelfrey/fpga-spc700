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

parameter OUTPUT_AUDIO_RATE = 32000;
parameter CLOCKS_PER_SAMPLE = 32;

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

assign ram_write_enable = 0;



/////////////////////////////////////////////


reg [7:0] test;
assign ram_data = test;

reg [15:0] wave;

always @(posedge clock) begin
  test <= reset ? ram_address[7:0] : ram_address[15:8];
  clock_counter <= reset ? 0 : clock_counter+1;

  if(clock_counter == 0) begin
    if(reset) begin
      wave <= 0;
    end else begin 
      wave <= wave + 100;
    end
  end
end

assign audio_valid = 0;
assign idle = 0;
assign dsp_reg_data_out = 0;
assign dac_out_l = {11'b0, 5'b10110};
assign dac_out_r = wave;
  
endmodule