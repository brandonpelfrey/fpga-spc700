// TODO docs
module BRRDecoder(
  input reset,
  input clock,

  input start_address [15:0], // Start address for the current sample
  input loop_address [15:0],  // Loop address for the current sample

  input do_decode,  // Execute decoder/reading logic
  input do_consume, // Advance sample_out_* to point to the next sample

  output remaining_sample_count [7:0],
  output sample_out_0, // Latest sample
  output sample_out_1, // Second most recent sample
  output sample_out_2, // Third most recent sample
);

localparam READ_BUFFER_SIZE = 16;

localparam STATE_INIT = 0,
           STATE_READ_HEADER = 1,
           STATE_READ_DATA = 2,
           STATE_PROCESS_SAMPLE = 3,
           STATE_OUTPUT_AND_WAIT = 4,
           STATE_END = 5;

reg [7:0] state; // Current state

reg [15:0] current_block_addr;   // Current block starting address (header)
reg [7:0]  current_block_offset; // Current block current read offset

// Samples read from BRR data, before filtering is applied. 
signed reg [15:0] read_buffer   [READ_BUFFER_SIZE-1:0];

// The ADPCM filter to apply to the data in read_buffer
reg        [1:0]  filter_buffer [READ_BUFFER_SIZE-1:0];

// Current index for writing data into read_buffer. 
reg [7:0] read_buffer_index;
wire [2:0] rbi0 = read_buffer_index;
wire [2:0] rbi1 = (read_buffer_index + 1) & (READ_BUFFER_SIZE - 1);

// Number of samples that can be consumed externally.
reg remaining_sample_count [7:0];

reg cycle_count [7:0];

// Reset
always @(posedge clock) begin
  if(reset) begin
    ram_address          <= start_address;
    ram_read_request     <= 1;
    state                <= STATE_INIT;
    current_block_offset <= 0;
    cycle_count          <= 0;
  end
end

// Consume samples ?
always @(posedge clock) begin
  if(!reset) begin

  end
end

// Decode samples
always @(posedge clock) begin
  if(!reset) begin



    case(state)
      // Determine what the next decoder cycles will do.
      STATE_INIT: begin

      end

      ///////////////////////////////////////////////////////////////////////////////////
      STATE_READ_HEADER: begin
        // Expected: ram_address pointing at a header
        // Expected: ram_read_request was 1, so data is ready now
        header               <= ram_data;         // Read the header data
        ram_address          <= ram_address + 1;  // Next read request is the first ...
        current_block_offset <= 1;                // ... of actual sound data.
        ram_read_request     <= 1;
        state                <= STATE_READ_DATA;  // Go to the data reading state
      end

      ///////////////////////////////////////////////////////////////////////////////////
      STATE_READ_DATA: begin
        // BRR sample data is expressed as 4 bits per sample, sign extended, and
        // zero-padded by an amount given in the header. We always read two input nibbles
        // at a time, which produces two bytes in our ring buffer.
        read_buffer[rbi0]   <= { {12{ram_data[7]}}, ram_data[7:4] } << header[7:4];
        read_buffer[rbi1]   <= { {12{ram_data[3]}}, ram_data[3:0] } << header[7:4];

        // There are various filtering modes for incoming data. If the data is ADPCM 
        // encoded, then the later processing of this sample data will need to know which
        // filter was supposed to be applied for this block.
        filter_buffer[rbi0] <= header[3:2];
        filter_buffer[rbi1] <= header[3:2];

        read_buffer_index <= (read_buffer_index + 2) & (READ_BUFFER_SIZE - 1);
        unused_samples <= unused_samples + 2;
        current_block_offset <= current_block_offset + 1;

        // We read two new BRR samples in. A few possible next states...
        if (unused_samples >= 6) begin
          // If there are already at least 6 unused samples, then (after the two more we're
          // reading in this cycle) we have read everything that we need. If the cursor has
          // overflowed, then we need to perform sample processing. Otherwise, we're done
          // and we're ready for the processing pipeline to take over.

          // TODO: We're going to exit brr decoding at this point and hand off to the processor.
          // We need to decide ahead of time whether the next time we enter this, we will be
          // expected to:
          // - no more data needed for next output sample:   do nothing
          // - more data needed, some left in this block:    read next byte
          // - more data needed, nothing left in this block: get ready to read the next header



          // state            <= (cursor >= 4096) ? STATE_PROCESS_SAMPLE : STATE_OUTPUT_AND_WAIT;
          // ram_read_request <= 0;
        end else begin
          // Definitely need to read more data. Maybe header is next, maybe data is next..

          // BRR data comes in blocks of 8 samples. Check whether we are looping or not.
          if (block_index == 7) begin
            state            <= final_block_do_end  ? STATE_END : STATE_READ_HEADER;
            ram_address      <= final_block_do_loop ? loop_address : (ram_address + 1);
            ram_read_request <= !final_block_do_end;
          end else begin
            // We're in the middle of a set of BRR data blocks
            state       <= STATE_READ_DATA;
            ram_address <= ram_address + 1;
            ram_read_request <= 1;
          end
        end
      end



    endcase
    


  end
end

endmodule
