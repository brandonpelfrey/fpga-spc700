module TestDSP(
  input clock,
  input reset,
  output signed [15:0] dac_out_l,
  output signed [15:0] dac_out_r,
  output idle,

  input  [7:0] dsp_reg_address,
  input  [7:0] dsp_reg_data_in,
  output [7:0] dsp_reg_data_out,
  input        dsp_reg_write_enable,

  output [8*4-1:0] voice_states_out,

  output [15:0] ram_address,
  input [7:0] ram_data
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

  .clock(clock),
  .reset(reset),
  .idle(idle),

  .dac_out_l(dac_out_l),
  .dac_out_r(dac_out_r),

  .voice_states_out(voice_states_out)
);

endmodule