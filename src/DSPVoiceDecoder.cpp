#include <cstdint>
#include <vector>
#include <array>

#include "BasicBench.h"
#include "VDSPVoiceDecoder.h"
#include "types.h"
#include "wave.h"

const unsigned DSP_CYCLES_PER_SAMPLE = 96;
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

class DSPVoiceBench : public BasicBench<VDSPVoiceDecoder>
{
};

static char *STATE_NAMES[] = {
    "INIT",
    "HEADER",
    "DATA",
    "PROCESS",
    "OUTPUT",
    "END",
};

void dsp_test_wave_out(DSPVoiceBench &bench, const char *brr_path)
{
  RAM ram;
  ram.load(brr_path);

  const auto voice = bench.get();
  voice->pitch = 4096;
  voice->start_address = 0;
  // TODO: Loop point is not properly set, so loop will happen at the beginning

  bench.reset();
  WaveRecorder recorder;

  bool advance_set = false;
  unsigned samples = 0;
  for (int i = 0; i < 200000 && samples < 32000; ++i)
  {
    const int read_requested = voice->ram_read_request & 1;
    const int state = voice->state;
    const s16 output = voice->current_output;
    const unsigned cursor = voice->cursor;
    const unsigned block_index = voice->DSPVoiceDecoder__DOT__block_index;
    printf("[%06u] state:%8s read:%d cursor:%8u block_index:%u output:%d\n", i, STATE_NAMES[state], read_requested, cursor, block_index, output);

    if (voice->state == 5)
      break;

    voice->ram_data = ram.get(voice->ram_address);
    bench.tick();

    // When we're in the OUTPUT_AND_WAIT state, we need to trigger a pulse in advance_trigger to get our next sample.
    if (!advance_set && voice->state == 4)
    {
      voice->advance_trigger = 1;
      advance_set = true;
      recorder.push(output, output);
      samples++;
    }
    else if (advance_set)
    {
      voice->advance_trigger = 0;
      advance_set = false;
    }
  }
  recorder.save("./build/dsp_voice_test_wave_out.wav");
  printf("Simulated %llu ticks\n", bench.time());
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

  DSPVoiceBench bench;
  //dsp_test_wave_out(bench);
  dsp_test_wave_out(bench, argv[1]);
  return 0;
}