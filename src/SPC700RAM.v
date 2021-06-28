
module SPC700RAM(
  input      [15:0] in_apu_address,
  input      [7:0]  in_apu_data,
  output reg [7:0]  out_apu_data,
  input             in_apu_we,
  
  input      [15:0] in_ctrl_address,
  input  reg [7:0]  in_ctrl_data,
  output     [7:0]  out_ctrl_data,
  input             in_ctrl_we,
  
  input clock
);

parameter ADDRESS_BITS = 16;
reg [7:0] storage [(2**ADDRESS_BITS)-1:0];

// TODO : Testing BRR Playback
// initial $readmemh("../test_data/hk97.hex", storage);

// APU Port
always @(posedge clock) begin
  out_apu_data <= storage[in_apu_address];
  if (in_apu_we)
    storage[in_apu_address] <= in_apu_data;
end

// Control Port
always @(posedge clock) begin
  out_ctrl_data <= storage[in_ctrl_address];
  if (in_ctrl_we)
    storage[in_ctrl_address] <= in_ctrl_data;
end
	 
endmodule