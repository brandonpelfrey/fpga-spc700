module i2s(
	BCLK,
	DAC_LR_CLK,
	DAC_DATA
);
input BCLK;
output reg DAC_LR_CLK;
output reg DAC_DATA;

reg [15:0] counter;
reg signed [15:0] data_counter = 0;

always @(posedge BCLK) begin
	DAC_DATA <= ~DAC_DATA;
	DAC_LR_CLK <= (counter >= 25);

	case(counter)
		16'd51: begin
			counter <= 0;
			data_counter <= data_counter + $signed(1);
		end
		
		default: begin
			counter <= counter + 1;
		end
	endcase
end

endmodule