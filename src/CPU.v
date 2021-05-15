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
	reg [7:0] R [7:0]; /* Register File */
	reg [15:0] PC;     /* Program Counter */

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
	reg       enable;         /* Enable CPU execution (for debugging) */
	reg [6:0] stage;          /* Pipeline Stage (one-hot encoding) */
	reg [1:0] decode_bytes;   /* Instruction encoding bytes */
	reg [7:0] source_a_mode;  /* Execute: input field A mode */
	reg [2:0] source_a_index; /* Execute: input field A register index */
	reg [7:0] source_b_mode;  /* Execute: input field B mode */
	reg [2:0] source_b_index; /* Execute: input field B register index */
	reg       source_b_imm;   /* Execute: input field B select source_imm */
	reg       source_carry;   /* Execute: input carry bit */
	reg [7:0] source_imm;     /* Execute: instruction-inferred immediate */
	reg [7:0] result_mode;    /* Result output mode */
	reg [2:0] result_index;   /* Result output register index */
	reg [7:0] result;         /* Data output from compute stage */
	reg [7:0] status;         /* Status output from compute stage */
	reg [7:0] alu_mode;       /* ALU operation mode */

	/*
	 * Indexes for the internal register file.
	 *
	 * Because registers are not remapped, this is a combination of real CPU
	 * registers and internal temporary registers. Placing them in the same
	 * structure simplifies the implementation.
	 *
	 * TODO Only one stage(s) should read, and one stage(s) should write, to
	 *      the register file.
	 *
	 * Note: PC is special cased becasue it is the only 16-bit register.
	 */
	parameter REGISTER_A    = 0, /* "A" Register */
	          REGISTER_X    = 1, /* "X" Register */
	          REGISTER_Y    = 2, /* "Y" Register */
	          REGISTER_SP   = 3, /* "SP" Register */
	          REGISTER_PSW  = 4, /* "PSW" Register */
	          REGISTER_D1   = 5, /* Virtual register 1 for immediates */
	          REGISTER_D2   = 6, /* Virtual register 2 for immediates */
	          REGISTER_NULL = 7; /* Zero register */

	/*
	 * Control line bits for pipeline source and destination modes.
	 */
	/* TODO Does PC need control lines? */
	parameter DATA_R        = 0, /* Register file */
	          DATA_RAM      = 1; /* Memory */

	/*
	 * Control line bits for pipeline stage.
	 */
	parameter STAGE_FETCH   = 0, /* Instruction Fetch */
	          STAGE_DECODE  = 1, /* Instruction Decode */
	          STAGE_PARAM1  = 2, /* Second Parameter (byte) Fetch */
	          STAGE_PARAM2  = 3, /* Third Parameter (byte) Fetch */
	          STAGE_COMPUTE = 4, /* Result Compute */
	          STAGE_WRITE   = 5, /* Write result to register / memory */
	          STAGE_DELAY   = 6; /* Delay to match original hardware */

	/*
	 * The correspondence from data control lines for ALU operations.
	 */
	parameter ALU_OR     = 0,
	          ALU_AND    = 1,
	          ALU_XOR    = 2,
	          ALU_ANDNOT = 3,
	          ALU_ADD    = 4,
	          ALU_SUB    = 5,
	          ALU_NONE_A = 6,
	          ALU_NONE_B = 7;
	          /* TODO */

	/* XXX */
	reg [15:0] ram_address;
	reg [7:0] ram_write;
	reg ram_write_enable;

	assign out_halted = ~enable;
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

	/*
	 * Reset Logic
	 */
	always @(posedge clock)
	begin
		if (reset == 1'b1) begin
			enable <= 1'b1;
			stage <= (1 << STAGE_FETCH);
			decode_bytes <= 0;
			source_a_mode <= 0;
			source_a_index <= 0;
			source_b_mode <= 0;
			source_b_index <= 0;
			source_b_imm <= 0;
			source_carry <= 0;
			source_imm <= 0;
			result_mode <= 0;
			result_index <= 0;
			result <= 0;
			status <= 0;
			alu_mode <= 0;

			/* XXX Cleanup with final RAM */
			ram_address <= 16'b0000_0000_0000_0000;
			ram_write <= 8'b0000_0000;
			ram_write_enable <= 1'b0;

			R[REGISTER_A] <= 8'b0000_0000;
			R[REGISTER_X] <= 8'b0000_0000;
			R[REGISTER_Y] <= 8'b0000_0000;
			R[REGISTER_SP] <= 8'b0000_0000;
			R[REGISTER_PSW] <= 8'b0000_0000;
			R[REGISTER_NULL] <= 8'b0000_0000;
			PC <= 16'b0000_0000_0000_0000;
		end
	end

	/*
	 * Instruction Fetch
	 */
	always @(posedge clock)
	begin
		if (enable == 1'b1 && stage[STAGE_FETCH]) begin
			/* Prepare to read the instruction from memory. Result will be
			 * visible on the RAM output in the decode stage. */
			ram_address <= PC;
			ram_write_enable <= 1'b0;

			stage <= (1 << STAGE_DECODE);
		end
	end

	/*
	 * Instruction Decode
	 */
	/* TODO Convert decode to always @(*) / wire logic */
	always @(posedge clock)
	begin
		if (enable == 1'b1 && stage[STAGE_DECODE]) begin
			/* Break the instruction down into a series of control lines
			 * that determine which stages will run and their
			 * configuration. */
			casez (in_ram_read)
				8'b???_000_00: begin
					/* Status register operations. */
					casez (in_ram_read)
						8'b000_???_??: begin
							/* NOP */
							alu_mode <= (1 << ALU_NONE_A);
							source_a_index <= REGISTER_D1;
							result_index <= REGISTER_D1; /* Unused */
						end

						8'b001_???_??: begin
							/* CLP: PSW_P = 0 */
							alu_mode <= (1 << ALU_ANDNOT);
							source_a_index <= REGISTER_PSW;
							source_imm <= (1 << PSW_P);
							result_index <= REGISTER_PSW;
						end

						8'b010_???_??: begin
							/* SEP: PSW_P = 1 */
							alu_mode <= (1 << ALU_OR);
							source_a_index <= REGISTER_PSW;
							source_imm <= (1 << PSW_P);
							result_index <= REGISTER_PSW;
						end

						8'b011_???_??: begin
							/* CLC: PSW_C = 0 */
							alu_mode <= (1 << ALU_ANDNOT);
							source_a_index <= REGISTER_PSW;
							source_imm <= (1 << PSW_C);
							result_index <= REGISTER_PSW;
						end

						8'b100_???_??: begin
							/* SEC: PSW_C = 1 */
							alu_mode <= (1 << ALU_OR);
							source_a_index <= REGISTER_PSW;
							source_imm <= (1 << PSW_C);
							result_index <= REGISTER_PSW;
						end

						8'b101_???_??: begin
							/* CLI: PSW_I = 0 */
							alu_mode <= (1 << ALU_ANDNOT);
							source_a_index <= REGISTER_PSW;
							source_imm <= (1 << PSW_I);
							result_index <= REGISTER_PSW;
						end

						8'b110_???_??: begin
							/* SEI: PSW_I = 1 */
							alu_mode <= (1 << ALU_OR);
							source_a_index <= REGISTER_PSW;
							source_imm <= (1 << PSW_I);
							result_index <= REGISTER_PSW;
						end

						8'b111_???_??: begin
							/* CLV: PSW_V = 0 */
							alu_mode <= (1 << ALU_ANDNOT);
							source_a_index <= REGISTER_PSW;
							source_imm <= (1 << PSW_V);
							result_index <= REGISTER_PSW;
						end
					endcase

					stage <= (1 << STAGE_COMPUTE);
					decode_bytes <= 1;
					source_a_mode <= DATA_R;
					source_b_mode <= DATA_R;
					source_b_imm <= 1;
					result_mode <= DATA_R;
				end

				8'b???_010_00: begin
					/* ALU operation with immediate value */
					/* TODO This can probably have a common encoding
					 *      across many instruction types. */
					casez (in_ram_read)
						8'b000_???_??: begin
							/* ORA: A = A | #i */
							alu_mode <= (1 << ALU_OR);
							source_a_index <= REGISTER_A;
							result_index <= REGISTER_A;
						end

						8'b001_???_??: begin
							/* AND: A = A & #i */
							alu_mode <= (1 << ALU_AND);
							source_a_index <= REGISTER_A;
							result_index <= REGISTER_A;
						end

						8'b010_???_??: begin
							/* EORA: A = A ^ #i */
							alu_mode <= (1 << ALU_XOR);
							source_a_index <= REGISTER_A;
							result_index <= REGISTER_A;
						end

						8'b011_???_??: begin
							/* CMP: A - #i */
							alu_mode <= (1 << ALU_SUB);
							source_a_index <= REGISTER_A;
							result_index <= REGISTER_D1; /* Unused */
						end

						8'b100_???_??: begin
							/* ADC: A = A + #i + c */
							alu_mode <= (1 << ALU_ADD);
							source_a_index <= REGISTER_A;
							result_index <= REGISTER_A;
						end

						8'b101_???_??: begin
							/* SBC: A = A - #i - !c */
							alu_mode <= (1 << ALU_SUB);
							source_a_index <= REGISTER_A;
							result_index <= REGISTER_A;
						end

						8'b110_???_??: begin
							/* CPX: X - #i */
							alu_mode <= (1 << ALU_SUB);
							source_a_index <= REGISTER_X;
							result_index <= REGISTER_D1; /* Unused */
						end

						8'b111_???_??: begin
							/* LDA: A = #i */
							alu_mode <= (1 << ALU_NONE_B);
							source_a_index <= REGISTER_A;
							result_index <= REGISTER_A;
						end
					endcase

					stage <= (1 << STAGE_PARAM1);
					decode_bytes <= 2;
					source_a_mode <= DATA_R;
					source_b_mode <= DATA_R;
					source_b_index <= REGISTER_D1;
					source_b_imm <= 0;
					result_mode <= DATA_R;
				end

				8'b111_111_11: begin
					/* HLT */
					enable <= 1'b0;
				end

				default: begin
					/* Unimplemented Decoding */
					enable <= 1'b0;
				end
			endcase

			/* Always prepare to fetch next address, possibly unused. */
			ram_address <= PC + 1;
		end
	end

	/*
	 * Parameter 1 Fetch (optional)
	 */
	always @(posedge clock)
	begin
		/* TODO This could easily be combined with decode, but this simplifies
		 *      the code a little for now. */
		if (enable == 1'b1 && stage[STAGE_PARAM1]) begin
			R[REGISTER_D1] <= in_ram_read;
			if (decode_bytes == 2) begin
				stage <= (1 << STAGE_COMPUTE);
			end else begin
				stage <= (1 << STAGE_PARAM2);
				ram_address <= PC + 2;
			end
		end
	end

	/*
	 * Parameter 2 Fetch (optional)
	 */
	always @(posedge clock)
	begin
		if (enable == 1'b1 && stage[STAGE_PARAM2]) begin
			R[REGISTER_D2] <= in_ram_read;
			stage <= (1 << STAGE_COMPUTE);
		end
	end

	wire [7:0] source_a = R[source_a_index];
	wire [7:0] source_b = source_b_imm == 1'b1 ? source_imm : R[source_b_index];

	/*
	 * Result Computation
	 */
	always @(posedge clock)
	begin
		if (enable == 1'b1 && stage[STAGE_COMPUTE]) begin
			case (1'b1)
				alu_mode[ALU_OR]: begin
					result <= source_a | source_b;
				end

				alu_mode[ALU_AND]: begin
					result <= source_a & source_b;
				end

				alu_mode[ALU_XOR]: begin
					result <= source_a ^ source_b;
				end

				alu_mode[ALU_ANDNOT]: begin
					result <= source_a & ~source_b;
				end

				alu_mode[ALU_ADD]: begin
					result <= source_a + source_b + { 7'b000_0000, source_carry };
				end

				alu_mode[ALU_SUB]: begin
					result <= source_a - source_b - { 7'b000_0000, source_carry };
				end

				alu_mode[ALU_NONE_A]: begin
					result <= source_a;
				end

				alu_mode[ALU_NONE_B]: begin
					result <= source_b;
				end

				default: begin
					/* Unimplemented Decoding */
					enable <= 1'b0;
				end
			endcase

			stage <= (1 << STAGE_WRITE);
		end
	end

	/*
	 * Write-Back (register or memory)
	 */
	always @(posedge clock)
	begin
		if (enable == 1'b1 && stage[STAGE_WRITE]) begin
			R[result_index] <= result;

			PC <= PC + { 14'b00_0000_0000_0000, decode_bytes };
			stage <= (1 << STAGE_DELAY);
		end
	end

	/*
	 * Delay (optional, to match original hardware)
	 */
	always @(posedge clock)
	begin
		if (enable == 1'b1 && stage[STAGE_DELAY]) begin
			stage <= (1 << STAGE_FETCH);
		end
	end
endmodule
