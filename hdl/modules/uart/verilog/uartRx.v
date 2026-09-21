module uartRx ( input wire       clock,
                                 reset,
                                 baudRateX16Tick,
                                 uartRxLine,
                                 fifoFull,
               input wire [5:0]  controlReg,
               output wire [7:0] fifoData,
               output reg        fifoWe,
               output wire       frameError,
                                 breakDetected,
                                 parityError,
                                 overrunError );
  
  localparam [1:0] IDLE    = 2'b00;
  localparam [1:0] INIT    = 2'b01;
  localparam [1:0] RECEIVE = 2'b10;
  localparam [1:0] WRITE   = 2'b11;
  
  reg [1:0] s_stateMachineReg;
  
  // here the rx filter is defined
  reg [2:0] s_rxPipeReg;
  reg s_filteredRxReg, s_filteredRxDelayReg;
  wire [3:0] s_trigger = {uartRxLine, s_rxPipeReg};
  wire s_rxNegEdge = s_filteredRxDelayReg & ~s_filteredRxReg;
  
  always @(posedge clock)
    begin
      s_rxPipeReg          <= (reset == 1'b1) ? 3'd7 : (baudRateX16Tick == 1'b1) ? {s_rxPipeReg[1:0], uartRxLine} : s_rxPipeReg;
      s_filteredRxDelayReg <= (reset == 1'b1) ? 1'b1 : s_filteredRxReg;
      s_filteredRxReg      <= (reset == 1'b1) ? 1'b1 : (baudRateX16Tick == 1'b0) ? s_filteredRxReg :
                              (s_trigger == 4'h0) ? 1'b0 : (s_trigger == 4'hF) ? 1'b1 : s_filteredRxReg;
    end

  // here the shift register is defined
  reg [3:0]  s_baudCounterReg, s_bitCounterReg, s_bitCounterLoadValue;
  reg [10:0] s_shiftReg;
  reg [7:0]  s_dataBits;
  wire [3:0] s_baudCounterNext = (reset == 1'b1 || s_stateMachineReg == INIT) ? 4'h0 : 
                                 (s_stateMachineReg == RECEIVE && baudRateX16Tick == 1'b1) ? s_baudCounterReg + 4'd1 : s_baudCounterReg;
  wire       s_sampleTick = (s_baudCounterReg == 4'd7) ? baudRateX16Tick : 1'b0;
  wire       s_doShift = (s_bitCounterReg == 4'd0) ? 1'b0 : s_sampleTick;
  wire [3:0] s_bitCounterNext = (reset == 1'b1) ? 4'd0 : (s_stateMachineReg == INIT) ? s_bitCounterLoadValue :
                                (s_doShift == 1'b1) ? s_bitCounterReg - 4'd1 : s_bitCounterReg;
  wire [2:0] s_bitCounterSelect = {controlReg[3], controlReg[1:0]};

  always @(posedge clock)
    begin
      s_baudCounterReg  <= s_baudCounterNext;
      s_bitCounterReg   <= s_bitCounterNext;
      s_shiftReg        <= (reset == 1'b1) ? 11'd0 : (s_doShift == 1'b1) ? {s_filteredRxReg, s_shiftReg[10:1]} : s_shiftReg;
    end
  
  always @*
    case (s_bitCounterSelect)
      3'd0    : begin
                  s_bitCounterLoadValue <= 4'd7;
                  s_dataBits            <= {3'd0, s_shiftReg[9:5]};
                end
      3'd1    : begin
                  s_bitCounterLoadValue <= 4'd8;
                  s_dataBits            <= {2'd0, s_shiftReg[9:4]};
                end
      3'd2    : begin
                  s_bitCounterLoadValue <= 4'd9;
                  s_dataBits            <= {1'd0, s_shiftReg[9:3]};
                end
      3'd3    : begin
                  s_bitCounterLoadValue <= 4'd10;
                  s_dataBits            <= s_shiftReg[9:2];
                end
      3'd4    : begin
                  s_bitCounterLoadValue <= 4'd8;
                  s_dataBits            <= {3'd0, s_shiftReg[8:4]};
                end
      3'd5    : begin
                  s_bitCounterLoadValue <= 4'd9;
                  s_dataBits            <= {2'd0, s_shiftReg[8:3]};
                end
      3'd6    : begin
                  s_bitCounterLoadValue <= 4'd10;
                  s_dataBits            <= {1'd0, s_shiftReg[8:2]};
                end
      default : begin
                  s_bitCounterLoadValue <= 4'd11;
                  s_dataBits            <= s_shiftReg[8:1];
                end
    endcase

  // here the state machine is defined
  reg [1:0] s_stateMachineNext;
  
  always @*
    case (s_stateMachineReg)
      IDLE    : s_stateMachineNext <= (s_rxNegEdge == 1'b1) ? INIT : IDLE;
      INIT    : s_stateMachineNext <= RECEIVE;
      RECEIVE : s_stateMachineNext <= (s_bitCounterReg == 4'd0) ? WRITE : RECEIVE;
      default : s_stateMachineNext <= IDLE;
    endcase
    
    always @(posedge clock) s_stateMachineReg <= (reset == 1'b1) ? IDLE : s_stateMachineNext;
 
  // here all data related signals are defined
  reg  s_isBreak, s_frameErrorReg, s_breakReg, s_overrunReg, s_parityErrorReg, s_delayReg;
  reg [7:0]  s_dataOutReg;
  wire [3:0] s_xorStage1;
  wire [1:0] s_xorStage2 = {(s_xorStage1[3] ^ s_xorStage1[2]) , (s_xorStage1[0] ^ s_xorStage1[1]) };
  wire s_dataParity = s_xorStage2[1] ^ s_xorStage2[0];
  wire s_8BitBreak = (s_shiftReg[10:1] == 10'd0) ? 1'b1 : 1'b0;
  wire s_7BitBreak = (s_shiftReg[10:2] == 9'd0) ? 1'b1 : 1'b0;
  wire s_6BitBreak = (s_shiftReg[10:3] == 8'd0) ? 1'b1 : 1'b0;
  wire s_5BitBreak = (s_shiftReg[10:4] == 7'd0) ? 1'b1 : 1'b0;
  wire s_parity    = ~(s_shiftReg[9] ^ controlReg[4]);
  wire s_parityError = (controlReg[5] == 1'b1) ? (s_parity ^ s_dataParity) & controlReg[3] :
                       ~(s_shiftReg[9] ^ controlReg[4]) & controlReg[3];
  
  assign frameError    = s_frameErrorReg;
  assign breakDetected = s_breakReg;
  assign overrunError  = s_overrunReg;
  assign parityError   = s_parityErrorReg;
  assign fifoData      = s_dataOutReg;
  
  always @*
    case (controlReg[1:0])
      2'd0    : s_isBreak <= s_5BitBreak;
      2'd1    : s_isBreak <= s_6BitBreak;
      2'd2    : s_isBreak <= s_7BitBreak;
      default : s_isBreak <= s_8BitBreak;
    endcase
  
  genvar n;
  
  generate
    for (n = 0; n < 4; n = n + 1)
	   begin : gen
        assign s_xorStage1[n] = s_dataBits[n*2] ^ s_dataBits[n*2 + 1];
		end
  endgenerate
  
  always @(posedge clock)
    begin
      s_frameErrorReg  <= (reset == 1'b1) ? 1'b0 : (s_stateMachineReg == WRITE) ? s_shiftReg[10] | s_isBreak : s_frameErrorReg;
      s_breakReg       <= (reset == 1'b1) ? 1'b0 : (s_stateMachineReg == WRITE) ? s_isBreak : s_breakReg;
      s_overrunReg     <= (reset == 1'b1) ? 1'b0 : (s_stateMachineReg == WRITE) ? fifoFull & ~s_isBreak : s_overrunReg;
      s_parityErrorReg <= (reset == 1'b1) ? 1'b0 : (s_stateMachineReg == WRITE) ? s_parityError : s_parityErrorReg;
      s_dataOutReg     <= (s_stateMachineReg == WRITE) ? s_dataBits : s_dataOutReg;
      s_delayReg       <= (reset == 1'b1 || s_stateMachineReg != WRITE) ? 1'b0 : 1'b1;
      fifoWe           <= s_delayReg & ~s_overrunReg;
    end
  
endmodule
