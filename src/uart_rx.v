
module uart_rx 
  #(parameter CLOCKS_PER_BIT = 8)
(
  input clock,             // Used to drive state machine
  input uart_data,         // UART input data line
  output [7:0] byte_in,    // The received byte, valid when byte_ready is high
  output reg byte_ready,   // Pulse one clock cycle to initiate transmit
  input reset
);

localparam STATE_IDLE       = 4'd0;
localparam STATE_START_BIT  = 4'd1;
localparam STATE_READ_BITS  = 4'd2;
localparam STATE_END_BIT    = 4'd3;

reg [3:0] state /* synthesis noprune */ = STATE_IDLE;
reg [7:0] bit_counter /* synthesis noprune */;
reg [7:0] data_buff /* synthesis noprune */;
reg [7:0] clock_counter /* synthesis noprune */;

assign byte_in[7:0] = data_buff[7:0];

always @(posedge clock) begin
  if(reset) begin
    state <= STATE_IDLE;
  end
  else
  case (state) 
    STATE_IDLE: begin
      if(~uart_data) begin
        state <= STATE_START_BIT;
        clock_counter <= 0;
      end
    end

    STATE_START_BIT: begin
      // Get us to the middle of the first data bit, read it in
      if(clock_counter == CLOCKS_PER_BIT + (CLOCKS_PER_BIT-1)/2) begin
        clock_counter <= 0;
        bit_counter <= 1;
        state <= STATE_READ_BITS;
        data_buff <= {uart_data, 7'b0};
      end else 
        clock_counter <= clock_counter + 1;
    end

    STATE_READ_BITS: begin
      if(clock_counter == (CLOCKS_PER_BIT-1)) begin
        clock_counter <= 0;
        if(bit_counter == 7) begin
          // By this point, we're halfway into the middle of the stop bit
			 data_buff   <= {uart_data, data_buff[7:1]};
          state        <= STATE_END_BIT;
          bit_counter  <= 0;
          byte_ready   <= 1;
        end else begin
          bit_counter <= bit_counter + 8'b1;
          data_buff   <= {uart_data, data_buff[7:1]};
        end
      end else
        clock_counter <= clock_counter + 8'b1;
    end

    STATE_END_BIT: begin
      // uart was set high in WRITE_BITS, and will stay there
      // when we get back to IDLE state.
      byte_ready <= 0;
      if(uart_data) begin
        state         <= STATE_IDLE;
        clock_counter <= 0;
        bit_counter   <= 0;
      end
    end

  endcase
end

endmodule