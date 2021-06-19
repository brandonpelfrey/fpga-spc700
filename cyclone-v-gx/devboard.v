module clock_divider(input_clock, i2c_clock, audio_clock, audio_bclk, cpu_clock);
	input input_clock;
	
	output i2c_clock;
	output audio_clock;
	output audio_bclk;
	output cpu_clock;
	
	reg [27:0] divider_state;
	
	assign i2c_clock = divider_state[15];
	assign cpu_clock = divider_state[21];
	
	wire clk_12288mhz = divider_state[1];
	
	// MCLK is 384 * sample rate (=32 Khz) = 12.288 Mhz
	wire mclk = clk_12288mhz;
	
	// BCLK is sample rate (32 Khz) * 2 * 32 = 2.048 Mhz (= mclk / 6)
	reg bclk;
	reg [31:0] bclk_counter;
	always @(posedge clk_12288mhz) begin
		if(bclk_counter == 32'd5) begin
			bclk_counter <= 0;
			bclk <= ~bclk;
		end else
			bclk_counter <= bclk_counter + 32'd1;
	end
	
	assign audio_clock = mclk;
	assign audio_bclk = bclk;
		
	always @(posedge input_clock)
	begin
		divider_state <= divider_state + 24'd1;
	end
endmodule

module devboard(
		SW, PB,                 // Input Switches
		LEDR, LEDG,             // Output LEDs
		CLK50,                  // Reference Clocks
		HEX0, HEX1, HEX2, HEX3, // Output 7-segment Displays
		I2C_SCLK, I2C_SDAT,     // I2C bus (HDMI, Audio)
		AUD_XCK, AUD_BCLK, AUD_DACDAT, AUD_DACLRCK, // Audio Codec (SSM2603)
		UART_TX, UART_RX
);
	// Clocks
	input CLK50;
	wire CLK_AUDIO;
	wire CLK_I2C;
	wire CLK_CPU;
	
	// UART
	output UART_TX;
	input  UART_RX;
	
	// User Input
	input [9:0]SW;
	input [3:0]PB;
	
	// LED / Displays
	output [6:0]HEX0;
	output [6:0]HEX1;
	output [6:0]HEX2;
	output [6:0]HEX3;
	output [9:0]LEDR;
	output [7:0]LEDG;
	
	// I2C
	output I2C_SCLK;
	inout wire I2C_SDAT;
	
	// Audio Codec
	output AUD_XCK; // Master clock
	output AUD_BCLK;
	output AUD_DACDAT;
	output AUD_DACLRCK;
	
	assign AUD_XCK = CLK_AUDIO;
	
	// Clock Control
	clock_divider divider(CLK50, CLK_I2C, CLK_AUDIO, AUD_BCLK, CLK_CPU);
	
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
	reg UART_BASE_CLK /* synthesis noprune */;
	uart_clk_gen uart_clk_gen_0 (.refclk(CLK50), .outclk_0(UART_BASE_CLK));
	
	// UART_BASE_CLK is 14.745600, which is 32 * 460800
	reg [7:0] uart_clk_counter /* synthesis noprune */;
	always @(posedge UART_BASE_CLK)
		uart_clk_counter <= uart_clk_counter + 1;
		
	// the base clock counter is 128 times the actual baud. We use 8 clock
	// cycles per bit, meaninng we should only divide by 16.
	wire uart_clk = uart_clk_counter[0];
	
	reg [7:0]  uart_byte /* synthesis noprune */;
	reg uart_tx_write /* synthesis noprune */;
	wire uart_tx_ready;
	
	reg uart_tx_dat /* synthesis noprune */;
	assign UART_TX = uart_tx_dat;
	
	uart_tx uart_tx_0 (
	  .clock(uart_clk),
	  .uart_data(uart_tx_dat),    
	  .byte_out(uart_byte),    
	  .write_trigger(uart_tx_write),    
	  .ready_to_transmit(uart_tx_ready),
	  .reset(0)
	);
	defparam uart_tx_0.CLOCKS_PER_BIT = 16;
	
	reg uart_rx_reg;
	always @(posedge uart_clk)
		uart_rx_reg <= UART_RX;
	
	wire [7:0] byte_in;
	wire uart_rx_byte_ready;
	uart_rx uart_rx_0 (
	  .clock(uart_clk),
	  .uart_data(uart_rx_reg),   
	  .byte_in(byte_in),
	  .byte_ready(uart_rx_byte_ready),
	  .reset(0)
	);
	defparam uart_rx_0.CLOCKS_PER_BIT = 16;
		
	reg [7:0] uart_rx_byte_latch;
	always @(posedge uart_clk)
		if(uart_rx_byte_ready)
			uart_rx_byte_latch <= byte_in;
	
	hexdisplay hex2(uart_rx_byte_latch[3:0], HEX2);
	hexdisplay hex3(uart_rx_byte_latch[7:4], HEX3);
	
	reg [3:0] tx_state = 0;
	always @(posedge uart_clk) begin
		case(tx_state) 
			4'd0: begin
				if(uart_tx_ready) begin
					tx_state <= 1;
					uart_byte <= uart_byte + 1;
					uart_tx_write <= 1;
				end
			end
			
			4'd1: begin
				uart_tx_write <= 0;
				tx_state <= 2;
			end
			
			4'd2: begin
				tx_state <= 0;
			end
		endcase
	end
	
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
		.start_trigger(pb3_debounced),
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
	assign LEDG[0] = CLK_CPU;
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
	  .reset(debounced_pb0),
	  .dac_out_l(dsp_l),
	  .dac_out_r(dsp_r),
	  .voice_states_out(dsp_voice_states_out),
	  .major_step(major_step)
	);
endmodule
