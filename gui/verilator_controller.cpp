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

  for(u8 i=0; i<128; ++i) {
    out->register_values[i] = top.___05Fdebug_out_regs[i];
  }

  for (u8 i = 0; i < DSPState::num_voices; ++i)
  {
    const unsigned voice_state = (top.voice_states_out >> (i * 4)) & 0b1111;
    out->voice[i].fsm_state = voice_state;
    out->voice[i].decoder_address = top.___05Fdebug_voice_ram_address[i];
    out->voice[i].decoder_cursor = top.___05Fdebug_voice_cursors[i];
    out->voice[i].decoder_output = top.___05Fdebug_voice_output[i];
  }

  return true;
}
bool VerilatorController::getMemoryState(MemoryState *) { return true; }

// Set State
bool VerilatorController::setCPURegister(uint8_t registerIndex, uint8_t value) { return true; }

bool VerilatorController::setDSPRegister(uint8_t registerIndex, uint8_t value)
{
  std::lock_guard lock(m_user_command_mutex);
  UserCommand new_command = Command_SetDSPRegValue{registerIndex, value};
  m_user_commands.push_back(new_command);
  return true;
}

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
  const u8 max_volume = 0x7F;
  const u8 voice_volume = max_volume / 8;

  setDSPRegister(DSPRegister_VOLL0, voice_volume);
  setDSPRegister(DSPRegister_VOLL1, voice_volume);
  setDSPRegister(DSPRegister_VOLL2, voice_volume);
  setDSPRegister(DSPRegister_VOLL3, voice_volume);
  setDSPRegister(DSPRegister_VOLL4, voice_volume);
  setDSPRegister(DSPRegister_VOLL5, voice_volume);
  setDSPRegister(DSPRegister_VOLL6, voice_volume);
  setDSPRegister(DSPRegister_VOLL7, voice_volume);

  setDSPRegister(DSPRegister_VOLR0, voice_volume);
  setDSPRegister(DSPRegister_VOLR1, voice_volume);
  setDSPRegister(DSPRegister_VOLR2, voice_volume);
  setDSPRegister(DSPRegister_VOLR3, voice_volume);
  setDSPRegister(DSPRegister_VOLR4, voice_volume);
  setDSPRegister(DSPRegister_VOLR5, voice_volume);
  setDSPRegister(DSPRegister_VOLR6, voice_volume);
  setDSPRegister(DSPRegister_VOLR7, voice_volume);

  setDSPRegister(DSPRegister_ENVX0, voice_volume);
  setDSPRegister(DSPRegister_ENVX1, voice_volume);
  setDSPRegister(DSPRegister_ENVX2, voice_volume);
  setDSPRegister(DSPRegister_ENVX3, voice_volume);
  setDSPRegister(DSPRegister_ENVX4, voice_volume);
  setDSPRegister(DSPRegister_ENVX5, voice_volume);
  setDSPRegister(DSPRegister_ENVX6, voice_volume);
  setDSPRegister(DSPRegister_ENVX7, voice_volume);

  const u16 vpitch = 4096 / 4; // nominal
  const u8 PL = vpitch & 0xFF;
  const u8 PH = (vpitch >> 8) & 0x3F;

  setDSPRegister(DSPRegister_PL0, PL);
  setDSPRegister(DSPRegister_PL1, PL);
  setDSPRegister(DSPRegister_PL2, PL);
  setDSPRegister(DSPRegister_PL3, PL);
  setDSPRegister(DSPRegister_PL4, PL);
  setDSPRegister(DSPRegister_PL5, PL);
  setDSPRegister(DSPRegister_PL6, PL);
  setDSPRegister(DSPRegister_PL7, PL);

  setDSPRegister(DSPRegister_PH0, PH);
  setDSPRegister(DSPRegister_PH1, PH);
  setDSPRegister(DSPRegister_PH2, PH);
  setDSPRegister(DSPRegister_PH3, PH);
  setDSPRegister(DSPRegister_PH4, PH);
  setDSPRegister(DSPRegister_PH5, PH);
  setDSPRegister(DSPRegister_PH6, PH);
  setDSPRegister(DSPRegister_PH7, PH);

  setDSPRegister(DSPRegister_MVOLL, max_volume);
  setDSPRegister(DSPRegister_MVOLR, max_volume);
}

void VerilatorController::sim_thread_func()
{
  auto &top = *m_dsp_bench->get();
  while (!m_quit)
  {
    // Run any commands requested. Note that setting registers etc involves clocking the design!
    if (!m_user_commands.empty())
    {
      std::lock_guard lock(m_user_command_mutex);
      for (const auto &cmd_variant : m_user_commands)
      {
        if (std::holds_alternative<Command_SetDSPRegValue>(cmd_variant))
        {
          const Command_SetDSPRegValue &cmd = std::get<Command_SetDSPRegValue>(cmd_variant);
          top.dsp_reg_address = cmd.dsp_reg;
          top.dsp_reg_data_in = cmd.reg_value;
          top.dsp_reg_write_enable = 1;
          m_dsp_bench->tick();
          top.dsp_reg_write_enable = 0;
        }
      }
      m_user_commands.clear();
    }

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
