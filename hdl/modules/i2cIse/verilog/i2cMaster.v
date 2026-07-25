module i2cMaster #( parameter CLOCK_FREQUENCY = 12000000,
                    parameter I2C_FREQUENCY = 1000000)
                 ( input wire        clock,
                                     reset,
                                     startWrite,
                                     startRead,
                   input wire [6:0]  address,
                   input wire [7:0]  regIn,
                   input wire [7:0]  dataIn,
                   output wire [7:0] dataOut,
                   output wire       ackError,
                                     busy,
                                     SCL,
                   inout wire        SDA );

  /*
   * This is a simple implementation of an I2C master interface
   * that communicates at 100kHz and is able to send/receive 1 data byte.
   *
   */

  localparam CLOCK_DIVIDER_VALUE = (CLOCK_FREQUENCY)/(I2C_FREQUENCY*4);
  localparam NR_OF_BITS = $clog2(CLOCK_DIVIDER_VALUE+1);
  localparam [4:0] IDLE = 5'd0;
  localparam [4:0] SENDSTART = 5'd1;
  localparam [4:0] A6 = 5'd2;
  localparam [4:0] A5 = 5'd3;
  localparam [4:0] A4 = 5'd4;
  localparam [4:0] A3 = 5'd5;
  localparam [4:0] A2 = 5'd6;
  localparam [4:0] A1 = 5'd7;
  localparam [4:0] A0 = 5'd8;
  localparam [4:0] ACK1 = 5'd9;
  localparam [4:0] SENDSTOP = 5'd10;
  localparam [4:0] R7 = 5'd11;
  localparam [4:0] R6 = 5'd12;
  localparam [4:0] R5 = 5'd13;
  localparam [4:0] R4 = 5'd14;
  localparam [4:0] R3 = 5'd15;
  localparam [4:0] R2 = 5'd16;
  localparam [4:0] R1 = 5'd17;
  localparam [4:0] R0 = 5'd18;
  localparam [4:0] ACK2 = 5'd19;
  localparam [4:0] D7 = 5'd20;
  localparam [4:0] D6 = 5'd21;
  localparam [4:0] D5 = 5'd22;
  localparam [4:0] D4 = 5'd23;
  localparam [4:0] D3 = 5'd24;
  localparam [4:0] D2 = 5'd25;
  localparam [4:0] D1 = 5'd26;
  localparam [4:0] D0 = 5'd27;
  localparam [4:0] ACK3 = 5'd28;
  localparam [4:0] DIR = 5'd29;
  
  reg [4:0] s_stateMachineReg, s_stateMachineNext;

  /*
   *
   * Here we define the action indication signals
   *
   */
  reg  s_isReadActionReg, s_actionPendingReg, s_firstReadPassReg;
  wire s_isReadActionNext = (reset == 1'b1) ? 1'b0 : 
                            (startWrite == 1'b1 || startRead == 1'b1) ? startRead : s_isReadActionReg;
  wire s_actionPendingNext = (reset == 1'b1 || (s_stateMachineReg != IDLE && s_firstReadPassReg == 1'b0)) ? 1'b0 :
                             (startWrite == 1'b1 || startRead == 1'b1) ? 1'b1 : s_actionPendingReg;

  assign busy = (s_stateMachineReg == IDLE && s_actionPendingReg == 1'b0) ? 1'b0 : 1'b1;

  always @(posedge clock) 
    begin
      s_isReadActionReg  <= s_isReadActionNext;
      s_actionPendingReg <= s_actionPendingNext;
    end
  
  /*
   *
   * Here the tick-counter is defined
   *
   */
  reg [NR_OF_BITS-1:0]  s_divideCounterReg;
  wire                  s_divideCounterIsZero = (s_divideCounterReg == {NR_OF_BITS{1'b0}}) ? 1'b1 : 1'b0;
  wire [NR_OF_BITS-1:0] s_divideCounterNext = (s_divideCounterIsZero == 1'b1 || reset == 1'b1) ? CLOCK_DIVIDER_VALUE - 1 : s_divideCounterReg - 1;
  
  always @(posedge clock) s_divideCounterReg <= s_divideCounterNext;
  
  /*
   *
   * Here we define the state machine
   *
   */
  reg [1:0] s_clockCountReg;
  reg       s_ackErrorReg;
  wire      s_ackErrorNext = (reset == 1'b1) ? 1'b0 : 
                             ((s_stateMachineReg == ACK1 || s_stateMachineReg == ACK2 ||
                               (s_stateMachineReg == ACK3 && s_isReadActionReg == 1'b0)) && s_divideCounterIsZero == 1'b1 && s_clockCountReg == 2'd2) ? SDA : s_ackErrorReg;
  wire      s_firstReadPassNext = (reset == 1'b1 || (s_stateMachineReg == SENDSTOP && s_clockCountReg == 2'd0 && s_divideCounterIsZero == 1'b1) ||
                                   ((s_stateMachineReg == ACK1 || s_stateMachineReg == ACK2) && s_ackErrorReg == 1'b1 && s_clockCountReg == 2'd0 && s_divideCounterIsZero == 1'b1)) ? 1'b0 : 
                                  (startRead == 1'b1) ? 1'b1 : s_firstReadPassReg;
  
  assign ackError = s_ackErrorReg;
  
  always @*
    case (s_stateMachineReg)
      IDLE      : s_stateMachineNext <= (s_actionPendingReg == 1'b1 && s_clockCountReg == 2'd0) ? SENDSTART : IDLE;
      SENDSTART : s_stateMachineNext <= A6;
      A6        : s_stateMachineNext <= A5;
      A5        : s_stateMachineNext <= A4;
      A4        : s_stateMachineNext <= A3;
      A3        : s_stateMachineNext <= A2;
      A2        : s_stateMachineNext <= A1;
      A1        : s_stateMachineNext <= A0;
      A0        : s_stateMachineNext <= DIR;
      DIR       : s_stateMachineNext <= ACK1;
      ACK1      : s_stateMachineNext <= (s_ackErrorReg != 1'b0) ? SENDSTOP : 
                                        (s_isReadActionReg == 1'b0 || s_firstReadPassReg == 1'b1) ? R7 : D7;
      R7        : s_stateMachineNext <= R6;
      R6        : s_stateMachineNext <= R5;
      R5        : s_stateMachineNext <= R4;
      R4        : s_stateMachineNext <= R3;
      R3        : s_stateMachineNext <= R2;
      R2        : s_stateMachineNext <= R1;
      R1        : s_stateMachineNext <= R0;
      R0        : s_stateMachineNext <= ACK2;
      ACK2      : s_stateMachineNext <= (s_ackErrorReg != 1'b0 || s_firstReadPassReg == 1'b1) ? SENDSTOP : D7;
      D7        : s_stateMachineNext <= D6;
      D6        : s_stateMachineNext <= D5;
      D5        : s_stateMachineNext <= D4;
      D4        : s_stateMachineNext <= D3;
      D3        : s_stateMachineNext <= D2;
      D2        : s_stateMachineNext <= D1;
      D1        : s_stateMachineNext <= D0;
      D0        : s_stateMachineNext <= ACK3;
      ACK3      : s_stateMachineNext <= SENDSTOP;
      default   : s_stateMachineNext <= IDLE;
    endcase
  
  always @(posedge clock)
    begin
      s_clockCountReg    <= (reset == 1'b1) ? 2'd0 : (s_divideCounterIsZero == 1'b1) ? s_clockCountReg + 2'd1 : s_clockCountReg;
      s_stateMachineReg  <= (reset == 1'b1) ? IDLE : (s_clockCountReg == 2'd0 && s_divideCounterIsZero == 1'b1) ? s_stateMachineNext : s_stateMachineReg;
      s_ackErrorReg      <= s_ackErrorNext;
      s_firstReadPassReg <= s_firstReadPassNext;
    end
  
  /*
   *
   * Here the SDA and SCL lines are defined
   *
   */
  reg s_sclReg,s_sdaReg, s_sdaNext;
  wire s_sclNext = (s_stateMachineReg == SENDSTART && s_clockCountReg == 2'd0) ? 1'b0 :
                   (s_stateMachineReg == SENDSTOP && (s_clockCountReg == 2'd1 || s_clockCountReg == 2'd2)) ? 1'b0:
                   (s_stateMachineReg != IDLE && s_stateMachineReg != SENDSTART && 
                    s_stateMachineReg != SENDSTOP && (s_clockCountReg == 2'd1 || s_clockCountReg == 2'd0)) ? 1'b0 : 1'b1;
  
  assign SDA = (s_sdaReg == 1'b0) ? 1'b0 : 1'bZ;
  assign SCL = s_sclReg;
  
  always @*
    case (s_stateMachineReg)
      SENDSTART  : s_sdaNext <= (s_clockCountReg == 2'd1) ? 1'b1 : 1'b0;
      A6         : s_sdaNext <= address[6];
      A5         : s_sdaNext <= address[5];
      A4         : s_sdaNext <= address[4];
      A3         : s_sdaNext <= address[3];
      A2         : s_sdaNext <= address[2];
      A1         : s_sdaNext <= address[1];
      A0         : s_sdaNext <= address[0];
      DIR        : s_sdaNext <= s_isReadActionReg & ~s_firstReadPassReg;
      R7         : s_sdaNext <= regIn[7];
      R6         : s_sdaNext <= regIn[6];
      R5         : s_sdaNext <= regIn[5];
      R4         : s_sdaNext <= regIn[4];
      R3         : s_sdaNext <= regIn[3];
      R2         : s_sdaNext <= regIn[2];
      R1         : s_sdaNext <= regIn[1];
      R0         : s_sdaNext <= regIn[0];
      D7         : s_sdaNext <= dataIn[7] | s_isReadActionReg;
      D6         : s_sdaNext <= dataIn[6] | s_isReadActionReg;
      D5         : s_sdaNext <= dataIn[5] | s_isReadActionReg;
      D4         : s_sdaNext <= dataIn[4] | s_isReadActionReg;
      D3         : s_sdaNext <= dataIn[3] | s_isReadActionReg;
      D2         : s_sdaNext <= dataIn[2] | s_isReadActionReg;
      D1         : s_sdaNext <= dataIn[1] | s_isReadActionReg;
      D0         : s_sdaNext <= dataIn[0] | s_isReadActionReg;
      SENDSTOP   : s_sdaNext <= 1'b0;
      default    : s_sdaNext <= 1'b1;
    endcase
  
  always @(posedge clock)
    begin
      s_sclReg <= (reset == 1'b1) ? 1'b1 : (s_divideCounterIsZero == 1'b1) ? s_sclNext : s_sclReg;
      s_sdaReg <= (reset == 1'b1) ? 1'b1 : (s_divideCounterIsZero == 1'b1) ? s_sdaNext : s_sdaReg;
    end

  /*
   *
   * Here the data out register is defined
   *
   */
  reg [7:0] s_dataOutReg;
  wire s_clockData = (s_divideCounterIsZero == 1'b1 && s_clockCountReg == 2'd2) ? 1'b1 : 1'b0;
  wire [7:0] s_dataOutNext;
  
  assign s_dataOutNext[7] = (reset == 1'b1) ? 1'b0 : (s_stateMachineReg == D7 && s_clockData == 1'b1) ? SDA : s_dataOutReg[7];
  assign s_dataOutNext[6] = (reset == 1'b1) ? 1'b0 : (s_stateMachineReg == D6 && s_clockData == 1'b1) ? SDA : s_dataOutReg[6];
  assign s_dataOutNext[5] = (reset == 1'b1) ? 1'b0 : (s_stateMachineReg == D5 && s_clockData == 1'b1) ? SDA : s_dataOutReg[5];
  assign s_dataOutNext[4] = (reset == 1'b1) ? 1'b0 : (s_stateMachineReg == D4 && s_clockData == 1'b1) ? SDA : s_dataOutReg[4];
  assign s_dataOutNext[3] = (reset == 1'b1) ? 1'b0 : (s_stateMachineReg == D3 && s_clockData == 1'b1) ? SDA : s_dataOutReg[3];
  assign s_dataOutNext[2] = (reset == 1'b1) ? 1'b0 : (s_stateMachineReg == D2 && s_clockData == 1'b1) ? SDA : s_dataOutReg[2];
  assign s_dataOutNext[1] = (reset == 1'b1) ? 1'b0 : (s_stateMachineReg == D1 && s_clockData == 1'b1) ? SDA : s_dataOutReg[1];
  assign s_dataOutNext[0] = (reset == 1'b1) ? 1'b0 : (s_stateMachineReg == D0 && s_clockData == 1'b1) ? SDA : s_dataOutReg[0];
  assign dataOut = s_dataOutReg;
  
  always @(posedge clock) s_dataOutReg <= s_dataOutNext;
endmodule
