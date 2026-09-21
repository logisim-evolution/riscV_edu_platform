module uartBus
  #( parameter DataBits = 32, // must be 32 for this module
     parameter AddrBits = 32, // must be > 4 for this module
     parameter [AddrBits-1:0] BaseAddress )
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
     // BTE_I is not used in this module
     
     // here all external signals are defined
     input  wire clock50MHz,
     output wire irq,
     input  wire RxD,
     output wire TxD);

  reg s_ackReg, s_errorReg, s_weReg, s_reReg;
  reg[2:0] s_indexReg;
  reg[31:0] s_dataInReg, s_dataOut;
  reg[3:0] s_byteEnablesReg;
  reg [15:0] s_divisorReg;
  reg [7:0]  s_lineControlReg, s_interruptEnableReg, s_scratchReg, s_modemControlReg;
  reg [7:6]  s_fifoControlReg;
  wire [7:0] s_weRegsVector;
  wire s_TxD;
  wire s_baudRateX16Tick, s_baudRateX2Tick;
  
  
  // Here all bus related signals are defined
  wire isMyTransaction = (ADDR_I[AddrBits-1:3] == BaseAddress[AddrBits-1:3]) ? CYC_I & STB_I : 1'b0;
  wire isCorrectTransaction = (CTI_I == 3'b000) ? isMyTransaction : 1'b0; // this module only supports classic transactions

  assign ERR_O = s_errorReg;
  assign ACK_O = s_ackReg;
  assign DAT_O = s_dataOut;

  always @(posedge CLK_I)
  begin
    s_ackReg         <= (RST_I == 1'b1) ? 1'b0 : ~s_ackReg & isCorrectTransaction;
    s_errorReg       <= (RST_I == 1'b1) ? 1'b0 : ~s_errorReg & isMyTransaction & ~isCorrectTransaction;
    s_weReg          <= ~s_ackReg & isCorrectTransaction & WE_I;
    s_reReg          <= ~s_ackReg & isCorrectTransaction & ~WE_I;
    s_indexReg       <= (RST_I == 1'b1) ? 3'd0 : (s_ackReg == 1'b0 && isCorrectTransaction == 1'b1) ? ADDR_I[2:0] : s_indexReg;
    s_dataInReg      <= (s_ackReg == 1'b0 && isCorrectTransaction == 1'b1) ? DAT_I : s_dataInReg;
    s_byteEnablesReg <= (s_ackReg == 1'b0 && isCorrectTransaction == 1'b1) ? SEL_I : s_byteEnablesReg;
  end
  
  // here the uart registers are defined
  assign TxD = s_TxD | s_modemControlReg[4];

  genvar n;
  generate
    for (n = 0; n < 4; n = n + 1)
    begin : gen
      assign s_weRegsVector[n]   = ~s_indexReg[2] & s_weReg & s_byteEnablesReg[n];
      assign s_weRegsVector[n+4] = s_indexReg[2] & s_weReg & s_byteEnablesReg[n];
    end
  endgenerate
  
  always @(posedge CLK_I)
    begin
      s_divisorReg[7:0]    <= (RST_I == 1'b1) ? 8'd0 : (s_weRegsVector[0] == 1'b1 && s_lineControlReg[7] == 1'b1) ? s_dataInReg[7:0] : s_divisorReg[7:0];
      s_divisorReg[15:8]   <= (RST_I == 1'b1) ? 8'd0 : (s_weRegsVector[1] == 1'b1 && s_lineControlReg[7] == 1'b1) ? s_dataInReg[15:8] : s_divisorReg[15:8];
      s_lineControlReg     <= (RST_I == 1'b1) ? 8'd0 : (s_weRegsVector[3] == 1'b1) ? s_dataInReg[31:24] : s_lineControlReg;
      s_interruptEnableReg <= (RST_I == 1'b1) ? 8'd0 : (s_weRegsVector[1] == 1'b1 && s_lineControlReg[7] == 1'b0) ? {6'd0, s_dataInReg[9:8]} : s_interruptEnableReg;
      s_scratchReg         <= (RST_I == 1'b1) ? 8'd0 : (s_weRegsVector[7] == 1'b1) ? s_dataInReg[31:24] : s_scratchReg;
      s_modemControlReg    <= (RST_I == 1'b1) ? 8'd0 : (s_weRegsVector[4] == 1'b1) ? {3'd0, s_dataInReg[4], 4'd0} : s_modemControlReg;
      s_fifoControlReg     <= (RST_I == 1'b1) ? 2'd0 : (s_weRegsVector[2] == 1'b1) ? s_dataInReg[23:22] : s_fifoControlReg;
    end

  // here the baud generator is defined
  baudGenerator bdg ( .clock(CLK_I),
                      .clock50MHz(clock50MHz),
                      .reset(RST_I),
                      .baudDivisor(s_divisorReg),
                      .baudRateX16Tick(s_baudRateX16Tick),
                      .baudRateX2Tick(s_baudRateX2Tick) );

  // here the tx path is defined
  wire s_TxFifoRe, s_TxFifoEmpty, s_TxFifoFull, s_TxBusy;
  wire s_TxFifoWe = ~s_TxFifoFull & s_weRegsVector[0] & ~s_lineControlReg[7];
  wire [7:0] s_TxFifoData;
  wire s_resetTxFifo = RST_I | (s_weRegsVector[2] & s_dataInReg[18]);
  
  uartTxFifo TXF ( .clock(CLK_I),
                   .reset(s_resetTxFifo),
                   .fifoRe(s_TxFifoRe),
                   .fifoWe(s_TxFifoWe),
                   .fifoEmpty(s_TxFifoEmpty),
                   .fifoFull(s_TxFifoFull),
                   .dataIn(s_dataInReg[7:0]),
                   .dataOut(s_TxFifoData));
  
  uartTx TXC ( .clock(CLK_I),
               .reset(RST_I),
               .baudRateX2tick(s_baudRateX2Tick),
               .controlReg(s_lineControlReg[6:0]),
               .fifoData(s_TxFifoData),
               .fifoEmpty(s_TxFifoEmpty),
               .busy(s_TxBusy),
               .fifoReadAck(s_TxFifoRe),
               .uartTxLine(s_TxD) );
  
  // here the Rx path is defined
  reg s_lineStatus1Reg;
  wire s_rxFifoEmpty, s_rxFifoWe, s_clearError, s_frameError, s_parityError, s_rxFifoFull, s_overrunError, s_break;
  wire [7:0] s_lineStatusReg, s_rxFifoData, s_receiverBufferReg;
  wire [4:0] s_rxNrOfEntries;
  wire s_resetRxFifo = RST_I | (s_weRegsVector[2] & s_dataInReg[17]);
  wire s_uartRx = (s_modemControlReg[4] == 1'b1) ? s_TxD : RxD;
  wire s_reRxFifo = s_reReg & ~s_indexReg[2] & s_byteEnablesReg[0];

  assign s_lineStatusReg[0] = ~s_rxFifoEmpty;
  assign s_lineStatusReg[1] = s_lineStatus1Reg;
  assign s_lineStatusReg[5] = s_TxFifoEmpty;
  assign s_lineStatusReg[6] = s_TxFifoEmpty & ~s_TxBusy;
  
  always @(posedge CLK_I) 
    begin
      s_lineStatus1Reg <= (s_clearError == 1'b1 || s_resetRxFifo == 1'b1) ? 1'b0 : s_lineStatus1Reg | s_overrunError;
    end
  
  uartRxFifo RXF ( .clock(CLK_I),
                   .reset(s_resetRxFifo),
                   .fifoRe(s_reRxFifo),
                   .fifoWe(s_rxFifoWe),
                   .clearError(s_clearError),
                   .frameErrorIn(s_frameError),
                   .parityErrorIn(s_parityError),
                   .breakIn(s_break),
                   .fifoEmpty(s_rxFifoEmpty),
                   .fifoFull(s_rxFifoFull),
                   .dataIn(s_rxFifoData),
                   .frameErrorOut(s_lineStatusReg[3]),
                   .parityErrorOut(s_lineStatusReg[2]),
                   .breakOut(s_lineStatusReg[4]),
                   .fifoError(s_lineStatusReg[7]),
                   .nrOfEntries(s_rxNrOfEntries),
                   .dataOut(s_receiverBufferReg));

  uartRx RXC ( .clock(CLK_I),
               .reset(RST_I),
               .baudRateX16Tick(s_baudRateX16Tick),
               .uartRxLine(s_uartRx),
               .fifoFull(s_rxFifoFull),
               .controlReg(s_lineControlReg[5:0]),
               .fifoData(s_rxFifoData),
               .fifoWe(s_rxFifoWe),
               .frameError(s_frameError),
               .breakDetected(s_break),
               .parityError(s_parityError),
               .overrunError(s_overrunError) );

  // here the irq's are defined
  reg s_lineStatusIrq, s_rxAvailableIrq, s_rxAvailableNext, s_txEmptyIrq;
  reg [1:0] s_txEmptyEdgeReg;
  wire s_txEmptyNext = (RST_I == 1'b1 || s_TxFifoWe == 1'b1 || (s_reReg == 1'b1 && s_indexReg[2] == 1'b0 && s_byteEnablesReg[2] == 1'b1 && s_rxAvailableIrq == 1'b0 && s_lineStatusIrq == 1'b0)) ? 1'b0 :
                       (s_txEmptyEdgeReg == 2'b01) ? 1'b1 : s_txEmptyIrq;
  wire [7:0] s_interruptIdentReg;
  assign s_interruptIdentReg[7:3] = 5'b11000;
  assign s_interruptIdentReg[2]   = s_lineStatusIrq | s_rxAvailableIrq;
  assign s_interruptIdentReg[1]   = s_lineStatusIrq | s_txEmptyIrq;
  assign s_interruptIdentReg[0]   = ~(s_lineStatusIrq | s_rxAvailableIrq | s_txEmptyIrq);
  assign irq = s_lineStatusIrq | s_rxAvailableIrq | s_txEmptyIrq;
  assign s_clearError = s_reReg & s_indexReg[2] & s_byteEnablesReg[1];
  
  always @(posedge CLK_I)
    begin
      s_lineStatusIrq  <= (RST_I == 1'b1 || s_clearError == 1'b1) ? 1'b0 :
                          (s_lineStatusIrq | s_lineStatusReg[4] | s_lineStatusReg[3] | s_lineStatusReg[2] | s_lineStatusReg[1]) & s_interruptEnableReg[2];
      s_rxAvailableIrq <= (RST_I == 1'b1) ? 1'b0 : s_rxAvailableNext & s_interruptEnableReg[0];
      s_txEmptyEdgeReg <= (RST_I == 1'b1) ? 2'd0 : {s_txEmptyEdgeReg[0], s_lineStatusReg[6]};
      s_txEmptyIrq     <= s_txEmptyNext;
    end
  
  always @*
    case (s_fifoControlReg)
      2'd0     : s_rxAvailableNext <= s_rxNrOfEntries[4] | s_rxNrOfEntries[3] | s_rxNrOfEntries[2] | s_rxNrOfEntries[1] | s_rxNrOfEntries[0];
      2'd1     : s_rxAvailableNext <= s_rxNrOfEntries[4] | s_rxNrOfEntries[3] | s_rxNrOfEntries[2];
      2'd2     : s_rxAvailableNext <= s_rxNrOfEntries[4] | s_rxNrOfEntries[3];
      default  : s_rxAvailableNext <= (s_rxNrOfEntries[4] == 1'b1 || s_rxNrOfEntries[4:1] == 4'd7) ? 1'b1 : 1'b0;
    endcase
  
  // finally we define the value read out of the core
  assign s_dataOut[31:24] = (s_indexReg[2] == 1'b1) ? s_scratchReg : s_lineControlReg;
  assign s_dataOut[23:16] = (s_indexReg[2] == 1'b1) ? 8'd0 : s_interruptIdentReg;
  assign s_dataOut[15:8]  = (s_indexReg[2] == 1'b1) ? s_lineStatusReg : (s_lineControlReg[7] == 1'b0) ? s_interruptEnableReg : s_divisorReg[15:8];
  assign s_dataOut[7:0]   = (s_indexReg[2] == 1'b1) ? s_modemControlReg : (s_lineControlReg[7] == 1'b0) ? s_receiverBufferReg : s_divisorReg[7:0];

endmodule
