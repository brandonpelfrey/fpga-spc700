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
	/**************************************************************************
	 * Module I/O
	 **************************************************************************/

	input clock;
	input reset;
	output [15:0] out_ram_address;
	output [7:0] out_ram_write;
	input [7:0] in_ram_read;
	output out_ram_write_enable;
	output out_halted;

	/**************************************************************************
	 * Global Definitions
	 **************************************************************************/

	/*
	 * Data: CPU Registers
	 */
	reg [15:0] PC;     /* Program Counter */
	reg [7:0] R [3:0]; /* Register File (see below) */
	reg [7:0] PSW;     /* Status register */

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
	          REGISTER_SP   = 3; /* "SP" Register */

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
	 * The correspondence from data control lines for ALU operations.
	 */
	parameter ALU_OR     = 0,
	          ALU_AND    = 1,
	          ALU_XOR    = 2,
	          ALU_ANDNOT = 3,
	          ALU_ADD    = 4,
	          ALU_SUB    = 5,
	          ALU_NONE_U = 6,
	          ALU_NONE_V = 7;
	          /* TODO */

	/**************************************************************************
	 * Memory Bus Logic
	 **************************************************************************/

	/*
	 * Memory bus control
	 */
	reg [15:0] ram_address;
	reg [7:0] ram_write;
	reg ram_write_enable;

	assign out_ram_address = ram_address;
	assign out_ram_write = ram_write;
	assign out_ram_write_enable = ram_write_enable & enable;

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
	/*
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

			X_alu_mode[ALU_NONE_U]: begin
				alu_result = X_data_A;
			end

			X_alu_mode[ALU_NONE_V]: begin
				alu_result = X_data_B;
			end

			default: begin
				alu_result = 8'bxxxx_xxxx;
			end
		endcase

		alu_zero = (alu_result == 8'b0000_0000);
	end
	*/

	/**************************************************************************
	 * Instruction Decoding Implementation
	 **************************************************************************/

	/*
	 * Instruction decoding produces a set of control lines that choose the
	 * execution path of the CPU. These operate on virtual U / V registers
	 * and write their result back to other registers and/or memory.
	 *
	 * U and V values can be sourced a few ways (decoder controlled constant,
	 * fetched immediate, existing register(s)). The U register is 16 bits
	 * but the decoder constants can only be 8 bits. The V register is just 8
	 * bits. The 16-bit U register is used for absolute addresses and
	 * operations that combine two CPU registers (e.g. DIV).
	 */

	/*
	 * Logic outputs from the decoder logic
	 */
	logic [0:0] decode_source_u_mode;  /* Input field U mode */
	logic [1:0] decode_source_u_index; /* Input field U register index */
	logic [7:0] decode_source_u_imm;   /* Input field U immediate value */

	logic [0:0] decode_source_v_mode;  /* Input field V mode */
	logic [1:0] decode_source_v_index; /* Input field V register index */
	logic [7:0] decode_source_v_imm;   /* Input field V immediate value */

	logic [3:0] decode_source_fetch;   /* Immediate values (see below) */
	logic       decode_source_carry;   /* Input carry bit */

	logic [1:0] decode_branch_load;    /* Load branch target from immediate */
	logic       decode_branch;         /* Branch instruction */

	logic [7:0] decode_result_mode;    /* Result output mode */
	logic [1:0] decode_result_index;   /* Result output register index */
	logic       decode_result_wb;      /* Enable writing result to register */
	logic [7:0] decode_status_mask;    /* Update mask for status register */
	logic [7:0] decode_status;         /* Raw value to update status with */
	logic       decode_alu_enable;     /* Enable ALU in execute stage */
	logic [7:0] decode_alu_mode;       /* ALU operation mode */
	logic       decode_error;          /* Invalid instruction */

	/*
	 * Constants used for decode_source_fetch. These control the number of and
	 * destination buffer for immediate bytes.
	 *
	 * Uses one-hot encoding.
	 *
	 * TODO Not sure if UV fetch is actually required, but UU definitely is.
	 */
	parameter DECODE_IMM_NONE = 0, /* No immediate data */
	          DECODE_IMM_U    = 1, /* Load U immediate byte only */
	          DECODE_IMM_V    = 2, /* Load V immediate byte only */
	          DECODE_IMM_UV   = 3; /* Load U byte then V byte immediates. */

	/*
	 * Constants used for decode_source_*_mode (u/v). These control whether
	 * the intermediate buffers U/V are sourced from immediate values or
	 * registers.
	 *
	 * Note: Immediate values can either be decoder immediates or the bytes
	 *       following the instruction. This distinction is controlled by
	 *       decode_source_fetch.
	 */
	parameter DATA_R        = 0, /* Register file */
	          DATA_IMM      = 1; /* Decoder-generated immediate */

	/*
	 * Implementation of decoding logic
	 */
	always @(*)
	begin
		decode_source_u_mode = DATA_R;
		decode_source_u_index = REGISTER_A;
		decode_source_u_imm = 8'bxxxx_xxxx;

		decode_source_v_mode = DATA_R;
		decode_source_v_index = REGISTER_A;
		decode_source_v_imm = 8'bxxxx_xxxx;

		decode_source_fetch = (1 << DECODE_IMM_NONE);
		decode_source_carry = 1'b0;

		decode_branch_load = 2'b0;
		decode_branch = 1'b0;

		decode_result_mode = DATA_R;
		decode_result_index = 2'bxx;
		decode_result_wb = 1'b0;
		decode_status_mask = 8'b0000_0000;
		decode_status = 8'b0000_0000;

		decode_alu_mode = 8'bxxxx_xxxx;
		decode_alu_enable = 1'b0;

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
				decode_alu_enable = 1'b0;
			end

			8'b001_000_00: begin
				/* CLP: PSW_P = 0 */
				decode_status_mask = (1 << PSW_P);
				decode_status = 8'b0000_0000;
				decode_alu_enable = 1'b0;
			end

			8'b010_000_00: begin
				/* SEP: PSW_P = 1 */
				decode_status_mask = (1 << PSW_P);
				decode_status = (1 << PSW_P);
				decode_alu_enable = 1'b0;
			end

			8'b011_000_00: begin
				/* CLC: PSW_C = 0 */
				decode_status_mask = (1 << PSW_C);
				decode_status = 8'b0000_0000;
				decode_alu_enable = 1'b0;
			end

			8'b100_000_00: begin
				/* SEC: PSW_C = 1 */
				decode_status_mask = (1 << PSW_C);
				decode_status = (1 << PSW_C);
				decode_alu_enable = 1'b0;
			end

			8'b101_000_00: begin
				/* CLI: PSW_I = 0 */
				decode_status_mask = (1 << PSW_I);
				decode_status = 8'b0000_0000;
				decode_alu_enable = 1'b0;
			end

			8'b110_000_00: begin
				/* SEI: PSW_I = 1 */
				decode_status_mask = (1 << PSW_I);
				decode_status = (1 << PSW_I);
				decode_alu_enable = 1'b0;
			end

			8'b111_000_00: begin
				/* CLV: PSW_V = 0 */
				decode_status_mask = (1 << PSW_V);
				decode_status = 8'b0000_0000;
				decode_alu_enable = 1'b0;
			end

			/*
			 * Column A2: Conditional Relative Branches
			 */
			8'b000_100_00: begin
				/* BPL: if (!PSW.N) PC += #i; */
				decode_alu_enable = 1'b1;
				decode_alu_mode = (1 << ALU_AND);
				decode_source_u_mode = DATA_IMM;
				decode_source_u_imm = (1 << PSW_N);
				decode_source_v_mode = DATA_IMM;
				decode_source_v_imm = PSW;
				decode_branch_load = 2'b01;
				decode_branch = 1'b1;
			end

			8'b001_100_00: begin
				/* BMI: if (PSW.N) PC += #i; */
				decode_alu_enable = 1'b1;
				decode_alu_mode = (1 << ALU_ANDNOT);
				decode_source_u_mode = DATA_IMM;
				decode_source_u_imm = (1 << PSW_N);
				decode_source_v_mode = DATA_IMM;
				decode_source_v_imm = PSW;
				decode_branch_load = 2'b01;
				decode_branch = 1'b1;
			end

			8'b010_100_00: begin
				/* BVC: if (!PSW.V) PC += #i; */
				decode_alu_enable = 1'b1;
				decode_alu_mode = (1 << ALU_AND);
				decode_source_u_mode = DATA_IMM;
				decode_source_u_imm = (1 << PSW_V);
				decode_source_v_mode = DATA_IMM;
				decode_source_v_imm = PSW;
				decode_branch_load = 2'b01;
				decode_branch = 1'b1;
			end

			8'b011_100_00: begin
				/* BVS: if (PSW.V) PC += #i; */
				decode_alu_enable = 1'b1;
				decode_alu_mode = (1 << ALU_ANDNOT);
				decode_source_u_mode = DATA_IMM;
				decode_source_u_imm = (1 << PSW_V);
				decode_source_v_mode = DATA_IMM;
				decode_source_v_imm = PSW;
				decode_branch_load = 2'b01;
				decode_branch = 1'b1;
			end

			8'b100_100_00: begin
				/* BCC: if (!PSW.C) PC += #i; */
				decode_alu_enable = 1'b1;
				decode_alu_mode = (1 << ALU_AND);
				decode_source_u_mode = DATA_IMM;
				decode_source_u_imm = (1 << PSW_C);
				decode_source_v_mode = DATA_IMM;
				decode_source_v_imm = PSW;
				decode_branch_load = 2'b01;
				decode_branch = 1'b1;
			end

			8'b101_100_00: begin
				/* BCS: if (PSW.C) PC += #i; */
				decode_alu_enable = 1'b1;
				decode_alu_mode = (1 << ALU_ANDNOT);
				decode_source_u_mode = DATA_IMM;
				decode_source_u_imm = (1 << PSW_C);
				decode_source_v_mode = DATA_IMM;
				decode_source_v_imm = PSW;
				decode_branch_load = 2'b01;
				decode_branch = 1'b1;
			end

			8'b110_100_00: begin
				/* BNE: if (!PSW.Z) PC += #i; */
				decode_alu_enable = 1'b1;
				decode_alu_mode = (1 << ALU_AND);
				decode_source_u_mode = DATA_IMM;
				decode_source_u_imm = (1 << PSW_Z);
				decode_source_v_mode = DATA_IMM;
				decode_source_v_imm = PSW;
				decode_branch_load = 2'b01;
				decode_branch = 1'b1;
			end

			8'b111_100_00: begin
				/* BEQ: if (PSW.Z) PC += #i; */
				decode_alu_enable = 1'b1;
				decode_alu_mode = (1 << ALU_ANDNOT);
				decode_source_u_mode = DATA_IMM;
				decode_source_u_imm = (1 << PSW_Z);
				decode_source_v_mode = DATA_IMM;
				decode_source_v_imm = PSW;
				decode_branch_load = 2'b01;
				decode_branch = 1'b1;
			end

			/*
			 * Column A3: Immediate Logical Operations
			 *
			 * TODO Status register mask
			 */
			8'b000_010_00: begin
				/* ORA: A = A | #i */
				decode_alu_enable = 1'b1;
				decode_alu_mode = (1 << ALU_OR);
				decode_source_u_index = REGISTER_A;
				decode_source_fetch = (1 << DECODE_IMM_V);
				decode_result_index = REGISTER_A;
				decode_result_wb = 1'b1;
			end

			8'b001_010_00: begin
				/* AND: A = A & #i */
				decode_alu_enable = 1'b1;
				decode_alu_mode = (1 << ALU_AND);
				decode_source_u_index = REGISTER_A;
				decode_source_fetch = (1 << DECODE_IMM_V);
				decode_result_index = REGISTER_A;
				decode_result_wb = 1'b1;
			end

			8'b010_010_00: begin
				/* EORA: A = A ^ #i */
				decode_alu_enable = 1'b1;
				decode_alu_mode = (1 << ALU_XOR);
				decode_source_u_index = REGISTER_A;
				decode_source_fetch = (1 << DECODE_IMM_V);
				decode_result_index = REGISTER_A;
				decode_result_wb = 1'b1;
			end

			8'b011_010_00: begin
				/* CMP: A - #i */
				decode_alu_enable = 1'b1;
				decode_alu_mode = (1 << ALU_SUB);
				decode_source_u_index = REGISTER_A;
				decode_source_fetch = (1 << DECODE_IMM_V);
			end

			8'b100_010_00: begin
				/* ADC: A = A + #i + c */
				decode_alu_enable = 1'b1;
				decode_alu_mode = (1 << ALU_ADD);
				decode_source_u_index = REGISTER_A;
				decode_source_fetch = (1 << DECODE_IMM_V);
				decode_result_index = REGISTER_A;
				decode_result_wb = 1'b1;
			end

			8'b101_010_00: begin
				/* SBC: A = A - #i - !c */
				decode_alu_enable = 1'b1;
				decode_alu_mode = (1 << ALU_SUB);
				decode_source_u_index = REGISTER_A;
				decode_source_fetch = (1 << DECODE_IMM_V);
				decode_result_index = REGISTER_A;
				decode_result_wb = 1'b1;
				decode_status_mask = (1 << PSW_Z); /* TODO N V H Z C */
			end

			8'b110_010_00: begin
				/* CPX: X - #i */
				decode_alu_enable = 1'b1;
				decode_alu_mode = (1 << ALU_SUB);
				decode_source_u_index = REGISTER_X;
				decode_source_fetch = (1 << DECODE_IMM_V);
			end

			8'b111_010_00: begin
				/* LDA: A = #i */
				decode_alu_enable = 1'b1;
				decode_alu_mode = (1 << ALU_NONE_U);
				decode_source_fetch = (1 << DECODE_IMM_U);
				decode_result_index = REGISTER_A;
				decode_result_wb = 1'b1;
			end

			/*
			 * Column A4: Direct page logical operations
			 */
			8'b000_110_00: begin
				/* OR: d[#j] |= #i */
				/* TODO */
				decode_alu_enable = 1'b1;
				decode_alu_mode = (1 << ALU_NONE_U);
				decode_source_fetch = (1 << DECODE_IMM_V);
				decode_result_index = REGISTER_A;
				decode_result_wb = 1'b1;
			end

			default: begin
				decode_error = 1'b1;
			end
		endcase
	end

	/**************************************************************************
	 * State Machine Implementation
	 **************************************************************************/

	/*
	 * In the original hardware the CPU would be clocked based on the rate it
	 * could access the memory bus. Instead this implementation uses the same
	 * clock as the DSP (3Mhz) but only uses the memory bus on the first of
	 * every three cycles.
	 *
	 * On the clock pulse that triggers reset, the initial PC fetch address is
	 * placed on the memory bus. The first cycle following reset can begin
	 * instruction decoding.
	 *
	 * Timing Diagram:
	 *
	 *      CPU 0     1     2     3     4     5     6
	 *          |_____|_____|_____|_____|_____|_____|
	 *          |  A  |  B  |  C  |  D  |  E  |  F  |
	 *          |MM RR|     |     |MM RR|     |     |
	 *          |__|__|__|__|__|__|__|__|__|__|__|__|
	 *          |  |  |  |  |  |  |  |  |  |  |  |  |
	 *      RAM 0  1  2  3  4  5  6  7  8  9  1  11 12
	 *
	 * In the diagram above, CPU clock cycles are labeled on top and RAM clock
	 * cycles are labeled on the bottom. RAM is clocked at 6MHz instead of
	 * 3MHz to hide the additional cycle of access latency for BRAM.
	 *
	 * i.e if the reset happens on cycle 0, PC will be exposed on the memory
	 * bus for the duration between CPU cycles 0 and 1 (logic propagation
	 * labeled "A"). The RAM will internally do its address lookup in the
	 * portion labeled "MM", and the output will be clocked into the RAM's
	 * output registers on RAM cycle 1. The result is available on the bus
	 * during the time marked RR which means it is available for processing in
	 * the CPU's cycle 1.
	 *
	 * This requires the CPU propagation delay to be less than (1 / 6MHz)
	 * instead of the actual 3MHz but simplifies logic.
	 */

	/*
	 * CPU global state
	 */
	reg [3:0]  state;              /* Current CPU state (see below) */
	reg [2:0]  bus_state;          /* Memory bus state (see below) */
	reg [15:0] fetch_pc;           /* Intermediate PC during fetching */

	/*
	 * Bit indexes for `state` that determine the current CPU operation. Uses
	 * one-hot encoding.
	 */
	parameter STATE_FETCH     = 0, /* Wait on instruction (first byte) fetch. */
	          STATE_DECODE    = 1, /* Decode instruction */
	          STATE_FETCH_IMM = 2, /* Wait on immediate byte(s) fetch. */
	          STATE_EXECUTE   = 3; /* TODO */

	/*
	 * Bit indexes for `bus_state` that keep track of the memory bus timing.
	 * Only every third cycle connects the CPU to the on the memory control
	 * lines.
	 */
	parameter MBUS_MASTER = 0,  /* CPU can set memory op during this cycle */
	          MBUS_WAIT   = 1,  /* Waiting for BRAM / result */
	          MBUS_RESULT = 2;  /* If read requested, output is available */

	/*
	 * Scratch state for execution. Initialized by decoder.
	 */
	reg [15:0] scratch_U;        /* Input field U value (16-bit) */
	reg [7:0]  scratch_V;        /* Input field V value (8-bit) */
	reg [3:0]  scratch_fetch;    /* Immedate value fetches required */

	/*
	 * Instruction decoding outputs. Scratch registers are named U / V to
	 * avoid confusion with CPU registers A / X / Y.
	 */
	reg        D_data_carry;     /* Input carry bit */
	reg [1:0]  D_out_index;      /* Result output register index */
	reg        D_out_wb;         /* Enable write-back to register */
	reg [7:0]  D_status_mask;    /* Update mask for status register */
	reg [7:0]  D_status;         /* Constant value for PSW updates */
	reg        D_alu_enable;     /* Enable ALU */
	reg [7:0]  D_alu_mode;       /* ALU operation mode */
	reg        D_branch;         /* Instruction is a branch */
	reg [7:0]  D_old_status;     /* Value of PSW at start of instruction */

	assign out_halted = ~enable;

	/*
	 * Common logic to move fetch address forward.
	 */
	wire [15:0] fetch_pc_next;
	assign fetch_pc_next = fetch_pc + 16'b0000_0000_0000_0001;

	/*
	 * Common Reset
	 */

	always @(posedge clock)
	begin
		if (reset == 1'b1) begin
			enable <= 1'b1;
			state <= (1 << STATE_FETCH);

			/* CPU register reset */
			/* TODO Allow these to be driven externally */
			PC <= 16'b0000_0000_0000_0000;
			R[REGISTER_A] <= 8'b0000_0000;
			R[REGISTER_X] <= 8'b0000_0000;
			R[REGISTER_Y] <= 8'b0000_0000;
			R[REGISTER_SP] <= 8'b0000_0000;
			PSW <= 8'b0000_0000;

			/* Scratch state reset */
			scratch_U <= 16'b0000_0000_0000_0000;
			scratch_V <= 8'b0000_0000;
			scratch_fetch <= (1 << DECODE_IMM_NONE);

			/* Initial fetch setup */
			/* Note: Keep synchronized with PC initialization */
			fetch_pc <= 16'b0000_0000_0000_0000;
			ram_address <= 16'b0000_0000_0000_0000;
			ram_write <= 8'b0000_0000;
			ram_write_enable <= 1'b0;
		end
	end

	/*
	 * Memory bus timing
	 */

	always @(posedge clock)
	begin
		if (reset == 1'b1) begin
			/* First state is MBUS_MASTER, but next state is already
			 * MBUS_WAIT. Common reset logic will place initial address on
			 * bus. */
			bus_state <= (1 << MBUS_WAIT);
		end else begin
			case (1'b1)
				bus_state[MBUS_MASTER]: begin
					bus_state <= (1 << MBUS_WAIT);
				end

				bus_state[MBUS_WAIT]: begin
					bus_state <= (1 << MBUS_RESULT);
				end

				bus_state[MBUS_RESULT]: begin
					bus_state <= (1 << MBUS_MASTER);
				end
			endcase
		end
	end

	/*
	 * Instruction fetch (initial byte only)
	 */

	always @(posedge clock)
	begin
		if (reset == 1'b1) begin
		end else if (enable && state[STATE_FETCH]) begin
			if (bus_state[MBUS_WAIT]) begin
				/* Next state will be MBUS_RESULT with data available. */
				state <= (1 << STATE_DECODE);
			end
		end
	end

	/*
	 * Instruction decode
	 */

	always @(posedge clock)
	begin
		if (reset == 1'b1) begin
			D_out_index <= 2'b00;
			D_out_wb <= 1'b0;
			D_status_mask <= 8'b0000_0000;
			D_status <= 8'b0000_0000;
			D_old_status <= 8'b0000_0000;

			D_data_carry <= 1'b0;
			D_alu_enable <= 1'b0;
			D_alu_mode <= 8'b0000_0000;

			D_branch <= 1'b0;
		end else if (enable && state[STATE_DECODE]) begin
			/* If branching, this will be updated by the execution stage. */
			fetch_pc <= fetch_pc_next;

			case (decode_source_u_mode)
				DATA_R: begin
					scratch_U <= { 8'b0000_0000, R[decode_source_u_index] };
				end

				DATA_IMM: begin
					scratch_U <= { 8'b0000_0000, decode_source_u_imm };
				end
			endcase

			case (decode_source_v_mode)
				DATA_R: begin
					scratch_V <= R[decode_source_v_index];
				end

				DATA_IMM: begin
					scratch_V <= decode_source_v_imm;
				end
			endcase

			scratch_fetch <= decode_source_fetch;
			D_data_carry <= decode_source_carry;

			D_branch <= decode_branch;

			D_out_index <= decode_result_index;
			D_out_wb <= decode_result_wb;
			D_status_mask <= decode_status_mask;
			D_status <= decode_status;
			D_old_status <= PSW;
			D_alu_mode <= decode_alu_mode;
			D_alu_enable <= decode_alu_enable;

			if (decode_source_fetch == DECODE_IMM_NONE) begin
				state <= (1 << STATE_DECODE); /* TODO */
			end else begin
				state <= (1 << STATE_FETCH_IMM);
			end

			/* TODO Multiple drivers */
			enable <= ~decode_error;
		end
	end

	/*
	 * Immediate byte(s) fetch
	 */

	always @(posedge clock)
	begin
		if (reset == 1'b1) begin
		end else if (enable && state[STATE_FETCH_IMM]) begin
			/* TODO */
			if (bus_state[MBUS_RESULT]) begin
				/*
				 * Data is available on the memory bus.
				 *
				 * We "waste" the entire cycle by only updating the scratch
				 * registers here instead of jumping into execute, but it keeps
				 * the timing consistent between instructions with / without
				 * fetched immediates since this cycle would otherwise be
				 * occupied by decode.
				 */
				case (1'b1)
					scratch_fetch[DECODE_IMM_U]: begin
						scratch_U <= { 8'b0000_0000, in_ram_read };
						state <= (1 << STATE_EXECUTE);
					end

					scratch_fetch[DECODE_IMM_UV]: begin
						scratch_U <= { 8'b0000_0000, in_ram_read };
						scratch_fetch <= (1 << DECODE_IMM_V);
						state <= (1 << STATE_FETCH_IMM);
					end

					scratch_fetch[DECODE_IMM_V]: begin
						scratch_V <= in_ram_read;
						state <= (1 << STATE_EXECUTE);
					end
				endcase
			end else begin
				/* Result not yet available - present address on control lines
				 * because decode does not. */
				ram_address <= fetch_pc;
				ram_write_enable <= 1'b0;
			end
		end
	end

	/*
	 * Debug
	 */

	`ifdef verilator
		function void debug_print_registers;
			/* verilator public */
			$display("A:      %02x", R[0]);
			$display("X:      %02x", R[1]);
			$display("Y:      %02x (+/-)", R[2]);
			$display("SP:     %02x", R[3]);
			$display("PSW:    %02x", PSW);
			$display("PC:     %04x", PC);
		endfunction;

		function void debug_print_decode;
			/* verilator public */
			$display("fetch_pc:        %04x", fetch_pc);
			$display("scratch_U:       %04x", scratch_U);
			$display("scratch_V:       %02x", scratch_V);
			$display("scratch_fetch:   %s%s%s%s",
			         scratch_fetch[DECODE_IMM_NONE] ? "N/A" : "",
			         scratch_fetch[DECODE_IMM_U]    ? "U"   : "",
			         scratch_fetch[DECODE_IMM_V]    ? "V"   : "",
			         scratch_fetch[DECODE_IMM_UV]   ? "U,V" : "");
			$display("D_data_carry:    %d",   D_data_carry);
			$display("D_out_index:     %d",   D_out_index);
			$display("D_out_wb:        %d",   D_out_wb);
			$display("D_status_mask:   %02x", D_status_mask);
			$display("D_status:        %02x", D_status);
			$display("D_alu_enable:    %d",   D_alu_enable);
			$display("D_alu_mode:      %s%s%s%s%s%s%s%s",
			         D_alu_mode[ALU_OR]     ? "U | V"  : "",
			         D_alu_mode[ALU_AND]    ? "U & V"  : "",
			         D_alu_mode[ALU_XOR]    ? "U ^ V"  : "",
			         D_alu_mode[ALU_ANDNOT] ? "U & ~V" : "",
			         D_alu_mode[ALU_ADD]    ? "U + V"  : "",
			         D_alu_mode[ALU_SUB]    ? "U - V"  : "",
			         D_alu_mode[ALU_NONE_U] ? "U"      : "",
			         D_alu_mode[ALU_NONE_V] ? "V"      : "");
			$display("D_branch:        %d",   D_branch);
			$display("D_old_status:    %02x", D_old_status);
		endfunction;

		function void debug_print_status;
			/* verilator public */
			$display("state:     %s%s",
			         state[STATE_FETCH]     ? "InitialFetch"   : "",
			         state[STATE_DECODE]    ? "Decode"         : "",
			         state[STATE_FETCH_IMM] ? "ImmediateFetch" : "");
			$display("bus_state: %s%s%s",
			         bus_state[MBUS_MASTER] ? "Master" : "",
			         bus_state[MBUS_WAIT]   ? "Wait"   : "",
			         bus_state[MBUS_RESULT] ? "Result" : "");
		endfunction;
	`endif
endmodule
