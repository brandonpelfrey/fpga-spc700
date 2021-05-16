#include <cstdint>
#include <vector>

#include "BasicBench.h"
#include "VTestDSP.h"

using u8 = uint8_t;
using u16 = uint16_t;
using u32 = uint32_t;
using u64 = uint64_t;

using s16 = int16_t;

const unsigned DSP_AUDIO_RATE = 32000;
const unsigned DSP_CYCLES_PER_SAMPLE = 96;
const unsigned DSP_CYCLES_PER_SEC = DSP_AUDIO_RATE * DSP_CYCLES_PER_SAMPLE;

namespace Wave
{
  struct RiffDescriptor
  {
    u32 chunkId;
    u32 chunkSize;
    u32 chunkFormat;
  };
  struct FMTSubChunk
  {
    u32 subchunk1ID;
    u32 subchunk1Size;
    u16 audioFormat;
    u16 numChannels;
    u32 sampleRate;
    u32 byteRate;
    u16 blockAlign;
    u16 bitsPerSample;
  };
  struct DataSubChunk
  {
    u32 subchunk2ID;
    u32 subchunk2Size;
  };
};

u32 rev(u32 in)
{
  const u32 a = (in >> 0) & 0xFF;
  const u32 b = (in >> 8) & 0xFF;
  const u32 c = (in >> 16) & 0xFF;
  const u32 d = (in >> 24) & 0xFF;
  return (a << 24) | (b << 16) | (c << 8) | (d << 0);
}

class WaveRecorder
{
private:
  std::vector<s16> m_samples;

public:
  WaveRecorder() {}
  void push(s16 left, s16 right)
  {
    m_samples.push_back(left);
    m_samples.push_back(right);
  }

  void save(const char *path)
  {
    // http://soundfile.sapp.org/doc/WaveFormat/

    assert(m_samples.size() % 2 == 0);
    const u32 dataSize = m_samples.size() * 2;

    auto f = fopen(path, "wb");
    {
      Wave::RiffDescriptor riff{rev(0x52494646), 36 + dataSize, rev(0x57415645)};
      fwrite(&riff, sizeof(riff), 1, f);
    }
    {
      Wave::FMTSubChunk fmt{rev(0x666d7420), 16, 1, 2, DSP_AUDIO_RATE, DSP_AUDIO_RATE * 2 * 2, 4, 16};
      fwrite(&fmt, sizeof(fmt), 1, f);
    }
    {
      Wave::DataSubChunk data{rev(0x64617461), dataSize};
      fwrite(&data, sizeof(data), 1, f);
    }
    fwrite(&m_samples[0], sizeof(u16), m_samples.size(), f);
    fclose(f);
  }
};

class SPCDSPBench : public BasicBench<VTestDSP>
{
public:
};

void dsp_test_wave_out(SPCDSPBench &bench)
{
  bench.reset();
  bench.tick();

  WaveRecorder recorder;
  for (int i = 0; i < DSP_CYCLES_PER_SEC; ++i)
  {
    if (i % DSP_CYCLES_PER_SAMPLE == 0)
    {
      auto dsp_test = bench.get();
      recorder.push(bench.get()->dac_out_l, bench.get()->dac_out_r);
    }

    bench.tick();
  }
  recorder.save("./build/test/dsp_test_wave_out.wav");
  printf("Simulated %llu ticks\n", bench.time());
}

int main(int argc, char **argv, char **env)
{
  Verilated::commandArgs(argc, argv);
  SPCDSPBench bench;

  dsp_test_wave_out(bench);
  return 0;
}
