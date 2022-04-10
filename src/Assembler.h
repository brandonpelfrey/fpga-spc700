#pragma once

#include <functional>
#include <cstdint>

class Assembler
{
public:
	Assembler(std::function<void(uint16_t, uint8_t)> write_func)
			: m_write_func(write_func), m_address(0)
	{
		return;
	}

	void set_address(const uint16_t address)
	{
		m_address = address;
	}

	/* Column 1A */

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

	/* Column 2A */

	void BPL(const uint8_t r)
	{
		write(0x10);
		write(r);
	}

	void BMI(const uint8_t r)
	{
		write(0x30);
		write(r);
	}

	void BVC(const uint8_t r)
	{
		write(0x50);
		write(r);
	}

	void BVS(const uint8_t r)
	{
		write(0x70);
		write(r);
	}

	void BCC(const uint8_t r)
	{
		write(0x90);
		write(r);
	}

	void BCS(const uint8_t r)
	{
		write(0xB0);
		write(r);
	}

	void BNE(const uint8_t r)
	{
		write(0xD0);
		write(r);
	}

	void BEQ(const uint8_t r)
	{
		write(0xF0);
		write(r);
	}

	/* Column 3A */

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
	std::function<void(uint16_t, uint8_t)> m_write_func;
	uint16_t m_address;

	void write(const uint8_t byte)
	{
		m_write_func(m_address, byte);
		m_address++;
	}
};
