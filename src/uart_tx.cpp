#include <cstdint>
#include <vector>
#include <array>

#include "BasicBench.h"
#include "Vuart_tx.h"
#include "types.h"


class UartTxBench : public BasicBench<Vuart_tx>
{
public:
};

void test_uart_tx(UartTxBench& bench) {
  bench.reset();
  bench->byte_out = 0b11110101;
  bench->write_trigger = 1;

  for(int i=0; i<8*12; ++i) {
    bench.tick();
    bench->write_trigger = 0;
    u8 uart_data = bench->uart_data;

    if(i % 8 == 0) {
      printf("t=%2u ", i);
    } else {
      printf("%u, ", uart_data);
      if(i%8 == 7)
       printf("\n");
    }
  }
}

int main(int argc, char **argv, char **env)
{
  Verilated::commandArgs(argc, argv);
  UartTxBench bench;
  test_uart_tx(bench);
  return 0;
}
