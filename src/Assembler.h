#pragma once

#include <cstdint>

class Assembler
{
public:
	Assembler(uint8_t *const memory)
		: m_memory(memory), m_address(0)
	{
		return;
	}

	void set_address(const uint16_t address)
	{
		m_address = address;
	}

	void NOP()
	{
		write(0x00);
	}

	void CLP()
	{
		write(0x20);
	}

	void SEP()
	{
		write(0x40);
	}

	void CLC()
	{
		write(0x60);
	}

	void SEC()
	{
		write(0x80);
	}

	void CLI()
	{
		write(0xA0);
	}

	void SEI()
	{
		write(0xC0);
	}

	void CLV()
	{
		write(0xE0);
	}

	/* Column missing */

	void ORA(const uint8_t imm)
	{
		write(0x08);
		write(imm);
	}

	void AND(const uint8_t imm)
	{
		write(0x28);
		write(imm);
	}

	void EORA(const uint8_t imm)
	{
		write(0x48);
		write(imm);
	}

	void CMP(const uint8_t imm)
	{
		write(0x68);
		write(imm);
	}

	void ADC(const uint8_t imm)
	{
		write(0x88);
		write(imm);
	}

	void SBC(const uint8_t imm)
	{
		write(0xA8);
		write(imm);
	}

	void CPX(const uint8_t imm)
	{
		write(0xC8);
		write(imm);
	}

	void LDA(const uint8_t imm)
	{
		write(0xE8);
		write(imm);
	}

	/* Column missing */

	void HLT()
	{
		write(0xFF);
	}

private:
	uint8_t *const m_memory;
	uint16_t m_address;

	void write(const uint8_t byte)
	{
		m_memory[m_address++] = byte;
	}
};
