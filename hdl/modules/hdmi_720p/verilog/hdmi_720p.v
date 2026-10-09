module hdmi_720p ( input wire pixelClockIn,
                              reset,
                              testPicture,
                              pixelClkX2,
                   output wire[4:0] hdmiRed,
                                    hdmiBlue,
                                    hdmiGreen,
                   output wire      pixelClock,
                                    horizontalSync,
                                    verticalSync,
                                    activePixel,

                   output reg [10:0] pixelIndex,
                   output reg [ 9:0] lineIndex,
                   output reg        requestPixel,
                                     newScreen,
                                     nextLine,
                                     hSyncOut,
                                     vSyncOut,
                   input wire        hSyncIn,
                                     vSyncIn,
                                     activeIn,
                   input wire [ 4:0] redIn,
                                     blueIn,
                   input wire [ 5:0] greenIn);

  localparam [1:0] BACKPORCH = 0,
                   ACTIVEPIXEL = 1,
                   FRONTPORCH = 2,
                   SYNC = 3;
  
  localparam [10:0] horizontalBackPorch = 11'd220-11'd1,
                    horizontalFrontPorch = 11'd110-11'd1,
                    horizontalSyncCount = 11'd40-11'd1,
                    horizontalActiveVideo = 11'd1280-11'd1;
  localparam [ 9:0] verticalBackPorch = 10'd20-10'd1,
                    verticalFrontPorch = 10'd5-10'd1,
                    verticalSyncCount = 10'd5-10'd1,
                    verticalActiveVideo = 10'd720-10'd1;
  reg [4:0] s_redReg, s_blueReg;
  reg [5:0] s_greenReg;
  reg       s_hSyncReg, s_vSyncReg, s_activeReg;
  wire s_activeVideo;
  wire s_horizontalCounterZero, s_nextLine, s_verticalCounterZero;
  wire [4:0] s_red, s_blue;
  wire [5:0] s_green;
  reg [1:0] s_horizontalNextState, s_verticalNextState;
  reg [1:0] s_horizontalState, s_verticalState;
  wire [10:0] s_horizontalCounterNext;
  reg [10:0] s_horizontalCounter, s_horizontalReloadValue;
  wire [9:0] s_verticalCounterNext;
  reg [9:0] s_verticalCounter, s_verticalReloadValue;
  wire s_horizontalSync, s_verticalSync, s_newScreen;
  reg s_earlyNextLine;
  

  /* all outputs are registered */
  reg s_pixelClockReg;
  OFS1P3IX hsyncff
    (.CD(reset),
     .D(s_hSyncReg),
     .SP(1'b1),
     .SCLK(pixelClkX2),
     .Q(horizontalSync));

  OFS1P3IX vsyncff
    (.CD(reset),
     .D(s_vSyncReg),
     .SP(1'b1),
     .SCLK(pixelClkX2),
     .Q(verticalSync));

  OFS1P3IX activeff
    (.CD(reset),
     .D(s_activeReg),
     .SP(1'b1),
     .SCLK(pixelClkX2),
     .Q(activePixel));

  OFS1P3IX clockff
    (.CD(reset),
     .D(s_pixelClockReg),
     .SP(1'b1),
     .SCLK(pixelClkX2),
     .Q(pixelClock));

  genvar i;
  generate
    for (i = 0; i < 5 ; i = i + 1)
      begin
        OFS1P3IX redff
          (.CD(reset),
           .D(s_redReg[i]),
           .SP(1'b1),
           .SCLK(pixelClkX2),
           .Q(hdmiRed[i]));
        OFS1P3IX greenff
          (.CD(reset),
           .D(s_greenReg[i+1]),
           .SP(1'b1),
           .SCLK(pixelClkX2),
           .Q(hdmiGreen[i]));
        OFS1P3IX blueff
          (.CD(reset),
           .D(s_blueReg[i]),
           .SP(1'b1),
           .SCLK(pixelClkX2),
           .Q(hdmiBlue[i]));
      end
  endgenerate
  
  always @(posedge pixelClkX2)
  begin
    s_pixelClockReg <= (reset == 1'b1) ? 1'b1 : ~s_pixelClockReg;
    s_redReg        <= (s_pixelClockReg == 1'b1) ? s_red : s_redReg;
    s_greenReg      <= (s_pixelClockReg == 1'b1) ? s_green : s_greenReg;
    s_blueReg       <= (s_pixelClockReg == 1'b1) ? s_blue : s_blueReg;
    s_hSyncReg     <= (s_pixelClockReg == 1'b0) ? s_hSyncReg : (testPicture == 0) ? hSyncIn : s_horizontalSync;
    s_vSyncReg     <= (s_pixelClockReg == 1'b0) ? s_vSyncReg : (testPicture == 0) ? vSyncIn : s_verticalSync;
    s_activeReg    <= (s_pixelClockReg == 1'b0) ? s_activeReg : (testPicture == 0) ? activeIn : s_activeVideo;
  end

  // here some control signals are defined
  always @(posedge pixelClockIn)
  begin
    s_earlyNextLine <= (s_horizontalState == ACTIVEPIXEL) ? s_horizontalCounterZero : 1'b0;
    newScreen       <= s_newScreen;
    nextLine        <= (s_verticalState == ACTIVEPIXEL) ? s_earlyNextLine : 1'b0;
    pixelIndex      <= horizontalActiveVideo - s_horizontalCounter;
    lineIndex       <= verticalActiveVideo - s_verticalCounter;
    requestPixel    <= s_activeVideo;
    hSyncOut        <= s_horizontalSync;
    vSyncOut        <= s_verticalSync;
  end
  
  // here the test picture is defined
  assign s_activeVideo = ((s_horizontalState == ACTIVEPIXEL)&&(s_verticalState == ACTIVEPIXEL)) ? 1'b1 : 1'b0;
  assign s_red   = (!s_activeVideo) ? 5'd0 : (testPicture) ? {s_horizontalCounter[9:8],3'b0} : redIn;
  assign s_green = (!s_activeVideo) ? 6'd0 : (testPicture) ? {s_horizontalCounter[7:6],4'b0} : greenIn;
  assign s_blue  = (!s_activeVideo) ? 5'd0 : (testPicture) ? {s_verticalCounter[8:7],3'b0} : blueIn;
  
  /* here we define the horizontal logic */
  assign s_horizontalSync = (s_horizontalState == SYNC) ? 1'b1 : 1'b0;
  assign s_horizontalCounterZero = (s_horizontalCounter == 0) ? 1'b1 : 1'b0;
  assign s_horizontalCounterNext = (s_horizontalCounterZero == 11'd1) ? s_horizontalReloadValue :
                                   s_horizontalCounter - 11'd1;
  
  always @*
  begin
    case (s_horizontalState)
      BACKPORCH   : s_horizontalNextState = ACTIVEPIXEL;
      ACTIVEPIXEL : s_horizontalNextState = FRONTPORCH;
      FRONTPORCH  : s_horizontalNextState = SYNC;
      default     : s_horizontalNextState = BACKPORCH;
    endcase
  end
  
  always @*
  begin
    case (s_horizontalNextState) 
      BACKPORCH   : s_horizontalReloadValue = horizontalBackPorch;
      ACTIVEPIXEL : s_horizontalReloadValue = horizontalActiveVideo;
      FRONTPORCH  : s_horizontalReloadValue = horizontalFrontPorch;
      default     : s_horizontalReloadValue = horizontalSyncCount;
    endcase
  end
  
  always @(posedge pixelClockIn)
  begin
    if (reset == 1'b1) 
      begin
        s_horizontalState   <= SYNC;
        s_horizontalCounter <= horizontalSyncCount;
      end
    else
      begin
        s_horizontalCounter <= s_horizontalCounterNext;
        if (s_horizontalCounterZero == 1'b1) s_horizontalState <= s_horizontalNextState;
      end
  end
  
  /* here we define the vertical logic */
  assign s_newScreen = s_verticalSync & s_verticalCounterZero;
  assign s_verticalSync = (s_verticalState == SYNC) ? 1'b1 : 1'b0;
  assign s_nextLine = (s_horizontalState == FRONTPORCH) ? s_horizontalCounterZero : 1'b0;
  assign s_verticalCounterZero = (s_verticalCounter == 0) ? s_nextLine : 1'b0;
  assign s_verticalCounterNext = (s_verticalCounterZero == 1'b1) ? s_verticalReloadValue :
                                 (s_nextLine == 1'b1) ? s_verticalCounter - 10'd1 : s_verticalCounter;
  
  always @*
  begin
    case (s_verticalState)
      BACKPORCH   : s_verticalNextState = ACTIVEPIXEL;
      ACTIVEPIXEL : s_verticalNextState = FRONTPORCH;
      FRONTPORCH  : s_verticalNextState = SYNC;
      default     : s_verticalNextState = BACKPORCH;
    endcase
  end
  
  always @*
  begin
    case (s_verticalNextState) 
      BACKPORCH   : s_verticalReloadValue = verticalBackPorch;
      ACTIVEPIXEL : s_verticalReloadValue = verticalActiveVideo;
      FRONTPORCH  : s_verticalReloadValue = verticalFrontPorch;
      default     : s_verticalReloadValue = verticalSyncCount;
    endcase
  end
  
  always @(posedge pixelClockIn)
  begin
    if (reset == 1'b1) 
      begin
        s_verticalState   <= SYNC;
        s_verticalCounter <= verticalSyncCount;
      end
    else
      begin
        s_verticalCounter <= s_verticalCounterNext;
        if (s_verticalCounterZero == 1) s_verticalState <= s_verticalNextState;
      end
  end
endmodule
