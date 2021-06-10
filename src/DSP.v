`include "DSPVoiceDecoder.v"

// The S-DSP has a nominal output sample rate of 32KhZ, and originally
// had 96 clock cycles per sample (~3MhZ). In this system, we'll be shooting for
// 64 cycles per sample (So a 2.048 MhZ input clock, producing L/R samples once
// every 64 cycles).

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

module DSP (
  ram_address,
  ram_data,
  ram_write_enable,

  dsp_reg_address,
  dsp_reg_data_in,
  dsp_reg_data_out,
  dsp_reg_write_enable,

  clock,
  reset,
  dac_out_l,
  dac_out_r,
  idle,
  voice_states_out
);

inout [15:0] ram_address;
inout [7:0] ram_data;
output ram_write_enable;
input  [7:0] dsp_reg_address;
input  [7:0] dsp_reg_data_in;
output [7:0] dsp_reg_data_out;
input        dsp_reg_write_enable;
input clock;
input reset;
output signed [15:0] dac_out_l;
output signed [15:0] dac_out_r;
output idle;
output reg [8*4 - 1:0] voice_states_out;

reg signed [15:0] dac_sample_l;
reg signed [15:0] dac_sample_r;

genvar gi;
integer i;
parameter OUTPUT_AUDIO_RATE = 32000;
parameter CLOCKS_PER_SAMPLE = 32 * 2; // 32 "steps" * 3 clock cycles each
parameter N_VOICES = 8;

parameter N_MAJOR_STEPS = 64;
reg [N_MAJOR_STEPS-1:0] major_step;

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

assign ram_write_enable = 0;
//////////////////////////////////////////////

//DSPVoiceDecoder decoder(clock, reset, voice_states_out[3:0]);





//////////////////////////////////////////////

// Per-voice Reset Logic
for(gi=0; gi<N_VOICES; gi=gi+1) begin
always @(posedge clock)
	begin
		if (reset == 1'b1) begin
        VxENVX[gi] <= 8'b01111111;
        VxVOLL[gi] <= 8'b01111111 / 4;
        VxVOLR[gi] <= 8'b01111111 / 4;
        voice_states_out[4*gi+3:4*gi] <= 0;   
    end
  end
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

    end else begin
      // TODO
    end
    // End of voice state logic

    // DSP FSM logic
    case (1'b1)
      major_step[N_MAJOR_STEPS-1]: begin
        dac_sample_l <= 0;
        dac_sample_r <= 0;
      end
    endcase
  end


assign idle = 0;
assign dsp_reg_data_out = 0;
assign dac_out_l = dac_sample_l;
assign dac_out_r = dac_sample_r;
  
endmodule