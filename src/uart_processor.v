module uart_processor (
  input clock,

  // Incoming data
  input [7:0] in_uart_byte,
  input in_uart_byte_ready,
  output reg out_uart_rx_reset,
  
  // Outgoing data
  input tx_uart_idle,
  output reg [7:0] out_uart_byte,
  output reg out_uart_byte_ready,
  output reg out_uart_tx_reset,

  // Reset commands
  output reg apu_reset,
  output reg audio_reset,
  
  // RAM read/writes
  output reg [15:0] ram_address,
  output reg [7:0]  ram_data_write,
  input  reg [7:0]  ram_data_read,
  output reg        ram_we
);

parameter CLOCKS_PER_BIT = 40;

reg [7:0] incoming_buffer [511:0]; // Data coming from the host
reg [8:0] incoming_buffer_index /* synthesis noprune */;

reg [7:0] outgoing_buffer [511:0]; // Data going to the host
reg [8:0] outgoing_buffer_index;

reg [7:0] state /* synthesis noprune */ = 0;
reg [31:0] counter /* synthesis noprune */;

reg [31:0] transfer_n;
reg [31:0] timeout_counter;

localparam STATE_IDLE = 0;
localparam STATE_PROCESSING = 1;
localparam STATE_CLEANUP = 2;

localparam STATE_REPLY_SUCCESS = 3;
localparam STATE_REPLY_ERROR = 4;

localparam CMD_AUDIO_RESET = 8'h01;
localparam CMD_SET_RAM     = 8'h10;
localparam CMD_APU_RESET   = 8'h22;

always @(posedge clock) begin

  case(state)
    STATE_IDLE: begin
		out_uart_tx_reset   <= 0;
      // If the host triggers a command, latch in the command and start.
      if(in_uart_byte_ready) begin
        incoming_buffer[0] <= in_uart_byte;
        incoming_buffer_index <= 1;
        state <= STATE_PROCESSING;
		  counter <= 0;
		  timeout_counter <= 0;
      end
    end

    STATE_PROCESSING: begin
		case(incoming_buffer[0][7:0])
		  CMD_APU_RESET: begin
			 if(counter == 0) begin
				apu_reset <= 1;
			 end
			 if(counter < 32'd512)
				counter <= counter + 1;
			 else
				state <= STATE_REPLY_SUCCESS;
		  end
		  
		  CMD_AUDIO_RESET: begin
			 if(counter == 0) begin
				audio_reset <= 1;
			 end
			 if(counter < 32'd512)
				counter <= counter + 1;
			 else
				state <= STATE_REPLY_SUCCESS;
		  end
		  
		  CMD_SET_RAM: begin
			// 0      : Command
			// 1,2    : (hi, lo) Start Address
			// 3      : N bytes
			// 4..4+N : Data
			
			if(timeout_counter > CLOCKS_PER_BIT * 12 * 512) begin
				state <= STATE_REPLY_ERROR;
			end
			else if(incoming_buffer_index < 4) begin
				timeout_counter <= timeout_counter + 1;
				if(in_uart_byte_ready) begin
					incoming_buffer[incoming_buffer_index] <= in_uart_byte;
					incoming_buffer_index <= incoming_buffer_index + 1;
				end
			end
			else if(incoming_buffer_index == 4) begin
				timeout_counter <= timeout_counter + 1;
				if(in_uart_byte_ready) begin
					// This new byte is the first byte to actually write to RAM
					incoming_buffer_index <= incoming_buffer_index + 1;
					ram_address    <= {incoming_buffer[1], incoming_buffer[2]};
					ram_data_write <= in_uart_byte;
					ram_we         <= 1;
					counter        <= 0; // number of bytes read - 1
				end
			end
			else begin
				timeout_counter <= timeout_counter + 1;
				if( counter[7:0] == incoming_buffer[3][7:0] ) begin
					ram_we <= 0;
					state  <= STATE_REPLY_SUCCESS;       
				end
				else
				if(in_uart_byte_ready) begin
					counter <= counter + 1;
					ram_address <= ram_address + 1;
					ram_data_write <= in_uart_byte;
					ram_we <= 1;
				end
			end
		  end
		  
		  default: begin
			state <= STATE_REPLY_ERROR;
		  end
		endcase
    end
	 
	 STATE_REPLY_ERROR: begin
		if(tx_uart_idle) begin
			out_uart_byte       <= 8'b11111111;
			out_uart_byte_ready <= 1;
			state               <= STATE_CLEANUP;
			out_uart_rx_reset   <= 1;
		end
	 end
	 
	 STATE_REPLY_SUCCESS: begin
		if(tx_uart_idle) begin
			out_uart_byte       <= 8'b00000000;
			out_uart_byte_ready <= 1;
			state               <= STATE_CLEANUP;
		end
	 end

    STATE_CLEANUP: begin
	   // Wait for any previous transmission to complete
		out_uart_byte_ready <= 0;
		out_uart_rx_reset   <= 0;
//		out_uart_tx_reset   <= 1;
	 
		state       <= STATE_IDLE;
		apu_reset   <= 1'b0;
		audio_reset <= 1'b0;
		
		ram_address <= 0;
		ram_we      <= 0;
		transfer_n  <= 0;
		incoming_buffer_index <= 0;
    end

  endcase // main state machine
  
end // always clock
  
endmodule