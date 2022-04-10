#include "verilator_controller.h"

#include "VTestDSP_DSP.h"
#include "VTestDSP_TestDSP.h"

#include <thread>

VerilatorController::VerilatorController()
{
  m_dsp_bench = std::make_shared<BasicBench<VTestDSP>>();
  m_dsp_bench->reset();
  m_thread = std::thread([&]()
                         { sim_thread_func(); });
}

VerilatorController::~VerilatorController()
{
  m_quit = true;
  m_thread.join();
}

bool VerilatorController::getCPUState(CPUState *) { return true; }
bool VerilatorController::getDSPState(DSPState *) { return true; }
bool VerilatorController::getMemoryState(MemoryState *) { return true; }

// Set State
bool VerilatorController::setCPURegister(uint8_t registerIndex, uint8_t value) { return true; }
bool VerilatorController::setDSPRegister(uint8_t registerIndex, uint8_t value) { return true; }
bool VerilatorController::setMemorySpan(uint16_t addressOffset, uint16_t range, uint8_t *data) { return true; }

// Hardware control
void VerilatorController::singleStep() { ; }
void VerilatorController::resume() { ; }
void VerilatorController::stop() { ; }
void VerilatorController::setSpeed() { ; }

void VerilatorController::sim_thread_func()
{
  while (!m_quit)
  {
    // TODO : Process commands from controller

    // Tick
    if (m_step_count)
    {
      m_dsp_bench->tick();
      m_cycles++;

      if (m_step_count > 0)
        m_step_count--;
    }
  }
}
