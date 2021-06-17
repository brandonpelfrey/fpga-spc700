module clock_divider(input_clock, i2c_clock, audio_clock, audio_bclk, cpu_clock);
	input input_clock;
	
	output i2c_clock;
	output audio_clock;
	output audio_bclk;
	output cpu_clock;
	
	reg [27:0] divider_state;
	
	assign i2c_clock = divider_state[15];
	assign audio_clock = divider_state[1];
	assign audio_bclk = divider_state[3];
	assign cpu_clock = divider_state[21];
	
	// 50mhz input
	// /4 -> ~12.288 Mhz mclk
	// /4 -> bclk @ 32000khz gets 96 cycles per L/R pair
	
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
	
	assign AUD_XCK = CLK_AUDIO;
	
	// Clock Control
	clock_divider divider(CLK50, CLK_I2C, CLK_AUDIO, AUD_BCLK, CLK_CPU);
	
	// Push Button Controls
	wire i2c_button_read;
	wire i2c_button_write;
	wire i2c_button_start;
	wire i2c_button_end;
	wire pb1_debounced;
	wire pb3_debounced;
	
	button_debounce debouncer1(CLK_I2C, ~PB[0], i2c_button_read);
	button_debounce debouncer2(CLK_I2C, ~PB[1], pb1_debounced);
	button_debounce debouncer3(CLK_I2C, ~PB[2], i2c_button_end);
	button_debounce debouncer4(CLK_I2C, ~PB[3], pb3_debounced);
	
	// I2C Master
	reg i2c_start, i2c_end, i2c_write, i2c_read;
	wire [7:0] i2c_in;
	reg [7:0] i2c_out;
	wire i2c_error;
	wire i2c_ready;
	
	i2c_master i2c(CLK_I2C, I2C_SCLK, I2C_SDAT,
	               i2c_start, i2c_end, i2c_write, i2c_read,
	               i2c_error, i2c_ready, i2c_in, i2c_out);
		
	localparam integer AUDIO_INIT_DATA [0:5*11 + 2 - 1][0:1] = '{
		// 
		'{4'b0001, 8'b0},
		
		'{4'b1000, 8'b0}, '{4'b0010, 8'h34}, '{4'b0010, 6 << 1}, '{4'b0010, 8'b00110000}, '{4'b0100, 8'b0},
		'{4'b1000, 8'b0}, '{4'b0010, 8'h34}, '{4'b0010, 0 << 1}, '{4'b0010, 8'b10010111}, '{4'b0100, 8'b0},
		'{4'b1000, 8'b0}, '{4'b0010, 8'h34}, '{4'b0010, 1 << 1}, '{4'b0010, 8'b10010111}, '{4'b0100, 8'b0},
		'{4'b1000, 8'b0}, '{4'b0010, 8'h34}, '{4'b0010, 2 << 1}, '{4'b0010, 8'b01100001}, '{4'b0100, 8'b0},
		'{4'b1000, 8'b0}, '{4'b0010, 8'h34}, '{4'b0010, 3 << 1}, '{4'b0010, 8'b01100001}, '{4'b0100, 8'b0},
		'{4'b1000, 8'b0}, '{4'b0010, 8'h34}, '{4'b0010, 4 << 1}, '{4'b0010, 8'b00010000}, '{4'b0100, 8'b0},
		'{4'b1000, 8'b0}, '{4'b0010, 8'h34}, '{4'b0010, 5 << 1}, '{4'b0010, 8'b00000000}, '{4'b0100, 8'b0},
		'{4'b1000, 8'b0}, '{4'b0010, 8'h34}, '{4'b0010, 7 << 1}, '{4'b0010, 8'b00001110}, '{4'b0100, 8'b0},
		'{4'b1000, 8'b0}, '{4'b0010, 8'h34}, '{4'b0010, 8 << 1}, '{4'b0010, 8'b00011000}, '{4'b0100, 8'b0},
		
		// Delay
		'{4'b0001, 8'b0},
		
		'{4'b1000, 8'b0}, '{4'b0010, 8'h34}, '{4'b0010, 9 << 1}, '{4'b0010, 8'b00000001}, '{4'b0100, 8'b0},
		'{4'b1000, 8'b0}, '{4'b0010, 8'h34}, '{4'b0010, 6 << 1}, '{4'b0010, 8'b00100000}, '{4'b0100, 8'b0}
	};	
			
	reg i2c_wait = 0;
	reg[15:0] i2c_queue_index = 16'b0;
	reg [3:0] i2c_queue_state = 4'b0000;
	reg [31:0] i2c_wait_counter = 32'b0;
	
	always @(posedge CLK_I2C)
		if(pb3_debounced)
			i2c_wait <= 1;
	
	always @(posedge CLK_I2C) begin
		case(i2c_queue_state)
			4'b0000: begin
				i2c_wait_counter <= 32'b0;
				i2c_read         <= 0;
				
				if(i2c_wait & i2c_ready) begin
					i2c_queue_index <= i2c_queue_index + 4'b0001;
					if(AUDIO_INIT_DATA[i2c_queue_index][0][0]) begin
						i2c_queue_state <= 4'b0010;
					end else begin
						i2c_start <= AUDIO_INIT_DATA[i2c_queue_index][0][3];
						i2c_end   <= AUDIO_INIT_DATA[i2c_queue_index][0][2];
						i2c_write <= AUDIO_INIT_DATA[i2c_queue_index][0][1];
						i2c_out   <= AUDIO_INIT_DATA[i2c_queue_index][1][7:0];
						i2c_queue_state <= 4'b0001;
					end
				end
			end
			
			4'b0001: begin
				i2c_start <= 0;
				i2c_end <= 0;
				i2c_write <= 0;
				
				if(i2c_error || i2c_queue_index == (5*11+2-1)) // Maybe done?
					i2c_queue_state <= 4'b1000;
				else	
					i2c_queue_state <= 4'b0000;
			end
			
			4'b0010: begin
				if(i2c_wait_counter >= 50 ) begin // Wait ~50ms
					i2c_queue_state <= 4'b0000;
				end else begin
					i2c_wait_counter <= i2c_wait_counter + 32'b1;
				end
			end
			
			4'b1000: begin
				// Terminal I2C Setup state. Do nothing.
				i2c_queue_state <= 4'b1000;
			end
			
			default: begin
				i2c_queue_state <= 4'b0000;
			end
		endcase
	end				
						
	
	// Audio Codec controller
	ssm2603_codec audio_codec(AUD_BCLK, AUD_DACDAT, AUD_DACLRCK);

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
	assign LEDG[7] = i2c_wait;
	
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
