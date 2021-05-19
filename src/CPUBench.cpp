#include <cstdint>

#include "BasicBench.h"
#include "VCPUBench.h"
#include "Assembler.h"

class CPUBench : public BasicBench<VCPUBench>
{
public:
	CPUBench()
	{
		return;
	}

	void ram_write(const uint16_t address, const uint8_t data)
	{
		(*this)->CPUBench__DOT__ram__DOT__memory[address] = data;
	}

	uint8_t ram_read(const uint16_t address) const
	{
		return (*this)->CPUBench__DOT__ram__DOT__memory[address];
	}

	uint8_t *ram_data()
	{
		return (*this)->CPUBench__DOT__ram__DOT__memory;
	}

	void print()
	{
		printf("======== %d Ticks ========\n", this->time());
		printf("A:      %02x\n", (*this)->CPUBench__DOT__cpu__DOT__R[0]);
		printf("X:      %02x\n", (*this)->CPUBench__DOT__cpu__DOT__R[1]);
		printf("Y:      %02x\n", (*this)->CPUBench__DOT__cpu__DOT__R[2]);
		printf("SP:     %02x\n", (*this)->CPUBench__DOT__cpu__DOT__R[3]);
		printf("PSW:    %02x\n", (*this)->CPUBench__DOT__cpu__DOT__R[4]);
		printf("D1:     %02x\n", (*this)->CPUBench__DOT__cpu__DOT__R[5]);
		printf("D2:     %02x\n", (*this)->CPUBench__DOT__cpu__DOT__R[6]);
		printf("PC:     %04x\n", (*this)->CPUBench__DOT__cpu__DOT__PC);
		printf("----\n");
		printf("Stage   %04x\n", (*this)->CPUBench__DOT__cpu__DOT__stage);
		printf("ALU:    %04x\n", (*this)->CPUBench__DOT__cpu__DOT__X_alu_mode);
		printf("Br:     %01x\n", (*this)->CPUBench__DOT__cpu__DOT__W_branch);
		printf("BrTgtR: %02x (+/-)\n", (*this)->CPUBench__DOT__cpu__DOT__X_branch_target);
		printf("BrTgt:  %04x\n", (*this)->CPUBench__DOT__cpu__DOT__W_branch_target);
		printf("nPSW:   %02x\n", (*this)->CPUBench__DOT__cpu__DOT__W_status);
		printf("nPSWM:  %02x\n", (*this)->CPUBench__DOT__cpu__DOT__W_status_mask);
		printf("ILen:   %01x\n", (*this)->CPUBench__DOT__cpu__DOT__P_bytes);
		printf("MemD:   %02x\n", (*this)->out_ram_read);
		printf("MemA:   %02x\n", (*this)->CPUBench__DOT__cpu__DOT__ram_address);
		printf("\n");
	}

	void memory_dump()
	{
		for (unsigned i = 0; i < 16; ++i) {
			printf("%04x:", i * 16);
			for (unsigned j = 0; j < 16; ++j) {
				printf(" %02x", ram_data()[i * 16 + j]);
			}
			printf("\n");
		}
		printf("\n");
	}
};

int
main(int argc, char **argv, char **env)
{
	Verilated::commandArgs(argc, argv);
	CPUBench bench;
	Assembler assembler(bench.ram_data());

	bench.reset();

#if 0
	assembler.ORA(0xFF);
	assembler.AND(0x0F);
	assembler.EORA(0x11);
	assembler.LDA(0x34);
	assembler.ADC(0x10);
	assembler.SEP();
	assembler.SEC();
	assembler.SEI();
	assembler.CLP();
	assembler.CLC();
	assembler.CLI();
	assembler.SBC(0x14);
	assembler.BEQ(0xfe);
	assembler.HLT();
#else
	assembler.LDA(0x10);
	assembler.SBC(0x01);
	assembler.BNE(0xfc);
	assembler.HLT();
#endif


	while (!bench->out_halted) {
		//bench.print();
		bench.tick();
	}

	bench.print();

	bench.memory_dump();

	return 0;
}
