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

	bench.reset();

	/* OR A, 0xFF */
	bench.ram_write(0, 0x08);
	bench.ram_write(1, 0xFF);

	/* AND A, 0x0F */
	bench.ram_write(2, 0x28);
	bench.ram_write(3, 0x0F);

	/* XOR A, 0x11 */
	bench.ram_write(4, 0x48);
	bench.ram_write(5, 0x11);

	/* LDA 0x34 */
	bench.ram_write(6, 0xE8);
	bench.ram_write(7, 0x34);

	/* ADC 0x10 */
	bench.ram_write(8, 0x88);
	bench.ram_write(9, 0x10);

	while (!bench->out_halted) {
		bench.tick();
	}

	printf("Simulated %lu ticks\n\n", bench.time());
	bench.print();

	return 0;
}
