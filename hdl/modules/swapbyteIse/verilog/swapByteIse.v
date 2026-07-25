module swapByte 
  #(parameter [6:0]  customId = 8'd0,
    parameter W_DATA = 32) // Important, W_DATA must be 32 for this ISE
   ( input  wire [6:0]        ci_id,
     input  wire              ci_start,
     input  wire [W_DATA-1:0] ci_dataa,
     input  wire [W_DATA-1:0] ci_datab,
     output wire              ci_done,
     output wire [W_DATA-1:0] ci_result);

  wire s_isMyCustomInstruction = (ci_id == customId) ? ci_start : 1'b0;
  
  wire [31:0] s_swappedData = (ci_datab[0] == 1'b0) ? {ci_dataa[7:0], ci_dataa[15:8], ci_dataa[23:16], ci_dataa[31:24]} :
                                                      {ci_dataa[23:16], ci_dataa[31:24], ci_dataa[7:0], ci_dataa[15:8]};

  assign ci_done = s_isMyCustomInstruction;
  assign ci_result = (s_isMyCustomInstruction == 1'b1) ? s_swappedData : 32'd0;

endmodule
