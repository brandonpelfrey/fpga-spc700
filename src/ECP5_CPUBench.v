`include "CPU.v"
`include "TestRAM.v"

/*
 * Synthesizable module to expose the SPC700 CPU with ECP5 BRAM. Does not
 * include the DSP or any other hardware.
 */
module ECP5_CPUBench(
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
	// /*
	DP16KD
		#(
			.DATA_WIDTH_A(9))
		ram(
			.ADA0(ram_address[0]),
			.ADA1(ram_address[1]),
			.ADA2(ram_address[2]),
			.ADA3(ram_address[3]),
			.ADA4(ram_address[4]),
			.ADA5(ram_address[5]),
			.ADA6(ram_address[6]),
			.ADA7(ram_address[7]),
			.ADA8(ram_address[8]),
			.ADA9(ram_address[9]),
			.ADA10(ram_address[10]),
			.DIA0(ram_write[0]),
			.DIA1(ram_write[1]),
			.DIA2(ram_write[2]),
			.DIA3(ram_write[3]),
			.DIA4(ram_write[4]),
			.DIA5(ram_write[5]),
			.DIA6(ram_write[6]),
			.DIA7(ram_write[7]),
			.DOA0(ram_read[0]),
			.DOA1(ram_read[1]),
			.DOA2(ram_read[2]),
			.DOA3(ram_read[3]),
			.DOA4(ram_read[4]),
			.DOA5(ram_read[5]),
			.DOA6(ram_read[6]),
			.DOA7(ram_read[7]),
			.CLKA(clock),
			.CEA(1'b1),
			.OCEA(1'b1),
			.RSTA(reset),
			.WEA(ram_write_enable));
	// */

	/*
	TestRAM ram(
		.address(ram_address),
		.data_in(ram_write),
		.data_out(ram_read),
		.clock(clock),
		.write_enable(ram_write_enable));
	*/
endmodule
