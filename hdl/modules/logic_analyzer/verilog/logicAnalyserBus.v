module logicAnalyserBus
  #( parameter DataBits = 32, // must be 32 for this module
     parameter AddrBits = 32, // must be bigger than 13 for this module
     parameter [AddrBits-1:0] BaseAddress )
   ( input wire [63:0] tappedWires,
     
     // here the wishbone bus signals are defined
     input  wire CLK_I,
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
     input  wire [2:0] CTI_I // Registered feedback
     // BTE_I is not used in this module
     );

  reg         lacReset;
  wire        lacDone;
  wire [8:0]  lacStartAddress;
  wire [31:0] lacDataLow;
  wire [31:0] lacDataHigh;
  
  // configuration
  reg [2:0]  comparator0;
  reg [2:0]  comparator1;
  reg [2:0]  comparator2;
  reg [2:0]  comparator3;
  reg [63:0] mask0;
  reg [63:0] mask1;
  reg [63:0] mask2;
  reg [63:0] mask3;
  reg [63:0] reference0;
  reg [63:0] reference1;
  reg [63:0] reference2;
  reg [63:0] reference3;
  reg [1:0]  seqLen; // actual length is seqLen + 1
  reg [8:0]  postTrigSamples;

  // read-only addresses (ADDR_I [12:11])
  localparam LOW_BASE          = 2'd0;
  localparam HIGH_BASE         = 2'd1;
  localparam DONE              = 2'd2;
  localparam START_ADDRESS     = 2'd3;

  // write-only address (ADDR_I [6:2])
  localparam SEQ_LEN           = 5'h04;
  localparam POST_TRIG_SAMPLES = 5'h05;

  localparam MASK_0_LO         = 5'h10;
  localparam MASK_0_HI         = 5'h11;
  localparam MASK_1_LO         = 5'h12;
  localparam MASK_1_HI         = 5'h13;
  localparam MASK_2_LO         = 5'h14;
  localparam MASK_2_HI         = 5'h15;
  localparam MASK_3_LO         = 5'h16;
  localparam MASK_3_HI         = 5'h17;

  localparam REFERENCE_0_LO    = 5'h18;
  localparam REFERENCE_0_HI    = 5'h19;
  localparam REFERENCE_1_LO    = 5'h1a;
  localparam REFERENCE_1_HI    = 5'h1b;
  localparam REFERENCE_2_LO    = 5'h1c;
  localparam REFERENCE_2_HI    = 5'h1d;
  localparam REFERENCE_3_LO    = 5'h1e;
  localparam REFERENCE_3_HI    = 5'h1f;

  localparam COMPARATOR_0      = 5'h06;
  localparam COMPARATOR_1      = 5'h07;
  localparam COMPARATOR_2      = 5'h08;
  localparam COMPARATOR_3      = 5'h09;

  localparam RESET             = 5'h0f;

  wire isMyTransaction = (ADDR_I[AddrBits-1:13] == BaseAddress[AddrBits-1:13]) ? CYC_I & STB_I : 1'b0;
  wire lacReadAddress = ADDR_I[10:2];
  reg [10:0] addrReg;
  reg [DataBits-1:0] dataReg;
  reg isWriteTransaction;
  reg isError;
  reg genAck;
  reg [DataBits-1:0] s_readData;
  
  wire isCorrectTransaction = (CTI_I == 3'b000 && SEL_I == 4'b1111) ? isMyTransaction : 1'b0; // this module only supports clasic word transfers
  assign ERR_O = isError;
  assign ACK_O = genAck;
  
  // here we define the bus input regs
  always @(posedge CLK_I)
    begin
      addrReg <= (isCorrectTransaction == 1'b1) ? ADDR_I[12:2] : addrReg;
      dataReg <= (isCorrectTransaction == 1'b1) ? DAT_I : dataReg;
      isWriteTransaction <= isCorrectTransaction & WE_I & ~genAck;
      genAck  <= (RST_I == 1'b1) ? 1'b0 : ~genAck & isCorrectTransaction;
      isError <= (RST_I == 1'b1) ? 1'b0 : ~isError & isMyTransaction & ~isCorrectTransaction;
    end
  
  // here we define the read data
  assign DAT_O <= s_readData;
  always @*
    case (addrReg[10:9])
      LOW_BASE  : s_readData <= lacDataLow;
      HIGH_BASE : s_readData <= lacDataHigh;
      DONE      : s_readData <= { {DataBits-1{1'b0}}, lacDone };
      default   : s_readData <= { {DataBits-9{1'b0}}, lacStartAddress };
    endcase

  // here we define the write action
  always @(posedge(CLK_I))
    if (RST_I == 1'b1)
      begin
        lacReset        <= 1'b0;
        comparator0     <= 3'd0;
        comparator1     <= 3'd0;
        comparator2     <= 3'd0;
        comparator3     <= 3'd0;
        mask0           <= 64'd0;
        mask1           <= 64'd0;
        mask2           <= 64'd0;
        mask3           <= 64'd0;
        reference0      <= 64'd0;
        reference1      <= 64'd0;
        reference2      <= 64'd0;
        reference3      <= 64'd0;
        seqLen          <= 2'd0;
        postTrigSamples <= 9'd0;
      end
    else 
      begin
        lacReset <= 1'b0;
        if (isWriteTransaction == 1'b1)
          case (addrReg[4:0])
            RESET             : lacReset <= 1'b1;
            COMPARATOR_0      : comparator0 <= dataReg[2:0];
            COMPARATOR_1      : comparator1 <= dataReg[2:0];
            COMPARATOR_2      : comparator2 <= dataReg[2:0];
            COMPARATOR_3      : comparator3 <= dataReg[2:0];
            MASK_0_LO         : mask0[31:0] <= dataReg;
            MASK_0_HI         : mask0[63:32] <= dataReg;
            MASK_1_LO         : mask1[31:0] <= dataReg;
            MASK_1_HI         : mask1[63:32] <= dataReg;
            MASK_2_LO         : mask2[31:0] <= dataReg;
            MASK_2_HI         : mask2[63:32] <= dataReg;
            MASK_3_LO         : mask3[31:0] <= dataReg;
            MASK_3_HI         : mask3[63:32] <= dataReg;
            REFERENCE_0_LO    : reference0[31:0] <= dataReg;
            REFERENCE_0_HI    : reference0[63:32] <= dataReg;
            REFERENCE_1_LO    : reference1[31:0] <= dataReg;
            REFERENCE_1_HI    : reference1[63:32] <= dataReg;
            REFERENCE_2_LO    : reference2[31:0] <= dataReg;
            REFERENCE_2_HI    : reference2[63:32] <= dataReg;
            REFERENCE_3_LO    : reference3[31:0] <= dataReg;
            REFERENCE_3_HI    : reference3[63:32] <= dataReg;
            SEQ_LEN           : seqLen <= dataReg[1:0];
            POST_TRIG_SAMPLES : postTrigSamples <= dataReg[8:0];
          endcase
      end

endmodule
