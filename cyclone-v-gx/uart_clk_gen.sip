set_global_assignment -entity "uart_clk_gen" -library "lib_uart_clk_gen" -name IP_TOOL_NAME "altera_pll"
set_global_assignment -entity "uart_clk_gen" -library "lib_uart_clk_gen" -name IP_TOOL_VERSION "20.1"
set_global_assignment -entity "uart_clk_gen" -library "lib_uart_clk_gen" -name IP_TOOL_ENV "mwpim"
set_global_assignment -library "lib_uart_clk_gen" -name SPD_FILE [file join $::quartus(sip_path) "uart_clk_gen.spd"]

set_global_assignment -library "lib_uart_clk_gen" -name MISC_FILE [file join $::quartus(sip_path) "uart_clk_gen_sim/uart_clk_gen.vo"]
