/*
 * XXX Temporary for testing
 */
module TestRAM(address, data_in, data_out, clock, write_enable);
	input [15:0] address;
	input [7:0] data_in;
	output reg [7:0] data_out;
	input clock;
	input write_enable;

	reg [7:0] memory [65535:0];

	integer i;

	initial
	begin
		for (i = 0; i < 65536; i = i + 1) begin
			memory[i] = 0;
		end
	end

	always @(posedge clock)
	begin
		if (write_enable) begin
			memory[address] <= data_in;
		end else begin
			data_out <= memory[address];
		end
	end
endmodule
