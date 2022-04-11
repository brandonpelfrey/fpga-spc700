#pragma once

#include "controller.h"

#include "BasicBench.h"
#include "VTestDSP.h"

#include <memory>
#include <thread>

class RAM
{
private:
  std::array<u8, 64 * 1024> data;

public:
  void put(u16 addr, u8 val) { data[addr] = val; }
  void put(u16 addr, u32 length, u8 *source)
  {
    memcpy(&data[addr], source, length);
  }
  u8 get(u16 addr) { return data[addr]; }

  void load(const char *path)
  {
    auto file = fopen(path, "rb");
    fseek(file, 0, SEEK_END);
    const u64 file_size = ftell(file);
    fseek(file, 0, SEEK_SET);
    fread(&data[0], sizeof(u8), file_size, file);
    fclose(file);
  }
};

class VerilatorController : public Controller
{
public:
  VerilatorController();
  ~VerilatorController();

  void setAudioQueue(AudioQueue *audio_queue) final { m_audio_queue = audio_queue; }
  AudioQueue *getAudioQueue() final { return m_audio_queue; }

  // Retrieve state from the system
  bool getCPUState(CPUState *);
  bool getDSPState(DSPState *);
  bool getMemoryState(MemoryState *);

  // Set State
  bool setCPURegister(uint8_t registerIndex, uint8_t value);
  bool setDSPRegister(uint8_t registerIndex, uint8_t value);
  bool setMemorySpan(uint16_t addressOffset, uint32_t range, uint8_t *data);

  // Hardware control
  void singleStep();
  void resume();
  void stop();
  void setSpeed();
  void reset();

  uint64_t getCycleCount() const final { return m_dsp_bench->get_tick_count(); }

private:
  void sim_thread_func();

  int32_t m_step_count = -1;
  bool m_quit = false;

  std::thread m_thread;
  std::shared_ptr<BasicBench<VTestDSP>> m_dsp_bench;
  RAM m_ram;
  AudioQueue *m_audio_queue = nullptr;
};
