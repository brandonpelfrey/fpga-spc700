#include "verilator_controller.h"

#include "VTestDSP_DSP.h"
#include "VTestDSP_TestDSP.h"

#include <thread>
#include <vector>

const unsigned DSP_FRAME_RATE = 32000;
const unsigned DSP_CYCLES_PER_FRAME = 64;
const unsigned DSP_CYCLES_PER_SEC = DSP_FRAME_RATE * DSP_CYCLES_PER_FRAME;

VerilatorController::VerilatorController()
{
  m_dsp_bench = std::make_shared<BasicBench<VTestDSP>>();
  reset();

  // Kick off the simulation thread
  m_thread = std::thread([&]()
                         { sim_thread_func(); });
}

VerilatorController::~VerilatorController()
{
  m_quit = true;
  m_thread.join();
}

bool VerilatorController::getCPUState(CPUState *) { return true; }
bool VerilatorController::getDSPState(DSPState *out)
{
  if (!out)
    return false;

  // Some of how this is accessed will have to change once we have a more proper top module
  const auto &top = *m_dsp_bench->get();
  out->major_cycle = top.major_step;
  out->ram_address = top.ram_address;
  out->ram_data = top.ram_data;

  for (u8 i = 0; i < DSPState::num_voices; ++i)
  {
    const unsigned voice_state = (top.voice_states_out >> (i * 4)) & 0b1111;
    out->voice[i].fsm_state = voice_state;
  }

  return true;
}
bool VerilatorController::getMemoryState(MemoryState *) { return true; }

// Set State
bool VerilatorController::setCPURegister(uint8_t registerIndex, uint8_t value) { return true; }
bool VerilatorController::setDSPRegister(uint8_t registerIndex, uint8_t value) { return true; }
bool VerilatorController::setMemorySpan(uint16_t addressOffset, uint32_t range, uint8_t *data)
{
  assert(addressOffset < 64 * 1024);
  assert(addressOffset + range <= 64 * 1024);
  m_ram.put(addressOffset, range, data);
  return true;
}

// Hardware control
void VerilatorController::singleStep() { m_step_count = 1; }
void VerilatorController::resume() { m_step_count = -1; }
void VerilatorController::stop() { m_step_count = 0; }
void VerilatorController::setSpeed() { ; }
void VerilatorController::reset()
{
  m_dsp_bench->reset();

  // Initialize state
  const auto &top = *m_dsp_bench->get();
  for (int v = 0; v < 8; v++)
  {
    const u16 vpitch = 4096 / 4; // nominal
    const u8 max_volume = 0xEF;
    const u8 voice_volume = max_volume / 8;

    // Pitch low (x2)
    top.dsp_reg_address = (v << 4) | 2;
    top.dsp_reg_data_in = vpitch & 0xFF;
    top.dsp_reg_write_enable = 1;
    m_dsp_bench->tick();

    // Pitch high (x3)
    top.dsp_reg_address = (v << 4) | 3;
    top.dsp_reg_data_in = (vpitch >> 8) & 0x3F;
    top.dsp_reg_write_enable = 1;
    m_dsp_bench->tick();

    // Volume Left (x0)
    top.dsp_reg_address = (v << 4) | 0;
    top.dsp_reg_data_in = voice_volume;
    top.dsp_reg_write_enable = 1;
    m_dsp_bench->tick();

    // Volume Right (x1)
    top.dsp_reg_address = (v << 4) | 1;
    top.dsp_reg_data_in = voice_volume;
    top.dsp_reg_write_enable = 1;
    m_dsp_bench->tick();
  }

  top.dsp_reg_write_enable = 0;
}

void VerilatorController::sim_thread_func()
{
  auto &top = *m_dsp_bench->get();
  while (!m_quit)
  {
    // If we're buffering audio to the host, but the host hasn't consumed enough, we'll wait.
    if (m_audio_queue)
    {
      while (m_audio_queue->isFull())
        std::this_thread::yield();
    }

    // Clock the system
    if (m_step_count != 0)
    {
      // Clock the top module
      m_dsp_bench->tick();

      // Service shared RAM requests
      top.ram_data = m_ram.get(top.ram_address);

      if (m_step_count > 0)
        m_step_count--;

      // Audio output
      const bool sample_ready = top.major_step == DSP_CYCLES_PER_FRAME - 1;
      if (!m_audio_queue->isFull() && sample_ready)
        m_audio_queue->push(top.dac_out_l, top.dac_out_r);
    }
    else
    {
      std::this_thread::yield();
    }
  }
}
