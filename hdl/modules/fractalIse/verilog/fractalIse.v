module fractalIse 
  #( parameter [6:0] FRACTAL_CI = 7'h20,
     parameter [6:0] NMAX_CI = 7'h21,
     parameter W_DATA = 32)
   ( input  wire clock,
     input  wire reset, // active high
     input  wire [6:0]        ci_id,
     input  wire              ci_start,
     input  wire [W_DATA-1:0] ci_dataa,
     input  wire [W_DATA-1:0] ci_datab,
     output wire              ci_done,
     output wire [W_DATA-1:0] ci_result);

  /* This module implements a fractal calculation accellerator.
   * it reacts on two ci_id's, namely:
   * FRACTAL_CI : do a fractal calculation
   * NMAX_CI    : write the maximal of iterations taken.
   * Important: W_DATA must be bigger or equal to 32!
   */

  localparam [1:0] IDLE     = 2'd0;
  localparam [1:0] CALCMULT = 2'd1;
  localparam [1:0] DOADD    = 2'd2;
  localparam [1:0] DONE     = 2'd3;

  reg [1:0] s_stateReg, s_state1Reg;

  /*
   *
   * Here we define some control signals
   *
   */
  reg [15:0] s_nMaxReg;
  reg [1:0]  s_colorModelReg;
  reg [31:0] s_deltaReg;
  reg signed [31:0] s_cxReg, s_cyReg, s_cx1Reg;
  wire s_isMyNmax   = (ci_id == NMAX_CI) ? ci_start : 1'b0;
  wire s_startFract = (ci_id == FRACTAL_CI) ? ci_start : 1'b0;
  wire s_fractDone  = (s_stateReg == DONE && s_state1Reg == DONE) ? 1'b1 : 1'b0;
  
  assign ci_done = s_isMyNmax | s_fractDone;
  
  always @(posedge clock)
    begin
      s_nMaxReg       <= (s_isMyNmax == 1'b1) ? ci_dataa[15:0] : s_nMaxReg;
      s_colorModelReg <= (s_isMyNmax == 1'b1) ? ci_dataa[17:16] : s_colorModelReg;
      s_deltaReg      <= (s_isMyNmax == 1'b1) ? ci_datab[31:0] : s_deltaReg;
      s_cxReg         <= (s_startFract == 1'b1) ? ci_dataa[31:0] : s_cxReg;
      s_cx1Reg        <= (s_startFract == 1'b1) ? ci_dataa[31:0] + s_deltaReg : s_cx1Reg;
      s_cyReg         <= (s_startFract == 1'b1) ? ci_datab[31:0] : s_cyReg;
    end

  /*
   *
   * Here the fractal calculation is done
   *
   */
  reg signed [31:0] s_xReg, s_yReg, s_xxReg, s_yyReg, s_xxhReg, s_yyhReg, s_2xyReg;
  reg signed [31:0] s_x1Reg, s_y1Reg, s_xx1Reg, s_yy1Reg, s_xxh1Reg, s_yyh1Reg, s_2xy1Reg;
  reg [15:0] s_nReg, s_n1Reg;
  wire signed [31:0] s_newX = s_xxReg - s_yyReg + s_cxReg;
  wire signed [31:0] s_newY = s_2xyReg + s_cyReg;
  wire signed [31:0] s_xNext = (s_startFract == 1'b1) ? ci_dataa[31:0] : (s_stateReg == DOADD) ? s_newX : s_xReg;
  wire signed [31:0] s_yNext = (s_startFract == 1'b1) ? ci_datab[31:0] : (s_stateReg == DOADD) ? s_newY : s_yReg;
  wire signed [63:0] s_multXX = s_xReg*s_xReg;
  wire signed [63:0] s_multYY = s_yReg*s_yReg;
  wire signed [63:0] s_multXY = s_xReg*s_yReg;
  wire signed [31:0] s_xxNext = (s_stateReg == CALCMULT) ? s_multXX[59:28] : s_xxReg;
  wire signed [31:0] s_yyNext = (s_stateReg == CALCMULT) ? s_multYY[59:28] : s_yyReg;
  wire signed [31:0] s_xxHiNext = (s_stateReg == CALCMULT) ? s_multXX[63:32] : s_xxhReg;
  wire signed [31:0] s_yyHiNext = (s_stateReg == CALCMULT) ? s_multYY[63:32] : s_yyhReg;
  wire signed [31:0] s_2xyNext = (s_stateReg == CALCMULT) ? s_multXY[58:27] : s_2xyReg;
  wire [15:0] s_nNext = (s_startFract == 1'b1) ? 16'd0 : (s_stateReg == CALCMULT) ? s_nReg + 16'd1 : s_nReg;
  wire [31:0] s_xxPlusYy = s_xxhReg + s_yyhReg;
  wire s_abort1 = (s_xxPlusYy[31:24] > 8'd4) ? 1'b1 : 1'b0;
  wire s_abort2 = (s_nMaxReg == s_nReg) ? 1'b1 : 1'b0;
  wire signed [31:0] s_newX1 = s_xx1Reg - s_yy1Reg + s_cx1Reg;
  wire signed [31:0] s_newY1 = s_2xy1Reg + s_cyReg;
  wire signed [31:0] s_x1Next = (s_startFract == 1'b1) ? ci_dataa[31:0]+s_deltaReg : (s_state1Reg == DOADD) ? s_newX1 : s_x1Reg;
  wire signed [31:0] s_y1Next = (s_startFract == 1'b1) ? ci_datab[31:0] : (s_state1Reg == DOADD) ? s_newY1 : s_y1Reg;
  wire signed [63:0] s_multXX1 = s_x1Reg*s_x1Reg;
  wire signed [63:0] s_multYY1 = s_y1Reg*s_y1Reg;
  wire signed [63:0] s_multXY1 = s_x1Reg*s_y1Reg;
  wire signed [31:0] s_xx1Next = (s_state1Reg == CALCMULT) ? s_multXX1[59:28] : s_xx1Reg;
  wire signed [31:0] s_yy1Next = (s_state1Reg == CALCMULT) ? s_multYY1[59:28] : s_yy1Reg;
  wire signed [31:0] s_xxHi1Next = (s_state1Reg == CALCMULT) ? s_multXX1[63:32] : s_xxh1Reg;
  wire signed [31:0] s_yyHi1Next = (s_state1Reg == CALCMULT) ? s_multYY1[63:32] : s_yyh1Reg;
  wire signed [31:0] s_2xy1Next = (s_state1Reg == CALCMULT) ? s_multXY1[58:27] : s_2xy1Reg;
  wire [15:0] s_n1Next = (s_startFract == 1'b1) ? 16'd0 : (s_state1Reg == CALCMULT) ? s_n1Reg + 16'd1 : s_n1Reg;
  wire [31:0] s_xxPlusYy1 = s_xxh1Reg + s_yyh1Reg;
  wire s_abort3 = (s_xxPlusYy1[31:24] > 8'd4) ? 1'b1 : 1'b0;
  wire s_abort4 = (s_nMaxReg == s_n1Reg) ? 1'b1 : 1'b0;
  
  always @(posedge clock)
    begin
      s_xReg     <= s_xNext;
      s_yReg     <= s_yNext;
      s_xxReg    <= s_xxNext;
      s_yyReg    <= s_yyNext;
      s_xxhReg   <= s_xxHiNext;
      s_yyhReg   <= s_yyHiNext;
      s_2xyReg   <= s_2xyNext;
      s_nReg     <= s_nNext;
      s_x1Reg    <= s_x1Next;
      s_y1Reg    <= s_y1Next;
      s_xx1Reg   <= s_xx1Next;
      s_yy1Reg   <= s_yy1Next;
      s_xxh1Reg  <= s_xxHi1Next;
      s_yyh1Reg  <= s_yyHi1Next;
      s_2xy1Reg  <= s_2xy1Next;
      s_n1Reg    <= s_n1Next;
    end
  
  /*
   *
   * Here the state machines are defined
   *
   */
  reg [1:0] s_stateNext, s_state1Next;
  
  always @*
    case (s_stateReg)
      IDLE     : s_stateNext <= (s_startFract == 1'b1) ? CALCMULT : IDLE;
      CALCMULT : s_stateNext <= DOADD;
      DOADD    : s_stateNext <= (s_abort1 == 1'b1 || s_abort2 == 1'b1) ? DONE : CALCMULT;
      DONE     : s_stateNext <= (s_fractDone == 1'b1) ? IDLE : DONE;
      default  : s_stateNext <= IDLE;
    endcase

  always @*
    case (s_state1Reg)
      IDLE     : s_state1Next <= (s_startFract == 1'b1) ? CALCMULT : IDLE;
      CALCMULT : s_state1Next <= DOADD;
      DOADD    : s_state1Next <= (s_abort3 == 1'b1 || s_abort4 == 1'b1) ? DONE : CALCMULT;
      DONE     : s_state1Next <= (s_fractDone == 1'b1) ? IDLE : DONE;
      default  : s_state1Next <= IDLE;
    endcase

  always @(posedge clock)
    begin
      s_stateReg  <= (reset == 1'b1) ? IDLE : s_stateNext;
      s_state1Reg <= (reset == 1'b1) ? IDLE : s_state1Next;
    end
  /*
   *
   * Here the colors are defined
   *
   */
  reg [15:0] s_selectedColor, s_selectedColor4;
  
  wire [15:0] s_blackAndWhite  = (s_nReg == s_nMaxReg) ? 16'd0 : 16'hFFFF;
  wire [15:0] s_GrayScale      = (s_nReg == s_nMaxReg) ? 16'd0 : {s_nReg[3:0], 1'b0, s_nReg[3:0], 2'b00, s_nReg[3:0], 1'b0};
  wire [4:0]  s_selected1      = {s_nReg[0],4'hF};
  wire [4:0]  s_selected2      = {~s_nReg[6:3],1'b0};
  wire [4:0]  s_red1           = (s_nReg[3] == 1'b1) ? s_selected1 : 5'd0;
  wire [5:0]  s_green1         = (s_nReg[2] == 1'b1) ? {s_selected1,1'b0} : 6'd0;
  wire [4:0]  s_blue1          = (s_nReg[1] == 1'b1) ? s_selected1 : 5'd0;
  wire [4:0]  s_red2           = (s_nReg[2] == 1'b1) ? s_selected2 : 5'd0;
  wire [5:0]  s_green2         = (s_nReg[1] == 1'b1) ? {s_selected2,1'b0} : 6'd0;
  wire [4:0]  s_blue2          = (s_nReg[0] == 1'b1) ? s_selected2 : 5'd0;
  wire [15:0] s_color1         = (s_nReg == s_nMaxReg) ? 16'd0 : {s_red1,s_green1,s_blue1};
  wire [15:0] s_color2         = (s_nReg == s_nMaxReg) ? 16'd0 : {s_red2,s_green2,s_blue2};

  wire [15:0] s_blackAndWhite1 = (s_n1Reg == s_nMaxReg) ? 16'd0 : 16'hFFFF;
  wire [15:0] s_GrayScale1     = (s_n1Reg == s_nMaxReg) ? 16'd0 : {s_n1Reg[3:0], 1'b0, s_n1Reg[3:0], 2'b00, s_n1Reg[3:0], 1'b0};
  wire [4:0]  s_selected3      = {s_n1Reg[0],4'hF};
  wire [4:0]  s_selected4      = {~s_n1Reg[6:3],1'b0};
  wire [4:0]  s_red3           = (s_n1Reg[3] == 1'b1) ? s_selected3 : 5'd0;
  wire [5:0]  s_green3         = (s_n1Reg[2] == 1'b1) ? {s_selected3,1'b0} : 6'd0;
  wire [4:0]  s_blue3          = (s_n1Reg[1] == 1'b1) ? s_selected3 : 5'd0;
  wire [4:0]  s_red4           = (s_n1Reg[2] == 1'b1) ? s_selected3 : 5'd0;
  wire [5:0]  s_green4         = (s_n1Reg[1] == 1'b1) ? {s_selected4,1'b0} : 6'd0;
  wire [4:0]  s_blue4          = (s_n1Reg[0] == 1'b1) ? s_selected4 : 5'd0;
  wire [15:0] s_color3         = (s_n1Reg == s_nMaxReg) ? 16'd0 : {s_red3,s_green3,s_blue3};
  wire [15:0] s_color4         = (s_n1Reg == s_nMaxReg) ? 16'd0 : {s_red4,s_green4,s_blue4};

  always @*
    case (s_colorModelReg)
      2'b00   : begin
                  s_selectedColor  <= s_blackAndWhite;
                  s_selectedColor4 <= s_blackAndWhite1;
                end
      2'b01   : begin
                  s_selectedColor  <= s_GrayScale;
                  s_selectedColor4 <= s_GrayScale1;
                end
      2'b10   : begin
                  s_selectedColor  <= s_color1;
                  s_selectedColor4 <= s_color3;
                end
      default : begin
                  s_selectedColor  <= s_color2;
                  s_selectedColor4 <= s_color4;
                end
    endcase
    
  /*
   *
   * finally we put the result
   *
   */
  assign ci_result = (s_fractDone == 1'b0) ? 32'd0 : {s_selectedColor[15:0], s_selectedColor4[15:0]};
endmodule
