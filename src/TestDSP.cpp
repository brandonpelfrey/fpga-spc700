#include <cstdint>
#include <vector>
#include <array>

#include "BasicBench.h"
#include "VTestDSP.h"
#include "VTestDSP_DSP.h"
#include "VTestDSP_TestDSP.h"
#include "types.h"
#include "wave.h"

const unsigned DSP_CYCLES_PER_SAMPLE = 64;
const unsigned DSP_CYCLES_PER_SEC = DSP_AUDIO_RATE * DSP_CYCLES_PER_SAMPLE;
double global_time = 0;

class RAM
{
private:
  std::array<u8, 64 * 1024> data;

public:
  void put(u16 addr, u8 val) { data[addr] = val; }
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

class SPCDSPBench : public BasicBench<VTestDSP>
{
public:
};

const char *const VOICE_STATES[] = {"i", "H", "D", "P", ".", "E"};

void dsp_test_wave_out(SPCDSPBench &bench, const char *brr_file_path)
{
  bench.reset();
  WaveRecorder recorder;

  RAM ram;
  ram.load(brr_file_path);

  // f * 2**(n / 12)
  // C Major (C E G C)
  const unsigned pitch[] = {4096, 5161, 6137, 8192, 2048, 1024, 512, 256};
  const unsigned MAXVOL = 0xEF;
  const unsigned Q = MAXVOL / 8;
  const unsigned vol[] = {Q, Q, Q, 0, 0, 0, 0, 0 };

  for (int v = 0; v < 8; v++)
  {
    const unsigned vpitch = pitch[v] * 1 / 8;

    // Pitch low (x2)
    bench->dsp_reg_address = (v << 4) | 2;
    bench->dsp_reg_data_in = vpitch & 0xFF;
    bench->dsp_reg_write_enable = 1;
    bench.tick();

    // Pitch high (x3)
    bench->dsp_reg_address = (v << 4) | 3;
    bench->dsp_reg_data_in = (vpitch >> 8) & 0xFF;
    bench->dsp_reg_write_enable = 1;
    bench.tick();

    // Volume Left (x0)
    bench->dsp_reg_address = (v << 4) | 0;
    bench->dsp_reg_data_in = vol[v];
    bench->dsp_reg_write_enable = 1;
    bench.tick();

    // Volume Right (x1)
    bench->dsp_reg_address = (v << 4) | 1;
    bench->dsp_reg_data_in = vol[v];
    bench->dsp_reg_write_enable = 1;
    bench.tick();
  }

  bench->dsp_reg_write_enable = 0;

  for (int i = 0; i < DSP_CYCLES_PER_SAMPLE * 32000 * 5; ++i)
  {
    const unsigned major_step = bench->major_step;

    // Logging
    if (0)
    {
      if (major_step == 0)
      {
        // printf("-------------------------------------\n");
        // printf("                      0 1 2 3 4 5 6 7 G\n");
      }
      // printf("[%08u] : major %2u ", i, major_step);
      for (int v = 0; v < 8; v++)
      {
        const unsigned voice_state = (bench->voice_states_out >> (v * 4)) & 0b1111;
        printf("%s ", VOICE_STATES[voice_state]);
      }
      printf(". | ");
      for (int v = 0; v < 8; v++)
      {
        // const unsigned pitch = bench->TestDSP__DOT__dsp__DOT__decoder_pitch[v];
        // printf("%6u ", pitch);
      }
      {
        const unsigned current_voice = bench->TestDSP->dsp->current_voice;
        const unsigned ram_address = bench->ram_address;
        // printf("current_voice %u ram_addr 0x%0X", current_voice, ram_address);
      }
      // printf("\n");
    }

    if (major_step == DSP_CYCLES_PER_SAMPLE-1)
    {
      // printf("%d\n", *(s16*)&bench->dac_out_l);
      recorder.push(bench->dac_out_l, bench->dac_out_r);
    }

    //////////////////////

    bench.tick();

    // Settle RAM access
    bench->ram_data = ram.get(bench->ram_address);
  }
  recorder.save("./build/dsp_test_wave_out.wav");
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

  if (argc < 2)
  {
    printf("Usage: %s brr_file_path\n", argv[0]);
    exit(1);
  }

  SPCDSPBench bench;
  dsp_test_wave_out(bench, argv[1]);
  return 0;
}
