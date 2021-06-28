// `include "DSPVoiceDecoder.v"

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
  voice_states_out,
  major_step
);

output reg [15:0] ram_address;
input  [7:0] ram_data;
output ram_write_enable;
input  [7:0] dsp_reg_address;
input  [7:0] dsp_reg_data_in;
output [7:0] dsp_reg_data_out;
input        dsp_reg_write_enable;
input clock;
input reset;
output reg signed [15:0] dac_out_l;
output reg signed [15:0] dac_out_r;
output [8*4 - 1:0] voice_states_out;

genvar gi;
integer i;
parameter OUTPUT_AUDIO_RATE = 32000;
parameter CLOCKS_PER_SAMPLE = 32 * 2; // 32 "steps" * 3 clock cycles each
parameter N_VOICES = 8;

parameter N_MAJOR_STEPS = 64;
output reg [5:0] major_step;

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
reg [7:0] VxOUTX  [N_VOICES-1:0];    // $x9 Value after envelope mult, but before VOL mult

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
  casez (dsp_reg_address)
    8'h?0: reg_data_out = VxVOLL[ dsp_reg_address[6:4] ];  
    8'h?1: reg_data_out = VxVOLR[ dsp_reg_address[6:4] ];  
    8'h?2: reg_data_out = VxPL[ dsp_reg_address[6:4] ];
    8'h?3: reg_data_out = VxPH[ dsp_reg_address[6:4] ];
    8'h?8: reg_data_out = {1'b0, VxENVX[dsp_reg_address[6:4]][6:0]};  
    8'h?9: reg_data_out = {1'b0, VxOUTX[dsp_reg_address[6:4]][6:0]};

    8'h0C: reg_data_out = MVOLL;
    8'h1C: reg_data_out = MVOLR;
    8'h2C: reg_data_out = EVOLL;
    8'h3C: reg_data_out = EVOLR;
    default: reg_data_out = 0;
  endcase
end

// Write to Reg
generate
for(gi=0; gi<N_VOICES; gi=gi+1) begin:per_voice_reset_logic
	always @(posedge clock) begin
	  if(reset) begin
	    VxVOLL[ gi ] <= 8'b01111111 >>> 2;
		 VxVOLR[ gi ] <= 8'b01111111 >>> 2;
		 VxENVX[ gi ] <= 8'b01111111;
	  end else
	  if(dsp_reg_write_enable) begin
		 casez (dsp_reg_address)
			{gi[3:0],4'h0}: VxVOLL[ gi ] <= dsp_reg_data_in;  
			{gi[3:0],4'h1}: VxVOLR[ gi ] <= dsp_reg_data_in;
			{gi[3:0],4'h2}: VxPL  [ gi ] <= dsp_reg_data_in;
			{gi[3:0],4'h3}: VxPH  [ gi ] <= dsp_reg_data_in;
			{gi[3:0],4'h8}: VxENVX[ gi ] <= dsp_reg_data_in & 8'b0111_1111;  
			{gi[3:0],4'h9}: VxOUTX[ gi ] <= dsp_reg_data_in;
			default: begin end
		 endcase
	  end
	end
end
endgenerate

// Write and reset for non-voice registers
always @(posedge clock) begin
  if(reset) begin
	  MVOLL <= 8'b01111111;
	  MVOLR <= 8'b01111111;
  end else
  if(dsp_reg_write_enable) begin
	 casez (dsp_reg_address)
		8'h0C: MVOLL <= dsp_reg_data_in;
		8'h1C: MVOLR <= dsp_reg_data_in;
		8'h2C: EVOLL <= dsp_reg_data_in;
		8'h3C: EVOLR <= dsp_reg_data_in;
		default: begin end
	 endcase
  end
end

assign ram_write_enable = 0;
//////////////////////////////////////////////

wire [15:0] decoder_ram_address [7:0];
wire decoder_write_requests [7:0];
wire signed [15:0] decoder_output [7:0];
wire decoder_reached_end [7:0];
reg decoder_advance_trigger [7:0];
wire [15:0] decoder_cursor [7:0];

// Form the pitch for each voice from registers
wire [13:0] decoder_pitch [7:0];
generate
for(gi=0; gi<8; gi=gi+1) begin:m
  assign decoder_pitch[gi] = {VxPH[gi][5:0], VxPL[gi][7:0]};
end
endgenerate

// Used to control whether clock ticks occur for a given voice. This is used
// during initial reset
reg [7:0] voice_clock_en = 8'b11111111;

DSPVoiceDecoder decoders [7:0] (
  .clock( {8{clock}} & voice_clock_en[7:0] ),
  .reset( {8{reset}} ),
  .state( voice_states_out ),
  .ram_address(decoder_ram_address),
  .ram_data(ram_data),
  .ram_read_request( decoder_write_requests ), /// !!!!!! TODO FIXME BROKEN
  .start_address( 16'b0 ),
  .loop_address( 16'b0 ),
  .pitch( decoder_pitch ),
  .current_output( decoder_output ),
  .reached_end( decoder_reached_end ),
  .advance_trigger( decoder_advance_trigger ),
  .cursor( decoder_cursor) );

//////////////////////////////////////////////

// Clocked logic - Reset

localparam VOICE_CYCLES = 12;
localparam integer VOICE_RESUME [7:0] = '{ 26, 22, 18, 14, 10, 6, 2, 62 };

// Combinatorial mixing logic
// Combinatorial circuit continuously feeds into 'sample' which is latched into dac_out at M63
reg signed [31:0] dac_sample_l;
reg signed [31:0] dac_sample_r;
always @* begin
  dac_sample_l =                $signed(decoder_output[0]) * $signed(VxVOLL[0]);
  dac_sample_l = dac_sample_l + $signed(decoder_output[1]) * $signed(VxVOLL[1]); 
  dac_sample_l = dac_sample_l + $signed(decoder_output[2]) * $signed(VxVOLL[2]);
  dac_sample_l = dac_sample_l + $signed(decoder_output[3]) * $signed(VxVOLL[3]);
  dac_sample_l = dac_sample_l + $signed(decoder_output[4]) * $signed(VxVOLL[4]);
  dac_sample_l = dac_sample_l + $signed(decoder_output[5]) * $signed(VxVOLL[5]);
  dac_sample_l = dac_sample_l + $signed(decoder_output[6]) * $signed(VxVOLL[6]);
  dac_sample_l = dac_sample_l + $signed(decoder_output[7]) * $signed(VxVOLL[7]);
  dac_sample_l = dac_sample_l >>> 7;

  dac_sample_l = (dac_sample_l * $signed(MVOLL)) >>> 7;

  dac_sample_r =                $signed(decoder_output[0]) * $signed(VxVOLR[0]);
  dac_sample_r = dac_sample_r + $signed(decoder_output[1]) * $signed(VxVOLR[1]); 
  dac_sample_r = dac_sample_r + $signed(decoder_output[2]) * $signed(VxVOLR[2]);
  dac_sample_r = dac_sample_r + $signed(decoder_output[3]) * $signed(VxVOLR[3]);
  dac_sample_r = dac_sample_r + $signed(decoder_output[4]) * $signed(VxVOLR[4]);
  dac_sample_r = dac_sample_r + $signed(decoder_output[5]) * $signed(VxVOLR[5]);
  dac_sample_r = dac_sample_r + $signed(decoder_output[6]) * $signed(VxVOLR[6]);
  dac_sample_r = dac_sample_r + $signed(decoder_output[7]) * $signed(VxVOLR[7]);
  dac_sample_r = dac_sample_r >>> 7;

  dac_sample_r = (dac_sample_r * $signed(MVOLR)) >>> 7;
end

reg [2:0] current_voice;
assign ram_address = decoder_ram_address[current_voice];

always @(posedge clock) begin
	
	if (reset == 1'b1) begin
		major_step <= 63;
		for(i=0; i<8; i=i+1) begin
			decoder_advance_trigger[i] <= (i == 32'd0) ? 1'b1 : 1'b0;
		end
	end
	  
	if (reset == 1'b0) begin
		major_step <= major_step + 6'd1;
		
	  // Enable and disable clocking for each voice at the right times
	  for(i=0; i<8; i=i+1) begin
		 // Start each voice at a predetermined time in the schedule. All voice logic
		 // is disabled at the end of the schedule and then the process repeats next
		 // schedule.
		 if(major_step == VOICE_RESUME[i][5:0]) begin
			decoder_advance_trigger[i] <= 1;
			current_voice <= i[2:0];
		 end

		 if(decoder_advance_trigger[i])
			decoder_advance_trigger[i] <= 0;
	  end

	  // DSP FSM logic
	  case (major_step)

		 6'd63: begin
			dac_out_l <= dac_sample_l[15:0];
			dac_out_r <= dac_sample_r[15:0];
		 end
		 default: begin end
	  endcase
	end
end
	  
endmodule