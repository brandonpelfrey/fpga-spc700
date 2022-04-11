#pragma once

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
  };

  DSPVoiceState voice[8];
  u16 ram_address;
  u8 ram_data;
  u32 major_cycle;
};

class AudioQueue
{
public:
  static constexpr u32 SampleCount = (4096 * 4) * 2;
  using SampleType = s16;

  // head = no data, but would be the next location
  // tail = points to oldest data
  // if head==tail, empty

  AudioQueue()
  {
    sample_data.resize(SampleCount);
  }

  bool isFull() const
  {
    const u32 current_entries = head - tail;
    return current_entries >= SampleCount;
  }

  bool isEmpty() const { return head == tail; }

  void push(SampleType left, SampleType right)
  {
    assert(!isFull());
    sample_data[head % SampleCount] = left;
    head++;
    sample_data[head % SampleCount] = right;
    head++;
  }

  u32 availableFrames() const { return (head - tail) / 2; }

  void consumeFrames(SampleType *dst, u32 num_frames)
  {
    assert(availableFrames() >= num_frames);
    // TODO : 1 or 2 memcpys
    for (u32 i = 0; i < 2*num_frames; ++i)
      *dst++ = sample_data[(tail + i) % SampleCount]; // i even=left, odd=right

    tail += num_frames * 2;

    // Adjust head/tail to avoid wrapping since they both keep growing with push/consume calls.
    // This is stupid, but works. Could change the size calculations instead
    if (tail > SampleCount && head > SampleCount)
    {
      tail -= SampleCount;
      head -= SampleCount;
    }
  }

private:
  std::vector<SampleType> sample_data;
  std::atomic<u32> head = {};
  std::atomic<u32> tail = {};
};

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

  // Hardware control
  virtual void singleStep() = 0;
  virtual void resume() = 0;
  virtual void stop() = 0;
  virtual void setSpeed() = 0;
  virtual void reset() = 0;

  virtual uint64_t getCycleCount() const = 0;
};
