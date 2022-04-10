#pragma once

#include "controller.h"

#include "BasicBench.h"
#include "VTestDSP.h"

#include <memory>
#include <thread>

class VerilatorController : public Controller
{
public:
  VerilatorController();
  ~VerilatorController();

  // Retrieve state from the system
  bool getCPUState(CPUState *);
  bool getDSPState(DSPState *);
  bool getMemoryState(MemoryState *);

  // Set State
  bool setCPURegister(uint8_t registerIndex, uint8_t value);
  bool setDSPRegister(uint8_t registerIndex, uint8_t value);
  bool setMemorySpan(uint16_t addressOffset, uint16_t range, uint8_t *data);

  // Hardware control
  void singleStep();
  void resume();
  void stop();
  void setSpeed();

  uint64_t getCycleCount() const final { return m_cycles; }

private:
  void sim_thread_func();

  uint64_t m_cycles = 0;
  int32_t m_step_count = -1;
  bool m_quit = false;

  std::thread m_thread;
  std::shared_ptr<BasicBench<VTestDSP>> m_dsp_bench;
};
