
module uart_tx 
  #(parameter CLOCKS_PER_BIT = 40)
(
  input clock,             // Used to drive state machine
  output reg uart_data,    // UART output data line
  input [7:0] byte_out,    // The byte the user wishes to send
  input write_trigger,     // Pulse one clock cycle to initiate transmit
  output ready_to_transmit,// High when a new transmit may take place
  input reset
);

localparam STATE_IDLE       = 0;
localparam STATE_START_BIT  = 1;
localparam STATE_WRITE_BITS = 2;
localparam STATE_END_BIT    = 3;

reg [3:0] state /* synthesis noprune */;
reg [7:0] bit_counter /* synthesis noprune */;
reg [7:0] data_buff /* synthesis noprune */;
reg [7:0] clock_counter /* synthesis noprune */;

assign ready_to_transmit = state == STATE_IDLE;

always @(posedge clock) begin
  if(reset) begin
    state <= STATE_IDLE;
	 clock_counter <= 0;
	 bit_counter <= 0;
    uart_data <= 1;
  end
  else
  case (state) 
    STATE_IDLE: begin
      if(write_trigger) begin
        state         <= STATE_START_BIT;
        data_buff     <= byte_out;
        clock_counter <= 0;
        uart_data     <= 0; // Pull low to begin start bit
      end
    end

    STATE_START_BIT: begin
      if(clock_counter == (CLOCKS_PER_BIT-1)) begin
        state         <= STATE_WRITE_BITS;
        clock_counter <= 0;
        bit_counter   <= 0;
        uart_data     <= data_buff[0];
      end else
        clock_counter <= clock_counter + 8'b1;
    end

    STATE_WRITE_BITS: begin
      if(clock_counter == (CLOCKS_PER_BIT-1)) begin
        clock_counter <= 0;
        if(bit_counter == 7) begin
          state         <= STATE_END_BIT;
          bit_counter   <= 0;
          uart_data     <= 1; // Pull high to begin the stop bit
        end else begin
          bit_counter   <= bit_counter + 8'b1;
          uart_data     <= data_buff[1];
          data_buff     <= {1'b0, data_buff[7:1]};
        end
      end else
        clock_counter <= clock_counter + 8'b1;
    end

    STATE_END_BIT: begin
      // uart was set high in WRITE_BITS, and will stay there
      // when we get back to IDLE state.
      if(clock_counter == (CLOCKS_PER_BIT-1)) begin
        state         <= STATE_IDLE;
        clock_counter <= 0;
        bit_counter   <= 0;
      end else
        clock_counter <= clock_counter + 8'b1;
    end

  endcase
end

    
endmodule
