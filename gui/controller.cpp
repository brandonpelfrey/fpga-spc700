#include "controller.h"

void Controller::loadSPCFromFile(const char *file_path)
{
  // https://wiki.superfamicom.org/spc-and-rsn-file-format
  auto file = fopen(file_path, "rb");
  fseek(file, 0, SEEK_END);
  const u32 file_size = ftell(file);
  fseek(file, 0, SEEK_SET);
  assert(file_size >= 0x10180);

  // Read entire file contents
  std::vector<u8> data(file_size);
  fread(&data[0], sizeof(u8), file_size, file);
  fclose(file);

#define LOAD(dst, offset, size) memcpy(dst, &data[offset], size);
  // Load SPC700 Registers
  u16 PC;
  u8 A, X, Y, PSW, SP;
  LOAD(&PC, 0x25, 2)
  LOAD(&A, 0x27, 1)
  LOAD(&X, 0x28, 1)
  LOAD(&Y, 0x29, 1)
  LOAD(&PSW, 0x2A, 1)
  LOAD(&SP, 0x2B, 1)
  setCPURegister(CPURegisterIndex_A, A);
  setCPURegister(CPURegisterIndex_X, X);
  setCPURegister(CPURegisterIndex_Y, Y);
  setCPURegister(CPURegisterIndex_SP, SP);
  setCPURegister(CPURegisterIndex_PSW, PSW);
  setCPURegister(CPURegisterIndex_PCHigh, PC >> 8);
  setCPURegister(CPURegisterIndex_PCLow, PC & 0xFF);

  // Load RAM
  std::array<u8, 64 * 1024> ram;
  LOAD(ram.data(), 0x100, ram.size())
  setMemorySpan(0, ram.size(), ram.data());

  // Load DSP Registers
  u8 dsp_regs[128];
  LOAD(&dsp_regs[0], 0x10100, 128)
  for (u8 i = 0; i < 128; ++i)
    setDSPRegister(i, dsp_regs[i]);
}

const char *dsp_register_names[128] = {
#define DSP_REGISTER(index, voice, name, description) #name,
#include "dsp_registers.h"
#undef DSP_REGISTER
};

const char *dsp_register_descriptions[128] = {
#define DSP_REGISTER(index, voice, name, description) #description,
#include "dsp_registers.h"
#undef DSP_REGISTER
};

const char *getDSPRegisterName(u8 register_index)
{
  assert(register_index < 128);
  return dsp_register_names[register_index];
}

const char *getDSPRegisterDescription(u8 register_index)
{
  assert(register_index < 128);
  return dsp_register_descriptions[register_index];
}
