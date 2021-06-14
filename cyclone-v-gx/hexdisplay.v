module hexdisplay(
	value, // 4-bit Display Value
	led    // 7-Segment Display / Output Lines
);
	input [3:0]value;
	output [6:0]led;
	
	assign led = (value == 4'h0) ? ~7'b0111111 :
	             (value == 4'h1) ? ~7'b0000110 :
				 (value == 4'h2) ? ~7'b1011011 :
				 (value == 4'h3) ? ~7'b1001111 :
				 (value == 4'h4) ? ~7'b1100110 :
				 (value == 4'h5) ? ~7'b1101101 :
				 (value == 4'h6) ? ~7'b1111101 :
				 (value == 4'h7) ? ~7'b0000111 :
				 (value == 4'h8) ? ~7'b1111111 :
				 (value == 4'h9) ? ~7'b1100111 :
				 (value == 4'hA) ? ~7'b1110111 :
				 (value == 4'hB) ? ~7'b1111100 :
				 (value == 4'hC) ? ~7'b0111001 :
				 (value == 4'hD) ? ~7'b1011110 :
				 (value == 4'hE) ? ~7'b1111001 :
				                   ~7'b1110001;
endmodule
