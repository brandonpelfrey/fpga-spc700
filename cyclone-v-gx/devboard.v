module clock_divider(input_clock, i2c_clock, audio_clock, cpu_clock);
	input input_clock;
	
	output i2c_clock;
	output audio_clock;
	output cpu_clock;
	
	reg [27:0] divider_state;
	
	assign i2c_clock = divider_state[15];
	assign audio_clock = divider_state[2];
	assign cpu_clock = divider_state[23];
	
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
		AUD_XCK, AUD_BCLK, AUD_DACDAT, AUD_DACLRCK // Audio Codec (SSM2603)
);
	// Clocks
	input CLK50;
	wire CLK_AUDIO;
	wire CLK_I2C;
	wire CLK_CPU;
	
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
	
	// Clock Control
	clock_divider divider(CLK50, CLK_I2C, CLK_AUDIO, CLK_CPU);
	
	// Push Button Controls
	wire i2c_button_read;
	wire i2c_button_write;
	wire i2c_button_start;
	wire i2c_button_end;
	
	button_debounce debouncer1(CLK_I2C, PB[0], i2c_button_read);
	button_debounce debouncer2(CLK_I2C, PB[1], i2c_button_write);
	button_debounce debouncer3(CLK_I2C, PB[2], i2c_button_end);
	button_debounce debouncer4(CLK_I2C, PB[3], i2c_button_start);
	
	// I2C Master
	reg i2c_start, i2c_end, i2c_write, i2c_read;
	wire [7:0] i2c_in;
	reg [7:0] i2c_out;
	wire i2c_error;
	wire i2c_ready;
	
	i2c_master i2c(CLK_I2C, I2C_SCLK, I2C_SDAT,
	               i2c_start, i2c_end, i2c_write, i2c_read,
	               i2c_error, i2c_ready, i2c_in, i2c_out);
	
	// Audio Codec controller
//	ssm2603_codec audio_codec(CLK_AUDIO, AUD_XCK, AUD_BCLK, AUD_DACDAT, AUD_DACLRCK);

	wire MCLK = CLK_AUDIO;
	
	reg[2:0] bclk_counter;
	always @(posedge MCLK) begin
		bclk_counter <= bclk_counter + 3'd1;
	end
	
	assign AUD_BCLK = bclk_counter[2];
	assign AUD_XCK = MCLK;
	
	i2s audio_codec(
		.BCLK(AUD_BCLK),
		.DAC_LR_CLK(AUD_DACLRCK),
		.DAC_DATA(AUD_DACDAT)
	);
	
	// Soft CPU
	wire [15:0]CPU_R0;
	wire [15:0]CPU_MEM_ADDRESS;
	
	//cpu_blockram cpu_ram(CLK_CPU, CPU_MEM_ADDRESS[8:1], CPU_MEM_BUS, CPU_MEM_WRITE);
	//cpu16 cpu(i2c_button_start, CLK_CPU, CPU_R0, CPU_MEM_ADDRESS);
	
	// Debug Outputs
	assign LEDG[0] = CLK_CPU;
	assign LEDG[1] = PB[1];
	
	hexdisplay hex0(CPU_MEM_ADDRESS[3:0],   HEX0);
	hexdisplay hex1(CPU_MEM_ADDRESS[7:4],   HEX1);
//	hexdisplay hex2(CPU_MEM_ADDRESS[11:8],  HEX2);
//	hexdisplay hex3(CPU_MEM_ADDRESS[15:12], HEX3);
	
	
	wire [8*4 - 1:0] dsp_voice_states_out;
	wire [2:0] decoder_state;
	wire [15:0] dsp_ram_addr = CPU_MEM_ADDRESS;
	wire [7:0] dsp_ram_data = SW[7:0];
	
	wire [15:0] dsp_reg_address;
	wire [7:0] dsp_reg_data_in;
	wire [7:0] dsp_reg_data_out;
	wire dsp_reg_write_enable;
	
	wire [15:0] dsp_l;
	wire [15:0] dsp_r;
	
	wire [5:0] major_step;
	
//	assign LEDG[3:1] = dsp_l[3:1];
//	assign LEDG[7:4] = dsp_l[7:4];
	
	assign LEDR[0] = dsp_voice_states_out[4*0 + 3 : 4*0] == 4'd2;
	assign LEDR[1] = dsp_voice_states_out[4*1 + 3 : 4*1] == 4'd2;
	assign LEDR[2] = dsp_voice_states_out[4*2 + 3 : 4*2] == 4'd2;
	assign LEDR[3] = dsp_voice_states_out[4*3 + 3 : 4*3] == 4'd2;
	assign LEDR[4] = dsp_voice_states_out[4*4 + 3 : 4*4] == 4'd2;
	assign LEDR[5] = dsp_voice_states_out[4*5 + 3 : 4*5] == 4'd2;
	assign LEDR[6] = dsp_voice_states_out[4*6 + 3 : 4*6] == 4'd2;
	assign LEDR[7] = dsp_voice_states_out[4*7 + 3 : 4*7] == 4'd2;
	
	hexdisplay hex2(major_step[3:0], HEX2);
	hexdisplay hex3(major_step[5:4], HEX3);
	
	DSP dsp(
	  .ram_address(dsp_ram_addr),
	  .ram_data(dsp_ram_data),
	  .ram_write_enable(0),

	  .dsp_reg_address(dsp_reg_address),
	  .dsp_reg_data_in(dsp_reg_data_in),
	  .dsp_reg_data_out(dsp_reg_data_out),
	  .dsp_reg_write_enable(dsp_reg_write_enable),

	  .clock(CLK_CPU),
	  .reset(i2c_button_read),
	  .dac_out_l(dsp_l),
	  .dac_out_r(dsp_r),
	  .voice_states_out(dsp_voice_states_out),
	  .major_step(major_step)
	);
endmodule
