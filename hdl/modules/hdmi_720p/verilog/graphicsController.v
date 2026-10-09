module graphicsController 
  #( parameter DataBits = 32, // must be 32 for this module
     parameter AddrBits = 32,
     parameter [AddrBits-1:0] BaseAddress = 'h0 )
   ( input  wire CLK_I,
     input  wire RST_I,
     
     output wire [9:0]  graphicsWidth,
     output wire [9:0]  graphicsHeight,
     // here we define the interface to the pixel buffer
     input wire         newScreen,
     input wire         newLine,
     output wire        bufferWe,
     output wire [8:0]  bufferAddress,
     output wire [31:0] bufferData,
     output wire        writeIndex,
     output wire        dualPixel,
     output wire        grayscale,

     // here the bus master interface signals are defined
     input  wire [DataBits-1:0] master_DAT_I,
     output wire [DataBits-1:0] master_DAT_O,
     // TAGD_I and TAGD_O are not implemented
     input  wire master_ACK_I,
     output reg [AddrBits-1:0] master_ADDR_O,
     output wire master_CYC_O,
     input  wire master_ERR_I,
     // LOCK_O is not used
     // RTY_I is not implemented
     output wire [(DataBits/8)-1:0] master_SEL_O,
     output wire master_STB_O,
     // TGA_O and TGC_O are not implemented
     output wire master_WE_O,
     output wire [2:0] master_CTI_O, 
     output wire [1:0] master_BTE_O, // Registered feedback

     // here the bus slave interface signals are defined
     input  wire [DataBits-1:0] slave_DAT_I,
     output reg  [DataBits-1:0] slave_DAT_O,
     // TAGD_I and TAGD_O are not implemented
     output wire slave_ACK_O,
     input  wire [AddrBits-1:0] slave_ADDR_I,
     input  wire slave_CYC_I,
     output wire slave_ERR_O,
     // LOCK_I is not used
     // RTY_I is not implemented
     input  wire [(DataBits/8)-1:0] slave_SEL_I,
     input  wire slave_STB_I,
     // TGA_O and TGC_O are not implemented
     input  wire slave_WE_I,
     input  wire [2:0] slave_CTI_I // Registered feedback
     // BTE_I is not used
   );

  /*
   * This module implements a memory mapped slave that has following memory map (baseAddress+) and allows only word single accesses:
   * 0 -> The width of the graphic area (read-write) (maximum value is 640) (1<<31 gives double pixel, here maximum value 320)
   * 4 -> The height of the graphic area (read-write) (maximum value is 720) (1<<31 gives double line, here maximum value 360)
   * 8 -> The color mode: 1 for RGB565 16 bits/pixel (default), 2 for grayscale 8bits/pixel
   * C -> The start address of the frame/pixel buffer (read-write). It needs to be word-alligned
   *      (bits 1,0 need to be 0) otherwise the module is disabled. The graphic screen will be
   *      black if the modules is disabled.
   * 
   * Furthermore, it provides a DMA-master that reads the pixels from the bus if the modules is
   * enabled.
   *
   */
  reg  s_ackReg, s_errReg;
  reg[9:0]   s_graphicsWidthReg, s_graphicsHeightReg;
  reg        s_dualLineReg, s_dualPixelReg, s_grayScaleReg;
  reg [31:0] s_frameBufferAddressReg, s_selectedData, s_dataInReg;
  wire isMyTransaction = (slave_ADDR_I[AddrBits-1:4] == BaseAddress[AddrBits-1:4]) ? slave_CYC_I & slave_STB_I : 1'b0;
  wire isValidTransaction = (slave_SEL_I == 4'hf && slave_CTI_I == 3'd0) ? isMyTransaction : 1'b0;
  wire s_weWidth  = (slave_ADDR_I[3:2] == 2'd0) ? isValidTransaction & slave_WE_I & ~s_ackReg : 1'b0;
  wire s_weHeight = (slave_ADDR_I[3:2] == 2'd1) ? isValidTransaction & slave_WE_I & ~s_ackReg : 1'b0;
  wire s_weGray = (slave_ADDR_I[3:2] == 2'd2) ? isValidTransaction & slave_WE_I & ~s_ackReg : 1'b0;
  wire s_weFrame = (slave_ADDR_I[3:2] == 2'd3) ? isValidTransaction & slave_WE_I & ~s_ackReg : 1'b0;
  wire [9:0] s_graphicsWidth = (s_dataInReg[31] == 1'b1 && s_dataInReg[9:0] > 10'd320) ? 10'd640 :
                               (s_dataInReg[31] == 1'b1) ? {s_dataInReg[8:0], 1'b0} :
                               (s_dataInReg[9:0] > 10'd640) ? 10'd640 : s_dataInReg[9:0];
  wire [9:0] s_graphicsHeight = (s_dataInReg[31] == 1'b1 && s_dataInReg[9:0] > 10'd360) ? 10'd720 :
                                (s_dataInReg[31] == 1'b1) ? {s_dataInReg[8:0],1'b0} :
                                (s_dataInReg[9:0] > 10'd720) ? 10'd720 : s_dataInReg[9:0];
  
  assign graphicsWidth = s_graphicsWidthReg;
  assign graphicsHeight = s_graphicsHeightReg;
  assign dualPixel = s_dualPixelReg;
  assign grayscale = s_grayScaleReg;
  assign slave_ACK_O = s_ackReg;
  assign slave_ERR_O = s_errReg;
  
  always @*
    case (slave_ADDR_I[3:2])
      2'd0    : s_selectedData <= (s_dualPixelReg == 1'b0) ? {22'd0, s_graphicsWidthReg} : {s_dualPixelReg,22'd0, s_graphicsWidthReg[9:1]};
      2'd1    : s_selectedData <= (s_dualLineReg == 1'b0) ? {22'd0, s_graphicsHeightReg} : {s_dualLineReg,22'd0, s_graphicsHeightReg[9:1]};
      2'd2    : s_selectedData <= {30'd0,s_grayScaleReg,~s_grayScaleReg};
      default : s_selectedData <= s_frameBufferAddressReg;
    endcase
  
  always @(posedge CLK_I)
    begin
      slave_DAT_O             <= s_selectedData;
      s_dataInReg             <= slave_DAT_I;
      s_graphicsWidthReg      <= (RST_I == 1'b1) ? 10'd512 : (s_weWidth == 1'b1) ? s_graphicsWidth : s_graphicsWidthReg;
      s_graphicsHeightReg     <= (RST_I == 1'b1) ? 10'd512 : (s_weHeight == 1'b1) ? s_graphicsHeight : s_graphicsHeightReg;
      s_frameBufferAddressReg <= (RST_I == 1'b1) ? 32'd1 : (s_weFrame == 1'b1) ? s_dataInReg : s_frameBufferAddressReg;
      s_dualLineReg           <= (RST_I == 1'b1) ? 1'b0 : (s_weHeight == 1'b1) ? s_dataInReg[31] : s_dualLineReg;
      s_dualPixelReg          <= (RST_I == 1'b1) ? 1'b0 : (s_weWidth == 1'b1) ? s_dataInReg[31] : s_dualPixelReg;
      s_grayScaleReg          <= (RST_I == 1'b1) ? 1'b0 : (s_weGray == 1'b1) ? s_dataInReg[1] : s_grayScaleReg;
      s_ackReg                <= (isMyTransaction == 1'b1 && s_ackReg == 1'b0) ? isValidTransaction : 1'b0;
      s_errReg                <= (isMyTransaction == 1'b1 && s_errReg == 1'b0) ? ~isValidTransaction : 1'b0;
    end
  
  /* here the bus-master DMA-controller is defined */
  localparam IDLE = 3'd0;
  localparam DO_READ = 3'd1;
  localparam READ_DONE = 3'd2;
  localparam ERROR = 3'd3;
  localparam INIT_WRITE_BLACK = 3'd4;
  localparam WRITE_BLACK = 3'd5;
  
  reg[2:0] s_dmaStateReg, s_dmaStateNext;
  reg s_skipLineReg;
  reg [9:0] s_writeAddressReg;
  reg s_writeBufferIndexReg;
  wire s_requestData = newScreen | (newLine & ~s_dualLineReg) | (newLine & s_dualLineReg & ~s_skipLineReg);
  /* the number of pixels per line are:
     s_dualPixelReg:  s_grayScaleReg:  NrOfPixels:          NrOfWords (32-bit):
            0               0          s_graphicsWidthReg   s_graphicsWidthReg >> 1
            0               1          s_graphicsWidthReg   s_graphicsWidthReg >> 2
            1               0          s_graphicsWidthReg   s_graphicsWidthReg >> 2
            1               1          s_graphicsWidthReg   s_graphicsWidthReg >> 3
  */
  wire [1:0] s_burstSizeSel = {s_dualLineReg,s_grayScaleReg};
  reg [8:0] s_nrOfWordsToFetch;
  
  assign writeIndex = s_writeBufferIndexReg;
  assign bufferAddress = s_writeAddressReg[8:0];
  assign bufferData = (s_dmaStateReg == WRITE_BLACK) ? 32'd0 : master_DAT_I;
  assign bufferWe = (s_dmaStateReg == WRITE_BLACK || (s_dmaStateReg == DO_READ && master_ACK_I == 1'b1)) ? 1'b1 : 1'b0;
  assign master_CYC_O = (s_dmaStateReg == DO_READ) ? 1'b1 : 1'b0;
  assign master_STB_O = (s_dmaStateReg == DO_READ) ? 1'b1 : 1'b0;
  assign master_DAT_O = 32'd0;
  assign master_SEL_O = 4'hF;
  assign master_WE_O = 1'b0;
  assign master_CTI_O = (s_dmaStateReg == DO_READ && s_writeAddressReg[8:0] == s_nrOfWordsToFetch) ? 3'b111 : 3'b001;
  assign master_BTE_O = 2'd0;
  
  always @*
    case (s_burstSizeSel)
      2'b00   : s_nrOfWordsToFetch <= {1'b0,s_graphicsWidthReg[9:1]} - 9'd1;
      2'b11   : s_nrOfWordsToFetch <= {3'b0,s_graphicsWidthReg[9:3]} - 9'd1;
      default : s_nrOfWordsToFetch <= {2'd0,s_graphicsWidthReg[9:2]} - 9'd1;
    endcase
  
  always @*
    case (s_dmaStateReg)
      IDLE             : s_dmaStateNext <= (s_requestData == 1'b1 && s_frameBufferAddressReg[1:0] == 2'd0) ? DO_READ :
                                           (s_requestData == 1'b1) ? INIT_WRITE_BLACK : IDLE;
      DO_READ          : s_dmaStateNext <= ((s_writeAddressReg[8:0] == s_nrOfWordsToFetch && master_ACK_I == 1'b1) || master_ERR_I == 1'b1) ? READ_DONE : DO_READ;
      INIT_WRITE_BLACK : s_dmaStateNext <= WRITE_BLACK;
      WRITE_BLACK      : s_dmaStateNext <= (s_writeAddressReg[9] == 1'b1) ? IDLE : WRITE_BLACK;
      default          : s_dmaStateNext <= IDLE;
    endcase

  always @(posedge CLK_I)
    begin
      s_skipLineReg         <= (RST_I == 1'b1 || newScreen == 1'b1) ? 1'd0 : s_skipLineReg ^ newLine;
      s_writeBufferIndexReg <= (RST_I == 1'b1) ? 1'b0 : (s_dmaStateReg == READ_DONE || (s_dmaStateReg == WRITE_BLACK && s_writeAddressReg[9] == 1'b1)) ? ~s_writeBufferIndexReg : s_writeBufferIndexReg;
      s_dmaStateReg         <= (RST_I == 1'b1) ? IDLE : s_dmaStateNext;
      s_writeAddressReg     <= (s_dmaStateReg == IDLE) ? 10'd0 : (s_dmaStateReg == WRITE_BLACK || (s_dmaStateReg == DO_READ && master_ACK_I == 1'b1)) ? s_writeAddressReg + 10'd1 : s_writeAddressReg;
      master_ADDR_O         <= (RST_I == 1'b1 || newScreen == 1'b1) ? s_frameBufferAddressReg[AddrBits-1:0] : 
                               (s_dmaStateReg == DO_READ && master_ACK_I == 1'b1) ? master_ADDR_O + {{AddrBits-3{1'b0}},3'b100} : master_ADDR_O;
    end
endmodule
