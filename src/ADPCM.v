module ADPCM(
  input clock,
  input filter_type [1:0],
  input [2:0] samples_in [15:0],
  output sample_out [15:0],
);

wire [31:0] rbci32 = { {16{samples_in[0][15]}} , samples_in[0]};

// TODO : These have much simpler logic in terms of shift/add/sub.

wire signed [31:0] filter_0 = $signed(rbci32);

wire signed [31:0] filter_1 = $signed(rbci32) + $signed(samples_in[1]) * $signed(15) / $signed(16);

wire signed [31:0] filter_2 = $signed(rbci32) 
                                 + $signed(samples_in[1]) * $signed(61)  / $signed(32)
                                 + $signed(samples_in[2]) * $signed(-15) / $signed(16);

wire signed [31:0] filter_3 = $signed(rbci32) 
                                 + $signed(samples_in[1]) * $signed(115) / $signed(64) 
                                 + $signed(samples_in[2]) * $signed(-13) / $signed(16);

always @(posedge clock) begin
  case(filter_type) begin
    2'd0: sample_out <= filter_0[15:0];
    2'd1: sample_out <= filter_1[15:0];
    2'd2: sample_out <= filter_2[15:0];
    2'd3: sample_out <= filter_3[15:0];
  end
end

endmodule
