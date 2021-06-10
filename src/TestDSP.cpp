#include <cstdint>
#include <vector>

#include "BasicBench.h"
#include "VTestDSP.h"
#include "types.h"
#include "wave.h"

const unsigned DSP_CYCLES_PER_SAMPLE = 96;
const unsigned DSP_CYCLES_PER_SEC = DSP_AUDIO_RATE * DSP_CYCLES_PER_SAMPLE;
double global_time = 0;

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

u32 get_lowest_set_index(u32 in)
{
  for (u32 res = 0; res < 32; res++)
    if (in & (1 << res))
      return res;
  return 32;
}

double sc_time_stamp()
{
  return global_time;
}

int main(int argc, char **argv, char **env)
{
  Verilated::commandArgs(argc, argv);

  SPCDSPBench bench;
  dsp_test_wave_out(bench);
  return 0;
}
