module wishboneSlave
  #( parameter DataBits = 32, // must be a multiple of 8, eg. 8, 16, 24, 32, ...
     parameter AddrBits = 32 )
   ( input  wire CLK_I,
     input  wire RST_I,
     input  wire [DataBits-1:0] DAT_I,
     output wire [DataBits-1:0] DAT_O,
     // TAGD_I and TAGD_O are not implemented
     output wire ACK_O,
     input  wire [AddrBits-1:0] ADDR_I,
     input  wire CYC_I,
     output wire ERR_O,
     input  wire LOCK_I,
     // RTY_I is not implemented
     input  wire [(DataBits/8)-1:0] SEL_I,
     input  wire STB_I,
     // TGA_O and TGC_O are not implemented
     input  wire WE_I,
     input  wire [2:0] CTI_I // Registered feedback
);
