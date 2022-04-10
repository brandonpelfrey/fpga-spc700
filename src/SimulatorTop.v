module SimulatorTop(reset, clock, s_in, s_out, idle);
  input s_in;
  input reset, clock;
  output s_out;
  output idle;

  reg myr;
  reg r_idle;

  always @(posedge clock)
	begin
		if (reset == 1'b1) begin
      myr <= 1;
      r_idle <= 1;
    end else begin    
      myr <= s_in;
    end
  end

  not(s_out, myr);
  assign idle = r_idle;
endmodule
