#include <cstdint>

#include "BasicBench.h"
#include "VCPUBench.h"
#include "Assembler.h"

class CPUBench : public BasicBench<VCPUBench>
{
public:
	CPUBench()
	{
		(*this)->in_cpu_enable = 1;
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
		printf("InpA:   %04x\n", (*this)->CPUBench__DOT__cpu__DOT__source_a);
		printf("InpB:   %04x\n", (*this)->CPUBench__DOT__cpu__DOT__source_b);
		printf("Stat:   %04x\n", (*this)->CPUBench__DOT__cpu__DOT__status);
		printf("StatM:  %04x\n", (*this)->CPUBench__DOT__cpu__DOT__status_mask);
		printf("Stage   %04x\n", (*this)->CPUBench__DOT__cpu__DOT__stage);
		printf("ALU:    %04x\n", (*this)->CPUBench__DOT__cpu__DOT__alu_mode);
		printf("MemBus: %02x\n", (*this)->out_ram_read);
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
	assembler.BPL(0xff);
	assembler.HLT();
#endif

	assembler.LDA(0x10);
	assembler.SBC(0x01);
	assembler.BNE(0xfc);
	assembler.HLT();

	while (!bench->out_halted) {
		bench.tick();
	}

	printf("Simulated %lu ticks\n\n", bench.time());
	bench.print();

	return 0;
}
