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
	 * Data: Generic CPU state
	 */
	reg enable;          /* Enable CPU execution (for debugging) */

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
	parameter STAGE_FETCH   = 0, /* [F] Instruction Fetch */
	          STAGE_DECODE  = 1, /* [D] Instruction Decode */
	          STAGE_PARAM   = 2, /* [P] Parameter Bytes Fetch */
	          STAGE_EXECUTE = 3, /* [X] Logic Execution (X) */
	          STAGE_WRITE   = 4, /* [W] Write result to register / memory */
	          STAGE_DELAY   = 5; /* [S] Delay to match original hardware */
	          /* TODO Add memory stage */

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

	/**************************************************************************
	 * ALU Implementation (Sub, Add, Logical)
	 **************************************************************************/

	/*
	 * Logic outputs from the ALU logic
	 */
	logic [7:0] alu_result;
	logic       alu_zero;

	/*
	 * Implementation of ALU logic
	 */
	always @(*)
	begin
		case (1'b1)
			X_alu_mode[ALU_OR]: begin
				alu_result = X_data_A | X_data_B;
			end

			X_alu_mode[ALU_AND]: begin
				alu_result = X_data_A & X_data_B;
			end

			X_alu_mode[ALU_XOR]: begin
				alu_result = X_data_A ^ X_data_B;
			end

			X_alu_mode[ALU_ANDNOT]: begin
				alu_result = X_data_A & ~X_data_B;
			end

			X_alu_mode[ALU_ADD]: begin
				alu_result = X_data_A + X_data_B + { 7'b000_0000, X_data_carry };
			end

			X_alu_mode[ALU_SUB]: begin
				alu_result = X_data_A - X_data_B - { 7'b000_0000, X_data_carry };
			end

			X_alu_mode[ALU_NONE_A]: begin
				alu_result = X_data_A;
			end

			X_alu_mode[ALU_NONE_B]: begin
				alu_result = X_data_B;
			end
		endcase

		alu_zero = (alu_result == 8'b0000_0000);
	end

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

	logic [7:0] decode_branch_target;  /* Branch relative target */
	logic [1:0] decode_branch_load;    /* Load branch target from immediate */
	logic       decode_branch;         /* Branch instruction */

	logic [7:0] decode_result_mode;    /* Result output mode */
	logic [2:0] decode_result_index;   /* Result output register index */
	logic [7:0] decode_status_mask;    /* Update mask for status register */
	logic [7:0] decode_status;         /* Raw value to update status with */
	logic       decode_alu_enable;     /* Enable ALU in execute stage */
	logic [7:0] decode_alu_mode;       /* ALU operation mode */
	logic [1:0] decode_bytes;          /* Instruction byte length */
	logic [6:0] decode_stage;          /* Next pipeline stage */
	logic       decode_error;          /* Invalid instruction */

	/*
	 * Implementation of decoding logic
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

		decode_branch_target = 8'b0000_0000;
		decode_branch_load = 2'b0;
		decode_branch = 1'b0;

		decode_result_mode = DATA_R;
		decode_result_index = REGISTER_A;
		decode_status_mask = 8'b0000_0000;
		decode_status = 8'b0000_0000;

		decode_alu_mode = 8'b0000_0000;
		decode_alu_enable = 1'b1;

		decode_bytes = 2'd1;
		decode_stage = (1 << STAGE_PARAM);
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
				decode_result_index = REGISTER_D1; /* Unused */
				decode_alu_enable = 1'b0;
			end

			8'b001_000_00: begin
				/* CLP: PSW_P = 0 */
				decode_result_index = REGISTER_D1; /* Unused */
				decode_status_mask = (1 << PSW_P);
				decode_status = 8'b0000_0000;
				decode_alu_enable = 1'b0;
			end

			8'b010_000_00: begin
				/* SEP: PSW_P = 1 */
				decode_result_index = REGISTER_D1; /* Unused */
				decode_status_mask = (1 << PSW_P);
				decode_status = (1 << PSW_P);
				decode_result_index = REGISTER_D1; /* Unused */
				decode_alu_enable = 1'b0;
			end

			8'b011_000_00: begin
				/* CLC: PSW_C = 0 */
				decode_result_index = REGISTER_D1; /* Unused */
				decode_status_mask = (1 << PSW_C);
				decode_status = 8'b0000_0000;
				decode_alu_enable = 1'b0;
			end

			8'b100_000_00: begin
				/* SEC: PSW_C = 1 */
				decode_result_index = REGISTER_D1; /* Unused */
				decode_status_mask = (1 << PSW_C);
				decode_status = (1 << PSW_C);
				decode_alu_enable = 1'b0;
			end

			8'b101_000_00: begin
				/* CLI: PSW_I = 0 */
				decode_result_index = REGISTER_D1; /* Unused */
				decode_status_mask = (1 << PSW_I);
				decode_status = 8'b0000_0000;
				decode_alu_enable = 1'b0;
			end

			8'b110_000_00: begin
				/* SEI: PSW_I = 1 */
				decode_result_index = REGISTER_D1; /* Unused */
				decode_status_mask = (1 << PSW_I);
				decode_status = (1 << PSW_I);
				decode_alu_enable = 1'b0;
			end

			8'b111_000_00: begin
				/* CLV: PSW_V = 0 */
				decode_result_index = REGISTER_D1; /* Unused */
				decode_status_mask = (1 << PSW_V);
				decode_status = 8'b0000_0000;
				decode_alu_enable = 1'b0;
			end

			/*
			 * Column A2: Conditional Relative Branch
			 */
			8'b000_100_00: begin
				/* BPL: if (!PSW.N) PC += #i; */
				decode_alu_mode = (1 << ALU_AND);
				decode_source_a_index = REGISTER_PSW;
				decode_source_b_mode = DATA_IMM;
				decode_source_b_imm = (1 << PSW_N);
				decode_branch_load = 2'b01;
				decode_branch = 1'b1;
				decode_result_index = REGISTER_D1; /* Unused */
				decode_bytes = 2'd2;
			end

			/* XXX */

			8'b110_100_00: begin
				/* BNE: if (!PSW.Z) PC += #i; */
				decode_alu_mode = (1 << ALU_AND);
				decode_source_a_index = REGISTER_PSW;
				decode_source_b_mode = DATA_IMM;
				decode_source_b_imm = (1 << PSW_Z);
				decode_branch_load = 2'b01;
				decode_branch = 1'b1;
				decode_result_index = REGISTER_D1; /* Unused */
				decode_bytes = 2'd2;
			end

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
				decode_bytes = 2'd2;
			end

			8'b001_010_00: begin
				/* AND: A = A & #i */
				decode_alu_mode = (1 << ALU_AND);
				decode_source_a_index = REGISTER_A;
				decode_source_b_fetch = 2'b01;
				decode_result_index = REGISTER_A;
				decode_bytes = 2'd2;
			end

			8'b010_010_00: begin
				/* EORA: A = A ^ #i */
				decode_alu_mode = (1 << ALU_XOR);
				decode_source_a_index = REGISTER_A;
				decode_source_b_fetch = 2'b01;
				decode_result_index = REGISTER_A;
				decode_bytes = 2'd2;
			end

			8'b011_010_00: begin
				/* CMP: A - #i */
				decode_alu_mode = (1 << ALU_SUB);
				decode_source_a_index = REGISTER_A;
				decode_source_b_fetch = 2'b01;
				decode_result_index = REGISTER_D1; /* Unused */
				decode_bytes = 2'd2;
			end

			8'b100_010_00: begin
				/* ADC: A = A + #i + c */
				decode_alu_mode = (1 << ALU_ADD);
				decode_source_a_index = REGISTER_A;
				decode_source_b_fetch = 2'b01;
				decode_result_index = REGISTER_A;
				decode_bytes = 2'd2;
			end

			8'b101_010_00: begin
				/* SBC: A = A - #i - !c */
				decode_alu_mode = (1 << ALU_SUB);
				decode_source_a_index = REGISTER_A;
				decode_source_b_fetch = 2'b01;
				decode_result_index = REGISTER_A;
				decode_status_mask = (1 << PSW_Z); /* TODO N V H Z C */
				decode_bytes = 2'd2;
			end

			8'b110_010_00: begin
				/* CPX: X - #i */
				decode_alu_mode = (1 << ALU_SUB);
				decode_source_a_index = REGISTER_X;
				decode_source_b_fetch = 2'b01;
				decode_result_index = REGISTER_D1; /* Unused */
				decode_bytes = 2'd2;
			end

			8'b111_010_00: begin
				/* LDA: A = #i */
				decode_alu_mode = (1 << ALU_NONE_A);
				decode_source_a_fetch = 2'b01;
				decode_result_index = REGISTER_A;
				decode_bytes = 2'd2;
			end

			default: begin
				decode_error = 1'b1;
				decode_bytes = 2'd0;
			end
		endcase
	end

	/**************************************************************************
	 * Pipeline Implementation
	 **************************************************************************/

	/*
	 * Shared Pipeline State
	 */
	reg [6:0] stage;             /* Pipeline Stage (one-hot encoding) */

	/*
	 * State passed from Fetch (F) to Decode (D)
	 */
	reg [15:0] D_pc;             /* Address of the fetched instruction */

	/*
	 * State passed from Decode (D) to Param (P)
	 */
	reg [15:0] P_pc;             /* Address of the fetched instruction */
	reg [1:0]  P_data_A_fetch;   /* Input field A is a fetched immediate */
	reg        P_data_A_load;    /* Input field A is a load address */
	reg [7:0]  P_data_A;         /* Input field A value */
	reg [1:0]  P_data_B_fetch;   /* Input field B is a fetched immediate */
	reg        P_data_B_load;    /* Input field B is a load address */
	reg [7:0]  P_data_B;         /* Input field B value */
	reg        P_data_carry;     /* Input carry bit */
	reg [2:0]  P_out_index;      /* Result output register index */
	reg [7:0]  P_status_mask;    /* Update mask for status register */
	reg [7:0]  P_status;         /* Value of PSW at start of instruction */
	reg        P_alu_enable;     /* Enable ALU */
	reg [7:0]  P_alu_mode;       /* ALU operation mode */
	reg [1:0]  P_bytes;          /* Instruction encoding length */
	reg [7:0]  P_branch_target;  /* Signed relative branch target */
	reg [1:0]  P_branch_load;    /* Branch target is a fetched immediate */
	reg        P_branch;         /* Instruction is a branch */
	reg [7:0]  W_old_status;     /* XXX TODO Pass directly to write-back */

	/*
	 * State passed from Param (P) to Execute (X)
	 */
	reg [15:0] X_pc;             /* Address following the current instruction */
	reg [7:0]  X_data_A;         /* Input field A value */
	reg [7:0]  X_data_B;         /* Input field B value */
	reg        X_data_carry;     /* Input carry bit */
	reg [2:0]  X_out_index;      /* Result output register index */
	reg [7:0]  X_status_mask;    /* Update mask for status register */
	reg [7:0]  X_status;         /* Value of PSW at start of instruction */
	reg        X_alu_enable;     /* Enable ALU */
	reg [7:0]  X_alu_mode;       /* ALU operation mode */
	reg [1:0]  X_bytes;          /* Instruction encoding length */
	reg [7:0]  X_branch_target;  /* Signed relative branch target */
	reg        X_branch;         /* Instruction is a branch */

	/*
	 * State passed from Execute (X) to Write-Back (W)
	 */
	reg [15:0] W_pc;             /* Address following the current instruction */
	reg [7:0]  W_out;            /* Result of execute stage */
	reg [2:0]  W_out_index;      /* Result output register index */
	reg [7:0]  W_status_mask;    /* Update mask for status register */
	reg [7:0]  W_status;         /* Value of PSW at start of instruction */
	reg [15:0] W_branch_target;  /* Signed relative branch target */
	reg        W_branch;         /* Instruction is a branch */

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
	 * Instruction Fetch (F)
	 */
	always @(posedge clock)
	begin
		if (reset == 1'b1) begin
			D_pc <= 16'b0000_0000_0000_0000;
		end else if (enable == 1'b1 && stage[STAGE_FETCH]) begin
			D_pc <= PC;

			/* Prepare to read the instruction from memory. Result will be
			 * visible on the RAM output in the decode stage. */
			/* TODO */
			ram_address <= PC;
			ram_write_enable <= 1'b0;
			stage <= (1 << STAGE_DECODE);
		end
	end

	/*
	 * Instruction Decode (D)
	 */
	always @(posedge clock)
	begin
		if (reset == 1'b1) begin
			P_pc <= 16'b0000_0000_0000_0000;

			P_data_A_fetch <= 2'b0;
			P_data_A_load <= 1'b0;
			P_data_A <= 8'b0000_0000;

			P_data_B_fetch <= 2'b0;
			P_data_B_load <= 1'b0;
			P_data_B <= 8'b0000_0000;

			P_out_index <= 3'b000;
			P_status_mask <= 8'b0000_0000;
			P_status <= 8'b0000_0000;

			P_data_carry <= 1'b0;
			P_alu_enable <= 1'b0;
			P_alu_mode <= 8'b0000_0000;

			P_bytes <= 2'b00;
			P_branch_target <= 8'b0000_0000;
			P_branch_load <= 2'b00;
			P_branch <= 1'b0;

			/* TODO */
			W_old_status <= 8'b0000_0000;
		end else if (enable == 1'b1 && stage[STAGE_DECODE]) begin
			P_pc <= D_pc;

			P_data_A_fetch <= decode_source_a_fetch;
			P_data_A_load <= decode_source_a_load;
			case (decode_source_a_mode)
				DATA_R: begin
					P_data_A <= R[decode_source_a_index];
				end

				DATA_IMM: begin
					P_data_A <= decode_source_a_imm;
				end
			endcase

			P_data_B_fetch <= decode_source_b_fetch;
			P_data_B_load <= decode_source_b_load;
			case (decode_source_b_mode)
				DATA_R: begin
					P_data_B <= R[decode_source_b_index];
				end

				DATA_IMM: begin
					P_data_B <= decode_source_b_imm;
				end
			endcase

			P_data_carry <= decode_source_carry;

			P_branch_target <= decode_branch_target;
			P_branch_load <= decode_branch_load;
			P_branch <= decode_branch;

			P_out_index <= decode_result_index;
			P_status_mask <= decode_status_mask;
			P_status <= decode_status;
			P_alu_mode <= decode_alu_mode;
			P_alu_enable <= decode_alu_enable;
			P_bytes <= decode_bytes;

			/* TODO */
			W_old_status <= R[REGISTER_PSW];
			enable <= ~decode_error;
			stage <= (1 << STAGE_PARAM);

			/* Always prepare to fetch next address, possibly unused. */
			ram_address <= PC + 1;
		end
	end

	/*
	 * Parameter Fetch (P)
	 */
	/* TODO Add back support for 3-byte decodings */
	always @(posedge clock)
	begin
		/* TODO This could easily be combined with decode, but this simplifies
		 *      the code a little for now. */
		if (reset == 1'b1) begin
			X_pc <= 16'b0000_0000_0000_0000;

			X_data_A <= 8'b0000_0000;
			X_data_B <= 8'b0000_0000;
			X_data_carry <= 1'b0;

			X_out_index <= 3'b000;
			X_status_mask <= 8'b0000_0000;
			X_status <= 8'b0000_0000;

			X_alu_enable <= 1'b0;
			X_alu_mode <= 8'b0000_0000;
			X_bytes <= 2'b00;
			X_branch_target <= 8'b0000_0000;
			X_branch <= 1'b0;
		end else if (enable == 1'b1 && stage[STAGE_PARAM]) begin
			/* TODO This can't stay here if this stage becomes optional */
			/* Branches are relative to the start of the following
			 * instruction. So this logic always applies even with branching. */
			X_pc <= P_pc + { 14'b00_0000_0000_0000, P_bytes };

			if (P_data_A_fetch[0]) begin
				X_data_A <= in_ram_read;
			end else begin
				X_data_A <= P_data_A;
			end

			if (P_data_B_fetch[0]) begin
				X_data_B <= in_ram_read;
			end else begin
				X_data_B <= P_data_B;
			end

			if (P_branch_load[0]) begin
				X_branch_target <= in_ram_read;
			end else begin
				X_branch_target <= P_branch_target;
			end

			X_data_carry <= P_data_carry;
			X_out_index <= P_out_index;
			X_status_mask <= P_status_mask;
			X_status <= P_status;
			X_alu_enable <= P_alu_enable;
			X_alu_mode <= P_alu_mode;
			X_bytes <= P_bytes;
			X_branch <= P_branch;

			/* TODO XXX */
			stage <= (1 << STAGE_EXECUTE);
		end
	end

	/*
	 * Logic Execution (X)
	 */
	always @(posedge clock)
	begin
		if (reset == 1'b1) begin
			W_pc <= 16'b0000_0000_0000_0000;
			W_out <= 8'b0000_0000;
			W_out_index <= 3'b000;
			W_status_mask <= 8'b0000_0000;
			W_status <= 8'b0000_0000;
			W_branch_target <= 16'b0000_0000_0000_0000;
			W_branch <= 1'b0;
		end else if (enable == 1'b1 && stage[STAGE_EXECUTE]) begin
			if (X_alu_enable) begin
				W_out <= alu_result;
				/* TODO remaining bits */
				W_status[PSW_Z] <= alu_zero;
			end else begin
				W_out <= 8'b0000_0000;
				W_status <= X_status;
			end

			W_out_index <= X_out_index;
			W_status_mask <= X_status_mask;

			W_pc <= X_pc;
			W_branch <= X_branch;
			if (X_branch) begin
				W_branch_target <= X_pc + { X_branch_target[7] ? 8'b1111_1111 : 8'b0000_0000, X_branch_target };
			end else begin
				W_branch_target <= 16'b0000_0000_0000_0000;
			end


			/* TODO XXX */
			stage <= (1 << STAGE_WRITE);
		end
	end

	/*
	 * Write-Back (register or memory, branch calculation)
	 */
	always @(posedge clock)
	begin
		if (reset == 1'b1) begin
			/* N/A */
		end else if (enable == 1'b1 && stage[STAGE_WRITE]) begin
			R[W_out_index] <= W_out;
			R[REGISTER_PSW] <= (W_old_status & ~W_status_mask) | (W_status & W_status_mask);

			/* Branches are taken when the status register has the 'Z' status
			 * (result of operation was 0). */
			if (W_branch && W_status[PSW_Z]) begin
				PC <= W_branch_target;
			end else begin
				PC <= W_pc;
			end

			stage <= (1 << STAGE_DELAY);
		end
	end

	/*
	 * Delay (optional, to match original hardware)
	 */
	always @(posedge clock)
	begin
		if (reset == 1'b1) begin
			/* N/A */
		end else if (enable == 1'b1 && stage[STAGE_DELAY]) begin
			stage <= (1 << STAGE_FETCH);
		end
	end
endmodule
