module logicAnalyserCore (
  input wire        CLK_I,
  input wire        RST_I, // system reset
  input wire        resetCore, // logic analyser reset (start a new capture)
  
  input wire [63:0] tappedWires,
  
  input  wire [8:0]  postTrigSamples,
  input  wire [1:0]  seqLen,
  input  wire [2:0]  comparator0,
  input  wire [2:0]  comparator1,
  input  wire [2:0]  comparator2,
  input  wire [2:0]  comparator3,
  input  wire [63:0] mask0,
  input  wire [63:0] mask1,
  input  wire [63:0] mask2,
  input  wire [63:0] mask3,
  input  wire [63:0] reference0,
  input  wire [63:0] reference1,
  input  wire [63:0] reference2,
  input  wire [63:0] reference3,
  output wire        done,
  output reg  [8:0]  startAddress,
  
  input  wire [8:0]  readAddress,
  output wire [31:0] dataLow,
  output wire [31:0] dataHigh);

  // comparators
  localparam ANY     = 3'd0;
  localparam EQ      = 3'd1;
  localparam LESS    = 3'd2;
  localparam GREATER = 3'd3;
  
  // fsm states
  localparam RESET  = 2'd0;
  localparam ACTIVE = 2'd1;
  localparam FINISH = 2'd2;
  localparam DONE   = 2'd3;
  
  reg [1:0]  currentState;
  reg [1:0]  validSampleReg;
  reg [8:0]  writeAddress;
  reg [8:0]  resetCounter;
  reg [8:0]  endCounter;
  reg [63:0] tappedWiresReg;
  reg [63:0] tappedWiresDelayedReg;
  reg [9:0]  trigShift;
  reg        trigFound;
  wire [8:0] ramWriteAddress = (currentState == RESET) ? resetCounter : writeAddress;
  wire       ramWriteEnable = (currentState == RESET) ? 1'b1 : validSampleReg[1];
  
  // to not influence the tapped wires, we first latch them
  always @(posedge CLK_I)
    if (RST_I == 1'b1 || resetCore == 1'b1)
      begin
        tappedWiresReg        <= 64'd0;
        tappedWiresDelayedReg <= 64'd0;
        validSampleReg        <= 2'd0;
      end
    else if (currentState == ACTIVE || currentState == FINISH)
      begin
        tappedWiresReg        <= tappedWires;
        tappedWiresDelayedReg <= tappedWiresReg;
        validSampleReg        <= {validSampleReg[0],1'b1};
      end
    else
      begin
        tappedWiresReg        <= 64'd0;
        tappedWiresDelayedReg <= tappedWiresReg;
        validSampleReg        <= {validSampleReg[0],1'b0};
      end

  // here we define the trigger
  always @*
    case (seqLen)
      2'b00   : trigFound <= trigShift[0];
      2'b01   : trigFound <= (trigShift[2:1] == 2'b11) ? 1'b1 : 1'b0;
      2'b10   : trigFound <= (trigShift[5:3] == 3'b111) ? 1'b1 : 1'b0;
      default : trigFound <= (trigShift[9:6] == 4'b1111) ? 1'b1 : 1'b0;
    endcase
  
  // here we define the trigShift
  always @(posedge CLK_I)
    if (RST_I == 1'b1 || resetCore == 1'b1)
      trigShift <= 10'd0;
    else if (currentState == ACTIVE)
    begin
      case (comparator0)
        ANY     : trigShift[0] <= 1'b1;
        EQ      : trigShift[0] <= ((tappedWiresReg & mask0) == reference0) ? 1'b1 : 1'b0;
        LESS    : trigShift[0] <= ((tappedWiresReg & mask0)  < reference0) ? 1'b1 : 1'b0;
        default : trigShift[0] <= ((tappedWiresReg & mask0)  > reference0) ? 1'b1 : 1'b0;
      endcase
      case (comparator1)
        ANY     : trigShift[2] <= 1'b1;
        EQ      : trigShift[2] <= ((tappedWiresReg & mask1) == reference1) ? 1'b1 : 1'b0;
        LESS    : trigShift[2] <= ((tappedWiresReg & mask1)  < reference1) ? 1'b1 : 1'b0;
        default : trigShift[2] <= ((tappedWiresReg & mask1)  > reference1) ? 1'b1 : 1'b0;
      endcase
      case (comparator2)
        ANY     : trigShift[5] <= 1'b1;
        EQ      : trigShift[5] <= ((tappedWiresReg & mask2) == reference2) ? 1'b1 : 1'b0;
        LESS    : trigShift[5] <= ((tappedWiresReg & mask2)  < reference2) ? 1'b1 : 1'b0;
        default : trigShift[5] <= ((tappedWiresReg & mask2)  > reference2) ? 1'b1 : 1'b0;
      endcase
      case (comparator3)
        ANY     : trigShift[9] <= 1'b1;
        EQ      : trigShift[9] <= ((tappedWiresReg & mask3) == reference3) ? 1'b1 : 1'b0;
        LESS    : trigShift[9] <= ((tappedWiresReg & mask3)  < reference3) ? 1'b1 : 1'b0;
        default : trigShift[9] <= ((tappedWiresReg & mask3)  > reference3) ? 1'b1 : 1'b0;
      endcase
      trigShift[1] <= trigShift[0];
      trigShift[3] <= trigShift[1];
      trigShift[4] <= trigShift[2];
      trigShift[6] <= trigShift[3];
      trigShift[7] <= trigShift[4];
      trigShift[8] <= trigShift[5];
    end

  // here we define the reset counter used to clear the memory
  always @(posedge CLK_I)
    if (RST_I == 1'b1 || resetCore == 1'b1)
      resetCounter <= {9{1'b1}};
    else if (resetCounter > 9'd0)
      resetCounter <= resetCounter - 9'd1;

  // here we define the writeCounter
  always @(posedge CLK_I)
    if (RST_I == 1'b1)
      writeAddress <= 9'd0;
    else if (validSampleReg[1] == 1'b1)
      writeAddress <= writeAddress + 9'd1;
  
  // here we define the startAddress
  always @(posedge CLK_I)
    if (RST_I == 1'b1)
      startAddress <= 9'd0;
    else if (currentState == ACTIVE && trigFound == 1'b1)
      startAddress <= writeAddress + endCounter + 9'd2;

  // here we define the endCounter
  always @(posedge CLK_I)
    if (resetCore == 1'b1)
      endCounter <= postTrigSamples;
    else if (currentState == FINISH && endCounter != 9'd0)
      endCounter <= endCounter - 9'd1;

  // here we define the state machine
  always @(posedge CLK_I)
    if (RST_I == 1'b1)
      currentState <= DONE;
    else
      case (currentState)
        DONE    : currentState <= (resetCore == 1'b1) ? RESET : DONE;
        RESET   : currentState <= (resetCounter == 9'd0) ? ACTIVE : RESET;
        ACTIVE  : currentState <= (trigFound == 1'b0) ? ACTIVE :
                                  (endCounter == 9'd0) ? DONE : FINISH;
        default : currentState <= (endCounter == 9'd0) ? DONE : FINISH;
      endcase

  assign done = (currentState == DONE && validSampleReg == 2'd0) ? 1'b1 : 1'b0;
  
  // here we map the two ram components
  ssramPseudoDual
    #(.BITWIDTH(32),
      .NR_ENTRIES(512)) sramLow
     (.clock(CLK_I),
      .writeEnable(ramWriteEnable),
      .writeAddress(ramWriteAddress),
      .writeData(tappedWiresDelayedReg[31:0]),
      .readAddress(readAddress),
      .readData(dataLow));

  ssramPseudoDual
    #(.BITWIDTH(32),
      .NR_ENTRIES(512)) sramHi
     (.clock(CLK_I),
      .writeEnable(ramWriteEnable),
      .writeAddress(ramWriteAddress),
      .writeData(tappedWiresDelayedReg[63:32]),
      .readAddress(readAddress),
      .readData(dataHigh));

endmodule
