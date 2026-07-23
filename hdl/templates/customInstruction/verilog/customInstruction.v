module customInstruction 
  #(parameter [6:0] customId = 7'd0,
    parameter W_DATA = 32) // see hazard3 for value
   ( input  wire clock,
     input  wire reset, // active high
     input  wire [6:0]        ci_id,
     input  wire              ci_start,
     input  wire [W_DATA-1:0] ci_dataa,
     input  wire [W_DATA-1:0] ci_datab,
     output wire              ci_done,
     output wire [W_DATA-1:0] ci_result);
