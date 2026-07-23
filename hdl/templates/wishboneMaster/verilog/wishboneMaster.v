module wishboneMaster
  #( parameter DataBits = 32, // must be a multiple of 8, eg. 8, 16, 24, 32, ...
     parameter AddrBits = 32 )
   ( input  wire CLK_I,
     input  wire RST_I,
     input  wire [DataBits-1:0] DAT_I,
     output wire [DataBits-1:0] DAT_O,
     // TAGD_I and TAGD_O are not implemented
     input  wire ACK_I,
     output wire [AddrBits-1:0] ADDR_O,
     output wire CYC_O,
     input  wire ERR_I,
     output wire LOCK_O,
     // RTY_I is not implemented
     output wire [(DataBits/8)-1:0] SEL_O,
     output wire STB_O,
     // TGA_O and TGC_O are not implemented
     output wire WE_O,
     output wire [2:0] CTI_O // Registered feedback
);
