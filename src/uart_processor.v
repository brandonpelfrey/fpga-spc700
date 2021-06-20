module uart_processor (
  input clock,

  // Incoming data
  input [7:0] in_uart_byte,
  input in_uart_byte_ready,

  // Output reset
  output reset
);

reg [7:0] incoming_buffer [511:0]; // Data coming from the host
reg [8:0] incoming_buffer_index;

reg [7:0] outgoing_buffer [511:0]; // Data going to the host
reg [8:0] outgoing_buffer_index;

reg [7:0] state /* synthesis noprune */ = 0;
reg [31:0] counter /* synthesis noprune */;

reg reset_driver = 1'b0;
assign reset = reset_driver;

localparam STATE_IDLE = 0;
localparam STATE_PROCESSING = 1;
localparam STATE_CLEANUP = 2;

localparam CMD_RESET = 0;

always @(posedge clock) begin
  case(state)
    STATE_IDLE: begin
      // If the host triggers a command, latch in the command and start.
      if(in_uart_byte_ready) begin
        incoming_buffer[0] <= in_uart_byte;
        incoming_buffer_index <= 1;
        state <= STATE_PROCESSING;
		  counter <= 0;
      end
    end

    STATE_PROCESSING: begin
      case(incoming_buffer[0][7:0])
        CMD_RESET: begin
			 if(counter == 0) begin
				reset_driver <= 1;
			 end
			 if(counter < 32'd200000)
				counter <= counter + 1;
			 if(counter == 32'd200000)
				state <= STATE_CLEANUP;
        end
		  
		  default: begin
			state <= STATE_CLEANUP;
		  end
      endcase
    end

    STATE_CLEANUP: begin
      state <= STATE_IDLE;
      reset_driver <= 1'b0;
    end

  endcase
end
  
endmodule