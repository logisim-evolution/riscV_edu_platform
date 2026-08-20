module sevenSegmentUpdate #( parameter segmentId )
                          ( input wire [7:0] currentValue,
                            input wire [31:0] dataIn,
                            input wire [2:0] functionSelect,
                            output reg [7:0] newValue );
  
  wire [3:0] s_selectedData = dataIn[((segmentId + 1) * 4) - 1 : (segmentId * 4)];

  always @*
    case (functionSelect)
      segmentId : newValue <= dataIn[7:0];
      3'd4      : case (s_selectedData)
                    4'd0    : newValue <= {currentValue[7], 7'b0111111};
                    4'd1    : newValue <= {currentValue[7], 7'b0000110};
                    4'd2    : newValue <= {currentValue[7], 7'b1011011};
                    4'd3    : newValue <= {currentValue[7], 7'b1001111};
                    4'd4    : newValue <= {currentValue[7], 7'b1100110};
                    4'd5    : newValue <= {currentValue[7], 7'b1101101};
                    4'd6    : newValue <= {currentValue[7], 7'b1111101};
                    4'd7    : newValue <= {currentValue[7], 7'b0000111};
                    4'd8    : newValue <= {currentValue[7], 7'b1111111};
                    4'd9    : newValue <= {currentValue[7], 7'b1101111};
                    4'd10   : newValue <= {currentValue[7], 7'b1110111};
                    4'd11   : newValue <= {currentValue[7], 7'b1111100};
                    4'd12   : newValue <= {currentValue[7], 7'b0111001};
                    4'd13   : newValue <= {currentValue[7], 7'b1011110};
                    4'd14   : newValue <= {currentValue[7], 7'b1111001};
                    default : newValue <= {currentValue[7], 7'b1110001};
                  endcase
      3'd5      : case (s_selectedData)
                    4'd0    : newValue <= {currentValue[7], 7'b0111111};
                    4'd1    : newValue <= {currentValue[7], 7'b0000110};
                    4'd2    : newValue <= {currentValue[7], 7'b1011011};
                    4'd3    : newValue <= {currentValue[7], 7'b1001111};
                    4'd4    : newValue <= {currentValue[7], 7'b1100110};
                    4'd5    : newValue <= {currentValue[7], 7'b1101101};
                    4'd6    : newValue <= {currentValue[7], 7'b1111101};
                    4'd7    : newValue <= {currentValue[7], 7'b0000111};
                    4'd8    : newValue <= {currentValue[7], 7'b1111111};
                    4'd9    : newValue <= {currentValue[7], 7'b1101111};
                    default : newValue <= {currentValue[7], 7'd0};
                  endcase
      3'd6      : newValue <= {dataIn[segmentId],currentValue[6:0]};
      default   : newValue <= currentValue;
    endcase

endmodule
