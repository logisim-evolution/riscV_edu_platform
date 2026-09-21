module uartTx ( input wire        clock,
                                  reset,
                                  baudRateX2tick,
                input wire [6:0]  controlReg,
                input wire [7:0]  fifoData,
                input wire        fifoEmpty,
                output wire       busy,
                output reg        fifoReadAck,
                                  uartTxLine );
  
  localparam [1:0] IDLE  = 2'b00;
  localparam [1:0] LOAD  = 2'b01;
  localparam [1:0] SHIFT = 2'b10;
  
  reg [1:0] s_stateMachineReg;
  
  assign busy = (s_stateMachineReg == IDLE) ? 1'b0 : 1'b1;

  // here we define the parity
  wire [3:0] s_xorStage1;
  wire s_mux1 = (controlReg[0] == 1'b0) ? fifoData[6] : s_xorStage1[3];
  reg  s_mux2;
  wire [1:0] s_xorStage2 = { (s_xorStage1[2] ^ s_mux1), (s_xorStage1[0] ^ s_xorStage1[1]) };
  wire s_xorStage3 = s_mux2 ^ s_xorStage2[0];
  wire s_parityBit = (controlReg[3] == 1'b0) ? 1'b1 : (controlReg[5] == 1'b1) ? ~controlReg[4] : ~(s_xorStage3 ^ controlReg[4]);
  
  genvar n;
  
  generate
    for (n = 0; n < 4; n = n + 1)
	   begin : gen
        assign s_xorStage1[n] = fifoData[n * 2] ^ fifoData[n * 2 + 1];
		end
  endgenerate
  
  always @*
    case (controlReg[1:0])
      2'b00     : s_mux2 <= fifoData[4];
      2'b01     : s_mux2 <= s_xorStage1[2];
      default   : s_mux2 <= s_xorStage2[1];
    endcase
  
  // here we define the shifter
  reg        s_bitDoneReg;
  wire       s_bitDoneNext      = (reset == 1'b1 || s_stateMachineReg != SHIFT) ? 1'b0 : s_bitDoneReg ^ baudRateX2tick;
  wire       s_loadShifter      = (s_stateMachineReg == LOAD && baudRateX2tick == 1'b1) ? 1'b1 : 1'b0;
  wire       s_shiftOnePosition = s_bitDoneReg & baudRateX2tick;
  wire [9:0] s_shifterLoadValue;
  reg  [9:0] s_shiftReg;
  wire [9:0] s_shiftNext = (reset == 1'b1) ? 10'h3FF : (s_loadShifter == 1'b1) ? s_shifterLoadValue :
                           (s_shiftOnePosition == 1'b1) ? {s_shiftReg[8:0], 1'b1} : s_shiftReg;
  
  assign s_shifterLoadValue[9] = 1'b0;
  assign s_shifterLoadValue[8] = fifoData[0];
  assign s_shifterLoadValue[7] = fifoData[1];
  assign s_shifterLoadValue[6] = fifoData[2];
  assign s_shifterLoadValue[5] = fifoData[3];
  assign s_shifterLoadValue[4] = fifoData[4];
  assign s_shifterLoadValue[3] = (controlReg[1:0] == 2'b00) ? s_parityBit : fifoData[5];
  assign s_shifterLoadValue[2] = (controlReg[1:0] == 2'b01) ? s_parityBit : (controlReg[1] == 1'b1) ? fifoData[6] : 1'b1;
  assign s_shifterLoadValue[1] = (controlReg[1:0] == 2'b10) ? s_parityBit : (controlReg[1:0] == 2'b11) ? fifoData[7] : 1'b1;
  assign s_shifterLoadValue[0] = (controlReg[1:0] == 2'b11) ? s_parityBit : 1'b1;
  
  always @(posedge clock)
    begin
      s_bitDoneReg <= s_bitDoneNext;
      s_shiftReg   <= s_shiftNext;
      uartTxLine   <= (reset == 1'b1) ? 1'b1 : s_shiftReg[9] & ~controlReg[6];
      fifoReadAck  <= s_loadShifter;
    end

  // here we define the half bit counter
  reg  [4:0] s_halfBitCountReg, s_halfBitLoadValue;
  wire [4:0] s_halfBitCountNext = (reset == 1'b1) ? 5'd0 : (s_stateMachineReg == LOAD && baudRateX2tick == 1'b1) ? s_halfBitLoadValue :
                                  (s_halfBitCountReg == 5'd0 || baudRateX2tick == 1'b0) ? s_halfBitCountReg : s_halfBitCountReg - 5'd1;
  
  always @(posedge clock) s_halfBitCountReg <= s_halfBitCountNext;
  
  always @*
    case (controlReg[3:0])
      4'h0    : s_halfBitLoadValue <= 5'd14;
      4'h1    : s_halfBitLoadValue <= 5'd16;
      4'h2    : s_halfBitLoadValue <= 5'd18;
      4'h3    : s_halfBitLoadValue <= 5'd20;
      4'h4    : s_halfBitLoadValue <= 5'd15;
      4'h5    : s_halfBitLoadValue <= 5'd18;
      4'h6    : s_halfBitLoadValue <= 5'd20;
      4'h7    : s_halfBitLoadValue <= 5'd22;
      4'h8    : s_halfBitLoadValue <= 5'd16;
      4'h9    : s_halfBitLoadValue <= 5'd18;
      4'hA    : s_halfBitLoadValue <= 5'd20;
      4'hB    : s_halfBitLoadValue <= 5'd22;
      4'hC    : s_halfBitLoadValue <= 5'd17;
      4'hD    : s_halfBitLoadValue <= 5'd20;
      4'hE    : s_halfBitLoadValue <= 5'd22;
      default : s_halfBitLoadValue <= 5'd24;
    endcase
  
  // here we define the state machine
  reg [1:0] s_stateMachineNext;
  
  always @*
    case (s_stateMachineReg)
      IDLE     : s_stateMachineNext <= (fifoEmpty == 1'b0) ? LOAD : IDLE;
      LOAD     : s_stateMachineNext <= (baudRateX2tick == 1'b1) ? SHIFT : LOAD;
      SHIFT    : s_stateMachineNext <= (s_halfBitCountReg == 5'd1 && fifoEmpty == 1'b1) ? IDLE :
                                       (s_halfBitCountReg == 5'd1 && fifoEmpty == 1'b0) ? LOAD : SHIFT;
      default  : s_stateMachineNext <= IDLE;
    endcase
  
  always @(posedge clock) s_stateMachineReg <= (reset == 1'b1) ? IDLE : s_stateMachineNext;
endmodule
