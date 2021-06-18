
module SPC700RAM(
  input [15:0] address,
  inout [7:0] data,
  input clock,
  input write_enable
);

parameter ADDRESS_BITS = 16;
reg [7:0] storage [(2**ADDRESS_BITS)-1:0];

// TODO : Testing BRR Playback
initial $readmemh("../test_data/hk97.hex", storage);

assign data = write_enable ? storage[address] : 8'bz;

always @(posedge clock)
  if (write_enable)
    storage[address] <= data;

endmodule