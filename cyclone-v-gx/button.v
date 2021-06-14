module button_debounce(clk, input_button, output_changed);
	input clk;
	input input_button;
	output output_changed;
	
	reg sync0, sync1;
	
	reg old_state;
	reg state_change;
	reg [1:0]saturation;
	
	assign output_changed = state_change;
	
	always @(posedge clk) sync0 <= input_button;
	always @(posedge clk) sync1 <= sync0;
	
	always @(posedge clk)
	begin
		if (sync1 == ~old_state)
		begin
			if (saturation[1] == 1'b1) begin
				old_state <= sync1;
				state_change <= sync1;
				saturation <= 0;
			end
			else begin
				old_state <= ~sync1;
				state_change <= 1'b0;
				saturation <= saturation + 2'd1;
			end
		end
		else begin
			old_state <= sync1;
			state_change <= 1'b0;
			saturation <= 0;
		end
	end
endmodule
