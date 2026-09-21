module uartTxFifo ( input wire        clock,
                                      reset,
                                      fifoRe,
                                      fifoWe,
                    output wire       fifoEmpty,
                    output wire       fifoFull,
                    input wire [7:0]  dataIn,
                    output wire [7:0] dataOut);

  reg [3:0]  s_writeAddressReg, s_readAddressReg;
  reg        s_fifoFullReg, s_fifoEmptyReg;
  wire       s_fifoWe = (~fifoRe & fifoWe & ~s_fifoFullReg) | (fifoRe & fifoWe);
  wire       s_fifoRe = (fifoRe & ~fifoWe & ~s_fifoEmptyReg) | (fifoRe & fifoWe);
  wire [3:0] s_writeAddressNext = s_writeAddressReg + 4'd1;
  wire [3:0] s_readAddressNext = s_readAddressReg + 4'd1;
  wire       s_fifoFullNext = (reset == 1'b1 || (fifoRe == 1'b1 && fifoWe == 1'b0)) ? 1'b0 :
                              (fifoWe == 1'b1 && fifoRe == 1'b0 && s_writeAddressNext == s_readAddressReg) ? 1'b1 : s_fifoFullReg;
  wire       s_fifoEmptyNext = (reset == 1'b1 || (fifoRe == 1'b1 && fifoWe == 1'b0 && s_readAddressNext == s_writeAddressReg)) ? 1'b1 :
                               (fifoWe == 1'b1 && fifoRe == 1'b0) ? 1'b0 : s_fifoEmptyReg;
  
  assign fifoFull  = s_fifoFullReg;
  assign fifoEmpty = s_fifoEmptyReg;

  always @(posedge clock)
    begin
      s_fifoFullReg     <= s_fifoFullNext;
      s_fifoEmptyReg    <= s_fifoEmptyNext;
      s_writeAddressReg <= (reset == 1'b1) ? 4'd0 : (s_fifoWe == 1'b1) ? s_writeAddressNext : s_writeAddressReg;
      s_readAddressReg  <= (reset == 1'b1) ? 4'd0 : (s_fifoRe == 1'b1) ? s_readAddressNext : s_readAddressReg;
    end
    
  sramLutRam #(.nrOfAddressBits(4),
               .nrOfDataBits(8)) fifoMem 
              (.clock(clock),
               .writeEnable(s_fifoWe),
               .writeAddress(s_writeAddressReg),
               .readAddress(s_readAddressReg),
               .writeData(dataIn),
               .readData(dataOut) );
endmodule
