#pragma once

#include <array>
#include <cstdint>

struct MemoryState
{
  static constexpr uint32_t shared_memory_size = 64 * 1024;
  std::array<uint8_t, shared_memory_size> shared_memory;
};

struct CPUState
{
  uint8_t A, X, Y, PSW;
  uint16_t PC;
  bool is_halted;
};

struct DSPState
{
  static constexpr uint32_t num_voices = 8;
  struct DSPVoiceState
  {
  };

  DSPVoiceState voice[8];
  uint32_t majorCycle;
};

class Controller
{
public:
  virtual ~Controller() {}

  // Retrieve state from the system
  virtual bool getCPUState(CPUState *) = 0;
  virtual bool getDSPState(DSPState *) = 0;
  virtual bool getMemoryState(MemoryState *) = 0;

  // Set State
  virtual bool setCPURegister(uint8_t registerIndex, uint8_t value) = 0;
  virtual bool setDSPRegister(uint8_t registerIndex, uint8_t value) = 0;
  virtual bool setMemorySpan(uint16_t addressOffset, uint16_t range, uint8_t *data) = 0;

  // Hardware control
  virtual void singleStep() = 0;
  virtual void resume() = 0;
  virtual void stop() = 0;
  virtual void setSpeed() = 0;

  virtual uint64_t getCycleCount() const = 0;
};
