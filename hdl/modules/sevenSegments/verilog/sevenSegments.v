module sevenSegments
  #( parameter DataBits = 32, // must be 32 for this module
     parameter AddrBits = 32, // must be > 5 for this module
     parameter [AddrBits-1:0] BaseAddress )
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
     output wire [2:0] displaySelect,
     output wire [7:0] nSegments);

  reg ackReg;
  reg errorReg;
  reg weReg;
  reg [31:0] baseAddressReg;
  reg [31:0] dataInReg;
  reg [31:0] s_dataOut;
  reg [2:0] indexReg;
  reg [7:0]  s_displ1Reg, s_displ2Reg, s_displ3Reg, s_displ4Reg;
  wire [7:0] s_displ1Next, s_displ2Next, s_displ3Next, s_displ4Next;
  reg [2:0] s_scanReg;
  reg [7:0] s_selectedSegment;

  wire isMyTransaction = (ADDR_I[AddrBits-1:5] == baseAddressReg[AddrBits-1:5]) ? CYC_I & STB_I : 1'b0;
  wire isCorrectTransaction = (CTI_I == 3'b000 && SEL_I == 4'b1111) ? isMyTransaction : 1'b0; // this module only supports clasic word transfers
  assign ERR_O = errorReg;
  assign ACK_O = ackReg;
  assign DAT_O = s_dataOut;
  assign displaySelect = s_scanReg;
  assign nSegments = ~s_selectedSegment;

  always @(posedge CLK_I)
  begin
    ackReg         <= (RST_I == 1'b1) ? 1'b0 : ~ackReg & isCorrectTransaction;
    errorReg       <= (RST_I == 1'b1) ? 1'b0 : ~errorReg & isMyTransaction & ~isCorrectTransaction;
    weReg          <= ~ackReg & isCorrectTransaction & WE_I;
    indexReg       <= (RST_I == 1'b1) ? 3'd0 : (ackReg == 1'b0 && isCorrectTransaction == 1'b1) ? ADDR_I[4:2] : indexReg;
    dataInReg      <= (ackReg == 1'b0 && isCorrectTransaction == 1'b1) ? DAT_I : dataInReg;
    baseAddressReg <= (RST_I == 1'b1) ? BaseAddress : 
                      (weReg == 1'b1 && indexReg == 3'b111) ? dataInReg : baseAddressReg;
  end
  
  always @*
    case (indexReg)
      3'd7    : s_dataOut <= baseAddressReg;
      3'd0,
      3'd4    : s_dataOut <= {24'd0, s_displ1Reg};
      3'd1,
      3'd5    : s_dataOut <= {24'd0, s_displ2Reg};
      3'd2,
      3'd6    : s_dataOut <= {24'd0, s_displ3Reg};
      default : s_dataOut <= {24'd0, s_displ4Reg};
    endcase

  // here we define the registers for the 4 seven segments
  sevenSegmentUpdate #( .segmentId(0) ) seg1
                      ( .currentValue(s_displ1Reg),
                        .dataIn(s_dataInReg),
                        .functionSelect(indexReg),
                        .newValue(s_displ1Next) );
  
  sevenSegmentUpdate #( .segmentId(1) ) seg2
                      ( .currentValue(s_displ2Reg),
                        .dataIn(s_dataInReg),
                        .functionSelect(indexReg),
                        .newValue(s_displ2Next) );
  
  sevenSegmentUpdate #( .segmentId(2) ) seg3
                      ( .currentValue(s_displ3Reg),
                        .dataIn(s_dataInReg),
                        .functionSelect(indexReg),
                        .newValue(s_displ3Next) );
  
  sevenSegmentUpdate #( .segmentId(3) ) seg4
                      ( .currentValue(s_displ4Reg),
                        .dataIn(s_dataInReg),
                        .functionSelect(indexReg),
                        .newValue(s_displ4Next) );

  always @(posedge CLK_I)
    begin
      s_displ1Reg <= (RST_I == 1'b1) ? 8'd0 : (weReg == 1'b1) ? s_displ1Next : s_displ1Reg;
      s_displ2Reg <= (RST_I == 1'b1) ? 8'd0 : (weReg == 1'b1) ? s_displ2Next : s_displ2Reg;
      s_displ3Reg <= (RST_I == 1'b1) ? 8'd0 : (weReg == 1'b1) ? s_displ3Next : s_displ3Reg;
      s_displ4Reg <= (RST_I == 1'b1) ? 8'd0 : (weReg == 1'b1) ? s_displ4Next : s_displ4Reg;
    end

  always @(posedge CLK_I) s_scanReg <= (RST_I == 1'b1 || (s_scanReg == 3'd0 && oneKhzTick == 1'b1)) ? 3'd4 : (oneKhzTick == 1'b1) ? s_scanReg - 3'd1 : s_scanReg;
 
  always @*
    case (s_scanReg)
      3'd0    : s_selectedSegment <= s_displ4Reg;
      3'd1    : s_selectedSegment <= s_displ3Reg;
      3'd2    : s_selectedSegment <= s_displ2Reg;
      3'd3    : s_selectedSegment <= s_displ1Reg;
      default : s_selectedSegment <= 8'd0;
    endcase

endmodule
