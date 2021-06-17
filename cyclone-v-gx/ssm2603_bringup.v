module ssm2603_bringup(
	input start_trigger,
	input CLK_I2C,
	output i2c_out,
	output i2c_start,
	output i2c_end,
	output i2c_write,
	output i2c_read,
	input i2c_ready,
	input i2c_error	
);

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
		if(start_trigger)
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

endmodule