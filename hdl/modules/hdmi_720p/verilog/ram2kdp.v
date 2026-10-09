module dualPortRam2k ( input wire [8:0]  address1,
                                         address2,
                       input wire        clock1,
                                         clock2,
                                         writeEnable,
                       input wire [31:0] dataIn1,
                       output reg [31:0] dataOut2);

  reg [31:0] memory [511:0];
  
  always @(posedge clock1)
  begin
    if (writeEnable) memory[address1] <= dataIn1;
  end
  
  always @(posedge clock2) dataOut2 <= memory[address2];

endmodule
