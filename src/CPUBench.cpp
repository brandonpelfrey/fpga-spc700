#include <string>
#include <cstdint>

#include "BasicBench.h"
#include "VCPUBench.h"
#include "VCPUBench_CPU.h"
#include "VCPUBench_CPUBench.h"
#include "VCPUBench_TestRAM.h"
#include "Assembler.h"

class CPUBench : public BasicBench<VCPUBench> {
public:
	CPUBench()
	{
		return;
	}

	void ram_write(const uint16_t address, const uint8_t data)
	{
		(*this)->CPUBench->ram->memory[address] = data;
	}

	uint8_t ram_read(const uint16_t address) const
	{
		return static_cast<uint8_t>((*this)->CPUBench->ram->memory[address]);
	}

	void print() const
	{
		printf("======== %d Ticks ========\n", this->time());
		(*this)->CPUBench->cpu->debug_print_registers();
		printf("----\n");
		(*this)->CPUBench->cpu->debug_print_decode();
		printf("----\n");
		(*this)->CPUBench->cpu->debug_print_status();
		printf("MemD:   %02x\n", (*this)->out_ram_read);
		printf("\n");
	}

	void memory_dump() const
	{
		for (unsigned i = 0; i < 16; ++i) {
			printf("%04x:", i * 16);
			for (unsigned j = 0; j < 16; ++j) {
				printf(" %02x", ram_read(i * 16 + j));
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
	Assembler assembler([&](uint16_t address, uint8_t value) {
		bench.ram_write(address, value);
	});

	bench.reset();

#if 0
	// assembler.ORA(0xFF);
	// assembler.AND(0x0F);
	// assembler.EORA(0x11);
	assembler.LDA(0x34);
	assembler.ADC(0x10);
	// assembler.SEP();
	// assembler.SEC();
	// assembler.SEI();
	assembler.CLP();
	assembler.CLC();
	assembler.CLI();
	assembler.SBC(0x14);
	// assembler.BEQ(0xfe);
	assembler.HLT();
#else
	assembler.LDA(0x10);
	assembler.SBC(0x01);
	assembler.BNE(0xfc);
	assembler.HLT();
#endif

	//while (!bench->out_halted) {
	for (unsigned i = 0; i < 5; ++i) {
		bench.print();
		bench.tick();
	}

	bench.print();
	bench.memory_dump();

	return 0;
}
