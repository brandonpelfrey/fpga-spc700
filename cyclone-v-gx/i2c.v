module i2c_master(
	clock,                // Control and drive clock
	i2c_sclk, i2c_sdat,   // External I2C interface
	start_transaction, end_transaction, start_write, start_read, // Control Lines
	out_error, out_ready, // Status Lines
	data_in, data_out     // Data Feed / Output
);
	input clock;
	input start_transaction;
	input end_transaction;
	input start_write;
	input start_read;
	
	output out_error;
	output out_ready;
	
	output i2c_sclk;
	inout i2c_sdat;
	
	output [7:0] data_in;
	input [7:0] data_out;
	
	reg [3:0] state;
	reg busy;
	reg active;
	reg en_write, sclk, sdat, error;
	reg ready;
	
	reg [7:0] buf_in;
	reg [7:0] buf_out;
	
	reg [7:0] data;
	reg [3:0] i2c_state;
	reg [2:0] data_bit;
	
	assign i2c_sclk = sclk;
	assign i2c_sdat = en_write ? sdat : 1'bz;
	
	assign out_error = error;
	assign out_ready = ready;
	
	assign data_in = buf_in;
	
	always @(posedge clock)
	begin
		if (busy) begin
			case (state)
				// Re-Start Transaction
				4'b0000: begin
					busy <= 1'b1;
					active <= 1'b1;
					state <= 4'b1111;
					en_write <= 1'b1;
					sdat <= 1'b1;
					sclk <= 1'b1;
				end
				
				4'b1111: begin
					busy <= 1'b0;
					active <= 1'b1;
					state <= 4'b0000;
					en_write <= 1'b1;
					sdat <= 1'b0;
					sclk <= 1'b1;
				end
				
				// End Transaction
				4'b0001: begin
					busy <= 1'b0;
					active <= 1'b0;
					state <= 4'b0000;
					en_write <= 1'b1;
					sdat <= 1'b1;
					sclk <= 1'b1;
				end
				
				// Write Byte
				4'b0010: begin
					busy <= 1'b1;
					active <= 1'b1;
					state <= 4'b0011;
					en_write <= 1'b1;
					sdat <= buf_out[7 - data_bit];
					sclk <= 1'b0;
				end
				
				4'b0011: begin
					busy <= 1'b1;
					active <= 1'b1;
					state <= 4'b0100;
					en_write <= 1'b1;
					sdat <= buf_out[7 - data_bit];
					sclk <= 1'b1;
				end
				
				4'b0100: begin
					busy <= 1'b1;
					active <= 1'b1;
					state <= (&data_bit) ? 4'b1001 : 4'b0010;
					en_write <= 1'b1;
					sdat <= buf_out[7 - data_bit];
					sclk <= 1'b0;
					data_bit <= data_bit + 3'b001;
				end
				
				// Read Byte
				4'b0101: begin
					busy <= 1'b1;
					active <= 1'b1;
					state <= 4'b0111;
					en_write <= 1'b0;
					sdat <= 1'b0;
					sclk <= 1'b0;
				end
				
				4'b0111: begin
					busy <= 1'b1;
					active <= 1'b1;
					state <= 4'b1000;
					en_write <= 1'b0;
					sdat <= 1'b0;
					sclk <= 1'b1;
				end
				
				4'b1000: begin
					busy <= 1'b1;
					active <= 1'b1;
					state <= (&data_bit) ? 4'b1100 : 4'b0101;
					en_write <= 1'b0;
					sdat <= 1'b0;
					buf_in[7 - data_bit] <= i2c_sdat;
					sclk <= 1'b0;
					data_bit <= data_bit + 3'b001;
				end
				
				// Write ACK
				4'b1001: begin
					busy <= 1'b1;
					active <= 1'b1;
					state <= 4'b1010;
					en_write <= 1'b0;
					sdat <= 1'b1;
					sclk <= 1'b0;
				end
				
				4'b1010: begin
					busy <= 1'b1;
					active <= 1'b1;
					state <= 4'b1011;
					en_write <= 1'b0;
					sdat <= 1'b1;
					sclk <= 1'b1;
				end
				
				4'b1011: begin
					busy <= 1'b0;
					active <= 1'b1;
					state <= 4'b0000;
					en_write <= 1'b0;
					sdat <= 1'b1;
					sclk <= 1'b0;
					error <= i2c_sdat;
				end
				
				// Read ACK
				4'b1100: begin
					busy <= 1'b1;
					active <= 1'b1;
					state <= 4'b1101;
					en_write <= 1'b1;
					sdat <= 1'b1;
					sclk <= 1'b0;
				end
				
				4'b1101: begin
					busy <= 1'b1;
					active <= 1'b1;
					state <= 4'b1110;
					en_write <= 1'b1;
					sdat <= 1'b1;
					sclk <= 1'b1;
				end
				
				4'b1110: begin
					busy <= 1'b0;
					active <= 1'b1;
					state <= 4'b0000;
					en_write <= 1'b1;
					sdat <= 1'b1;
					sclk <= 1'b0;
				end
			endcase
			
			ready <= 1'b0;
		end else if (start_transaction && ~active) begin
			busy <= 1'b0;
			active <= 1'b1;
			state <= 4'b0000;
			ready <= 1'b0;
			
			en_write <= 1'b1;
			sdat <= 1'b0;
			sclk <= 1'b1;
		end else if (start_transaction && active) begin
			busy <= 1'b1;
			active <= 1'b1;
			state <= 4'b0000;
			ready <= 1'b0;
			
			en_write <= 1'b1;
			sdat <= 1'b1;
			sclk <= 1'b0;
		end else if (end_transaction && active) begin
			busy <= 1'b1;
			active <= 1'b1;
			state <= 4'b0001;
			ready <= 1'b0;
			
			en_write <= 1'b1;
			sdat <= 1'b0;
			sclk <= 1'b1;
		end else if (start_write && active) begin
			busy <= 1'b1;
			active <= 1'b1;
			state <= 4'b0010;
			ready <= 1'b0;
			
			en_write <= 1'b1;
			sdat <= 1'b0;
			sclk <= 1'b0;
			
			data_bit <= 3'b000;
			buf_out <= data_out;
		end else if (start_read && active) begin
			busy <= 1'b1;
			active <= 1'b1;
			state <= 4'b0101;
			ready <= 1'b0;
			
			en_write <= 1'b0;
			sdat <= 1'b0;
			sclk <= 1'b0;
			
			buf_in <= 8'b0000_0000;
			data_bit <= 3'b000;
		end else if (active) begin
			busy <= 1'b0;
			active <= 1'b1;
			state <= 4'b0000;
			ready <= 1'b1;
			
			en_write <= 1'b1;
			sdat <= 1'b0;
			sclk <= 1'b0;
		end else begin
			busy <= 1'b0;
			active <= 1'b0;
			state <= 4'b0000;
			ready <= 1'b1;
			error <= 1'b0;
			
			en_write <= 1'b1;
			sclk <= 1'b1;
			sdat <= 1'b1;
		end
	end
endmodule
