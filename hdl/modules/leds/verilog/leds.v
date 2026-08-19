module leds 
  #( parameter DataBits = 32, // must be 32 for this module
     parameter AddrBits = 32, // must be > 11 for this module
     parameter [AddrBits-1:0] BaseAddress = 32'h50000000)
   ( input  wire CLK_I,
     input  wire RST_I,
     input  wire [DataBits-1:0] DAT_I,
     output wire [DataBits-1:0] DAT_O,
     // TAGD_I and TAGD_O are not implemented
     output wire ACK_O,
     input  wire [AddrBits-1:0] ADDR_I,
     input  wire CYC_I,
     output wire ERR_O,
     // LOCK_I is not used in this module
     // RTY_I is not implemented
     input  wire [(DataBits/8)-1:0] SEL_I,
     input  wire STB_I,
     // TGA_O and TGC_O are not implemented
     input  wire WE_I,
     input  wire [2:0] CTI_I, // Registered feedback
     // BTE_I is not used in this module

     // here the external signals are defined
     input wire        oneKhzTick,
     output wire [3:0] rgbRow,
     output reg [9:0]  nRed,
     output reg [9:0]  nGreen,
     output reg [9:0]  nBlue);

  reg ackReg;
  reg errorReg;
  reg weReg;
  reg [31:0] baseAddressReg;
  reg [8:0] indexReg;
  reg [31:0] dataInReg;
  wire [31:0] s_dataOut;
  reg [2:0] s_ledsReg [127:0];
  reg [3:0] s_rowSelectReg;
  wire [2:0] s_ledsNext [127:0];
  wire [127:0] s_weRed, s_weGreen, s_weBlue;
  wire [11:0] s_selectedLine [11:0];
  wire s_pixelBased = indexReg[8];
  wire [7:0] s_pixelIndex = indexReg[7:0];
  
  wire isMyTransaction = (ADDR_I[AddrBits-1:11] == baseAddressReg[AddrBits-1:11]) ? CYC_I & STB_I : 1'b0;
  wire isCorrectTransaction = (CTI_I == 3'b000 && SEL_I == 4'b1111) ? isMyTransaction : 1'b0; // this module only supports clasic word transfers
  assign ERR_O = errorReg;
  assign ACK_O = ackReg;
  assign DAT_O = s_dataOut;

  always @(posedge CLK_I)
  begin
    ackReg         <= (RST_I == 1'b1) ? 1'b0 : ~ackReg & isCorrectTransaction;
    errorReg       <= (RST_I == 1'b1) ? 1'b0 : ~errorReg & isMyTransaction & ~isCorrectTransaction;
    weReg          <= ~ackReg & isCorrectTransaction & WE_I;
    indexReg       <= (ackReg == 1'b0 && isCorrectTransaction == 1'b1) ? ADDR_I[10:2] : indexReg;
    dataInReg      <= (ackReg == 1'b0 && isCorrectTransaction == 1'b1) ? DAT_I : dataInReg;
    baseAddressReg <= (RST_I == 1'b1) ? BaseAddress : 
                      (weReg == 1'b1 && indexReg == 9'b111111111) ? dataInReg : baseAddressReg;
  end
  
  assign s_dataOut = (indexReg == 9'b111111111) ? baseAddressReg :
                     (s_pixelBased == 1'b1) ? {29'd0,s_ledsReg[s_pixelIndex[6:0]]} : {20'd0,s_selectedLine[s_pixelIndex[5:2]]};
                     
  
  /*
   *
   * Here the led functionality is defined
   *
   */
  
  genvar n;

  generate
    for ( n = 0 ; n < 128 ; n = n + 1 )
      begin : genleds
        assign s_selectedLine[n/12][n%12] = (s_pixelIndex[1:0] == 2'd0) ? s_ledsReg[n][0] :
                                            (s_pixelIndex[1:0] == 2'd1) ? s_ledsReg[n][1] :
                                            (s_pixelIndex[1:0] == 2'd2) ? s_ledsReg[n][2] : s_ledsReg[n][0] & s_ledsReg[n][1] & s_ledsReg[n][2];
        assign s_ledsNext[n][0] = (s_pixelBased == 1'b1) ? dataInReg[0] : 
                                  (s_pixelIndex[7:6] == 2'd0) ? dataInReg[11-(n % 12)] :
                                  (s_pixelIndex[7:6] == 2'd1) ? dataInReg[11-(n % 12)] | s_ledsReg[n][0] :
                                  (s_pixelIndex[7:6] == 2'd2) ? ~dataInReg[11-(n % 12)] & s_ledsReg[n][0] : dataInReg[11-(n % 12)] ^ s_ledsReg[n][0];
        assign s_ledsNext[n][1] = (s_pixelBased == 1'b1) ? dataInReg[1] : 
                                  (s_pixelIndex[7:6] == 2'd0) ? dataInReg[11-(n % 12)] :
                                  (s_pixelIndex[7:6] == 2'd1) ? dataInReg[11-(n % 12)] | s_ledsReg[n][1] :
                                  (s_pixelIndex[7:6] == 2'd2) ? ~dataInReg[11-(n % 12)] & s_ledsReg[n][1] : dataInReg[11-(n % 12)] ^ s_ledsReg[n][1];
        assign s_ledsNext[n][2] = (s_pixelBased == 1'b1) ? dataInReg[2] : 
                                  (s_pixelIndex[7:6] == 2'd0) ? dataInReg[11-(n % 12)] :
                                  (s_pixelIndex[7:6] == 2'd1) ? dataInReg[11-(n % 12)] | s_ledsReg[n][2] :
                                  (s_pixelIndex[7:6] == 2'd2) ? ~dataInReg[11-(n % 12)] & s_ledsReg[n][2] : dataInReg[11-(n % 12)] ^ s_ledsReg[n][2];
        assign s_weRed[n]   = ((s_pixelBased == 1'b1 && s_pixelIndex[6:0] == n) ||
                               (s_pixelBased == 1'b0 && s_pixelIndex[5:2] == (n/12) && (s_pixelIndex[1:0] == 2'd2 ||s_pixelIndex[1:0] == 2'd3))) ? weReg : 1'b0;
        assign s_weGreen[n] = ((s_pixelBased == 1'b1 && s_pixelIndex[6:0] == n) ||
                               (s_pixelBased == 1'b0 && s_pixelIndex[5:2] == (n/12) && (s_pixelIndex[1:0] == 2'd1 ||s_pixelIndex[1:0] == 2'd3))) ? weReg : 1'b0;
        assign s_weBlue[n]  = ((s_pixelBased == 1'b1 && s_pixelIndex[6:0] == n) ||
                               (s_pixelBased == 1'b0 && s_pixelIndex[5:2] == (n/12) && (s_pixelIndex[1:0] == 2'd0 ||s_pixelIndex[1:0] == 2'd3))) ? weReg : 1'b0;
        always @(posedge CLK_I) 
          begin
            s_ledsReg[n][0] <= (RST_I == 1'b1) ? 1'b0 : (s_weBlue[n] == 1'b1) ? s_ledsNext[n][0] : s_ledsReg[n][0];
            s_ledsReg[n][1] <= (RST_I == 1'b1) ? 1'b0 : (s_weGreen[n] == 1'b1) ? s_ledsNext[n][1] : s_ledsReg[n][1];
            s_ledsReg[n][2] <= (RST_I == 1'b1) ? 1'b0 : (s_weRed[n] == 1'b1) ? s_ledsNext[n][2] : s_ledsReg[n][2];
          end
      end
    for ( n = 0 ; n < 10 ; n = n + 1 )
      begin : gencolors
         always @(posedge CLK_I)
           begin
             nRed[n]   <= ~s_ledsReg[n*12+s_rowSelectReg][2];
             nGreen[n] <= ~s_ledsReg[n*12+s_rowSelectReg][1];
             nBlue[n]  <= ~s_ledsReg[n*12+s_rowSelectReg][0];
           end
      end
  endgenerate
        
  always @(posedge CLK_I) s_rowSelectReg <= (RST_I == 1'b1 || (s_rowSelectReg == 4'd0 && oneKhzTick == 1'b1)) ? 4'd11 : (oneKhzTick == 1'b1) ? s_rowSelectReg - 4'd1 : s_rowSelectReg;
    
  assign rgbRow = s_rowSelectReg;

endmodule
