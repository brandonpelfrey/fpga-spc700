#include <cstdint>

#include "VSimulatorTop.h"
#include "verilated.h"

#define TILE_WIDTH 32
#define TILE_HEIGHT 32

template <class Module>
class BasicBench
{
public:
  BasicBench()
      : m_tick(0), m_module(new Module)
  {
    return;
  }

  ~BasicBench()
  {
    delete m_module;
  }

  void reset()
  {
    m_module->reset = 1;
    m_module->eval();
    m_module->clock = 1;
    m_module->eval();
    m_module->reset = 0;
    m_module->clock = 0;
    m_module->eval();

    m_tick = 0;
  }

  void tick()
  {
    m_module->eval();
    m_module->clock = 1;
    m_module->eval();
    m_module->clock = 0;

    ++m_tick;
  }

  bool done() const
  {
    return Verilated::gotFinish();
  }

  uint64_t time() const
  {
    return m_tick;
  }

  Module *operator->()
  {
    return m_module;
  }

  const Module *operator->() const
  {
    return m_module;
  }

  Module *get()
  {
    return m_module;
  }

  const Module *get() const
  {
    return m_module;
  }

private:
  uint64_t m_tick;
  Module *const m_module;
};

class SPCAudioBench : public BasicBench<VSimulatorTop>
{
public:
  void
  destage_tile(uint32_t *framebuffer)
  {
    // for (unsigned i = 0; i < TILE_WIDTH * TILE_HEIGHT; ++i)
    // {
    //   get()->read_address = i;
    //   tick();
    //   framebuffer[i] = get()->read_color;
    // }
  }
};

int main(int argc, char **argv, char **env)
{
  Verilated::commandArgs(argc, argv);
  SPCAudioBench bench;

  /* Issue render start */
  bench.reset();
  bench.tick();

  while (!bench->idle)
  {
    bench.tick();
  }

  printf("Simulated %lu ticks\n", bench.time());

  /* Load result for display. */
  // uint32_t framebuffer[TILE_WIDTH * TILE_HEIGHT];
  // bench.destage_tile(framebuffer);
  // write_ppm("bench.ppm", framebuffer);
  // system("display -resize 512x512 -filter point bench.ppm");

  return 0;
}
