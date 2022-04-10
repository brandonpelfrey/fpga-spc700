#include <string>
#include <cstdint>

#include "BasicBench.h"
#include "VCPUBench.h"
#include "VCPUBench_CPU.h"
#include "VCPUBench_CPUBench.h"
#include "VCPUBench_TestRAM.h"
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
		(*this)->CPUBench->ram->memory[address] = data;
	}

	uint8_t ram_read(const uint16_t address) const
	{
		return static_cast<uint8_t>((*this)->CPUBench->ram->memory[address]);
	}

	void print() const
	{
		printf("======== %d Ticks ========\n", this->time());
		printf("A:      %02x\n", (*this)->CPUBench->cpu->R[0]);
		printf("X:      %02x\n", (*this)->CPUBench->cpu->R[1]);
		printf("Y:      %02x\n", (*this)->CPUBench->cpu->R[2]);
		printf("SP:     %02x\n", (*this)->CPUBench->cpu->R[3]);
		printf("PSW:    %02x\n", (*this)->CPUBench->cpu->PSW);
		printf("PC:     %04x\n", (*this)->CPUBench->cpu->PC);
		printf("----\n");
		printf("Stage:  %s\n", this->pipeline_status().c_str());
		// printf("ALU:    %04x\n", (*this)->CPUBench->cpu->X_alu_mode);
		// printf("Br:     %01x\n", (*this)->CPUBench->cpu->W_branch);
		// printf("BrTgtR: %02x (+/-)\n", (*this)->CPUBench->cpu->X_branch_target);
		// printf("BrTgt:  %04x\n", (*this)->CPUBench->cpu->W_branch_target);
		// printf("nPSW:   %02x\n", (*this)->CPUBench->cpu->W_status);
		// printf("nPSWM:  %02x\n", (*this)->CPUBench->cpu->W_status_mask);
		// printf("ILen:   %01x\n", (*this)->CPUBench->cpu->P_bytes);
		printf("TODO \n");
		printf("MemD:   %02x\n", (*this)->out_ram_read);
		printf("\n");
	}

	std::string pipeline_status() const
	{
		std::string result;
		// result += (*this)->CPUBench->cpu->F_ready ? 'F' : '.';
		// result += (*this)->CPUBench->cpu->D_ready ? 'D' : '.';
		// result += (*this)->CPUBench->cpu->P_ready ? 'P' : '.';
		// result += (*this)->CPUBench->cpu->L_ready ? 'L' : '.';
		// result += (*this)->CPUBench->cpu->X_ready ? 'X' : '.';
		// result += (*this)->CPUBench->cpu->W_ready ? 'W' : '.';
		// result += (*this)->CPUBench->cpu->Z_ready ? 'Z' : '.';
		result += "TODO";
		return result;
	}

	void memory_dump() const
	{
		for (unsigned i = 0; i < 16; ++i)
		{
			printf("%04x:", i * 16);
			for (unsigned j = 0; j < 16; ++j)
			{
				printf(" %02x", ram_read(i * 16 + j));
			}
			printf("\n");
		}
		printf("\n");
	}
};

int main(int argc, char **argv, char **env)
{
	Verilated::commandArgs(argc, argv);
	CPUBench bench;
	Assembler assembler([&](uint16_t address, uint8_t value) {
		bench.ram_write(address, value);
	});

	bench.reset();

#if 1
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

	while (!bench->out_halted)
	{
		// bench.print();
		bench.tick();
	}

	bench.print();

	bench.memory_dump();

	return 0;
}
