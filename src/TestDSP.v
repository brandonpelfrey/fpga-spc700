module TestDSP(
  input clock,
  input reset,
  output [15:0] audio_output,
  output idle
);

reg audio_valid;

wire [15:0] address;
wire [7:0] data;
wire write_enable;

SPC700RAM ram(
  .address(address),
  .data(data),
  .write_enable(write_enable),
  .clock(clock)
);

DSP dsp(
  .ram_address(address),
  .ram_data(data),
  .ram_write_enable(write_enable),
  .clock(clock),
  .reset(reset),
  .idle(idle),
  .audio_valid(audio_valid),
  .audio_output(audio_output)
);

endmodule