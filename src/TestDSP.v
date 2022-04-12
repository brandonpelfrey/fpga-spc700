module TestDSP(
  input clock,
  input reset,
  output signed [15:0] dac_out_l,
  output signed [15:0] dac_out_r,

  input  [7:0] dsp_reg_address,
  input  [7:0] dsp_reg_data_in,
  output [7:0] dsp_reg_data_out,
  input        dsp_reg_write_enable,

  output [8*4-1:0] voice_states_out,

`ifdef DEBUG_DSP
  output [7:0] __debug_out_regs [127:0],
  output [15:0] __debug_voice_cursors [7:0],
  output signed [15:0] __debug_voice_output [7:0],
  output [15:0] __debug_voice_ram_address [7:0],
`endif

  output [15:0] ram_address,
  input [7:0] ram_data,
  output [5:0] major_step
);

// wire [15:0] address;
// wire [7:0] data;
wire write_enable;

// SPC700RAM ram(
//   .address(address),
//   .data(data),
//   .write_enable(write_enable),
//   .clock(clock)
// );

DSP dsp(
  .ram_address(ram_address),
  .ram_data(ram_data),
  .ram_write_enable(write_enable),

  .dsp_reg_address(dsp_reg_address),
  .dsp_reg_data_in(dsp_reg_data_in),
  .dsp_reg_data_out(dsp_reg_data_out),
  .dsp_reg_write_enable(dsp_reg_write_enable),

`ifdef DEBUG_DSP
  .__debug_out_regs(__debug_out_regs),
  .__debug_voice_cursors(__debug_voice_cursors),
  .__debug_voice_output(__debug_voice_output),
  .__debug_voice_ram_address(__debug_voice_ram_address),
`endif

  .clock(clock),
  .reset(reset),

  .dac_out_l(dac_out_l),
  .dac_out_r(dac_out_r),

  .voice_states_out(voice_states_out),
  .major_step(major_step)
);

endmodule
