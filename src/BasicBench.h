#pragma once

#include "verilated.h"

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
