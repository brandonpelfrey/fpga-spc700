#include <cstdint>

#include "BasicBench.h"
#include "VTestDSP.h"

class SPCDSPBench : public BasicBench<VTestDSP>
{
public:
};

void dsp_test_donothing(SPCDSPBench &bench)
{
  bench.reset();
  bench.tick();

  for (int i = 0; i < 100; ++i)
  {
    bench.tick();
  }

  printf("Simulated %llu ticks\n", bench.time());
}

int main(int argc, char **argv, char **env)
{
  Verilated::commandArgs(argc, argv);
  SPCDSPBench bench;

  dsp_test_donothing(bench);
  return 0;
}
