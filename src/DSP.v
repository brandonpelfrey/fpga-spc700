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

  `ifdef DEBUG_DSP
    __debug_out_regs,
    __debug_voice_cursors,
    __debug_voice_output,
    __debug_voice_ram_address,
  `endif

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

// 128 registers.
localparam [6:0] REG_VOLL   [7:0] = '{7'h00,7'h10,7'h20,7'h30,7'h40,7'h50,7'h60,7'h70};
localparam [6:0] REG_VOLR   [7:0] = '{7'h01,7'h11,7'h21,7'h31,7'h41,7'h51,7'h61,7'h71};
localparam [6:0] REG_PL     [7:0] = '{7'h02,7'h12,7'h22,7'h32,7'h42,7'h52,7'h62,7'h72};
localparam [6:0] REG_PH     [7:0] = '{7'h03,7'h13,7'h23,7'h33,7'h43,7'h53,7'h63,7'h73};
localparam [6:0] REG_SRCN   [7:0] = '{7'h04,7'h14,7'h24,7'h34,7'h44,7'h54,7'h64,7'h74};
localparam [6:0] REG_ADSR1  [7:0] = '{7'h05,7'h15,7'h25,7'h35,7'h45,7'h55,7'h65,7'h75};
localparam [6:0] REG_ADSR2  [7:0] = '{7'h06,7'h16,7'h26,7'h36,7'h46,7'h56,7'h66,7'h76};
localparam [6:0] REG_GAIN   [7:0] = '{7'h07,7'h17,7'h27,7'h37,7'h47,7'h57,7'h67,7'h77};
localparam [6:0] REG_ENVX   [7:0] = '{7'h08,7'h18,7'h28,7'h38,7'h48,7'h58,7'h68,7'h78};
localparam [6:0] REG_OUTX   [7:0] = '{7'h09,7'h19,7'h29,7'h39,7'h49,7'h59,7'h69,7'h79};
localparam [6:0] REG_MVOLL  = 7'h0c;
localparam [6:0] REG_EFB    = 7'h0d;
localparam [6:0] REG_COEF   [7:0] = '{7'h0f,7'h1f,7'h2f,7'h3f,7'h4f,7'h5f,7'h6f,7'h7f};
localparam [6:0] REG_MVOLR  = 7'h1c;
localparam [6:0] REG_EVOLL  = 7'h2c;
localparam [6:0] REG_PMON   = 7'h2d;
localparam [6:0] REG_EVOLR  = 7'h3c;
localparam [6:0] REG_NON    = 7'h3d;
localparam [6:0] REG_KON    = 7'h4c;
localparam [6:0] REG_EON    = 7'h4d;
localparam [6:0] REG_KOF    = 7'h5c;
localparam [6:0] REG_DIR    = 7'h5d;
localparam [6:0] REG_FLG    = 7'h6c;
localparam [6:0] REG_ESA    = 7'h6d;
localparam [6:0] REG_ENDX   = 7'h7c;
localparam [6:0] REG_EDL    = 7'h7d;

`ifdef DEBUG_DSP
output [7:0] __debug_out_regs [127:0];
output [15:0] __debug_voice_cursors [7:0];
output signed [15:0] __debug_voice_output [7:0];
output [15:0] __debug_voice_ram_address [7:0];
`endif

///////////////////////////////////////////////////////////////////////////////
// DSP Registers

reg [7:0] _regs   [127:0];           // ALL REGS!

`ifdef DEBUG_DSP
assign __debug_out_regs = _regs;
generate
for(gi=0; gi<8; gi+=1) begin:gen_debout_outputs
  assign __debug_voice_output[gi] = decoder_output[gi];
  assign __debug_voice_cursors[gi] = decoder_cursor[gi];
  assign __debug_voice_ram_address[gi] = decoder_ram_address[gi];
end
endgenerate
`endif

/////////////////////////////////////////////
// Register read/write logic
reg [7:0] reg_data_out;
assign dsp_reg_data_out = reg_data_out;

// Read reg
assign reg_data_out = _regs[ dsp_reg_address[6:0] ];

// Register resets
generate
for(gi=0; gi<128; gi+=1) begin:register_write_reset
  always @(posedge clock) begin
    if(reset) begin
      _regs[gi] <= 8'b0;
    end
  end
end
endgenerate

// Register writes
always @(posedge clock) begin
  if(!reset && dsp_reg_write_enable) begin // from outside
    _regs[ dsp_reg_address[6:0] ] <= dsp_reg_data_in;
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
for(gi=0; gi<8; gi=gi+1) begin:decoder_input_assignments
  //  14 bit decoder pitch = {Pitch High              , Pitch Low               }
  assign decoder_pitch[gi] = {_regs[ REG_PH[gi] ][5:0], _regs[ REG_PL[gi] ][7:0]};  //{VxPH[gi][5:0], VxPL[gi][7:0]};
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
  .start_address( 16'b0 ), // TODO
  .loop_address( 16'b0 ), // TODO
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
  dac_sample_l =                $signed(decoder_output[0]) * $signed(_regs[REG_VOLL[0]]);
  dac_sample_l = dac_sample_l + $signed(decoder_output[1]) * $signed(_regs[REG_VOLL[1]]); 
  dac_sample_l = dac_sample_l + $signed(decoder_output[2]) * $signed(_regs[REG_VOLL[2]]);
  dac_sample_l = dac_sample_l + $signed(decoder_output[3]) * $signed(_regs[REG_VOLL[3]]);
  dac_sample_l = dac_sample_l + $signed(decoder_output[4]) * $signed(_regs[REG_VOLL[4]]);
  dac_sample_l = dac_sample_l + $signed(decoder_output[5]) * $signed(_regs[REG_VOLL[5]]);
  dac_sample_l = dac_sample_l + $signed(decoder_output[6]) * $signed(_regs[REG_VOLL[6]]);
  dac_sample_l = dac_sample_l + $signed(decoder_output[7]) * $signed(_regs[REG_VOLL[7]]);
  dac_sample_l = dac_sample_l >>> 7;

  dac_sample_l = (dac_sample_l * $signed( _regs[REG_MVOLL] )) >>> 7;

  dac_sample_r =                $signed(decoder_output[0]) * $signed(_regs[REG_VOLR[0]]);
  dac_sample_r = dac_sample_r + $signed(decoder_output[1]) * $signed(_regs[REG_VOLR[1]]);
  dac_sample_r = dac_sample_r + $signed(decoder_output[2]) * $signed(_regs[REG_VOLR[2]]);
  dac_sample_r = dac_sample_r + $signed(decoder_output[3]) * $signed(_regs[REG_VOLR[3]]);
  dac_sample_r = dac_sample_r + $signed(decoder_output[4]) * $signed(_regs[REG_VOLR[4]]);
  dac_sample_r = dac_sample_r + $signed(decoder_output[5]) * $signed(_regs[REG_VOLR[5]]);
  dac_sample_r = dac_sample_r + $signed(decoder_output[6]) * $signed(_regs[REG_VOLR[6]]);
  dac_sample_r = dac_sample_r + $signed(decoder_output[7]) * $signed(_regs[REG_VOLR[7]]);
  dac_sample_r = dac_sample_r >>> 7;

  dac_sample_r = (dac_sample_r * $signed(_regs[REG_MVOLL])) >>> 7;
end

reg [2:0] current_voice /* verilator public */;
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
