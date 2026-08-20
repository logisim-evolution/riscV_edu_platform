module debouncerWithIrq ( input wire  clock,
                                      reset,
                                      nButtonIn,
                                      scanTick,
                                      enablePressIrq,
                                      enableReleaseIrq,
                                      resetPressIrq,
                                      resetReleaseIrq,
                          output wire pressIrq,
                                      releasIrq,
                                      currentState );

  /*
   *
   * To debounce and prevent metastability we use a 4-bit shift register
   *
   */
  reg [3:0] s_shiftRegisterReg;
  wire [3:0] s_shiftRegisterNext;
  
  assign s_shiftRegisterNext[0]   = (reset == 1'b1) ? 1'b0 : (scanTick == 1'b1) ? ~nButtonIn : s_shiftRegisterReg[0];
  assign s_shiftRegisterNext[3:1] = (reset == 1'b1) ? 3'd0 : s_shiftRegisterReg[2:0];
  assign currentState = s_shiftRegisterReg[3];
  
  always @(posedge clock) s_shiftRegisterReg <= s_shiftRegisterNext;

  /*
   *
   * here we do the irq handling
   *
   */
  reg s_pressIrqReg, s_releaseIrqReg;
  wire s_pressDetected = ~s_shiftRegisterReg[3] & s_shiftRegisterReg[2];
  wire s_releaseDetected = s_shiftRegisterReg[3] & ~s_shiftRegisterReg[2];
  
  assign pressIrq = s_pressIrqReg;
  assign releasIrq = s_releaseIrqReg;
  
  always @(posedge clock)
    begin
      s_pressIrqReg   <= (reset == 1'b1 || resetPressIrq == 1'b1) ? 1'b0 : s_pressIrqReg | (s_pressDetected & enablePressIrq);
      s_releaseIrqReg <= (reset == 1'b1 || resetReleaseIrq == 1'b1) ? 1'b0 : s_releaseIrqReg | (s_releaseDetected & enableReleaseIrq);
    end
endmodule
