/*****************************************************************************\
|                      Copyright (C) 2021-2022 Luke Wren                      |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

module hazard3_alu #(
`include "hazard3_config.vh"
,
`include "hazard3_width_const.vh"
) (
	input  wire [W_ALUOP-1:0] aluop,
	input  wire [W_DATA-1:0]  op_a,
	input  wire [W_DATA-1:0]  op_b,
	output reg  [W_DATA-1:0]  result,
	output wire               cmp
);

`include "hazard3_ops.vh"

// ----------------------------------------------------------------------------
// Fiddle around with add/sub, comparisons etc (all related).

wire sub = !(aluop == ALUOP_ADD);

wire inv_op_b = sub && !(
	aluop == ALUOP_AND || aluop == ALUOP_OR || aluop == ALUOP_XOR || aluop == ALUOP_RS2
);

wire [W_DATA-1:0] op_b_inv = op_b ^ {W_DATA{inv_op_b}};

wire [W_DATA-1:0] sum  = op_a + op_b_inv + {{W_DATA-1{1'b0}}, sub};
wire [W_DATA-1:0] op_xor = op_a ^ op_b;

wire cmp_is_unsigned = aluop == ALUOP_LTU;

wire lt = op_a[W_DATA-1] == op_b[W_DATA-1] ? sum[W_DATA-1]  :
          cmp_is_unsigned                  ? op_b[W_DATA-1] : op_a[W_DATA-1] ;

assign cmp = aluop == ALUOP_SUB ? |op_xor : lt;

// ----------------------------------------------------------------------------
// Separate units for shift, ctz etc

wire [W_DATA-1:0] shift_dout;
wire shift_right_nleft =
	aluop == ALUOP_SRL ||
	aluop == ALUOP_SRA;

wire shift_arith = aluop == ALUOP_SRA;

hazard3_shift_barrel #(
`include "hazard3_config_inst.vh"
) shifter (
	.din         (op_a),
	.shamt       (op_b[4:0]),
	.right_nleft (shift_right_nleft),
	.arith       (shift_arith),
	.dout        (shift_dout)
);


// ----------------------------------------------------------------------------
// Output mux, with simple operations inline

// iCE40: We can implement all bitwise ops with 1 LUT4/bit total, since each
// result bit uses only two operand bits. Much better than feeding each into
// main mux tree. Doesn't matter for big-LUT FPGAs or for implementations with
// bitmanip extensions enabled.

reg [W_DATA-1:0] bitwise;

always @ (*) begin: bitwise_ops
	case (aluop[1:0])
		ALUOP_AND[1:0]: bitwise = op_a & op_b_inv;
		ALUOP_OR [1:0]: bitwise = op_a | op_b_inv;
		ALUOP_XOR[1:0]: bitwise = op_a ^ op_b_inv;
		ALUOP_RS2[1:0]: bitwise =        op_b_inv;
	endcase
end

always @ (*) begin
	casez ({|EXTENSION_A, aluop})
		// Base ISA
		{1'bz, ALUOP_ADD    }: result = sum;
		{1'bz, ALUOP_SUB    }: result = sum;
		{1'bz, ALUOP_LT     }: result = {{W_DATA-1{1'b0}}, lt};
		{1'bz, ALUOP_LTU    }: result = {{W_DATA-1{1'b0}}, lt};
		{1'bz, ALUOP_SRL    }: result = shift_dout;
		{1'bz, ALUOP_SRA    }: result = shift_dout;
		{1'bz, ALUOP_SLL    }: result = shift_dout;
		// A
		{1'b1, ALUOP_MAX    }: result = lt ? op_b : op_a;
		{1'b1, ALUOP_MIN    }: result = lt ? op_a : op_b;
		{1'b1, ALUOP_MAXU   }: result = lt ? op_b : op_a;
		{1'b1, ALUOP_MINU   }: result = lt ? op_a : op_b;

		default:                    result = bitwise;
	endcase
end

// ----------------------------------------------------------------------------
// Properties for base-ISA instructions

`ifdef HAZARD3_ASSERTIONS
`ifndef RISCV_FORMAL
// Really we're just interested in the shifts and comparisons, as these are
// the nontrivial ones. However, easier to test everything!

wire clk;
always @ (posedge clk) begin
	case(aluop)
	default: begin end
	ALUOP_ADD: assert(result == op_a + op_b);
	ALUOP_SUB: assert(result == op_a - op_b);
	ALUOP_LT:  assert(result == $signed(op_a) < $signed(op_b));
	ALUOP_LTU: assert(result == op_a < op_b);
	ALUOP_AND: assert(result == (op_a & op_b));
	ALUOP_OR:  assert(result == (op_a | op_b));
	ALUOP_XOR: assert(result == (op_a ^ op_b));
	ALUOP_SRL: assert(result == op_a >> op_b[4:0]);
	ALUOP_SRA: assert($signed(result) == $signed(op_a) >>> $signed(op_b[4:0]));
	ALUOP_SLL: assert(result == op_a << op_b[4:0]);
	endcase
end
`endif
`endif

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
