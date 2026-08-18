module ssramPseudoDual 
  #( parameter BITWIDTH   = 32,
     parameter NR_ENTRIES = 512 )
   ( input wire                          clock,
     input wire                          writeEnable,
     input wire [$clog2(NR_ENTRIES)-1:0] writeAddress,
     input wire [BITWIDTH-1:0]           writeData,
     input wire [$clog2(NR_ENTRIES)-1:0] readAddress,
     output reg [BITWIDTH-1:0]           readData);

  reg [BITWIDTH-1:0] memory [NR_ENTRIES-1:0];

  always @(posedge clock)
    begin
      if (writeEnable == 1'b1) memory[writeAddress] <= writeData;
      readData <= memory[readAddress];
    end

endmodule
