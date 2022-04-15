// Simple queue for audio 
module SampleQueue 
#(  
  parameter QUEUE_SIZE = 16
)
(
  input clock,
  input reset,

  input enqueue,
  input [15:0] input_sample,

  output reg [DATA_ADDR_WIDTH-1:0] size,

  input dequeue,
  output reg [15:0] output_latch
);

reg [15:0] data [QUEUE_SIZE-1:0];
parameter DATA_ADDR_WIDTH = $clog2(QUEUE_SIZE);

wire is_full = &size;
wire is_empty = !(|size);

always @(posedge clock) begin
  if(reset) begin
    size <= 0;
    output_latch <= 0;
  end else begin
    if(enqueue & !is_full) begin
      data[size] <= input_sample;
      size <= size + 1;
    end 
    else if(dequeue & !is_empty) begin
      output_latch <= data[size - 1];
      size <= size - 1;
    end
  end
end

endmodule
