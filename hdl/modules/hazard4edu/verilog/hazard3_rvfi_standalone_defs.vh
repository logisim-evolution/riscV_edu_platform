/*****************************************************************************\
|                      Copyright (C) 2021-2025 Luke Wren                      |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Macros for building Hazard3 with RVFI trace port outside of the
// riscv-formal test harness. For example, when including the trace port in a
// synthesised processor.
`ifdef HAZARD3_RVFI_STANDALONE

`define RISCV_FORMAL
`define RISCV_FORMAL_NRET 1
`define RISCV_FORMAL_XLEN 32
`define RISCV_FORMAL_ILEN 32
`define RISCV_FORMAL_MEM_FAULT
`define RISCV_FORMAL_ALIGNED_MEM

`define RVFI_OUTPUTS \
  output wire        rvfi_valid, \
  output wire [63:0] rvfi_order, \
  output wire [31:0] rvfi_insn, \
  output wire        rvfi_trap, \
  output wire        rvfi_halt, \
  output wire        rvfi_intr, \
  output wire [1:0]  rvfi_mode, \
  output wire [1:0]  rvfi_ixl, \
  output wire [4:0]  rvfi_rs1_addr, \
  output wire [4:0]  rvfi_rs2_addr, \
  output wire [31:0] rvfi_rs1_rdata, \
  output wire [31:0] rvfi_rs2_rdata, \
  output wire [4:0]  rvfi_rd_addr, \
  output wire [31:0] rvfi_rd_wdata, \
  output wire [31:0] rvfi_pc_rdata, \
  output wire [31:0] rvfi_pc_wdata, \
  output wire [31:0] rvfi_mem_addr, \
  output wire [3:0]  rvfi_mem_rmask, \
  output wire [3:0]  rvfi_mem_wmask, \
  output wire [31:0] rvfi_mem_rdata, \
  output wire [31:0] rvfi_mem_wdata, \
  output wire        rvfi_mem_fault, \
  output wire [3:0]  rvfi_mem_fault_rmask, \
  output wire [3:0]  rvfi_mem_fault_wmask

`define RVFI_WIRES \
  wire        rvfi_valid; \
  wire [63:0] rvfi_order; \
  wire [31:0] rvfi_insn; \
  wire        rvfi_trap; \
  wire        rvfi_halt; \
  wire        rvfi_intr; \
  wire [1:0]  rvfi_mode; \
  wire [1:0]  rvfi_ixl; \
  wire [4:0]  rvfi_rs1_addr; \
  wire [4:0]  rvfi_rs2_addr; \
  wire [31:0] rvfi_rs1_rdata; \
  wire [31:0] rvfi_rs2_rdata; \
  wire [4:0]  rvfi_rd_addr; \
  wire [31:0] rvfi_rd_wdata; \
  wire [31:0] rvfi_pc_rdata; \
  wire [31:0] rvfi_pc_wdata; \
  wire [31:0] rvfi_mem_addr; \
  wire [3:0]  rvfi_mem_rmask; \
  wire [3:0]  rvfi_mem_wmask; \
  wire [31:0] rvfi_mem_rdata; \
  wire [31:0] rvfi_mem_wdata; \
  wire        rvfi_mem_fault; \
  wire [3:0]  rvfi_mem_fault_rmask; \
  wire [3:0]  rvfi_mem_fault_wmask;

`define RVFI_CONN \
  .rvfi_valid (rvfi_valid), \
  .rvfi_order (rvfi_order), \
  .rvfi_insn (rvfi_insn), \
  .rvfi_trap (rvfi_trap), \
  .rvfi_halt (rvfi_halt), \
  .rvfi_intr (rvfi_intr), \
  .rvfi_mode (rvfi_mode), \
  .rvfi_ixl (rvfi_ixl), \
  .rvfi_rs1_addr (rvfi_rs1_addr), \
  .rvfi_rs2_addr (rvfi_rs2_addr), \
  .rvfi_rs1_rdata (rvfi_rs1_rdata), \
  .rvfi_rs2_rdata (rvfi_rs2_rdata), \
  .rvfi_rd_addr (rvfi_rd_addr), \
  .rvfi_rd_wdata (rvfi_rd_wdata), \
  .rvfi_pc_rdata (rvfi_pc_rdata), \
  .rvfi_pc_wdata (rvfi_pc_wdata), \
  .rvfi_mem_addr (rvfi_mem_addr), \
  .rvfi_mem_rmask (rvfi_mem_rmask), \
  .rvfi_mem_wmask (rvfi_mem_wmask), \
  .rvfi_mem_rdata (rvfi_mem_rdata), \
  .rvfi_mem_wdata (rvfi_mem_wdata), \
  .rvfi_mem_fault (rvfi_mem_fault), \
  .rvfi_mem_fault_rmask (rvfi_mem_fault_rmask), \
  .rvfi_mem_fault_wmask (rvfi_mem_fault_wmask)

  `endif
