`include "CPU.v"
`include "TestRAM.v"

/*
 * Test bench to expose the SPC700 CPU with 64KiB of RAM. Does not include the
 * DSP or any other hardware.
 */
module CPUBench(
	/* Basic Control */
	clock, reset,

	/* Test Control */
	out_ram_read,

	/* Debug */
	out_halted
);
	/*
	 * Inputs / Outputs
	 */
	input         clock;
	input         reset;
	output [7:0]  out_ram_read;
	output        out_halted;

	/*
	 * Module Connections
	 */
	wire [15:0] ram_address;
	wire [7:0] ram_write;
	wire [7:0] ram_read;
	wire ram_write_enable;

	assign out_ram_read = ram_read;

	CPU cpu(
		.clock(clock),
		.reset(reset),
		.out_ram_address(ram_address),
		.out_ram_write(ram_write),
		.in_ram_read(ram_read),
		.out_ram_write_enable(ram_write_enable),
		.out_halted(out_halted));

	TestRAM ram (
		.address(ram_address),
		.data_in(ram_write),
		.data_out(ram_read),
		.clock(clock),
		.write_enable(ram_write_enable));
endmodule
