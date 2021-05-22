`include "CPU.v"

/*
 * Synthesizable module to expose the SPC700 CPU with Ice40 BRAM. Does not
 * include the DSP or any other hardware.
 */
module Ice40_CPUBench(
	/* Basic Control */
	clock,
	reset,

	/* Debug */
	out_address,
	out_halted
);
	/*
	 * Inputs / Outputs
	 */
	input         clock;
	input         reset;
	output [15:0] out_address;
	output        out_halted;

	/*
	 * Module Connections
	 */
	wire [15:0] ram_address;
	wire [7:0] ram_write;
	wire [7:0] ram_read;
	wire ram_write_enable;

	/*
	 * Export RAM address. This prevents the entire CPU from being optimized
	 * away by yosys.
	 */
	assign out_address = ram_address;

	CPU cpu(
		.clock(clock),
		.reset(reset),
		.out_ram_address(ram_address),
		.out_ram_write(ram_write),
		.in_ram_read(ram_read),
		.out_ram_write_enable(ram_write_enable),
		.out_halted(out_halted));

	/* TODO This instantiates only 512 bytes of usable memory */
	SB_RAM40_4K
		#(
			.WRITE_MODE(1),
			.READ_MODE(1))
		ram(
			.RADDR(ram_address[8:0]),
			.RDATA(ram_read),
			.RE(1'b1),
			.RCLK(clock),
			.RCLKE(1'b1),
			.WADDR(ram_address[8:0]),
			.WDATA(ram_write),
			.WE(ram_write_enable),
			.WCLK(clock),
			.WCLKE(1'b1));
endmodule
