/*
 * Test bench to expose the SPC700 CPU with 64KiB of RAM. Does not include the
 * DSP or any other hardware.
 */
module CPUBench(
	/* Basic Control */
	clock, reset,

	/* Test Control */
	in_cpu_enable,
	in_ram_address,
	in_ram_write,
	in_ram_write_enable,
	out_ram_read,

	/* Debug */
	out_halted
);
	/*
	 * Inputs / Outputs
	 */
	input         clock;
	input         reset;
	input         in_cpu_enable;
	input  [15:0] in_ram_address;
	input  [7:0]  in_ram_write;
	input         in_ram_write_enable;
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

	TestRAM ram(
		.address(in_cpu_enable ? ram_address : in_ram_address),
		.data_in(in_cpu_enable ? ram_write : in_ram_write),
		.data_out(ram_read),
		.clock(~clock),
		.write_enable(in_cpu_enable ? ram_write_enable : in_ram_write_enable));
endmodule
