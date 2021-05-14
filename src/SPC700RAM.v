
module SPC700RAM(
  input [15:0] address,
  inout [7:0] data,
  input clock,
  input write_enable
);

parameter ADDRESS_BITS = 16;

reg [7:0] storage [(2**ADDRESS_BITS)-1:0];
assign data = write_enable ? storage[address] : 8'b0;

always @(posedge clock)
  if (write_enable)
    storage[address] <= data;

endmodule