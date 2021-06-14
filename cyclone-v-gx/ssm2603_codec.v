module ssm2603_codec(
	CLK,     // Reference Clock (ideal 12.288MHz)
	AUD_XCK, // Data for Sending Data
	AUD_BCLK,// 
	AUD_DACDAT,
	AUD_DACLRCK
);
	input CLK;

	output AUD_XCK;
	output AUD_BCLK;
	output AUD_DACDAT;
	output AUD_DACLRCK;

	reg is_new_frame;
	wire is_left_channel;
	reg [5:0]frame_position;
	
	reg [16:0]audio_sample_l;
	reg [16:0]audio_sample_r;
	reg audio_lrck;
	reg audio_dacdat;
	
	// Testing only
	reg [15:0]target_sample;
	
	assign AUD_XCK = CLK;
	assign AUD_BCLK = bclk_clock;
	
	reg bclk_clock;
	reg [1:0] bclk_counter;
	always @(negedge CLK) begin
		bclk_counter <= bclk_counter + 1;
		bclk_clock <= bclk_counter == 0;
	end
	
	assign AUD_DACDAT = audio_dacdat;
	assign AUD_DACLRCK = audio_lrck;
	
	// With reference clock at ~12MHz and output at 48KHz, we have 256 cycles
	// to transfer 2 16-bit channels. Each channel is right-padded with an
	// extra 112 zero bits.
	assign is_left_channel = frame_position[5];
	
	always @(negedge bclk_clock)
	begin	
		if (is_new_frame) begin
			//target_sample <= target_sample + 16'b0000_011_1000_0010;
			target_sample[11:0] <= target_sample[11:0] + 1;
			
			audio_sample_l <= { target_sample[14:0], 1'b0 };
			audio_sample_r <= target_sample;
			
			audio_dacdat <= 0;
			audio_lrck <= 1'b0;
		end else begin
			if (is_left_channel) begin
				audio_sample_l <= target_sample[8] ? 16'h3FFF : 16'hCFFF;//{ audio_sample_l[15:0], 1'b0 };
				audio_dacdat   <= audio_sample_l[16];
				audio_lrck <= 1'b0;
			end else begin
				audio_sample_r <= { audio_sample_r[15:0], 1'b0 };
				audio_dacdat <= audio_sample_r[16];
				audio_lrck <= 1'b1;
			end
		end
		
		{ is_new_frame, frame_position } <= { 1'b0, frame_position } + 7'b000_0001;
	end
endmodule
