`default_nettype none

module hazard3_dm_ecp5 #(
    // Where there are multiple harts per DM, the least-indexed hart is the
    // least-significant on each concatenated hart access bus.
    parameter N_HARTS      = 1,
    // Where there are multiple DMs, the address of each DM should be a
    // multiple of 'h200, so that bits[8:2] decode correctly.
    parameter NEXT_DM_ADDR = 32'h0000_0000,
    // Implement support for system bus access:
    parameter HAVE_SBA     = 1,
    parameter DTMCS_IDLE_HINT = 3'd4,
    parameter W_PADDR         = 9,

    // Do not modify:
    parameter ABITS           = W_PADDR - 2, // do not modify
    parameter XLEN         = 32,                               // Do not modify
    parameter W_HARTSEL    = N_HARTS > 1 ? $clog2(N_HARTS) : 1 // Do not modify
) (
    // DM is assumed to be in same clock domain as core; clock crossing
    // (if any) is inside DTM, or between DTM and DM.
    input  wire                      clk,
    input  wire                      rst_n,

    // Reset request/acknowledge. "req" is a pulse >= 1 cycle wide. "done" is
    // level-sensitive, goes high once component is out of reset.
    //
    // The "sys" reset (ndmreset) is conventionally everything apart from DM +
    // DTM, but, as per section 3.2 in 0.13.2 debug spec: "Exactly what is
    // affected by this reset is implementation dependent, as long as it is
    // possible to debug programs from the first instruction executed." So
    // this could simply be an all-hart reset.
    output wire                      sys_reset_req,
    input  wire                      sys_reset_done,
    output wire [N_HARTS-1:0]        hart_reset_req,
    input  wire [N_HARTS-1:0]        hart_reset_done,

    // Hart run/halt control
    output wire [N_HARTS-1:0]        hart_req_halt,
    output wire [N_HARTS-1:0]        hart_req_halt_on_reset,
    output wire [N_HARTS-1:0]        hart_req_resume,
    input  wire [N_HARTS-1:0]        hart_halted,
    input  wire [N_HARTS-1:0]        hart_running,

    // Hart access to data0 CSR (assumed to be core-internal but per-hart)
    output wire [N_HARTS*XLEN-1:0]   hart_data0_rdata,
    input  wire [N_HARTS*XLEN-1:0]   hart_data0_wdata,
    input  wire [N_HARTS-1:0]        hart_data0_wen,

    // Hart instruction injection
    output wire [N_HARTS*32-1:0]     hart_instr_data,
    output wire [N_HARTS-1:0]        hart_instr_data_vld,
    input  wire [N_HARTS-1:0]        hart_instr_data_rdy,
    input  wire [N_HARTS-1:0]        hart_instr_caught_exception,
    input  wire [N_HARTS-1:0]        hart_instr_caught_ebreak,

    // System bus access (optional) -- can be hooked up to the standalone AHB
    // shim (hazard3_sbus_to_ahb.v) or the SBA input port on the processor
    // wrapper, which muxes SBA into the processor's load/store bus access
    // port. SBA does not increase debugger bus throughput, but supports
    // minimally intrusive debug bus access for e.g. Segger RTT.
    output wire [31:0]               sbus_addr,
    output wire                      sbus_write,
    output wire [1:0]                sbus_size,
    output wire                      sbus_vld,
    input  wire                      sbus_rdy,
    input  wire                      sbus_err,
    output wire [31:0]               sbus_wdata,
    input  wire [31:0]               sbus_rdata
);

wire dmi_rst_n;
wire dmihardreset_req;
wire assert_dmi_reset_n;
wire dmi_psel;
wire dmi_penable;
wire dmi_pwrite;
wire [W_PADDR-1:0] dmi_paddr;
wire [31:0]        dmi_pwdata;
wire [31:0]        dmi_prdata;
wire dmi_pready;
wire dmi_pslverr;

assign assert_dmi_reset_n = !dmihardreset_req || rst_n;

hazard3_reset_sync reset_sync (
    .clk(clk),
    .rst_n_in(assert_dmi_reset_n),
    .rst_n_out(dmi_rst_n)
);

hazard3_ecp5_jtag_dtm #(
    .DTMCS_IDLE_HINT(DTMCS_IDLE_HINT),
    .W_PADDR(W_PADDR),
    .ABITS(ABITS)
) hazard3_ecp5_jtag_dtm_instance (
    .dmihardreset_req(dmihardreset_req),
    .clk_dmi(clk),
    .rst_n_dmi(dmi_rst_n),
    .dmi_psel(dmi_psel),
    .dmi_penable(dmi_penable),
    .dmi_pwrite(dmi_pwrite),
    .dmi_paddr(dmi_paddr),
    .dmi_pwdata(dmi_pwdata),
    .dmi_prdata(dmi_prdata),
    .dmi_pready(dmi_pready),
    .dmi_pslverr(dmi_pslverr)
);

hazard3_dm #(
    .N_HARTS(N_HARTS),
    .NEXT_DM_ADDR(NEXT_DM_ADDR),
    .HAVE_SBA(HAVE_SBA),
    .XLEN(XLEN),
    .W_HARTSEL(W_HARTSEL)
) hazard3_dm_instance (
    .clk(clk),
    .rst_n(rst_n),
    .dmi_psel(dmi_psel),
    .dmi_penable(dmi_penable),
    .dmi_pwrite(dmi_pwrite),
    .dmi_paddr(dmi_paddr),
    .dmi_pwdata(dmi_pwdata),
    .dmi_prdata(dmi_prdata),
    .dmi_pready(dmi_pready),
    .dmi_pslverr(dmi_pslverr),
    .sys_reset_req(sys_reset_req),
    .sys_reset_done(sys_reset_done),
    .hart_reset_req(hart_reset_req),
    .hart_reset_done(hart_reset_done),
    .hart_req_halt(hart_req_halt),
    .hart_req_halt_on_reset(hart_req_halt_on_reset),
    .hart_req_resume(hart_req_resume),
    .hart_halted(hart_halted),
    .hart_running(hart_running),
    .hart_data0_rdata(hart_data0_rdata),
    .hart_data0_wdata(hart_data0_wdata),
    .hart_data0_wen(hart_data0_wen),
    .hart_instr_data(hart_instr_data),
    .hart_instr_data_vld(hart_instr_data_vld),
    .hart_instr_data_rdy(hart_instr_data_rdy),
    .hart_instr_caught_exception(hart_instr_caught_exception),
    .hart_instr_caught_ebreak(hart_instr_caught_ebreak),
    .sbus_addr(sbus_addr),
    .sbus_write(sbus_write),
    .sbus_size(sbus_size),
    .sbus_vld(sbus_vld),
    .sbus_rdy(sbus_rdy),
    .sbus_err(sbus_err),
    .sbus_wdata(sbus_wdata),
    .sbus_rdata(sbus_rdata)
);

endmodule