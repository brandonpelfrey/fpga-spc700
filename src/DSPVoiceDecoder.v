module DSPVoiceDecoder (
  clock,
  reset,
  state,
  ram_address,
  ram_data,
  ram_read_request,

  start_address,
  loop_address,
  pitch,
  current_output,
  reached_end,
  advance_trigger,
  cursor
);

////////////////////////////////////////
// Internal constants
parameter READ_BUFFER_BYTES = 8;

////////////////////////////////////////
// External State
input clock;
input reset;
output reg [3:0] state;
output reg [15:0] ram_address;
input reg [7:0] ram_data;
output reg ram_read_request;
input [15:0] start_address;
input [15:0] loop_address;
input [13:0] pitch;
output reg [15:0] current_output; // Current 16-bit signed raw sample output 
output reg reached_end;
input advance_trigger;

/////////////////////////////////////////
// Internal State

// 'Cursor' tracks the position within the byte.
output reg [15:0] cursor;
reg [2:0]  cursor_i;
reg [2:0]  unused_samples;

reg signed [15:0] read_buffer   [7:0];
reg        [1:0]  filter_buffer [7:0];

reg [2:0] read_buffer_index;
reg [3:0] block_index;
reg signed [15:0] previous_samples [3:0];

// Headers for current bytes being decoded vs next
reg [7:0] header;
wire header_end   = header[0];
wire header_loop  = header[1];
wire [1:0] filter = header[3:2];

wire final_block_do_end  = header_end & (!header_loop);
wire final_block_do_loop = header_end & header_loop;

parameter STATE_INIT = 0,
          STATE_READ_HEADER = 1,
          STATE_READ_DATA = 2,
          STATE_PROCESS_SAMPLE = 3,
          STATE_OUTPUT_AND_WAIT = 4,
          STATE_END = 5;

wire [2:0] rbi0 = read_buffer_index;
wire [2:0] rbi1 = (read_buffer_index + 1) & 7;

always @(posedge clock) begin
  if(reset) begin
    $display("RESET %m");
    cursor_i <= 0;
    cursor <= {2'b0, pitch} + 4096;
    state <= STATE_INIT;
    header <= 0;

    read_buffer[0] <= 0; filter_buffer[0] <= 0;
    read_buffer[1] <= 0; filter_buffer[1] <= 0;
    read_buffer[2] <= 0; filter_buffer[2] <= 0;
    read_buffer[3] <= 0; filter_buffer[3] <= 0;
    read_buffer[4] <= 0; filter_buffer[4] <= 0;
    read_buffer[5] <= 0; filter_buffer[5] <= 0;
    read_buffer[6] <= 0; filter_buffer[6] <= 0;
    read_buffer[7] <= 0; filter_buffer[7] <= 0;

    read_buffer_index   <= 0;
    block_index         <= 0;

    previous_samples[0] <= 0;
    previous_samples[1] <= 0;

    unused_samples      <= 0;

    ram_address         <= start_address;

    /////////////////////////////

  end else begin

    // Reader state 
    case(state)

      ///////////////////////////////////////////////////////////////////////////////////
      STATE_INIT: begin
        if(advance_trigger) begin
          ram_address      <= start_address;
          ram_read_request <= 1;
          state            <= STATE_READ_HEADER;
          reached_end      <= 0;
          //$display("INIT %m cursor %d", cursor);
        end
      end

      ///////////////////////////////////////////////////////////////////////////////////
      STATE_READ_HEADER: begin
        header           <= ram_data;
        state            <= STATE_READ_DATA;
        ram_address      <= ram_address + 1;
        ram_read_request <= 1;
        block_index      <= 0;
      end

      ///////////////////////////////////////////////////////////////////////////////////
      STATE_READ_DATA: begin
        read_buffer[rbi0]   <= { {12{ram_data[7]}}, ram_data[7:4] } << header[7:4];
        read_buffer[rbi1]   <= { {12{ram_data[3]}}, ram_data[3:0] } << header[7:4];

        filter_buffer[rbi0] <= header[3:2];
        filter_buffer[rbi1] <= header[3:2];

        read_buffer_index <= (read_buffer_index + 2) & 7;
        unused_samples <= unused_samples + 2;
        block_index <= block_index + 1;

        if (unused_samples >= 2) begin
          //$display("DATA: %m cursor %d", cursor);
          state            <= (cursor >= 4096) ? STATE_PROCESS_SAMPLE : STATE_OUTPUT_AND_WAIT;
          ram_read_request <= 0;
        end else begin
          if (block_index == 7) begin
            state            <= final_block_do_end  ? STATE_END : STATE_READ_HEADER;
            ram_address      <= final_block_do_loop ? loop_address : (ram_address + 1);
            ram_read_request <= !final_block_do_end;
          end else begin
            state       <= STATE_READ_DATA;
            ram_address <= ram_address + 1;
            ram_read_request <= 1;
          end
        end
      end

      ///////////////////////////////////////////////////////////////////////////////////
      STATE_PROCESS_SAMPLE: begin
        // We can only be in this state if cursor >= 4096 in the cursor.
        previous_samples[3] <= previous_samples[2];
        previous_samples[2] <= previous_samples[1];
        previous_samples[1] <= previous_samples[0];
        previous_samples[0] <= filter_out;
        cursor              <= cursor - 4096;
        cursor_i            <= (cursor_i + 1) & 3'b111;
        unused_samples      <= unused_samples - 1;

        // Come back to this state if we need to do this again. Otherwise, output.
        state <= (cursor >= 4096*2) ? STATE_PROCESS_SAMPLE : STATE_OUTPUT_AND_WAIT;
      end
      
      ///////////////////////////////////////////////////////////////////////////////////
      STATE_OUTPUT_AND_WAIT: begin

        current_output <= current_output_x[15:0];

        // $display("cursor %d rbi %d cursor_i %d PS [%d : %d : %d : %d]", cursor, read_buffer_index, cursor_i, previous_samples[0], previous_samples[1], previous_samples[2], previous_samples[3]);

        // Wait here until a signal to advance occurs
        if (advance_trigger) begin
          cursor <= cursor + {2'b0, pitch};
          
          if (unused_samples >= 4) begin
            state <= ( (cursor + {2'b0, pitch}) >= 4096) ? STATE_PROCESS_SAMPLE : STATE_OUTPUT_AND_WAIT;
          end else begin
            if (block_index == 8) begin
              state            <= final_block_do_end  ? STATE_END    : STATE_READ_HEADER;
              ram_address      <= final_block_do_loop ? loop_address : (ram_address + 1);
              ram_read_request <= !final_block_do_end;
            end else begin
              state            <= STATE_READ_DATA;
              ram_address      <= ram_address + 1;
              ram_read_request <= 1;
            end
          end

        end

      end

      ///////////////////////////////////////////////////////////////////////////////////
      STATE_END: begin
        reached_end <= 1;
      end

    endcase
    // End voice FSM logic

  end
end

// Combinatorial logic

reg signed [15:0] filter_out;
wire [31:0] rbci32 = { {16{read_buffer[cursor_i][15]}} , read_buffer[cursor_i]};
wire signed [31:0] filter_0 = $signed(rbci32);
wire signed [31:0] filter_1 = $signed(rbci32) + $signed(previous_samples[0]) * $signed(15) / $signed(16);
wire signed [31:0] filter_2 = $signed(rbci32) 
                                 + $signed(previous_samples[0]) * $signed(61)  / $signed(32)
                                 + $signed(previous_samples[1]) * $signed(-15) / $signed(16);
wire signed [31:0] filter_3 = $signed(rbci32) 
                                 + $signed(previous_samples[0]) * $signed(115) / $signed(64) 
                                 + $signed(previous_samples[1]) * $signed(-13) / $signed(16);
always @* begin
  filter_out = filter_0[15:0];
  if(filter_buffer[cursor_i] == 1) filter_out = filter_1[15:0];
  if(filter_buffer[cursor_i] == 2) filter_out = filter_2[15:0];
  if(filter_buffer[cursor_i] == 3) filter_out = filter_3[15:0];
end

// Linear interpolation of the two samples surrounding the cursor. Use more bits for precision.
//  PS[1] ....... PS[0]
//           ^
//         cursor
reg signed [31:0] current_output_x;
always @* begin
  current_output_x =                    $signed(previous_samples[0]) * $signed({1'b0, cursor[11:0]});
  current_output_x = current_output_x + $signed(previous_samples[1]) * $signed({1'b0, 12'd4095 - cursor[11:0]});
  current_output_x = current_output_x >>> 12;
end

endmodule