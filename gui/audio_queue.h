#pragma once

#include <atomic>
#include <cassert>
#include <vector>

#include "types.h"

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
    sample_data[(head + 1) % SampleCount] = right;
    head += 2;
  }

  u32 availableFrames() const { return (head - tail) / 2; }

  void consumeFrames(SampleType *dst, u32 num_frames)
  {
    assert(availableFrames() >= num_frames);
    // TODO : 1 or 2 memcpys
    for (u32 i = 0; i < 2 * num_frames; ++i)
      *dst++ = sample_data[(tail + i) % SampleCount]; // i even=left, odd=right

    tail += num_frames * 2;
  }

private:
  std::vector<SampleType> sample_data;
  std::atomic<u64> head = {};
  std::atomic<u64> tail = {};
};
