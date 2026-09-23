/*****************************************************************************\
|                      Copyright (C) 2021-2023 Luke Wren                      |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Little instructions go in, big instructions come out

`default_nettype none

module hazard3_instr_decompress #(
`include "hazard3_config.vh"
) (
	input  wire        clk,
	input  wire        rst_n,

	input  wire [31:0] instr_in,

	output reg         instr_is_32bit,
	output reg  [31:0] instr_out,

	// If instruction is a non-final uop, need to suppress PC update, and null
	// the PC offset in the mepc address in stage 3.
	output wire        instr_out_is_uop,
	output wire        instr_out_is_final_uop,
	output wire        instr_out_uop_no_pc_update,
	// Indicate instr_out is a uop from the noninterruptible part of a uop
	// sequence. If one uop is noninterruptible, all following uops until the
	// end of the sequence are also noninterruptible.
	output wire        instr_out_uop_atomic,
	// Current ucode sequence is stalled on downstream execution
	input  wire        instr_out_uop_stall,
	input  wire        instr_out_uop_clear,

	// To regnum decoder in frontend
	output wire [3:0]  df_uop_step,

	output reg         invalid
);

`include "rv_opcodes.vh"

localparam W_REGADDR = 5;
localparam PASSTHROUGH = ~|EXTENSION_C;

// Long-register formats: cr, ci, css
// Short-register formats: ciw, cl, cs, cb, cj
wire [W_REGADDR-1:0] rd_l  = instr_in[11:7];
wire [W_REGADDR-1:0] rs1_l = instr_in[11:7];
wire [W_REGADDR-1:0] rs2_l = instr_in[6:2];
wire [W_REGADDR-1:0] rd_s  = {2'b01, instr_in[4:2]};
wire [W_REGADDR-1:0] rs1_s = {2'b01, instr_in[9:7]};
wire [W_REGADDR-1:0] rs2_s = {2'b01, instr_in[4:2]};

// Mapping of cx -> x immediate formats (we are *expanding* instructions, not
// decoding them):

wire [31:0] imm_ci = {
	{7{instr_in[12]}},
	instr_in[6:2],
	20'h00000
};

wire [31:0] imm_cj = {
	instr_in[12],
	instr_in[8],
	instr_in[10:9],
	instr_in[6],
	instr_in[7],
	instr_in[2],
	instr_in[11],
	instr_in[5:3],
	{9{instr_in[12]}},
	12'h000
};

wire [31:0] imm_cb ={
	{4{instr_in[12]}},
	instr_in[6:5],
	instr_in[2],
	13'h0000,
	instr_in[11:10],
	instr_in[4:3],
	instr_in[12],
	7'h00
};

function [31:0] rfmt_rd;  input [4:0] rd;  begin rfmt_rd  = {20'h00000, rd, 7'h00};   end endfunction
function [31:0] rfmt_rs1; input [4:0] rs1; begin rfmt_rs1 = {12'h000, rs1, 15'h0000}; end endfunction
function [31:0] rfmt_rs2; input [4:0] rs2; begin rfmt_rs2 = {7'h00, rs2, 20'h00000};  end endfunction

// ----------------------------------------------------------------------------
// Push/pop and friends

// The longest uop sequence is a maximal cm.popretz:
//
// - 13x lw                     (counter = 0..12)
// - 1x addi to set a0 to zero  (counter = 13   ) < atomic section
// - 1x jalr to jump through ra (counter = 14   ) < atomic section
// - 1x addi to adjust sp       (counter = 15   ) < atomic section

wire [3:0] uop_ctr;
reg  [3:0] uop_ctr_nxt_in_seq;
reg        in_uop_seq;
reg        uop_no_pc_update;

wire uop_seq_end      = 1'b0;
wire uop_atomic       = 1'b0;

assign instr_out_is_uop = in_uop_seq;
assign instr_out_is_final_uop = uop_seq_end;
assign instr_out_uop_atomic = uop_atomic;
assign instr_out_uop_no_pc_update = uop_no_pc_update;
assign df_uop_step = uop_ctr;

// ----------------------------------------------------------------------------

generate
if (PASSTHROUGH) begin: instr_passthrough
	always @ (*) begin
		instr_is_32bit = 1'b1;
		instr_out = instr_in;
		invalid = 1'b0;
	end
end else begin: instr_decompress
	always @ (*) begin
		if (instr_in[1:0] == 2'b11) begin
			instr_is_32bit = 1'b1;
			instr_out = instr_in;
			invalid = 1'b0;
			in_uop_seq = 1'b0;
			uop_no_pc_update = 1'b0;
			uop_ctr_nxt_in_seq = uop_ctr;
		end else begin
			instr_is_32bit = 1'b0;
			instr_out = 32'd0;
			invalid = 1'b0;
			in_uop_seq = 1'b0;
			uop_no_pc_update = 1'b0;
			uop_ctr_nxt_in_seq = uop_ctr;
			casez (instr_in[15:0])
			`RVOPC_C_ADDI4SPN: begin
				instr_out = `RVOPC_NOZ_ADDI | rfmt_rd(rd_s) | rfmt_rs1(5'd2)
					| {2'h0, instr_in[10:7], instr_in[12:11], instr_in[5], instr_in[6], 2'b00, 20'h00000};
				invalid   = ~|instr_in[12:2]; // Always-invalid all-zeroes instruction
			end
			`RVOPC_C_LW:   instr_out = `RVOPC_NOZ_LW | rfmt_rd(rd_s) | rfmt_rs1(rs1_s)
				| {5'h00, instr_in[5], instr_in[12:10], instr_in[6], 2'b00, 20'h00000};
			`RVOPC_C_SW:   instr_out = `RVOPC_NOZ_SW | rfmt_rs2(rs2_s) | rfmt_rs1(rs1_s)
				| {5'h00, instr_in[5], instr_in[12], 13'h0000, instr_in[11:10], instr_in[6], 2'b00, 7'h00};
			`RVOPC_C_ADDI: instr_out = `RVOPC_NOZ_ADDI | rfmt_rd(rd_l) | rfmt_rs1(rs1_l) | imm_ci;
			`RVOPC_C_JAL:  instr_out = `RVOPC_NOZ_JAL  | rfmt_rd(5'd1) | imm_cj;
			`RVOPC_C_J:    instr_out = `RVOPC_NOZ_JAL  | rfmt_rd(5'd0) | imm_cj;
			`RVOPC_C_LI:   instr_out = `RVOPC_NOZ_ADDI | rfmt_rd(rd_l) | imm_ci;
			`RVOPC_C_LUI: begin
				if (rd_l == 5'd2) begin
					// addi16sp
					instr_out = `RVOPC_NOZ_ADDI | rfmt_rd(5'd2) | rfmt_rs1(5'd2) |
						{{3{instr_in[12]}}, instr_in[4:3], instr_in[5], instr_in[2], instr_in[6], 24'h000000};
				end else begin
					instr_out = `RVOPC_NOZ_LUI | rfmt_rd(rd_l) | {{15{instr_in[12]}}, instr_in[6:2], 12'h000};
				end
				invalid = ~|{instr_in[12], instr_in[6:2]}; // RESERVED if imm == 0
			end
			`RVOPC_C_SLLI: instr_out = `RVOPC_NOZ_SLLI | rfmt_rd(rs1_l) | rfmt_rs1(rs1_l) | imm_ci;
			`RVOPC_C_SRAI: instr_out = `RVOPC_NOZ_SRAI | rfmt_rd(rs1_s) | rfmt_rs1(rs1_s) | imm_ci;
			`RVOPC_C_SRLI: instr_out = `RVOPC_NOZ_SRLI | rfmt_rd(rs1_s) | rfmt_rs1(rs1_s) | imm_ci;
			`RVOPC_C_ANDI: instr_out = `RVOPC_NOZ_ANDI | rfmt_rd(rs1_s) | rfmt_rs1(rs1_s) | imm_ci;
			`RVOPC_C_AND:  instr_out = `RVOPC_NOZ_AND  | rfmt_rd(rs1_s) | rfmt_rs1(rs1_s) | rfmt_rs2(rs2_s);
			`RVOPC_C_OR:   instr_out = `RVOPC_NOZ_OR   | rfmt_rd(rs1_s) | rfmt_rs1(rs1_s) | rfmt_rs2(rs2_s);
			`RVOPC_C_XOR:  instr_out = `RVOPC_NOZ_XOR  | rfmt_rd(rs1_s) | rfmt_rs1(rs1_s) | rfmt_rs2(rs2_s);
			`RVOPC_C_SUB:  instr_out = `RVOPC_NOZ_SUB  | rfmt_rd(rs1_s) | rfmt_rs1(rs1_s) | rfmt_rs2(rs2_s);
			`RVOPC_C_ADD: begin
				if (|rs2_l) begin
					instr_out = `RVOPC_NOZ_ADD | rfmt_rd(rd_l) | rfmt_rs1(rs1_l) | rfmt_rs2(rs2_l);
				end else if (|rs1_l) begin // jalr
					instr_out = `RVOPC_NOZ_JALR | rfmt_rd(5'd1) | rfmt_rs1(rs1_l);
				end else begin // ebreak
					instr_out = `RVOPC_NOZ_EBREAK;
				end
			end
			`RVOPC_C_MV: begin
				if (|rs2_l) begin // mv
					instr_out = `RVOPC_NOZ_ADD | rfmt_rd(rd_l) | rfmt_rs2(rs2_l);
				end else begin // jr
					instr_out = `RVOPC_NOZ_JALR | rfmt_rs1(rs1_l);
					invalid = ~|rs1_l; // RESERVED
				end
			end
			`RVOPC_C_LWSP: begin
				instr_out = `RVOPC_NOZ_LW | rfmt_rd(rd_l) | rfmt_rs1(5'd2) |
					{4'h0, instr_in[3:2], instr_in[12], instr_in[6:4], 2'b00, 20'h00000};
				invalid = ~|rd_l; // RESERVED
			end
			`RVOPC_C_SWSP:    instr_out = `RVOPC_NOZ_SW | rfmt_rs2(rs2_l) | rfmt_rs1(5'd2)
				| {4'h0, instr_in[8:7], instr_in[12], 13'h0000, instr_in[11:9], 2'b00, 7'h00};
			`RVOPC_C_BEQZ:     instr_out = `RVOPC_NOZ_BEQ | rfmt_rs1(rs1_s) | imm_cb;
			`RVOPC_C_BNEZ:     instr_out = `RVOPC_NOZ_BNE | rfmt_rs1(rs1_s) | imm_cb;			
			`RVOPC_C_MUL: begin
				instr_out = `RVOPC_NOZ_MUL    | rfmt_rd(rs1_s) | rfmt_rs1(rs1_s) | rfmt_rs2(rs2_s);
				invalid = ~|EXTENSION_M;
			end

			default: invalid = 1'b1;
			endcase
		end
	end
end
endgenerate

assign uop_ctr = 4'h0;

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
