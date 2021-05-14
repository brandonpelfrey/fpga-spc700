#include <cstdint>

#include "BasicBench.h"
#include "VCPUBench.h"

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

	void print()
	{
		printf("======== %8d Ticks ========\n", this->time());
		printf("A:      %02x\n", (*this)->CPUBench__DOT__cpu__DOT__A);
		//printf("X:      %02x\n", (*this)->CPUBench__DOT__cpu__DOT__X);
		//printf("Y:      %02x\n", (*this)->CPUBench__DOT__cpu__DOT__Y);
		printf("PC:     %04x\n", (*this)->CPUBench__DOT__cpu__DOT__PC);
		printf("MEMBUS: %04x\n", (*this)->out_ram_read);
		printf("\n");
	}
};

int
main(int argc, char **argv, char **env)
{
	Verilated::commandArgs(argc, argv);
	CPUBench bench;

	bench.reset();
	bench.ram_write(0, 8);

	while (!bench->out_halted) {
		bench.tick();
	}

	printf("Simulated %lu ticks\n\n", bench.time());
	bench.print();

	return 0;
}
