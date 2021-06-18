module ssm2603_codec(
	AUD_BCLK, AUD_DACDAT, AUD_DACLRCK, in_l16, in_r16
);
	input AUD_BCLK;
	output AUD_DACDAT;
	output AUD_DACLRCK;
	input signed [15:0] in_l16;
	input signed [15:0] in_r16;

	reg is_new_frame;
	reg [8:0]frame_position;
	
	reg signed [31:0] next_audio_sample_l;
	reg signed [31:0] next_audio_sample_r;
	
	reg signed [31:0] audio_sample_l;
	reg signed [31:0] audio_sample_r;
	reg audio_lrck;
	reg audio_dacdat;
	
	// Testing only
//	reg signed [31:0] sin_data [0:63] /* synthesis ram_init_file = "sin_data.mif" */;
//	reg [5:0] sin_data_index = 0;
	reg signed [31:0] target_sample;
	
	assign AUD_DACDAT = audio_dacdat;
	assign AUD_DACLRCK = audio_lrck;
	
	always @(negedge AUD_BCLK)
	begin
		// 50000000 / 4 = mclk; mclk / 4 = bclk ~= 12.288Mhz. 12.288Mhz / (32000 s/sec) = 96 clocks per LR sample pair
		// 96 clocks per LR pair. Need lrck set low during #95, then high during 47
		
		// Left justified, with lrck high = Left channel
		if(frame_position == 63)
			audio_lrck <= 1;
		else if(frame_position == 31)
			audio_lrck <= 0;

		if(frame_position == 61) begin
			next_audio_sample_l <= {in_l16[15:0], 16'b0};
			next_audio_sample_r <= {in_r16[15:0], 16'b0};
		end
		
		if (frame_position == 63) begin
//       target_sample <= target_sample + 32'd134217 * 32'd440;
//			sin_data_index <= sin_data_index + 6'b1;
//			target_sample <= sin_data[sin_data_index];
//			audio_sample_l <= {target_sample[30:0], 1'b0};
//			audio_sample_r <= 32'b0;
//			audio_dacdat <= target_sample[31];
			
			frame_position <= 0;
			audio_sample_l <= {next_audio_sample_l[30:0], 1'b0};
			audio_sample_r <= next_audio_sample_r[31:0];
			audio_dacdat   <= next_audio_sample_l[31];

		end else begin
			if (frame_position < 31) begin
				audio_sample_l <= { audio_sample_l[30:0], 1'b0 };
				audio_dacdat <= audio_sample_l[31];
			end else begin
				audio_sample_r <= { audio_sample_r[30:0], 1'b0 };
				audio_dacdat <= audio_sample_r[31];
			end
			frame_position <= frame_position + 9'd1;
		end
	end
	
endmodule
