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
	 * Data: CPU Pipeline, organized by the writing stage.
	 */
	reg       enable;         /* Enable CPU execution (for debugging) */
	reg [6:0] stage;          /* Pipeline Stage (one-hot encoding) */
	reg [7:0] old_status;     /* Fetch:   Value of PSW at start of instruction */
	reg [1:0] bytes;          /* Decode:  Instruction encoding bytes */
	reg [1:0] source_a_fetch; /* Decode:  Input field A is a fetched immediate */
	reg       source_a_load;  /* Decode:  Input field A is a load address */
	reg [7:0] source_a_mode;  /* Decode:  Input field A mode */
	reg [7:0] source_a;       /* Decode:  Input field A value */
	reg [1:0] source_b_fetch; /* Decode:  Input field B is a fetched immediate */
	reg       source_b_load;  /* Decode:  Input field B is a load address */
	reg [7:0] source_b_mode;  /* Decode:  Input field B mode */
	reg [7:0] source_b;       /* Decode:  Input field B value */
	reg       source_carry;   /* Decode:  Input carry bit */
	reg [7:0] result_mode;    /* Decode:  Result output mode */
	reg [2:0] result_index;   /* Decode:  Result output register index */
	reg [7:0] status_mask;    /* Decode:  Update mask for status register */
	reg [7:0] alu_mode;       /* Decode:  ALU operation mode */
	reg       branch;         /* Decode:  Branch instruction */
	reg [7:0] result;         /* Compute: Data result from compute stage */
	reg [7:0] status;         /* Compute: Status output from compute stage */

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
	parameter DATA_R        = 0, /* Register file */
	          DATA_IMM      = 1; /* Decoder-generated immediate */

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

	reg test;

	/**************************************************************************
	 * Instruction Decoding Implementation
	 **************************************************************************/

	/*
	 * Logic outputs from the decoder logic
	 */
	logic [1:0] decode_source_a_fetch; /* Input field A fetch from immediate */
	logic       decode_source_a_load;  /* Input field A load from RAM */
	logic [7:0] decode_source_a_mode;  /* Input field A mode */
	logic [2:0] decode_source_a_index; /* Input field A register index */
	logic [7:0] decode_source_a_imm;   /* Input field A immediate value */

	logic [1:0] decode_source_b_fetch; /* Input field B fetch from immediate */
	logic       decode_source_b_load;  /* Input field B load from RAM */
	logic [7:0] decode_source_b_mode;  /* Input field B mode */
	logic [2:0] decode_source_b_index; /* Input field B register index */
	logic [7:0] decode_source_b_imm;   /* Input field B immediate value */

	logic       decode_source_carry;   /* Input carry bit */
	logic [7:0] decode_result_mode;    /* Result output mode */
	logic [2:0] decode_result_index;   /* Result output register index */
	logic [7:0] decode_status_mask;    /* Update mask for status register */
	logic [7:0] decode_alu_mode;       /* ALU operation mode */
	logic [1:0] decode_bytes;          /* Instruction byte length */
	logic       decode_branch;         /* Branch instruction */
	logic [6:0] decode_stage;          /* Next pipeline stage */
	logic       decode_error;          /* Invalid instruction */

	/*
	 *
	 */
	always @(*)
	begin
		decode_source_a_fetch = 2'b00;
		decode_source_a_load = 1'b0;
		decode_source_a_mode = DATA_R;
		decode_source_a_index = REGISTER_A;
		decode_source_a_imm = 8'b0000_0000;

		decode_source_b_fetch = 2'b00;
		decode_source_b_load = 1'b0;
		decode_source_b_mode = DATA_R;
		decode_source_b_index = REGISTER_A;
		decode_source_b_imm = 8'b0000_0000;

		decode_source_carry = 1'b0;
		decode_result_mode = DATA_R;
		decode_result_index = REGISTER_A;
		decode_status_mask = 8'b0000_0000;
		decode_alu_mode = 8'b0000_0000;

		decode_bytes = 2'd1;
		decode_branch = 1'b0;
		decode_stage = (1 << STAGE_COMPUTE);
		decode_error = 1'b0;

		/* Instructions are grouped by similarity in the decoding logic by
		 * splitting the 8 bits into three sections: XXX_YYY_ZZ. Instructions
		 * with matching YYY_ZZ portions are similar. YYY refers to the column
		 * here and ZZ is the column set, e.g. B3 is column 3 set B. */
		case (in_ram_read)
			/*
			 * Column A1: Status control
			 */
			8'b000_000_00: begin
				/* NOP */
				decode_alu_mode = (1 << ALU_NONE_A);
				decode_source_b_index = REGISTER_D1;
				decode_result_index = REGISTER_D1; /* Unused */
			end

			8'b001_000_00: begin
				/* CLP: PSW_P = 0 */
				decode_alu_mode = (1 << ALU_AND);
				decode_source_a_index = REGISTER_PSW;
				decode_source_b_mode = DATA_IMM;
				decode_source_b_imm = ~(1 << PSW_P);
				decode_result_index = REGISTER_PSW;
			end

			8'b010_000_00: begin
				/* SEP: PSW_P = 1 */
				decode_alu_mode = (1 << ALU_OR);
				decode_source_a_index = REGISTER_PSW;
				decode_source_b_mode = DATA_IMM;
				decode_source_b_imm = (1 << PSW_P);
				decode_result_index = REGISTER_PSW;
			end

			8'b011_000_00: begin
				/* CLC: PSW_C = 0 */
				decode_alu_mode = (1 << ALU_AND);
				decode_source_a_index = REGISTER_PSW;
				decode_source_b_mode = DATA_IMM;
				decode_source_b_imm = ~(1 << PSW_C);
				decode_result_index = REGISTER_PSW;
			end

			8'b100_000_00: begin
				/* SEC: PSW_C = 1 */
				decode_alu_mode = (1 << ALU_OR);
				decode_source_a_index = REGISTER_PSW;
				decode_source_b_mode = DATA_IMM;
				decode_source_b_imm = (1 << PSW_C);
				decode_result_index = REGISTER_PSW;
			end

			8'b101_000_00: begin
				/* CLI: PSW_I = 0 */
				decode_alu_mode = (1 << ALU_AND);
				decode_source_a_index = REGISTER_PSW;
				decode_source_b_mode = DATA_IMM;
				decode_source_b_imm = ~(1 << PSW_I);
				decode_result_index = REGISTER_PSW;
			end

			8'b110_000_00: begin
				/* SEI: PSW_I = 1 */
				decode_alu_mode = (1 << ALU_OR);
				decode_source_a_index = REGISTER_PSW;
				decode_source_b_mode = DATA_IMM;
				decode_source_b_imm = (1 << PSW_I);
				decode_result_index = REGISTER_PSW;
			end

			8'b111_000_00: begin
				/* CLV: PSW_V = 0 */
				decode_alu_mode = (1 << ALU_AND);
				decode_source_a_index = REGISTER_PSW;
				decode_source_b_mode = DATA_IMM;
				decode_source_b_imm = ~(1 << PSW_V);
				decode_result_index = REGISTER_PSW;
			end

			/*
			 * Column A2: Conditional Relative Branch
			 */

			/*
			 * Column A3: Immediate Logical Operations
			 *
			 * TODO Status register mask
			 */
			8'b000_010_00: begin
				/* ORA: A = A | #i */
				decode_alu_mode = (1 << ALU_OR);
				decode_source_a_index = REGISTER_A;
				decode_source_b_fetch = 2'b01;
				decode_result_index = REGISTER_A;
				decode_stage = (1 << STAGE_PARAM1);
				decode_bytes = 2'd2;
			end

			8'b001_010_00: begin
				/* AND: A = A & #i */
				decode_alu_mode = (1 << ALU_AND);
				decode_source_a_index = REGISTER_A;
				decode_source_b_fetch = 2'b01;
				decode_result_index = REGISTER_A;
				decode_stage = (1 << STAGE_PARAM1);
				decode_bytes = 2'd2;
			end

			8'b010_010_00: begin
				/* EORA: A = A ^ #i */
				decode_alu_mode = (1 << ALU_XOR);
				decode_source_a_index = REGISTER_A;
				decode_source_b_fetch = 2'b01;
				decode_result_index = REGISTER_A;
				decode_stage = (1 << STAGE_PARAM1);
				decode_bytes = 2'd2;
			end

			8'b011_010_00: begin
				/* CMP: A - #i */
				decode_alu_mode = (1 << ALU_SUB);
				decode_source_a_index = REGISTER_A;
				decode_source_b_fetch = 2'b01;
				decode_result_index = REGISTER_D1; /* Unused */
				decode_stage = (1 << STAGE_PARAM1);
				decode_bytes = 2'd2;
			end

			8'b100_010_00: begin
				/* ADC: A = A + #i + c */
				decode_alu_mode = (1 << ALU_ADD);
				decode_source_a_index = REGISTER_A;
				decode_source_b_fetch = 2'b01;
				decode_result_index = REGISTER_A;
				decode_stage = (1 << STAGE_PARAM1);
				decode_bytes = 2'd2;
			end

			8'b101_010_00: begin
				/* SBC: A = A - #i - !c */
				decode_alu_mode = (1 << ALU_SUB);
				decode_source_a_index = REGISTER_A;
				decode_source_b_fetch = 2'b01;
				decode_result_index = REGISTER_A;
				decode_stage = (1 << STAGE_PARAM1);
				decode_bytes = 2'd2;
			end

			8'b110_010_00: begin
				/* CPX: X - #i */
				decode_alu_mode = (1 << ALU_SUB);
				decode_source_a_index = REGISTER_X;
				decode_source_b_fetch = 2'b01;
				decode_result_index = REGISTER_D1; /* Unused */
				decode_stage = (1 << STAGE_PARAM1);
				decode_bytes = 2'd2;
			end

			8'b111_010_00: begin
				/* LDA: A = #i */
				decode_alu_mode = (1 << ALU_NONE_A);
				decode_source_a_fetch = 2'b01;
				decode_result_index = REGISTER_A;
				decode_stage = (1 << STAGE_PARAM1);
				decode_bytes = 2'd2;
			end

			default: begin
				decode_error = 1'b1;
			end
		endcase
	end

	/**************************************************************************
	 * Pipeline Implementation
	 **************************************************************************/

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
			old_status <= 0;
			bytes <= 0;

			source_a_fetch <= 0;
			source_a_load <= 0;
			source_a_mode <= 0;
			source_a <= 0;

			source_b_fetch <= 0;
			source_b_load <= 0;
			source_b_mode <= 0;
			source_b <= 0;

			source_carry <= 0;
			result_mode <= 0;
			result_index <= 0;
			status_mask <= 0;
			alu_mode <= 0;

			branch <= 0;
			result <= 0;
			status <= 0;

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
			old_status <= R[REGISTER_PSW];

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
			source_a_fetch <= decode_source_a_fetch;
			source_a_load <= decode_source_a_load;
			source_a_mode <= decode_source_a_mode;
			case (decode_source_a_mode)
				DATA_R: begin
					source_a <= R[decode_source_a_index];
				end

				DATA_IMM: begin
					source_a <= decode_source_a_imm;
				end
			endcase

			source_b_fetch <= decode_source_b_fetch;
			source_b_load <= decode_source_b_load;
			source_b_mode <= decode_source_b_mode;
			case (decode_source_b_mode)
				DATA_R: begin
					source_b <= R[decode_source_b_index];
				end

				DATA_IMM: begin
					source_b <= decode_source_b_imm;
				end
			endcase

			source_carry <= decode_source_carry;
			result_mode <= decode_result_mode;
			result_index <= decode_result_index;
			status_mask <= decode_status_mask;
			alu_mode <= decode_alu_mode;
			bytes <= decode_bytes;
			branch <= decode_branch;
			enable <= ~decode_error;
			stage <= decode_stage;

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
			if (source_a_fetch[0]) begin
				source_a <= in_ram_read;
			end

			if (source_b_fetch[0]) begin
				source_b <= in_ram_read;
			end

			if (bytes == 2) begin
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
			if (source_a_fetch[1]) begin
				source_a <= in_ram_read;
			end

			if (source_b_fetch[1]) begin
				source_b <= in_ram_read;
			end

			stage <= (1 << STAGE_COMPUTE);
		end
	end

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

			/* Branches are relative to the start of the following
			 * instruction. So this logic always applies even with branching. */
			PC <= PC + { 14'b00_0000_0000_0000, bytes };

			stage <= (1 << STAGE_WRITE);
		end
	end

	/*
	 * Write-Back (register or memory, branch calculation)
	 */
	always @(posedge clock)
	begin
		if (enable == 1'b1 && stage[STAGE_WRITE]) begin
			R[result_index] <= result;

			/* TODO: This conflicts with decodings that directly update the
			 *       status register. */
			//R[REGISTER_PSW] <= (old_status & ~status_mask) | (status & status_mask);

			/* Branches are taken when the status register has the 'Z' status
			 * (result of operation was 0). */
			//if (branch && status[PSW_Z]) begin
			//	PC <= PC + {  };
			//end

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
