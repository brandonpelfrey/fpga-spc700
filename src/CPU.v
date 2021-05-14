/*
 * Implementation of the SPC700 CPU. Runs at double the frequency of the
 * original hardware.
 */
module CPU(
	/* Basic Control */
	clock, reset,

	/* Memory Access */
	out_ram_address, out_ram_write, in_ram_read, out_ram_write_enable,

	/* Debug */
	out_halted
);
	/*
	 * Inputs / Outputs
	 */
	input clock;
	input reset;
	output [15:0] out_ram_address;
	output [7:0] out_ram_write;
	input [7:0] in_ram_read;
	output out_ram_write_enable;
	output out_halted;

	/*
	 * Data: CPU Registers
	 */
	reg [7:0] A;   /* Accumulator */
	reg [7:0] X;   /* General Register */
	reg [7:0] Y;   /* General Register */
	reg [7:0] SP;  /* Stack Pointer */
	reg [15:0] PC; /* Fetch Address */
	reg [7:0] PSW; /* Status Register */

	/*
	 * For the status register, these are the individual flag positions.
	 */
	parameter PSW_N = 0, /* Negative */
	          PSW_V = 1, /* Overflow */
	          PSW_P = 2, /* Direct Page Selector */
	          PSW_B = 3, /* Break */
	          PSW_H = 4, /* Half Carry */
	          PSW_I = 5, /* Interrupt Enabled (unused) */
	          PSW_Z = 6, /* Zero */
	          PSW_C = 7; /* Carry */

	/*
	 * Data: CPU Pipeline
	 */
	reg       cpu_enable;   /* Enable CPU execution (for debugging) */
	reg [5:0] cpu_stage;    /* Pipeline Stage (one-hot encoding) */
	reg [7:0] cpu_data1;    /* Fetched second instruction byte */
	reg [7:0] cpu_data2;    /* Fetched third instruction byte */
	reg [7:0] cpu_source_a; /* Execute stage input field A */
	reg [7:0] cpu_source_b; /* Execute stage input field B */
	reg       cpu_carry;    /* Execute stage enable carry input */
	reg [3:0] cpu_alu_mode; /* ALU operation mode */
	reg [8:0] cpu_result;   /* Write stage output field */

	/*
	 * Control line bits for pipeline source and destinations.
	 */
	parameter CONTROL_A    = 0, /* "A" Register */
	          CONTROL_X    = 1, /* "X" Register */
	          CONTROL_Y    = 2, /* "Y" Register */
	          CONTROL_SP   = 3, /* "SP" Register */
	          CONTROL_PSW  = 4, /* "PSW" Register */
	          /* TODO Does PC need control lines? */
	          CONTROL_D1   = 5, /* Second Instruction Byte */
	          CONTROL_D2   = 6, /* Third Instruction Byte */
	          CONTROL_RAM  = 7, /* Memory */
	          CONTROL_NONE = 8; /* None */

	/*
	 * Control line bits for pipeline stage.
	 */
	parameter STAGE_FETCH   = 0, /* Instruction Fetch */
	          STAGE_DECODE  = 1, /* Instruction Decode / Parameter Fetch */
	          STAGE_PARAM   = 2, /* Second Parameter Fetch */
	          STAGE_COMPUTE = 3, /* Result Compute */
	          STAGE_WRITE   = 4, /* Write result to register / memory */
	          STAGE_DELAY   = 5; /* Delay to match original hardware */

	/*
	 * The correspondence from data control lines for ALU operations.
	 */
	parameter ALU_OR     = 0,
	          ALU_AND    = 1,
	          ALU_XOR    = 2,
	          ALU_ANDNOT = 3;
	          /* TODO */

	/* XXX */
	reg [15:0] ram_address;
	reg [7:0] ram_write;
	reg ram_write_enable;

	assign out_halted = ~cpu_enable;
	assign out_ram_address = ram_address;
	assign out_ram_write = ram_write;
	assign out_ram_write_enable = ram_write_enable;

	/*
	 * Implementation of the CPU pipeline. Pipeline stages may be skipped
	 * based on the decoded instruction.
	 *
	 * The delay stage ensures that the instructions are executed at the same
	 * speed as the original hardware. Since the actual SPC700 CPU takes a
	 * minimum of 2 cycles for every instruction, we always have enough time (at
	 * 2x speed) for the minimum 4 stages (fetch, decode, compute, write).
	 */
	always @(posedge clock)
	begin
		if (reset == 1'b1) begin
			cpu_enable <= 1'b1;
			cpu_stage <= (1 << STAGE_FETCH);
			cpu_data1 <= 0;
			cpu_data2 <= 0;
			cpu_source_a <= 0;
			cpu_source_b <= 0;
			cpu_result <= 0;

			/* XXX Cleanup with final RAM */
			ram_address <= 16'b0000_0000_0000_0000;
			ram_write <= 8'b0000_0000;
			ram_write_enable <= 1'b0;

			A <= 8'b0000_0000;
			X <= 8'b0000_0000;
			Y <= 8'b0000_0000;
			SP <= 8'b0000_0000;
			PC <= 16'b0000_0000_0000_0000;
			PSW <= 8'b0000_0000;
		end else if (cpu_enable == 1'b1) case (1'b1)
			/*
			 * Instruction Fetch
			 */
			cpu_stage[STAGE_FETCH]: begin
				/* Prepare to read the instruction from memory. Result will be
				 * visible on the RAM output in the decode stage. */
				ram_address <= PC;
				ram_write_enable <= 1'b0;

				cpu_stage <= (1 << STAGE_DECODE);
			end

			/*
			 * Decode and Parameter A Fetch
			 */
			cpu_stage[STAGE_DECODE]: begin
				/* Break the instruction down into a series of control lines
				 * that determine which stages will run and their
				 * configuration. */
				casez (in_ram_read)
					8'b???_010_00: begin
						/* ALU operation with immediate value */
						/* TODO This can probably have a common encoding
						 *      across many instruction types. */
						casez (in_ram_read)
							8'b000_???_??: begin
								/* OR */
								cpu_alu_mode <= ALU_OR;
							end

							8'b001_???_??: begin
								/* OR */
								cpu_alu_mode <= ALU_AND;
							end

							8'b010_???_??: begin
								/* OR */
								cpu_alu_mode <= ALU_XOR;
							end

							default: begin
								/* Unimplemented Decoding */
								cpu_enable <= 1'b0;
							end
						endcase

						cpu_stage <= (1 << STAGE_COMPUTE);
						cpu_source_a <= CONTROL_A;
						cpu_source_b <= CONTROL_D1;
						cpu_result <= CONTROL_A;
						ram_address <= PC + 1;
					end

					default: begin
						/* Unimplemented Decoding */
						cpu_enable <= 1'b0;
					end
				endcase
			end

			cpu_stage[STAGE_PARAM]: begin
				/* TODO Third instruction byte control lines */
				cpu_data1 <= in_ram_read;
				cpu_stage <= (1 << STAGE_COMPUTE);
			end

			cpu_stage[STAGE_COMPUTE]: begin
				cpu_stage <= (1 << STAGE_WRITE);
				A <= A + 1'b1;
				PC <= PC + 1'b1;
			end

			cpu_stage[STAGE_WRITE]: begin
				cpu_stage <= (1 << STAGE_DELAY);
			end

			cpu_stage[STAGE_DELAY]: begin
				cpu_stage <= (1 << STAGE_FETCH);
			end
		endcase
	end
endmodule
