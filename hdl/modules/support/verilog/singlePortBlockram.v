module singlePortBlockRam #( parameter nrOfAddressBits = 4,
                             parameter nrOfDataBits = 8 )
                           ( input wire                       clock,
                             input wire                       writeEnable,
                             input wire [nrOfAddressBits-1:0] address,
                             input wire [nrOfDataBits-1:0]    dataIn,
                             output reg [nrOfDataBits-1:0]    dataOut );

  reg [nrOfDataBits-1:0] s_memory [(2**nrOfAddressBits)-1:0];
  
  always @(posedge clock)
  begin
    if (writeEnable == 1'b1) s_memory[address] <= dataIn;
    dataOut <= s_memory[address];
  end

endmodule
