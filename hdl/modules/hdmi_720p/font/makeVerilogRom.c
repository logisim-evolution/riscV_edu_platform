#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include "ami386__8x8.h"

void printline(FILE *fout, int index ) {
  int mask = 1<<7;
  int value = ami386__8x8[index];
  if (value != 0) {
    fprintf(fout , "      11'h%03X : data <= 8'h%02X;\n" , index , value );
  }
  while (mask != 0) {
    printf( (mask&value) != 0 ? "*" : " " );
    mask >>= 1;
  }
  printf("\n");
}

int main() {
  int charId,lineId;
  FILE *fout;
  fout = fopen("ami386__8x8.v","w");
  fprintf( fout, "module charRom ( input wire        clock,\n");
  fprintf( fout, "                 input wire [10:0] address,\n");
  fprintf( fout, "                 output reg [7:0]  data);\n\n");
  
  fprintf( fout, "  always @(posedge clock)\n");
  fprintf( fout, "  begin\n");
  fprintf( fout, "    case (address)\n");
  for (charId = 0 ; charId < 128 ; charId++) {
    for (lineId = 0 ; lineId < 8 ; lineId++) {
      printline(fout, (charId<<3)+lineId);
    }
  }
  fprintf( fout, "      default : data <= 8'h00;\n");
  fprintf( fout, "    endcase\n");
  fprintf( fout, "  end\n");
  fprintf( fout, "endmodule\n");
  fclose( fout );
}
