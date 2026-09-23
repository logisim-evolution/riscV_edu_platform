module sramSlave
  #( parameter DataBits = 32, // must be 32 for this module
     parameter AddrBits = 32,
     parameter [AddrBits-1:0] BaseAddress = 0,
     parameter nrOfEntriesInBytes = 64*1024 ) // must be a 2^m value
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
     input  wire [1:0] BTE_I);

  localparam nrOfBusAddressBits = $clog2(nrOfEntriesInBytes);
  localparam IDLE   = 2'b00;
  localparam ERROR  = 2'b01;
  localparam SINGLE = 2'b10;
  localparam BURST  = 2'b11;

  wire s_nClock = ~CLK_I;
  wire s_isMyTransaction = (ADDR_I[AddrBits-1:nrOfBusAddressBits] == BaseAddress[AddrBits-1:nrOfBusAddressBits]) ? CYC_I & STB_I : 1'b0;
  wire s_isCorrectTransaction = (CTI_I == 3'b000 || CTI_I == 3'b111 || ((CTI_I == 3'b001 | CTI_I == 3'b010) && BTE_I == 2'd00)) ? s_isMyTransaction : 1'b0;
  reg [1:0] s_stateReg, s_stateNext;
  wire [3:0] s_byteWe = (WE_I == 1'b1 && STB_I == 1'b1 && s_isCorrectTransaction == 1'b1) ? SEL_I : 4'd0;;
  wire [nrOfBusAddressBits-3:0] s_ramAddress = ADDR_I[nrOfBusAddressBits-1:2];
  
  assign ERR_O = (s_stateReg == ERROR) ? STB_I & CYC_I : 1'b0;
  assign ACK_O = ((s_stateReg == BURST && s_isCorrectTransaction == 1'b1) || s_stateReg == SINGLE) ? STB_I & CYC_I : 1'b0;
  
  // here the state machine is defined
  always @*
    case (s_stateReg)
      IDLE    : s_stateNext <= (s_isMyTransaction == 1'b1 && s_isCorrectTransaction == 1'b0) ? ERROR :
                               (s_isCorrectTransaction == 1'b1 && CTI_I == 3'b000) ? SINGLE :
                               (s_isCorrectTransaction == 1'b1) ? BURST : IDLE;
      BURST   : s_stateNext <= (s_isCorrectTransaction == 1'b0 && CYC_I == 1'b1 && STB_I == 1'b1) ? ERROR :
                               (CTI_I == 3'b111 || CYC_I ==1'b0) ? IDLE : BURST;
      default : s_stateNext <= IDLE;
    endcase
  
  always @(posedge CLK_I)
    s_stateReg <= (RST_I == 1'b1) ? IDLE : s_stateNext;
  
  // here the memories are defined
  
  singlePortBlockRam #(.nrOfAddressBits(nrOfBusAddressBits-2),
                       .nrOfDataBits(8)) byte0
                      (.clock(s_nClock),
                       .writeEnable(s_byteWe[0]),
                       .address(s_ramAddress),
                       .dataIn(DAT_I[7:0]),
                       .dataOut(DAT_O[7:0]) );

  singlePortBlockRam #(.nrOfAddressBits(nrOfBusAddressBits-2),
                       .nrOfDataBits(8)) byte1
                      (.clock(s_nClock),
                       .writeEnable(s_byteWe[1]),
                       .address(s_ramAddress),
                       .dataIn(DAT_I[15:8]),
                       .dataOut(DAT_O[15:8]) );

  singlePortBlockRam #(.nrOfAddressBits(nrOfBusAddressBits-2),
                       .nrOfDataBits(8)) byte2
                      (.clock(s_nClock),
                       .writeEnable(s_byteWe[2]),
                       .address(s_ramAddress),
                       .dataIn(DAT_I[23:16]),
                       .dataOut(DAT_O[23:16]) );

  singlePortBlockRam #(.nrOfAddressBits(nrOfBusAddressBits-2),
                       .nrOfDataBits(8)) byte3
                      (.clock(s_nClock),
                       .writeEnable(s_byteWe[3]),
                       .address(s_ramAddress),
                       .dataIn(DAT_I[31:24]),
                       .dataOut(DAT_O[31:24]) );

endmodule
