module uartRxFifo ( input wire        clock,
                                      reset,
                                      fifoRe,
                                      fifoWe,
                                      clearError,
                                      frameErrorIn,
                                      parityErrorIn,
                                      breakIn,
                    output wire       fifoEmpty,
                    output wire       fifoFull,
                    input wire [7:0]  dataIn,
                    output wire       frameErrorOut,
                                      parityErrorOut,
                                      breakOut,
                    output reg        fifoError,
                    output wire [4:0] nrOfEntries,
                    output wire [7:0] dataOut);

  reg [3:0]   s_writeAddressReg, s_readAddressReg;
  reg         s_fifoFullReg, s_fifoEmptyReg;
  reg [15:0]  s_frameErrorReg, s_parityErrorReg, s_breakReg;
  wire [15:0] s_frameErrorNext, s_parityErrorNext, s_breakNext, s_clearError, s_writeError;
  reg [4:0]   s_nrOfEntriesReg;
  wire        s_fifoWe = (~fifoRe & fifoWe & ~s_fifoFullReg) | (fifoRe & fifoWe);
  wire        s_fifoRe = (fifoRe & ~fifoWe & ~s_fifoEmptyReg) | (fifoRe & fifoWe);
  wire [3:0]  s_writeAddressNext = s_writeAddressReg + 4'd1;
  wire [3:0]  s_readAddressNext = s_readAddressReg + 4'd1;
  wire        s_fifoFullNext = (reset == 1'b1 || (s_fifoRe == 1'b1 && s_fifoWe == 1'b0)) ? 1'b0 :
                               (s_fifoWe == 1'b1 && s_fifoRe == 1'b0 && s_writeAddressNext == s_readAddressReg) ? 1'b1 : s_fifoFullReg;
  wire        s_fifoEmptyNext = (reset == 1'b1 || (s_fifoRe == 1'b1 && s_fifoWe == 1'b0 && s_readAddressNext == s_writeAddressReg)) ? 1'b1 :
                                (s_fifoWe == 1'b1 && s_fifoRe == 1'b0) ? 1'b0 : s_fifoEmptyReg;
  wire [4:0]  s_nrOfEntriesNext = (reset == 1'b1) ? 5'd0 : (s_fifoWe == 1'b1 && s_fifoRe == 1'b0) ? s_nrOfEntriesReg + 5'd1 :
                                  (s_fifoWe == 1'b0 && s_fifoRe == 1'b1) ? s_nrOfEntriesReg - 5'd1 : s_nrOfEntriesReg;
  
  assign fifoFull       = s_fifoFullReg;
  assign fifoEmpty      = s_fifoEmptyReg;
  assign frameErrorOut  = s_frameErrorReg[s_readAddressReg];
  assign parityErrorOut = s_parityErrorReg[s_readAddressReg];
  assign breakOut       = s_breakReg[s_readAddressReg];
  assign nrOfEntries    = s_nrOfEntriesReg;

  always @(posedge clock)
    begin
      s_fifoFullReg     <= s_fifoFullNext;
      s_fifoEmptyReg    <= s_fifoEmptyNext;
      s_writeAddressReg <= (reset == 1'b1) ? 4'd0 : (s_fifoWe == 1'b1) ? s_writeAddressNext : s_writeAddressReg;
      s_readAddressReg  <= (reset == 1'b1) ? 4'd0 : (s_fifoRe == 1'b1) ? s_readAddressNext : s_readAddressReg;
      s_frameErrorReg   <= s_frameErrorNext;
      s_parityErrorReg  <= s_parityErrorNext;
      s_breakReg        <= s_breakNext;
      fifoError         <= (s_frameErrorReg == 16'd0 && s_parityErrorReg == 16'd0 && s_breakReg == 16'd0) ? 1'b0 : 1'b1;
      s_nrOfEntriesReg  <= s_nrOfEntriesNext;
    end
    
  
  genvar n;
  
  generate
    for (n = 0; n < 16 ; n = n + 1)
      begin : gen
        assign s_clearError[n]      = (s_readAddressReg == n && 
                                       ((s_fifoRe == 1'b1 && s_fifoWe == 1'b0) ||
                                        (s_fifoRe == 1'b1 && s_fifoWe == 1'b1 && s_writeAddressReg != n) ||
                                        clearError == 1'b1)) ? 1'b1 : 1'b0;
        assign s_writeError[n]      = (s_writeAddressReg == n && s_fifoWe == 1'b1 && s_fifoFullReg == 1'b0) ? 1'b1 : 1'b0;
        assign s_frameErrorNext[n]  = (reset == 1'b1 || s_clearError[n] == 1'b1) ? 1'b0 : (s_writeError[n] == 1'b1) ? frameErrorIn : s_frameErrorReg[n];
        assign s_parityErrorNext[n] = (reset == 1'b1 || s_clearError[n] == 1'b1) ? 1'b0 : (s_writeError[n] == 1'b1) ? parityErrorIn : s_parityErrorReg[n];
        assign s_breakNext[n]       = (reset == 1'b1 || s_clearError[n] == 1'b1) ? 1'b0 : (s_writeError[n] == 1'b1) ? breakIn : s_breakReg[n];
      end
  endgenerate
    
  sramLutRam #(.nrOfAddressBits(4),
               .nrOfDataBits(8)) fifoMem 
              (.clock(clock),
               .writeEnable(s_fifoWe),
               .writeAddress(s_writeAddressReg),
               .readAddress(s_readAddressReg),
               .writeData(dataIn),
               .readData(dataOut) );
endmodule
