module clock_divider(
	input in_50_mhz, 
	
	output out_18_432_mhz,
	output out_audio_mclk,
	output out_audio_bclk,
	output out_i2c_clock
);
	
	// Main clock for the system is 18.432 Mhz which supports common UART 
	// baud rates as well as the N*32 Khz frequencies needed for the audio
	// system.
	main_clk_gen clk_gen(
		.refclk(in_50_mhz),
		.outclk_0(out_18_432_mhz)
	);
	
	// Audio clocks (SSM2603 Data sheet, page 26)
	// - MCLK can be 18.432 Mhz with SR mode b0110
	// - BCLK == (32,000 samp/sec * 2 channels * 32bits/samp) = 2.048 Mhz
	//   - (This means BCLK is main clock / 9)
	//     This isn't an even multiple :( . But we do 4 cycles low, 5 cycles high
	
	reg [3:0] bclk_counter = 0;
	reg bclk_tictoc;
	always @(posedge out_18_432_mhz) begin
		bclk_counter <= (bclk_counter == 4'd8) ? 0 : bclk_counter + 4'd1;
		
		if(bclk_counter == 4'd8)
			bclk_tictoc <= 0;
		if(bclk_counter == 4'd3)
			bclk_tictoc <= 1;			
	end
	
	assign out_audio_mclk = out_18_432_mhz;
	assign out_audio_bclk = bclk_tictoc;
	
	// UART clocking
	// 115200 baud ~ 160 main clock cycles per uart clock tick
	// 460800 baud ~ 40  main clock cycles per uart clock tick
	// UART modules internally handle clock division so we don't produce signals here.
	
	// I2C clocking ~ 18.432 Mhz / 2^10 = 18 Khz
	reg [11:0] i2c_counter;
	always @(posedge out_18_432_mhz)
		i2c_counter <= i2c_counter + 12'd1;
		
	assign out_i2c_clock = i2c_counter[9];
	
endmodule

module devboard(
	input  [9:0] SW, 
	input  [3:0] PB,
	output [9:0] LEDR, 
	output [7:0] LEDG,
	
	input CLK50,  // Reference Clock
	
	output [6:0] HEX0,   // Output 7-segment Displays
	output [6:0] HEX1, 
	output [6:0] HEX2,
	output [6:0] HEX3, 
	
	output I2C_SCLK, // I2C bus (HDMI, Audio)
	inout I2C_SDAT,     
	
	output AUD_MCLK,  // Audio Codec (SSM2603)
	output AUD_BCLK,
	output AUD_DACDAT,
	output AUD_DACLRCK, 
	
	output UART_TX, // UART
	input UART_RX
);
	// Clocks
	wire CLK_AUDIO;
	wire CLK_I2C;
		
	assign AUD_MCLK = CLK_AUDIO;
	wire uart_clk;
	wire clk_18_432_mhz;
	
	// Clock Generation
	clock_divider divider(
		.in_50_mhz(CLK50),
		.out_18_432_mhz(clk_18_432_mhz),
		.out_audio_mclk(CLK_AUDIO),
		.out_audio_bclk(AUD_BCLK),
		.out_i2c_clock(CLK_I2C)
	);
	
	assign uart_clk = clk_18_432_mhz;
	
	// Push Button Controls
	wire pb0_debounced;
	wire pb1_debounced;
	wire pb2_debounced;
	wire pb3_debounced;
	button_debounce debouncer1(CLK_I2C, ~PB[0], pb0_debounced);
	button_debounce debouncer2(CLK_I2C, ~PB[1], pb1_debounced);
	button_debounce debouncer3(CLK_I2C, ~PB[2], pb2_debounced);
	button_debounce debouncer4(CLK_I2C, ~PB[3], pb3_debounced);
	
	// UART	
	reg [7:0]  uart_byte /* synthesis noprune */;
	reg uart_tx_write /* synthesis noprune */;
	wire uart_tx_ready;
	
	uart_tx uart_tx_0 (
	  .clock(uart_clk),
	  .uart_data(UART_TX),    
	  .byte_out(uart_byte),    
	  .write_trigger(uart_tx_write),    
	  .ready_to_transmit(uart_tx_ready),
	  .reset(0)
	);
	defparam uart_tx_0.CLOCKS_PER_BIT = 40;
	
	wire [7:0] byte_in;
	wire uart_rx_byte_ready;
	uart_rx uart_rx_0 (
	  .clock(uart_clk),
	  .uart_data(UART_RX),   
	  .byte_in(byte_in),
	  .byte_ready(uart_rx_byte_ready),
	  .reset(0)
	);
	defparam uart_rx_0.CLOCKS_PER_BIT = 40;
		
	reg [7:0] uart_rx_byte_latch;
	always @(posedge uart_clk)
		if(uart_rx_byte_ready)
			uart_rx_byte_latch <= byte_in;
	
	hexdisplay hex2(uart_rx_byte_latch[3:0], HEX2);
	hexdisplay hex3(uart_rx_byte_latch[7:4], HEX3);
	
	wire apu_reset;
	wire audio_reset;
	uart_processor uart_processor_0 (
		.clock(uart_clk),
		.in_uart_byte(byte_in),
	   .in_uart_byte_ready(uart_rx_byte_ready),
		.apu_reset(apu_reset),
		.audio_reset(audio_reset)
	);
	
	// I2C Master
	reg i2c_start, i2c_end, i2c_write, i2c_read;
	wire [7:0] i2c_in;
	reg [7:0] i2c_out;
	wire i2c_error;
	wire i2c_ready;
	
	i2c_master i2c(CLK_I2C, I2C_SCLK, I2C_SDAT,
	               i2c_start, i2c_end, i2c_write, i2c_read,
	               i2c_error, i2c_ready, i2c_in, i2c_out);

	ssm2603_bringup audio_bringup(
		.start_trigger(audio_reset),
		.CLK_I2C(CLK_I2C),
		.i2c_out(i2c_out),
		.i2c_start(i2c_start),
		.i2c_end(i2c_end),
		.i2c_write(i2c_write),
		.i2c_read(i2c_read),
		.i2c_ready(i2c_ready),
		.i2c_error(i2c_error)	
	);
			
	// Audio Codec controller
	wire signed [15:0] audio_sample_l16;
	wire signed [15:0] audio_sample_r16;
	ssm2603_codec audio_codec(AUD_BCLK, AUD_DACDAT, AUD_DACLRCK, audio_sample_l16, audio_sample_r16);
	
	wire [15:0] ram_address;
	wire [7:0] ram_data;
	wire ram_clock = AUD_BCLK;
	wire ram_we = 0;
	SPC700RAM apu_ram( 
		.address(ram_address),
		.data(ram_data),
		.clock(ram_clock),
		.write_enable(ram_we)
	);

	// Soft CPU
	wire [15:0]CPU_R0;
	wire [15:0]CPU_MEM_ADDRESS;
		
	// Debug Outputs
	//assign LEDG[0] = CLK_CPU;
	assign LEDG[1] = pb1_debounced;
	assign LEDG[3] = i2c_start;
	assign LEDG[4] = i2c_end;
	assign LEDG[5] = i2c_write;
	assign LEDG[6] = i2c_read;
	assign LEDG[7] = 0;
	
	hexdisplay hex0(CPU_MEM_ADDRESS[3:0],   HEX0);
	hexdisplay hex1(CPU_MEM_ADDRESS[7:4],   HEX1);
//	hexdisplay hex2(CPU_MEM_ADDRESS[11:8],  HEX2);
//	hexdisplay hex3(CPU_MEM_ADDRESS[15:12], HEX3);
	
	wire [8*4 - 1:0] dsp_voice_states_out;
	wire [2:0] decoder_state;
	wire [15:0] dsp_ram_addr = ram_address;
	wire [7:0] dsp_ram_data = ram_data;
	wire [15:0] dsp_reg_address;
	wire [7:0] dsp_reg_data_in;
	wire [7:0] dsp_reg_data_out;
	wire dsp_reg_write_enable;
	wire signed [15:0] dsp_l = audio_sample_l16;
	wire [15:0] dsp_r = audio_sample_r16;
	wire [5:0] major_step;
	
	assign LEDR[0] = dsp_voice_states_out[4*0 + 3 : 4*0] == 4'd2;
	assign LEDR[1] = dsp_voice_states_out[4*1 + 3 : 4*1] == 4'd2;
	assign LEDR[2] = dsp_voice_states_out[4*2 + 3 : 4*2] == 4'd2;
	assign LEDR[3] = dsp_voice_states_out[4*3 + 3 : 4*3] == 4'd2;
	assign LEDR[4] = dsp_voice_states_out[4*4 + 3 : 4*4] == 4'd2;
	assign LEDR[5] = dsp_voice_states_out[4*5 + 3 : 4*5] == 4'd2;
	assign LEDR[6] = dsp_voice_states_out[4*6 + 3 : 4*6] == 4'd2;
	assign LEDR[7] = dsp_voice_states_out[4*7 + 3 : 4*7] == 4'd2;
	
	DSP dsp(
	  .ram_address(dsp_ram_addr),
	  .ram_data(dsp_ram_data),
	  .ram_write_enable(0),

	  .dsp_reg_address(dsp_reg_address),
	  .dsp_reg_data_in(dsp_reg_data_in),
	  .dsp_reg_data_out(dsp_reg_data_out),
	  .dsp_reg_write_enable(dsp_reg_write_enable),

	  .clock(AUD_BCLK), 
	  .reset(apu_reset),
	  .dac_out_l(dsp_l),
	  .dac_out_r(dsp_r),
	  .voice_states_out(dsp_voice_states_out),
	  .major_step(major_step)
	);
endmodule
