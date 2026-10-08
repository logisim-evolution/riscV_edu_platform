module debugTop #(
    // Where there are multiple harts per DM, the least-indexed hart is the
    // least-significant on each concatenated hart access bus.
    parameter N_HARTS      = 1,
    // Where there are multiple DMs, the address of each DM should be a
    // multiple of 'h200, so that bits[8:2] decode correctly.
    parameter NEXT_DM_ADDR = 32'h0000_0000,
    // Implement support for system bus access:
    parameter DTMCS_IDLE_HINT = 3'd4,
    parameter W_PADDR         = 9
) (
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
    output wire [N_HARTS*32-1:0]     hart_data0_rdata,
    input  wire [N_HARTS*32-1:0]     hart_data0_wdata,
    input  wire [N_HARTS-1:0]        hart_data0_wen,

    // Hart instruction injection
    output wire [N_HARTS*32-1:0]     hart_instr_data,
    output wire [N_HARTS-1:0]        hart_instr_data_vld,
    input  wire [N_HARTS-1:0]        hart_instr_data_rdy,
    input  wire [N_HARTS-1:0]        hart_instr_caught_exception,
    input  wire [N_HARTS-1:0]        hart_instr_caught_ebreak,

    // wishbone master interface, replaces System bus
    input  wire                      CLK_I,
    input  wire                      RST_I,
    input  wire [31:0]               DAT_I,
    output wire [31:0]               DAT_O,
    // TAGD_I and TAGD_O are not implemented
    input  wire                      ACK_I,
    output wire [31:0]               ADDR_O,
    output wire                      CYC_O,
    input  wire                      ERR_I,
    // LOCK_O is not implemented
    // RTY_I is not implemented
    output reg [3:0]                SEL_O,
    output wire                     STB_O,
    // TGA_O and TGC_O are not implemented
    output wire                     WE_O,
    output wire [2:0]               CTI_O // Registered feedback
    // BTE_O is not implemented
);

localparam ABITS = W_PADDR - 2; // do not modify

wire dmi_rst;
wire dmihardreset_req;
wire assert_dmi_reset;
wire dmi_psel;
wire dmi_penable;
wire dmi_pwrite;
wire [W_PADDR-1:0] dmi_paddr;
wire [31:0]        dmi_pwdata;
wire [31:0]        dmi_prdata;
wire dmi_pready;
wire dmi_pslverr;

assign assert_dmi_reset = dmihardreset_req || RST_I;

hazard3_reset_sync reset_sync (
    .clk(CLK_I),
    .rst_in(assert_dmi_reset),
    .rst_out(dmi_rst)
);

hazard3_ecp5_jtag_dtm #(
    .DTMCS_IDLE_HINT(DTMCS_IDLE_HINT),
    .W_PADDR(W_PADDR),
    .ABITS(ABITS)
) hazard3_ecp5_jtag_dtm_instance (
    .dmihardreset_req(dmihardreset_req),
    .clk_dmi(CLK_I),
    .rst_dmi(dmi_rst),
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
    .NEXT_DM_ADDR(NEXT_DM_ADDR)
) hazard3_dm_instance (
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
    .CLK_I(CLK_I),
    .RST_I(RST_I),
    .DAT_I(DAT_I),
    .DAT_O(DAT_O),
    .ACK_I(ACK_I),
    .ADDR_O(ADDR_O),
    .CYC_O(CYC_O),
    .ERR_I(ERR_I),
    .SEL_O(SEL_O),
    .STB_O(STB_O),
    .WE_O(WE_O),
    .CTI_O(CTI_O)
);

endmodule
