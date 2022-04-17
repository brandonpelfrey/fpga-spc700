/*
 * XXX Temporary for testing
 */
module TestRAM(address, data_in, data_out, clock, write_enable);
	input [15:0] address;
	input [7:0] data_in;
	output reg [7:0] data_out;
	input clock;
	input write_enable;

	reg [7:0] memory [65535:0] /* verilator public */;

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
		end

		data_out <= memory[address];
	end

	//SB_RAM40_4K moo(.RADDR(address[10:0]), .RDATA(data_out), .RE(1'b1), .RCLK(clock), .RCLKE(1'b1));
endmodule
