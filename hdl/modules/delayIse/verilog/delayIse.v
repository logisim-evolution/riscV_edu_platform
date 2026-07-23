module delayIse #( parameter referenceClockFrequencyInHz = 12000000,
                   parameter W_DATA = 64,
                   parameter [6:0] customInstructionId = 7'd0 )
                 ( input  wire clock,
                   input  wire referenceClock,
                   input  wire reset, // active high
                   input  wire [6:0]        ci_id,
                   input  wire              ci_start,
                   input  wire [W_DATA-1:0] ci_dataa,
                   input  wire [W_DATA-1:0] ci_datab,
                   output wire              ci_done,
                   output wire [W_DATA-1:0] ci_result);

  /*
   *
   * This module implements a blocking delay element, where ci_dataa
   * presents the nr. of micro-seconds to wait. In case ci_dataa == 0
   * no delay is done.
   *
   */

  function integer clog2;
    input integer value;
    begin
      for (clog2 = 0; value > 0 ; clog2= clog2 + 1)
      value = value >> 1;
    end
  endfunction
  
  localparam tickReloadValue = referenceClockFrequencyInHz / 1000000;
  localparam nrOfBits = clog2(tickReloadValue);
  
  /*
   * Here we define the control signals
   *
   */
  wire isMyCi = (ci_id == customInstructionId) ? ci_start : 1'b0;
  reg s_doneReg;

  /*
   *
   * Here we define the tick generator that generates a
   * micro-second tick based on the clock.
   *
   */
   reg [nrOfBits-1:0] s_tickCounterReg;
   
   wire s_resetTickCounter, s_microSecTick;
   wire s_tickCounterZero = (s_tickCounterReg == {nrOfBits{1'b0}}) ? 1'b1 : 1'b0;
   wire [nrOfBits-1:0] s_tickCounterNext = (reset == 1'b1 || s_tickCounterZero == 1'b1 || s_resetTickCounter == 1'b1) ? tickReloadValue - 1 : s_tickCounterReg - 1;

   synchroFlop rsync ( .clockIn(clock),
                       .clockOut(referenceClock),
                       .reset(reset),
                       .D(isMyCi),
                       .Q(s_resetTickCounter) );

   synchroFlop usync ( .clockIn(referenceClock),
                       .clockOut(clock),
                       .reset(reset|isMyCi),
                       .D(s_tickCounterZero),
                       .Q(s_microSecTick) );
  
  always @(posedge referenceClock) s_tickCounterReg <= s_tickCounterNext;
  
  /*
   *
   * Here we define the main counter
   *
   */
  reg [W_DATA-1:0] s_delayCountReg;
  reg s_supressDoneReg;
  wire s_delayCountZero = (s_delayCountReg == {W_DATA{1'b0}}) ? 1'd1 : 1'd0;
  wire s_delayCountOne  = (s_delayCountReg == {{(W_DATA-1){1'b0}},1'b1}) ? 1'd1 : 1'd0;
  wire [W_DATA-1:0] s_delayCountNext = (reset == 1'b1) ? {W_DATA{1'b0}} :
                                       (isMyCi == 1'b1 && ci_datab[1] == 1'b0) ? ci_dataa :
                                       (s_microSecTick == 1'b1 && s_delayCountZero == 1'b0) ? s_delayCountReg - {{(W_DATA-1){1'b0}},1'b1} : s_delayCountReg;
  
  assign ci_result = (s_doneReg == 1'b1) ? s_delayCountReg : {W_DATA{1'b0}};
  
  always @(posedge clock) 
    begin
      s_supressDoneReg <= (reset == 1'b1 || s_delayCountZero == 1'b1) ? 1'b0 : (isMyCi == 1'b1 && ci_datab[1] == 1'b1) ? 1'b1 : s_supressDoneReg;
      s_delayCountReg <= s_delayCountNext;
    end
  
  /*
   *
   * Here we define the done signal
   *
   */
  wire s_doneNext = ((isMyCi == 1'b1 && ci_dataa == {W_DATA{1'b0}}) ||
                     (isMyCi == 1'b1 && ci_datab[0] == 1'b1) ||
                     (s_microSecTick == 1'b1 && s_delayCountOne == 1'b1 && s_supressDoneReg == 1'b0)) ? 1'b1 : 1'b0;
  
  assign ci_done = s_doneReg;
  
  always @(posedge clock) s_doneReg <= s_doneNext;
endmodule
