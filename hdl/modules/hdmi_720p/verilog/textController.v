module textController #(parameter [15:0] defaultForeGroundColor = 16'hFFFF,
                        parameter [15:0] defaultBackGroundColor = 16'd0,
                        parameter [6:0]  customIntructionNr = 7'd0,
                        parameter defaultSmallChars = 1'b1)
                       (input wire         clock,
                                           pixelClock,
                                           reset,
                        input wire [1:0]   nrOfScreens,
                        input wire [10:0]  pixelIndex,
                        input wire [9:0]   lineIndex,
                        output reg [10:0]  screenOffset,
                                           screenBar,
                                           screenHeight,
                        // here we define the custom instruction interface
                        input wire [6:0]   ciN,
                        input wire [31:0]  ciDataA,
                                           ciDataB,
                        input wire         ciStart,
                        output wire        ciDone,
                        output wire [31:0] ciResult,
                        // here we define the interface to the ram and screen controller
                        output wire        ramWe,
                        output wire [7:0]  ramData,
                        output wire [12:0] ramAddress,
                        output wire [12:0] ramLookupAddress,
                        output reg [2:0]   asciiBitSelector,
                                           asciiLineIndex,
                        output [15:0]      foreGroundColor,
                                           backGroundColor,
                        output             cursorVisible );

  /*
   * This is the text controller that supports following resolutions:
   * 
   * nrOfScreens:  SmallChars:  nrOfCharsPerLine: nrOfLines: CharResolution:
   *     0/1           0            40              45         16x16
   *     0/1           1            80              90          8x8
   *     2             0            40              22         16x16
   *     2             1            80              44          8x8
   *     3             0            40              14         16x16
   *     3             1            80              29          8x8
   *
   */
  
  /*
   * For the custom Intruction Interface:
   *
   * DataA[3..0]  DataB:                DataC:          Remark:
   *   0000       ForeGroundColor       --              Write new Color on 16Bits RGB565
   *   1000       --                    ForeGroundColor Read current Color on 16 bits RGB565
   *   0001       BackGoundColor        --              Write new Color on 16Bits RGB565
   *   1001       --                    BackGoundColor  Read current Color on 16 bits RGB565
   *   0010       Char ASCII            --              Write a character (7 bits) at the current cursor position
   *   0011       --                    --              Clear Screen
   *   0100       bit0:SmallChars       --              Set the smallChars parameter (changing this value will force a clear screen)
   *   0101       bit0:CursorVisible    --              Enable or disable the visible cursor
   *   0110       bit1-0 TextCorrection --              Set the text correction for Televisions (0-3 Chars/lines)
   *   1110       --                    TextCorrection  Read the text correction for Televisions (0-3 Chars/lines)
   *   1111       --                    Screen Info     Read bits[31:16] the number of lines and bits[15:0] number of characters each line
   *  others                                            No function
   *
   */
  
  wire s_busy;
  /*
   *
   * Here the custom instruction interface is defined
   *
   */
  reg [15:0] s_foreGroundColorReg, s_backGroundColorReg;
  reg [1:0]  s_TextCorrectionReg;
  reg [6:0]  s_delayedCharToBeWrittenReg;
  reg        s_cursorVisibleReg;
  reg        s_delayWeCharReg;
  reg        s_smallCharsReg;
  
  assign foreGroundColor = s_foreGroundColorReg;
  assign backGroundColor = s_backGroundColorReg;
  
  always @(posedge clock)
    begin
      screenOffset <= {6'd0,s_TextCorrectionReg,3'd0};
      screenBar    <= (nrOfScreens == 2'd3) ? 11'd12 : 11'd16;
    end
  
  wire s_isMyCustomInstruction = (ciN == customIntructionNr) ? ciStart : 1'b0;
  wire s_weForeGroudColor      = (ciDataA[3:0] == 4'h0) ? s_isMyCustomInstruction : 1'b0;
  wire s_weBackGroudColor      = (ciDataA[3:0] == 4'h1) ? s_isMyCustomInstruction : 1'b0;
  wire s_weSmallChars          = (ciDataA[3:0] == 4'h4) ? s_isMyCustomInstruction : 1'b0;
  wire s_SmallCharsChanged     = (s_weSmallChars == 1'b1 && ciDataB[0] != s_smallCharsReg) ? 1'b1 : 1'b0;
  wire s_weTextCorrection      = (ciDataA[3:0] == 4'h6) ? s_isMyCustomInstruction : 1'b0;
  wire s_textCorrectionChanged = (s_weTextCorrection == 1'b1 && ciDataB[1:0] != s_TextCorrectionReg) ? 1'b1 : 1'b0;
  wire s_clearScreen           = (reset == 1'b1 || (ciDataA[3:0] == 4'h3 && s_isMyCustomInstruction) || s_SmallCharsChanged == 1'b1 ||
                                  s_textCorrectionChanged == 1'b1) ? 1'b1 : 1'b0;
  wire s_weCursor              = (ciDataA[3:0] == 4'h5) ? s_isMyCustomInstruction : 1'b0;
  wire s_delayWeChar           = (ciDataA[3:0] == 4'h2 && s_isMyCustomInstruction == 1'b1) ? s_busy & ~s_delayWeCharReg : 1'b0;
  wire s_delayWeCharTaken      = s_delayWeCharReg & ~s_busy;
  wire s_weChar                = ((ciDataA[3:0] == 4'h2 && s_isMyCustomInstruction == 1'b1 && s_busy == 1'b0 && ciDataB[6:0] != 7'd10) || 
                                  (s_delayWeCharTaken == 1'b1 && s_busy == 1'b0 && s_delayedCharToBeWrittenReg != 7'd10)) ? 1'b1 : 1'b0;
  wire s_nextLine              = ((ciDataA[3:0] == 4'h2 && s_isMyCustomInstruction == 1'b1 && ciDataB[6:0] == 7'd10 && s_busy == 1'b0) || 
                                  (s_delayWeCharTaken == 1'b1 && s_delayedCharToBeWrittenReg == 7'd10 && s_busy == 1'b0)) ? 1'b1 : 1'b0;

  always @(posedge clock)
    begin
      s_foreGroundColorReg        <= (reset == 1'b1) ? defaultForeGroundColor : (s_weForeGroudColor == 1'b1) ? ciDataB[15:0] : s_foreGroundColorReg;
      s_backGroundColorReg        <= (reset == 1'b1) ? defaultBackGroundColor : (s_weBackGroudColor == 1'b1) ? ciDataB[15:0] : s_backGroundColorReg;
      s_smallCharsReg             <= (reset == 1'b1) ? defaultSmallChars : (s_weSmallChars == 1'b1) ? ciDataB[0] : s_smallCharsReg;
      s_cursorVisibleReg          <= (reset == 1'b1) ? 1'b1 : (s_weCursor == 1'b1) ? ciDataB[0] : s_cursorVisibleReg;
      s_delayWeCharReg            <= (reset == 1'b1 || s_delayWeCharTaken == 1'b1) ? 1'b0 : s_delayWeCharReg | s_delayWeChar;
      s_delayedCharToBeWrittenReg <= (s_delayWeCharReg == 1'b1) ? ciDataB[6:0] : s_delayedCharToBeWrittenReg;
      s_TextCorrectionReg         <= (reset == 1'b1) ? 2'd3 : (s_weTextCorrection == 1'b1) ? ciDataB[1:0] : s_TextCorrectionReg;
    end

  
  /*
   *
   * Here we define the screen parameters
   *
   */
  reg [6:0]  s_maxLines;
  wire [6:0] s_maxCharsPerLine = (s_smallCharsReg == 1'b1) ? 7'd80 - {5'd0,s_TextCorrectionReg} : 7'd40 - {5'd0,s_TextCorrectionReg};
  wire [2:0] s_lineSelect = {nrOfScreens, s_smallCharsReg};
  
  always @(posedge clock) 
    screenHeight = (s_smallCharsReg == 1'b1) ? {1'b0,s_maxLines,3'd0} : {s_maxLines,4'd0};
  
  always @*
    case (s_lineSelect)
      3'b000   : s_maxLines <= 7'd45 - {3'd0,s_TextCorrectionReg,2'd0};
      3'b001   : s_maxLines <= 7'd90 - {4'd0,s_TextCorrectionReg,1'd0};
      3'b010   : s_maxLines <= 7'd45 - {3'd0,s_TextCorrectionReg,2'd0};
      3'b011   : s_maxLines <= 7'd90 - {4'd0,s_TextCorrectionReg,1'd0};
      3'b100   : s_maxLines <= 7'd22 - {4'd0,s_TextCorrectionReg,1'd0};
      3'b101   : s_maxLines <= 7'd44 - {5'd0,s_TextCorrectionReg};
      3'b110   : s_maxLines <= 7'd14 - {4'd0,s_TextCorrectionReg,1'd0};
      default  : s_maxLines <= 7'd29 - {5'd0,s_TextCorrectionReg};
    endcase
  
  /*
   *
   * Here the output is defined
   *
   */
  reg [31:0] s_ciResult;
  
  assign ciResult = (s_isMyCustomInstruction == 1'b1 && ciDataA[3] == 1'b1) ? s_ciResult : 32'd0;
  
  always @*
    case (ciDataA[2:0])
      3'd0    : s_ciResult <= {16'd0, s_foreGroundColorReg};
      3'd1    : s_ciResult <= {16'd0, s_backGroundColorReg};
      3'd4    : s_ciResult <= {31'd0,s_smallCharsReg};
      3'd5    : s_ciResult <= {31'd0,s_cursorVisibleReg};
      3'd6    : s_ciResult <= {30'd0,s_TextCorrectionReg};
      3'd7    : s_ciResult <= {8'd0, s_maxLines, 8'd0, s_maxCharsPerLine};
      default : s_ciResult <= 32'd0;
    endcase

  /*
   *
   * Here the clear screen is handeled
   *
   */
  reg [13:0] s_clearScreenCounterReg;
  
  always @(posedge clock) s_clearScreenCounterReg <= (s_clearScreen == 1'b1) ? 13'd0 : (s_clearScreenCounterReg[13] == 1'b0) ? s_clearScreenCounterReg + 14'd1 : s_clearScreenCounterReg;
  
  /*
   *
   * Here the line cleaning is handeled
   *
   */
  reg [7:0] s_clearLineCounterReg;
  reg s_clearLine;
  
  always @(posedge clock) s_clearLineCounterReg <= (reset == 1'b1) ? 8'hFF : (s_clearLine == 1'b1) ? 8'd0 : (s_clearLineCounterReg[7] == 1'b0) ? s_clearLineCounterReg + 8'd1 : s_clearLineCounterReg;
  
  /*
   *
   * Here the busy signal is defined, and the done for the ci-interface
   *
   */
  
  assign s_busy = ~(s_clearScreenCounterReg[13] & s_clearLineCounterReg[7]);
  assign ciDone = (s_delayWeChar == 1'b0 && s_delayWeCharReg == 1'b0) ? s_isMyCustomInstruction : s_delayWeCharTaken;
  
  /*
   *
   * Here we define the cursor
   *
   */
  reg [6:0]  s_cursorXPos, s_cursorYPos;
  reg [12:0] s_screenOffsetReg;
  wire       s_isOnCursorXPos = ((s_smallCharsReg == 1'b1 && ((pixelIndex[10:3] - {5'd0,s_TextCorrectionReg}) == {1'b0,s_cursorXPos})) ||
                                 (s_smallCharsReg == 1'b0 && ((pixelIndex[10:4] - {5'd0,s_TextCorrectionReg}) == s_cursorXPos))) ? 1'b1 : 1'b0;
  wire       s_isOnCursorYPos = ((s_smallCharsReg == 1'b1 && (lineIndex == {s_cursorYPos,3'd7})) ||
                                 (s_smallCharsReg == 1'b0 && (lineIndex[9:1] == {s_cursorYPos[5:0],3'd7}))) ? 1'b1 : 1'b0;

  assign cursorVisible = s_isOnCursorXPos & s_isOnCursorYPos & s_cursorVisibleReg;
  
  always @(posedge clock)
    begin      
      if (s_clearScreen == 1'b1)
        begin
          s_cursorXPos      <= 7'd0;
          s_cursorYPos      <= 7'd0;
          s_screenOffsetReg <= 13'd0;
          s_clearLine       <= 1'b0;
        end
      else if (s_nextLine == 1'b1)
        begin
          s_cursorXPos      <= 7'd0;
          if (s_cursorYPos == (s_maxLines - 7'd1))
            begin
              s_screenOffsetReg <= (s_screenOffsetReg + {6'd0,s_maxCharsPerLine});
              s_clearLine       <= 1'b1;
            end
          else 
            begin
              s_cursorYPos <= s_cursorYPos+7'd1;
              s_clearLine  <= 1'b0;
            end
        end
     else if (s_weChar == 1'b1)
       begin
         if (s_cursorXPos == (s_maxCharsPerLine - 7'd1))
           begin
             s_cursorXPos <= 6'd0;
             if (s_cursorYPos == (s_maxLines - 7'd1))
               begin
                 s_screenOffsetReg <= (s_screenOffsetReg + {6'd0,s_maxCharsPerLine});
                 s_clearLine       <= 1'b1;
               end
             else
               begin
                 s_clearLine  <= 1'b0;
                 s_cursorYPos <= s_cursorYPos+7'd1;
               end
           end
         else
           begin
             s_cursorXPos <= s_cursorXPos + 7'd1;
             s_clearLine  <= 1'b0;
           end
       end
     else s_clearLine <= 1'b0;
    end
  
  /*
   *
   * Here the ram interface is defined
   *
   */
  reg [2:0] s_asciiBitIndex;
  wire [12:0] s_yposOffset = {6'd0,s_cursorYPos} * {6'd0,s_maxCharsPerLine};
  wire [12:0] s_lookupOffset1 = (s_smallCharsReg == 1'b1) ? {6'b0,lineIndex[9:3]} * {6'd0,s_maxCharsPerLine} : {7'b0,lineIndex[9:4]} * {6'd0,s_maxCharsPerLine};
  wire [12:0] s_lookupOffset2 = (s_smallCharsReg == 1'b1) ? {6'h0,pixelIndex[9:3]} - {10'd0,s_TextCorrectionReg} : {7'h0,pixelIndex[9:4]} - {10'd0,s_TextCorrectionReg};
  
  assign ramWe            = s_busy | s_weChar;
  assign ramData          = (s_busy == 1'b1) ? 8'd32 : (s_delayWeCharReg == 1'b1) ? {1'b0, s_delayedCharToBeWrittenReg} : {1'b0, ciDataB[6:0]};
  assign ramAddress       = (s_clearScreenCounterReg[13] == 1'b0) ? s_clearScreenCounterReg[12:0] :
                            (s_clearLineCounterReg[7] == 1'b0) ? s_screenOffsetReg + s_yposOffset + {6'd0,s_clearLineCounterReg[6:0]} : s_screenOffsetReg + s_yposOffset + {6'd0,s_cursorXPos};
  assign ramLookupAddress = s_screenOffsetReg + s_lookupOffset1 + s_lookupOffset2;
  
  always @(posedge pixelClock) 
    begin
      s_asciiBitIndex  <= (s_smallCharsReg == 1'b1) ? 3'd7 - pixelIndex[2:0] : 3'd7 - pixelIndex[3:1];
      asciiBitSelector <= s_asciiBitIndex;
      asciiLineIndex   <= (s_smallCharsReg == 1'b1) ? lineIndex[2:0] : lineIndex[3:1];
    end
endmodule
