#pragma once

#include "audio_queue.h"
#include "types.h"

#include <algorithm>
#include <atomic>
#include <array>
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <memory>
#include <mutex>
#include <queue>
#include <vector>

struct MemoryState
{
  static constexpr uint32_t shared_memory_size = 64 * 1024;
  std::array<uint8_t, shared_memory_size> shared_memory;
};

enum CPURegisterIndexes
{
  CPURegisterIndex_A = 0,
  CPURegisterIndex_PCHigh,
  CPURegisterIndex_PCLow,
  CPURegisterIndex_X,
  CPURegisterIndex_Y,
  CPURegisterIndex_PSW,
  CPURegisterIndex_SP,
};

enum DSPRegisters {
  #define DSP_REGISTER(index, voice, name, description) DSPRegister_##name = index,
  #include "dsp_registers.h"
  #undef DSP_REGISTER
};

struct CPUState
{
  uint8_t A, X, Y, PSW;
  uint16_t PC;
  bool is_halted;
};

enum DSPVoiceFSMStateBits
{
  DSPVoiceState_Init = 0,
  DSPVoiceState_ReadHeader,
  DSPVoiceState_ReadData,
  DSPVoiceState_ProcessSample,
  DSPVoiceState_OutputAndWait,
  DSPVoiceState_End,
};
using DSPVoiceFSMState = u8;

struct DSPState
{
  static constexpr uint32_t num_voices = 8;
  struct DSPVoiceState
  {
    DSPVoiceFSMState fsm_state;
    u16 decoder_address;
    u16 decoder_cursor;
    s16 decoder_output;
  };

  u8 register_values[128];
  DSPVoiceState voice[8];
  u16 ram_address;
  u8 ram_data;
  u32 major_cycle;
};



const char *getDSPRegisterName(u8 register_index);
const char *getDSPRegisterDescription(u8 register_index);

class Controller
{
public:
  virtual ~Controller() {}
  virtual void setAudioQueue(AudioQueue *) = 0;
  virtual AudioQueue *getAudioQueue() = 0;

  // Retrieve state from the system
  virtual bool getCPUState(CPUState *) = 0;
  virtual bool getDSPState(DSPState *) = 0;
  virtual bool getMemoryState(MemoryState *) = 0;

  // Set State
  virtual bool setCPURegister(uint8_t registerIndex, uint8_t value) = 0;
  virtual bool setDSPRegister(uint8_t registerIndex, uint8_t value) = 0;
  virtual bool setMemorySpan(uint16_t addressOffset, uint32_t range, uint8_t *data) = 0;

  void loadMemoryFromFile(const char *file_path)
  {
    auto file = fopen(file_path, "rb");
    fseek(file, 0, SEEK_END);
    const u32 file_size = ftell(file);
    fseek(file, 0, SEEK_SET);
    std::vector<u8> data(file_size);
    fread(&data[0], sizeof(u8), file_size, file);
    fclose(file);

    const u32 size = std::min((u32)(64 * 1024), file_size);
    setMemorySpan(0, size, &data[0]);
  }

  void loadSPCFromFile(const char *file_path);

  // Hardware control
  virtual void singleStep() = 0;
  virtual void resume() = 0;
  virtual void stop() = 0;
  virtual void setSpeed() = 0;
  virtual void reset() = 0;

  virtual uint64_t getCycleCount() const = 0;
};
