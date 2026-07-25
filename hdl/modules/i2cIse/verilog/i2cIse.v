module i2cCustomInstr 
  #( parameter CLOCK_FREQUENCY = 12000000,
     parameter I2C_FREQUENCY = 1000000,
     parameter [6:0] CUSTOM_ID = 8'h00,
     parameter W_DATA = 32) // Important: W_DATA must be 32!
   ( input  wire              clock,
     input  wire              reset, // active high
     input  wire [6:0]        ci_id,
     input  wire              ci_start,
     input  wire [W_DATA-1:0] ci_dataa,
     output wire              ci_done,
     output wire [W_DATA-1:0] ci_result,
     // here the I2C interface is defined
     output wire              SCL,
     inout wire               SDA);

  reg  s_startedI2cReg, s_doneReg, s_oldBusyReg;
  reg [31:0] s_inDataReg;
  wire s_busy, s_ackError;
  wire [7:0] s_i2cData;
  wire s_isMyCi = (ci_id == CUSTOM_ID) ? ci_start & ~s_startedI2cReg : 1'd0;
  wire s_startedI2cNext = (reset == 1'b1 || s_doneReg == 1'b1) ? 1'b0 : (s_isMyCi == 1'b1) ? 1'b1 : s_startedI2cReg;
  wire s_doneNext = (reset == 1'b1) ? 1'b0 : s_oldBusyReg & ~s_busy;
  wire s_startI2cRead  = ci_dataa[24] & s_isMyCi;
  wire s_startI2cWrite = ~ci_dataa[24] & s_isMyCi;
  
  assign ci_done = s_doneReg;
  assign ci_result = (s_doneReg == 1'b0) ? 32'd0 : {s_ackError,23'd0,s_i2cData};
  
  always @(posedge clock)
    begin
      s_startedI2cReg <= s_startedI2cNext;
      s_oldBusyReg    <= s_busy & ~reset;
      s_doneReg       <= s_doneNext;
      s_inDataReg     <= (s_isMyCi == 1'b1) ? ci_dataa : s_inDataReg;
    end

  i2cMaster #( .CLOCK_FREQUENCY(CLOCK_FREQUENCY),
               .I2C_FREQUENCY(I2C_FREQUENCY)) master
             ( .clock(clock),
               .reset(reset),
               .startWrite(s_startI2cWrite),
               .startRead(s_startI2cRead),
               .address(s_inDataReg[31:25]),
               .regIn(s_inDataReg[15:8]),
               .dataIn(s_inDataReg[7:0]),
               .dataOut(s_i2cData),
               .ackError(s_ackError),
               .busy(s_busy),
               .SCL(SCL),
               .SDA(SDA) );
endmodule
