library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.hazard3_constants.all;

entity hazard3_core is
    generic(
        -- Standard RISC-V ISA support
        EXTENSION_A         : boolean                                                  := TRUE;  -- Atomic read/modify/write instructions
        EXTENSION_C         : boolean                                                  := TRUE;  -- Compressed (variable-width) instructions
        EXTENSION_M         : boolean                                                  := TRUE;  -- Hardware multiply/divide/modulo instructions

        -- Custom RISC-V extensions
        -- Preemptive, prioritised interrupt support. Can be disabled if an external interrupt
        -- controller (e.g. PLIC) is used. If disabled, the external interrupts are OR'd into mip.meip.
        EXTENSION_XH3IRQ    : boolean                                                  := TRUE;
        -- PMPCFGMx CSRs to enforce PMP regions in M-mode without locking
        EXTENSION_XH3PMPM   : boolean                                                  := TRUE;

        -- Standard CSR support
        CSR_M_MANDATORY     : boolean                                                  := TRUE;  -- Bare minimum CSR support e.g. misa
        CSR_M_TRAP          : boolean                                                  := TRUE;  -- M-mode trap-handling CSRs and trap support
        CSR_COUNTER         : boolean                                                  := TRUE;  -- Performance counters and Zicntr CSRs
        -- Support the U (user) execution mode. Requires: CSR_M_TRAP
        U_MODE              : boolean                                                  := FALSE;

        -- Number of physical memory protection regions, or 0 for no PMP.
        PMP_REGIONS         : natural                                                  := 0;
        -- "G" parameter in the privileged spec. Minimum PMP region size is 1 << (G + 2) bytes.
        PMP_GRAIN           : natural                                                  := 0;
        -- Enable PMP support for the NAPOT and NA4 matching modes
        PMP_MATCH_NAPOT     : boolean                                                  := TRUE;
        -- Enable PMP support for the TOR (top-of-range) matching mode
        PMP_MATCH_TOR       : boolean                                                  := FALSE;
        -- If a bit is 1, the corresponding region's pmpaddr and pmpcfg registers are read-only
        PMP_HARDWIRED       : std_logic_vector(maximum(PMP_REGIONS, 1) - 1 downto 0)      := (others => '0');
        -- Values of pmpaddr registers whose PMP_HARDWIRED bits are set to 1 (32 bits per region)
        PMP_HARDWIRED_ADDR  : std_logic_vector(32 * maximum(PMP_REGIONS, 1) - 1 downto 0) := (others => '0');
        -- Values of pmpcfg registers whose PMP_HARDWIRED bits are set to 1 (8 bits per region)
        PMP_HARDWIRED_CFG   : std_logic_vector(8 * maximum(PMP_REGIONS, 1) - 1 downto 0)  := (others => '0');

        -- Support for run/halt and instruction injection from an external Debug Module, support
        -- for Debug Mode, and Debug Mode CSRs. Requires: CSR_M_MANDATORY, CSR_M_TRAP
        DEBUG_SUPPORT       : boolean                                                  := TRUE;
        -- Number of triggers which support type=2 execute=1. Requires: DEBUG_SUPPORT
        BREAKPOINT_TRIGGERS : natural                                                  := 8;

        -- Number of external IRQs. Note that if EXTENSION_XH3IRQ (IRQ Controller) is disabled, then
        -- multiple external interrupts are OR'd into mip.meip
        NUMBER_OF_IRQs      : integer range 1 to MAX_NUMBER_OF_IRQ_C                   := 8;
        -- Number of priority bits implemented for each interrupt in meipra
        IRQ_PRIORITY_BITS   : integer range 0 to 4                                     := 0;
        -- Disable the input registers on the external interrupts, IRQ-by-IRQ
        IRQ_INPUTREG_BYPASS : boolean_vector(NUMBER_OF_IRQs - 1 downto 0)              := (others => FALSE);

        -- Performance/size options
        -- Remove all forwarding paths except X->X, to save area
        REDUCED_BYPASS      : boolean                                                  := FALSE;
        -- Bits per clock for multiply/divide circuit, if present. Must be a power of 2.
        MULDIV_UNROLL       : positive                                                 := 2;
        -- Single-cycle multiply circuit for MUL instructions, retiring to stage 3
        MUL_FAST            : boolean                                                  := TRUE;
        -- Retire fast multiply results to stage 2 instead of stage 3. Requires: MUL_FAST
        MUL_FASTER          : boolean                                                  := TRUE;
        -- Extend the fast multiply circuit to also cover MULH*. Requires: MUL_FAST
        MULH_FAST           : boolean                                                  := TRUE;
        -- Separate comparator for branch comparisons, rather than using the ALU
        FAST_BRANCHCMP      : boolean                                                  := TRUE;
        -- Single-entry BTB, allocated on a taken backward branch
        BRANCH_PREDICTOR    : boolean                                                  := TRUE
    );
    port(
        -- Global signals
        clk           : in std_logic;
        clk_always_on : in std_logic;
        rst           : in std_logic;

        -- Address of first instruction executed
        reset_vector  : in std_logic_vector(31 downto 0);
        -- Initial value of trap vector base. Bits clear in MTVEC_WRITE_MASK_C will never change
        -- from this initial value. Bit 0 selects the vectoring mode (0: unvectored, 1: vectored).
        mtvec_init    : in std_logic_vector(31 downto 0);

        -- Power control signals
        pwrup_req   : out std_logic;
        pwrup_ack   : in  std_logic;
        clk_en      : out std_logic;
        unblock_out : out std_logic;
        unblock_in  : in  std_logic;

        -- Instruction fetch port
        bus_aph_req_i   : out std_logic;
        bus_aph_panic_i : out std_logic; -- e.g. branch mispredict + flush
        bus_aph_ready_i : in  std_logic;
        bus_dph_ready_i : in  std_logic;
        bus_dph_err_i   : in  std_logic;

        bus_haddr_i : out std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0);
        bus_hsize_i : out std_logic_vector(2 downto 0);
        bus_priv_i  : out std_logic;
        bus_rdata_i : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);

        -- Load/Store port
        bus_aph_req_d    : out std_logic;
        bus_aph_excl_d   : out std_logic;
        bus_aph_ready_d  : in  std_logic;
        bus_dph_ready_d  : in  std_logic;
        bus_dph_err_d    : in  std_logic;
        bus_dph_exokay_d : in  std_logic;

        bus_haddr_d  : out std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0);
        bus_hsize_d  : out std_logic_vector(2 downto 0);
        bus_priv_d   : out std_logic;
        bus_hwrite_d : out std_logic;
        bus_wdata_d  : out std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        bus_rdata_d  : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);

        -- Memory ordering signals
        fence_i_vld : out std_logic;
        fence_d_vld : out std_logic;
        fence_rdy   : in  std_logic;

        -- Debugger run/halt control
        dbg_req_halt          : in  std_logic;
        dbg_req_halt_on_reset : in  std_logic;
        dbg_req_resume        : in  std_logic;
        dbg_halted            : out std_logic;
        dbg_running           : out std_logic;

        -- Debugger access to data0 CSR
        dbg_data0_rdata : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        dbg_data0_wdata : out std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        dbg_data0_wen   : out std_logic;

        -- Debugger instruction injection
        dbg_instr_data             : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        dbg_instr_data_vld         : in  std_logic;
        dbg_instr_data_rdy         : out std_logic;
        dbg_instr_caught_exception : out std_logic;
        dbg_instr_caught_ebreak    : out std_logic;

        -- Identification CSR values
        mhartid_val : in std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        eco_version : in std_logic_vector(3 downto 0);

        -- Level-sensitive interrupt sources
        irq       : in std_logic_vector(NUMBER_OF_IRQs - 1 downto 0); --> mip.meip
        soft_irq  : in std_logic;                                     --> mip.msip
        timer_irq : in std_logic                                      --> mip.mtip
    );
end entity hazard3_core;

architecture rtl of hazard3_core is

    constant HSIZE_WORD  : std_logic_vector(2 downto 0) := "010";
    constant HSIZE_HWORD : std_logic_vector(2 downto 0) := "001";
    constant HSIZE_BYTE  : std_logic_vector(2 downto 0) := "000";


    signal x_stall    : std_logic;
    signal m_stall    : std_logic;
    signal debug_mode : std_logic;

    -- ============================================================================
    -- Pipe Stage F signals
    -- ============================================================================
    signal f_jump_req    : std_logic;
    signal f_jump_target : std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0);
    signal f_jump_priv   : std_logic;
    signal f_jump_rdy    : std_logic;
    signal f_jump_now    : std_logic;

    signal f_frontend_pwrdown_ok : std_logic;
    signal f_delay_first_fetch   : std_logic;

    -- Predecoded register numbers, for register file access
    signal f_rs1_coarse : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
    signal f_rs2_coarse : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
    signal f_rs1_fine   : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
    signal f_rs2_fine   : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);

    signal fd_cir                  : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
    signal fd_cir_raw              : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
    signal fd_cir_err              : std_logic_vector(1 downto 0);
    signal fd_cir_break_any        : std_logic;
    signal fd_cir_break_d_mode     : std_logic;
    signal fd_cir_predbranch       : std_logic_vector(1 downto 0);
    signal fd_cir_vld              : std_logic_vector(1 downto 0);
    signal fd_cir_is_32bit         : std_logic;
    signal fd_cir_invalid_16bit    : std_logic;
    signal fd_cir_is_uop           : std_logic;
    signal fd_cir_uop_nonfinal     : std_logic;
    signal fd_cir_uop_no_pc_update : std_logic;
    signal fd_cir_uop_atomic       : std_logic;

    signal df_cir_use           : std_logic_vector(1 downto 0);
    signal df_cir_flush_behind  : std_logic;

    signal df_uop_stall         : std_logic;
    signal df_uop_clear         : std_logic;
    signal df_lspair_phase_next : std_logic;

    signal x_btb_set             : std_logic;
    signal x_btb_set_src_addr    : std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0);
    signal x_btb_set_src_size    : std_logic;
    signal x_btb_set_target_addr : std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0);
    signal x_btb_clear           : std_logic;

    signal d_btb_target_addr : unsigned(ADDRESS_WIDTH_C - 1 downto 0);

    signal f_pmp_i_addr   : unsigned(ADDRESS_WIDTH_C - 1 downto 0);
    signal f_pmp_i_m_mode : std_logic;
    signal f_pmp_i_kill   : std_logic;

    signal f_trigger_addr         : unsigned(ADDRESS_WIDTH_C - 1 downto 0);
    signal f_trigger_m_mode       : std_logic;
    signal f_trigger_break_any    : std_logic_vector(1 downto 0);
    signal f_trigger_break_d_mode : std_logic_vector(1 downto 0);

    signal f_mem_size : std_logic;
    signal f_mem_addr : unsigned(ADDRESS_WIDTH_C - 1 downto 0);

    -- ============================================================================
    -- Pipe Stage X (Decode Logic) signals
    -- ============================================================================
    signal d_starved         : std_logic;
    signal d_imm             : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal d_rs1             : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
    signal d_rs2             : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
    signal d_rd              : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
    signal d_funct3_32b      : std_logic_vector(2 downto 0);
    signal d_funct7_32b      : std_logic_vector(6 downto 0);
    signal d_alusrc_a        : std_logic_vector(ALU_SOURCE_WIDTH_C - 1 downto 0);
    signal d_alusrc_b        : std_logic_vector(ALU_SOURCE_WIDTH_C - 1 downto 0);
    signal d_aluop           : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
    signal d_memop           : std_logic_vector(MEMOP_WIDTH_C - 1 downto 0);
    signal d_mulop           : std_logic_vector(MULOP_WIDTH_C - 1 downto 0);
    signal d_branchcond      : std_logic_vector(BRANCH_CONDITION_WIDTH_C - 1 downto 0);
    signal d_addr_offs       : std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0);
    signal d_addr_is_regoffs : std_logic;
    signal d_pc              : std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0);
    signal d_except          : std_logic_vector(EXCEPTION_WIDTH_C - 1 downto 0);
    signal d_sleep_wfi       : std_logic;
    signal d_sleep_block     : std_logic;
    signal d_sleep_unblock   : std_logic;
    signal d_no_pc_increment : std_logic;
    signal d_uninterruptible : std_logic;
    signal d_fence_i         : std_logic;
    signal d_fence_d         : std_logic;
    signal d_csr_ren         : std_logic;
    signal d_csr_wen         : std_logic;
    signal d_csr_wtype       : std_logic_vector(1 downto 0);
    signal d_csr_w_imm       : std_logic;
    signal d_lspair_offset   : std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0);

    signal x_jump_not_except : std_logic;
    signal x_mmode_execution : std_logic;
    signal x_trap_wfi        : std_logic;

    signal debug_dpc_wdata : std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0);
    signal debug_dpc_wen   : std_logic;
    signal debug_dpc_rdata : std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0);

    -- ============================================================================
    -- Pipe Stage X (Execution Logic) signals
    -- ============================================================================
    -- Register the write which took place to the regfile on previous cycle, and bypass.
    -- This is an alternative to a write -> read bypass in the regfile,
    -- which we can't implement whilst maintaining BRAM inference compatibility (iCE40).
    signal mw_rd_reg     : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
    signal mw_result_reg : std_logic_vector(DATA_WIDTH_C - 1 downto 0);

    -- From register file:
    signal x_rdata1 : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal x_rdata2 : std_logic_vector(DATA_WIDTH_C - 1 downto 0);

    -- Combinational signals for muxing
    signal x_rs1_bypass : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal x_rs2_bypass : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal x_op_a       : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal x_op_b       : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal x_alu_result : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal x_alu_cmp    : std_logic;

    signal m_trap_addr       : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal m_trap_is_irq     : std_logic;
    signal m_trap_enter_vld  : std_logic;
    signal m_trap_enter_soon : std_logic;
    signal m_trap_enter_rdy  : std_logic;
    signal m_trap_enter_now  : std_logic;

    signal x_mmode_loadstore  : std_logic;
    signal m_mmode_trap_entry : std_logic;

    signal xm_rs1_reg                          : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
    signal xm_rs2_reg                          : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
    signal xm_rd_reg                           : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
    signal xm_result_reg                       : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal xm_addr_align_reg                   : std_logic_vector(1 downto 0);
    signal xm_memop_reg                        : std_logic_vector(MEMOP_WIDTH_C - 1 downto 0);
    signal xm_except_reg                       : std_logic_vector(EXCEPTION_WIDTH_C - 1 downto 0);
    signal xm_except_to_d_mode_reg             : std_logic;
    signal xm_sleep_wfi_reg                    : std_logic;
    signal xm_sleep_block_reg                  : std_logic;
    signal xm_delay_irq_entry_on_ls_stagex_reg : std_logic;
    signal unblock_out_reg                     : std_logic;

    -- ============================================================================
    -- Stall logic signals
    -- ============================================================================
    signal x_stall_on_trap              : std_logic;
    signal d_memop_is_amo               : std_logic;
    signal x_stall_on_exclusive_overlap : std_logic;
    signal x_amo_phase_reg              : unsigned(2 downto 0);
    signal x_stall_on_amo               : std_logic;
    signal m_fast_mul_result_vld        : std_logic;
    signal m_generating_result          : std_logic;
    signal x_stall_on_raw               : std_logic;
    signal x_stall_on_fence             : std_logic;
    signal x_stall_muldiv               : std_logic;
    signal x_jump_req                   : std_logic;
    signal m_sleep_stall_release        : std_logic;
    signal x_loadstore_pmp_fail         : std_logic;
    signal x_trig_step_break            : std_logic;
    signal x_trig_break                 : std_logic;
    signal x_trig_break_d_mode          : std_logic;

    -- ============================================================================
    -- Execution logic signals
    -- ============================================================================
    -- Approximate regnums predecoded in stage 1, for the bypass mux
    signal d_rs1_predecoded_reg : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
    signal d_rs2_predecoded_reg : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
    signal d_rs1_predecoded_nxt : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
    signal d_rs2_predecoded_nxt : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);

    signal xm_rd_nxt : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
    signal mw_rd_nxt : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);

    -- One-hot select of the bypass source: (2) register file, (1) xm_result, (0) mw_result
    signal x_rs1_select_regs_xm_mw_reg : std_logic_vector(2 downto 0);
    signal x_rs2_select_regs_xm_mw_reg : std_logic_vector(2 downto 0);

    -- Load/store bus request
    signal x_unaligned_addr                : std_logic;
    signal mw_local_exclusive_reserved_reg : std_logic;
    signal x_memop_vld                     : std_logic;
    signal x_memop_write                   : std_logic;
    signal x_addr_addend                   : std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0);
    signal x_addr_sum                      : std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0);

    -- Fences
    signal m_dphase_in_flight : std_logic;
    signal x_fence_mask       : std_logic;

    -- Multiply/divide
    signal x_muldiv_result   : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal m_fast_mul_result : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal x_use_fast_mul    : std_logic;

    -- Branch handling
    signal x_jump_target          : std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0);
    signal x_jump_misaligned      : std_logic;
    signal x_branch_cmp_noinvert  : std_logic;
    signal x_branch_was_predicted : std_logic;
    signal x_branch_cmp           : std_logic;
    signal x_jump_req_unchecked   : std_logic;

    -- Memory protection
    signal x_pmp_cfg_addr  : unsigned(CSR_ADDRESS_WIDTH_C - 1 downto 0);
    signal x_pmp_cfg_wen   : std_logic;
    signal x_pmp_cfg_wdata : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal x_pmp_cfg_rdata : std_logic_vector(DATA_WIDTH_C - 1 downto 0);

    -- Triggers
    signal x_trig_cfg_addr  : unsigned(CSR_ADDRESS_WIDTH_C - 1 downto 0);
    signal x_trig_cfg_wen   : std_logic;
    signal x_trig_cfg_wdata : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal x_trig_cfg_rdata : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal x_trig_m_en      : std_logic;

    signal m_trig_event_interrupt  : std_logic;
    signal m_trig_event_exception  : std_logic;
    signal m_trig_event_trap_cause : std_logic_vector(3 downto 0);

    signal x_instr_ret : std_logic;

    -- CSRs and Trap Handling
    signal x_csr_wdata                  : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal x_csr_rdata                  : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal x_csr_illegal_access         : std_logic;
    signal x_csr_write_is_fetch_ordered : std_logic;
    signal x_csr_wen_soon               : std_logic;
    signal x_csr_wen                    : std_logic;
    signal x_csr_ren_soon               : std_logic;
    signal x_csr_ren                    : std_logic;

    -- "Previous" refers to next-most-recent instruction to be in D/X, i.e. the
    -- most recent instruction to reach stage M (which may or may not still be in M).
    signal prev_instr_was_32_bit_reg : std_logic;

    signal m_exception_return_addr : std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0);
    signal m_exception_return_offs : unsigned(2 downto 0);

    signal x_except                  : std_logic_vector(EXCEPTION_WIDTH_C - 1 downto 0);
    signal x_except_counts_as_retire : std_logic;

    signal m_delay_irq_entry       : std_logic;
    signal m_csr_delay_irq_entry   : std_logic;
    signal m_csr_access_mask_early : std_logic;
    signal m_csr_access_mask       : std_logic;

    signal m_pwr_allow_clkgate        : std_logic;
    signal m_pwr_allow_power_down     : std_logic;
    signal m_pwr_allow_sleep_on_block : std_logic;
    signal m_wfi_wakeup_req           : std_logic;
    signal m_clear_excl_on_trap_exit  : std_logic;

    -- ============================================================================
    -- Pipe Stage M signals
    -- ============================================================================
    signal m_rdata_pick_sext : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal m_wdata           : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal m_result          : std_logic_vector(DATA_WIDTH_C - 1 downto 0);

    signal m_bus_stall          : std_logic;
    signal m_reg_wen_if_nonzero : std_logic;
    signal m_reg_wen            : std_logic;

    signal x_regfile_raddr1 : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
    signal x_regfile_raddr2 : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);

begin

    dbg_halted  <= to_std_logic(DEBUG_SUPPORT) and debug_mode;
    dbg_running <= to_std_logic(DEBUG_SUPPORT) and not debug_mode;

    ---------------------------------------------------------------------------
    -- Pipe Stage F

    f_jump_now <= f_jump_req and f_jump_rdy;

    bus_aph_panic_i <= '0';

    bus_hsize_i <= HSIZE_WORD when ?? f_mem_size else HSIZE_HWORD;
    bus_haddr_i <= std_logic_vector(f_mem_addr);

    f_delay_first_fetch <= not pwrup_ack;

    frontend : entity work.hazard3_frontend
        generic map(
            PMP_REGIONS      => PMP_REGIONS,
            EXTENSION_C      => EXTENSION_C,
            EXTENSION_M      => EXTENSION_M,
            U_MODE           => U_MODE,
            DEBUG_SUPPORT    => DEBUG_SUPPORT,
            BRANCH_PREDICTOR => BRANCH_PREDICTOR
        )
        port map(
            clk                  => clk,
            rst                  => rst,

            reset_vector         => reset_vector,

            mem_size             => f_mem_size,
            mem_addr             => f_mem_addr,
            mem_priv             => bus_priv_i,
            mem_addr_vld         => bus_aph_req_i,
            mem_addr_rdy         => bus_aph_ready_i,

            mem_data             => bus_rdata_i,
            mem_data_err         => bus_dph_err_i,
            mem_data_vld         => bus_dph_ready_i,

            jump_target          => unsigned(f_jump_target),
            jump_priv            => f_jump_priv,
            jump_target_vld      => f_jump_req,
            jump_target_rdy      => f_jump_rdy,

            btb_set              => x_btb_set,
            btb_set_src_addr     => unsigned(x_btb_set_src_addr),
            btb_set_src_size     => x_btb_set_src_size,
            btb_set_target_addr  => unsigned(x_btb_set_target_addr),
            btb_clear            => x_btb_clear,
            btb_target_addr_out  => d_btb_target_addr,

            cir                  => fd_cir,
            cir_raw              => fd_cir_raw,
            cir_err              => fd_cir_err,
            cir_predbranch       => fd_cir_predbranch,
            cir_break_any        => fd_cir_break_any,
            cir_break_d_mode     => fd_cir_break_d_mode,
            cir_vld              => fd_cir_vld,
            cir_is_32bit         => fd_cir_is_32bit,
            cir_invalid_16bit    => fd_cir_invalid_16bit,
            cir_is_uop           => fd_cir_is_uop,
            cir_uop_nonfinal     => fd_cir_uop_nonfinal,
            cir_uop_no_pc_update => fd_cir_uop_no_pc_update,
            cir_uop_atomic       => fd_cir_uop_atomic,

            cir_use              => df_cir_use,
            cir_flush_behind     => df_cir_flush_behind,
            uop_stall            => df_uop_stall,
            uop_clear            => df_uop_clear,
            df_lspair_phase_next => df_lspair_phase_next,

            pwrdown_ok           => f_frontend_pwrdown_ok,
            delay_first_fetch    => f_delay_first_fetch,

            predecode_rs1_coarse => f_rs1_coarse,
            predecode_rs2_coarse => f_rs2_coarse,
            predecode_rs1_fine   => f_rs1_fine,
            predecode_rs2_fine   => f_rs2_fine,

            debug_mode           => debug_mode,
            dbg_instr_data       => dbg_instr_data,
            dbg_instr_data_vld   => dbg_instr_data_vld,
            dbg_instr_data_rdy   => dbg_instr_data_rdy,

            pmp_i_addr           => f_pmp_i_addr,
            pmp_i_m_mode         => f_pmp_i_m_mode,
            pmp_i_kill           => f_pmp_i_kill,

            trigger_addr         => f_trigger_addr,
            trigger_m_mode       => f_trigger_m_mode,
            trigger_break_any    => f_trigger_break_any,
            trigger_break_d_mode => f_trigger_break_d_mode
        );

    ---------------------------------------------------------------------------
    -- Pipe Stage X (Decode Logic)

    decode_u : entity work.hazard3_decode
        generic map(
            EXTENSION_A      => EXTENSION_A,
            EXTENSION_C      => EXTENSION_C,
            EXTENSION_M      => EXTENSION_M,
            CSR_M_MANDATORY  => CSR_M_MANDATORY,
            CSR_M_TRAP       => CSR_M_TRAP,
            CSR_COUNTER      => CSR_COUNTER,
            U_MODE           => U_MODE,
            DEBUG_SUPPORT    => DEBUG_SUPPORT,
            BRANCH_PREDICTOR => BRANCH_PREDICTOR
        )
        port map(
            clk                     => clk,
            rst                     => rst,

            reset_vector            => reset_vector,

            fd_cir                  => fd_cir,
            fd_cir_err              => fd_cir_err,
            fd_cir_predbranch       => fd_cir_predbranch,
            fd_cir_vld              => fd_cir_vld,
            fd_cir_is_32bit         => fd_cir_is_32bit,
            fd_cir_invalid_16bit    => fd_cir_invalid_16bit,
            fd_cir_is_uop           => fd_cir_is_uop,
            fd_cir_uop_nonfinal     => fd_cir_uop_nonfinal,
            fd_cir_uop_no_pc_update => fd_cir_uop_no_pc_update,
            fd_cir_uop_atomic       => fd_cir_uop_atomic,

            df_cir_use              => df_cir_use,
            df_cir_flush_behind     => df_cir_flush_behind,
            df_uop_stall            => df_uop_stall,
            df_uop_clear            => df_uop_clear,
            df_lspair_phase_next    => df_lspair_phase_next,

            d_pc                    => d_pc,
            x_jump_not_except       => x_jump_not_except,

            debug_mode              => debug_mode,
            m_mode                  => x_mmode_execution,
            trap_wfi                => x_trap_wfi,

            debug_dpc_wdata         => debug_dpc_wdata,
            debug_dpc_wen           => debug_dpc_wen,
            debug_dpc_rdata         => debug_dpc_rdata,

            d_starved               => d_starved,
            x_stall                 => x_stall,
            f_jump_now              => f_jump_now,
            f_jump_target           => f_jump_target,
            d_btb_target_addr       => std_logic_vector(d_btb_target_addr),

            d_imm                   => d_imm,
            d_rs1                   => d_rs1,
            d_rs2                   => d_rs2,
            d_rd                    => d_rd,
            d_funct3_32b            => d_funct3_32b,
            d_funct7_32b            => d_funct7_32b,
            d_alusrc_a              => d_alusrc_a,
            d_alusrc_b              => d_alusrc_b,
            d_aluop                 => d_aluop,
            d_memop                 => d_memop,
            d_mulop                 => d_mulop,
            d_csr_ren               => d_csr_ren,
            d_csr_wen               => d_csr_wen,
            d_csr_wtype             => d_csr_wtype,
            d_csr_w_imm             => d_csr_w_imm,
            d_branchcond            => d_branchcond,
            d_addr_offs             => d_addr_offs,
            d_addr_is_regoffs       => d_addr_is_regoffs,
            d_except                => d_except,
            d_sleep_wfi             => d_sleep_wfi,
            d_sleep_block           => d_sleep_block,
            d_sleep_unblock         => d_sleep_unblock,
            d_no_pc_increment       => d_no_pc_increment,
            d_uninterruptible       => d_uninterruptible,
            d_lspair_offset         => d_lspair_offset,
            d_fence_i               => d_fence_i,
            d_fence_d               => d_fence_d
        );

    ---------------------------------------------------------------------------
    -- Pipe Stage X (Execution Logic)

    m_trap_enter_rdy <= f_jump_rdy;
    m_trap_enter_now <= m_trap_enter_vld and m_trap_enter_rdy;

    ---------------------------------------------------------------------------
    -- Stall logic

    -- IRQs squeeze in between the instructions in X and M, so in this case X
    -- stalls but M can continue. -> X always stalls on M trap, M *may* stall.
    x_stall_on_trap <= (m_trap_enter_vld and not m_trap_enter_rdy) or
                       (m_trap_enter_soon and not m_trap_enter_vld);

    -- Stall inserted to avoid illegal pipelining of exclusive accesses on the bus
    -- (also gives time to update local monitor on direct lr.w -> sc.w instruction
    -- sequences). Note we don't check for AMOs in stage M, because AMOs fully
    -- fence off on their own completion before passing down the pipe.
    d_memop_is_amo <= '1' when EXTENSION_A and d_memop = MEMOP_C.ATOMIC_MEM_OP else '0';

    x_stall_on_exclusive_overlap <= '1' when EXTENSION_A and
        (d_memop_is_amo = '1' or d_memop = MEMOP_C.STORE_CONDITIONAL_WORD or d_memop = MEMOP_C.LOAD_RESERVED_WORD) and
        (xm_memop_reg = MEMOP_C.STORE_CONDITIONAL_WORD or xm_memop_reg = MEMOP_C.LOAD_RESERVED_WORD) else '0';

    -- AMOs are issued completely from X. We keep X stalled, and pass bubbles into
    -- M. Otherwise the exception handling would be even more of a mess. Phases
    -- 0-3 are read/write address/data phases. Phase 4 is error, due to HRESP or
    -- due to low HEXOKAY response to read.

    -- Also need to clear AMO if it follows an excepting instruction. Note we
    -- still stall on phase 3 when hready is high if hresp is also high, since we
    -- then proceed to phase 4 for the error response.
    x_stall_on_amo <= '1' when EXTENSION_A and d_memop_is_amo = '1' and m_trap_enter_soon = '0' and (
        x_amo_phase_reg < 3 or
        (x_amo_phase_reg = 3 and (bus_dph_ready_d = '0' or bus_dph_exokay_d = '0' or bus_dph_err_d = '1'))
    ) else '0';

    -- Read-after-write hazard detection (e.g. load-use)
    m_generating_result <= '1' when
        unsigned(xm_memop_reg) < unsigned(MEMOP_C.STORE_WORD) or
        (EXTENSION_A and xm_memop_reg = MEMOP_C.LOAD_RESERVED_WORD) or
        (EXTENSION_A and xm_memop_reg = MEMOP_C.STORE_CONDITIONAL_WORD) or -- sc.w success result is data phase
        (EXTENSION_M and m_fast_mul_result_vld = '1') else '0';

    X_STALL_ON_RAW_P : process(all) is
    begin
        x_stall_on_raw <= '0';
        if REDUCED_BYPASS then
            if ((or xm_rd_reg) = '1' and (xm_rd_reg = d_rs1 or xm_rd_reg = d_rs2)) or
               ((or mw_rd_reg) = '1' and (mw_rd_reg = d_rs1 or mw_rd_reg = d_rs2)) then
                x_stall_on_raw <= '1';
            end if;
        elsif ?? m_generating_result then
            -- With the full bypass network, load-use (or fast multiply-use) is the only RAW stall
            if (or xm_rd_reg) = '1' and xm_rd_reg = d_rs1 then
                -- Store addresses cannot be bypassed later, so there is no exception here.
                x_stall_on_raw <= '1';
            elsif (or xm_rd_reg) = '1' and xm_rd_reg = d_rs2 then
                -- Store data can be bypassed in M. Any other instructions must stall.
                x_stall_on_raw <= '0' when d_memop = MEMOP_C.STORE_WORD or
                                           d_memop = MEMOP_C.STORE_HALF or
                                           d_memop = MEMOP_C.STORE_BYTE else '1';
            end if;
        end if;
    end process X_STALL_ON_RAW_P;

    x_stall <= m_stall or
               x_stall_on_trap or
               x_stall_on_exclusive_overlap or
               x_stall_on_amo or
               x_stall_on_raw or
               x_stall_on_fence or
               x_stall_muldiv or
               (bus_aph_req_d and not bus_aph_ready_d) or
               (x_jump_req and not f_jump_rdy);

    x_trig_break        <= fd_cir_break_any or x_trig_step_break;
    x_trig_break_d_mode <= fd_cir_break_d_mode;

    ---------------------------------------------------------------------------
    -- Execution logic

    -- ALU, operand muxes and bypass

    -- Approximate regnums were predecoded in stage 1, for regfile read.
    -- (Approximate in the sense that they are invalid when the instruction
    -- doesn't *have* a register operand on that port.) These aren't usable for
    -- hazard checking but are fine for bypass, and make the bypass mux
    -- independent of stage 2 decode.
    PREDECODED_REGS : process(clk) is
    begin
        if rising_edge(clk) then
            if ?? rst then
                d_rs1_predecoded_reg <= (others => '0');
                d_rs2_predecoded_reg <= (others => '0');
            elsif ?? (d_starved or not x_stall) then
                d_rs1_predecoded_reg <= f_rs1_fine;
                d_rs2_predecoded_reg <= f_rs2_fine;
            end if;
        end if;
    end process PREDECODED_REGS;

    d_rs1_predecoded_nxt <= f_rs1_fine when ?? (d_starved or not x_stall) else d_rs1_predecoded_reg;
    d_rs2_predecoded_nxt <= f_rs2_fine when ?? (d_starved or not x_stall) else d_rs2_predecoded_reg;

    BYPASS_SELECT : process(clk) is
    begin
        if rising_edge(clk) then
            if ?? rst then
                x_rs1_select_regs_xm_mw_reg <= "000";
                x_rs2_select_regs_xm_mw_reg <= "000";
            else
                x_rs1_select_regs_xm_mw_reg <= "000" when d_rs1_predecoded_nxt = "00000"    else
                                               "010" when xm_rd_nxt = d_rs1_predecoded_nxt else
                                               "001" when mw_rd_nxt = d_rs1_predecoded_nxt else "100";
                x_rs2_select_regs_xm_mw_reg <= "000" when d_rs2_predecoded_nxt = "00000"    else
                                               "010" when xm_rd_nxt = d_rs2_predecoded_nxt else
                                               "001" when mw_rd_nxt = d_rs2_predecoded_nxt else "100";
            end if;
        end if;
    end process BYPASS_SELECT;

    x_rs1_bypass <= (x_rdata1      and x_rs1_select_regs_xm_mw_reg(2)) or
                    (xm_result_reg and x_rs1_select_regs_xm_mw_reg(1)) or
                    (mw_result_reg and x_rs1_select_regs_xm_mw_reg(0));

    x_rs2_bypass <= (x_rdata2      and x_rs2_select_regs_xm_mw_reg(2)) or
                    (xm_result_reg and x_rs2_select_regs_xm_mw_reg(1)) or
                    (mw_result_reg and x_rs2_select_regs_xm_mw_reg(0));

    -- AMO captures rdata into mw_result at end of read data phase, so we can
    -- feed back through the ALU.
    x_op_a <= mw_result_reg when EXTENSION_A and x_amo_phase_reg = 2 else
              d_pc          when d_alusrc_a = ALUSRCA_C.PC             else
              x_rs1_bypass;

    x_op_b <= d_imm when d_alusrc_b = ALUSRCB_C.IMM else x_rs2_bypass;

    alu : entity work.hazard3_alu
        generic map(
            EXTENSION_A => EXTENSION_A
        )
        port map(
            aluop  => d_aluop,
            op_a   => x_op_a,
            op_b   => x_op_b,
            result => x_alu_result,
            cmp    => x_alu_cmp
        );

    -- Load/store bus request

    x_unaligned_addr <= '1' when d_memop /= MEMOP_C.NONE and (
        (bus_hsize_d = HSIZE_WORD  and (or bus_haddr_d(1 downto 0)) = '1') or
        (bus_hsize_d = HSIZE_HWORD and bus_haddr_d(0) = '1')
    ) else '0';

    x_memop_vld <= '1' when d_memop /= MEMOP_C.NONE and not (
        (EXTENSION_A and d_memop = MEMOP_C.STORE_CONDITIONAL_WORD and mw_local_exclusive_reserved_reg = '0') or
        (EXTENSION_A and d_memop_is_amo = '1' and x_amo_phase_reg /= 0 and x_amo_phase_reg /= 2)
    ) else '0';

    x_memop_write <= '1' when
        d_memop = MEMOP_C.STORE_WORD or
        d_memop = MEMOP_C.STORE_HALF or
        d_memop = MEMOP_C.STORE_BYTE or
        (EXTENSION_A and d_memop = MEMOP_C.STORE_CONDITIONAL_WORD) or
        (EXTENSION_A and d_memop_is_amo = '1' and x_amo_phase_reg = 2) else '0';

    -- Always query the global monitor, except for store-conditional suppressed by local monitor.
    bus_aph_excl_d <= '1' when EXTENSION_A and (
        d_memop = MEMOP_C.LOAD_RESERVED_WORD or
        d_memop = MEMOP_C.STORE_CONDITIONAL_WORD or
        d_memop_is_amo = '1'
    ) else '0';

    -- AMO stalls the pipe, then generates two bus transfers per 4-cycle
    -- iteration, unless it bails out due to a bus fault or failed load
    -- reservation.
    AMO_PHASE : process(clk) is
    begin
        if rising_edge(clk) then
            if ?? rst then
                x_amo_phase_reg <= "000";
            else
                if not EXTENSION_A then
                    -- Without atomics the phase stays 0. Assigned anyway, as a register that is only
                    -- assigned in the reset branch would be inferred as a latch by GHDL.
                    x_amo_phase_reg <= "000";
                elsif d_memop_is_amo = '1' and (
                    (bus_aph_ready_d or bus_dph_ready_d or m_trap_enter_vld or x_unaligned_addr or x_loadstore_pmp_fail) = '1' or
                    x_amo_phase_reg = 4
                ) then
                    if ?? m_trap_enter_vld then
                        -- Bail out, squash the in-progress AMO.
                        x_amo_phase_reg <= "000";
                    elsif ?? (x_stall_on_raw or x_stall_on_exclusive_overlap or m_trap_enter_soon) then
                        -- First address phase stalled due to address dependency on
                        -- previous load/mul/etc. Shouldn't be possible in later phases.
                        x_amo_phase_reg <= "000";
                    elsif x_amo_phase_reg = 4 then
                        -- Clear fault phase once it goes through to stage 3 and excepts
                        if not x_stall then
                            x_amo_phase_reg <= "000";
                        end if;
                    elsif ?? (x_unaligned_addr or x_loadstore_pmp_fail) then
                        x_amo_phase_reg <= "100";
                    elsif x_amo_phase_reg = 1 and bus_dph_exokay_d = '0' then
                        -- Load reserve fail indicates the memory region does not support
                        -- exclusives, so we will never succeed at store. Exception.
                        x_amo_phase_reg <= "100";
                    elsif (x_amo_phase_reg = 1 or x_amo_phase_reg = 3) and bus_dph_err_d = '1' then
                        -- Bus fault. Exception.
                        x_amo_phase_reg <= "100";
                    elsif x_amo_phase_reg = 3 then
                        -- Either we're done, or the write failed. Either way, back to the start.
                        x_amo_phase_reg <= "000";
                    else
                        -- Default progression: read addr -> read data -> write addr -> write data
                        x_amo_phase_reg <= x_amo_phase_reg + 1;
                    end if;
                end if;
            end if;
        end if;
    end process AMO_PHASE;

    -- This adder is used for both branch targets and load/store addresses.
    -- Supporting all branch types already requires rs1 + I-fmt, and pc + B-fmt.
    -- B-fmt are almost identical to S-fmt, so we rs1 + S-fmt is almost free.
    x_addr_addend <= x_rs1_bypass when ?? d_addr_is_regoffs else d_pc;
    x_addr_sum    <= std_logic_vector(unsigned(x_addr_addend) + unsigned(d_addr_offs));

    BUS_REQUEST : process(all) is
    begin
        -- Need to be careful not to use anything hready-sourced to gate htrans!
        bus_haddr_d  <= x_addr_sum;
        bus_hwrite_d <= x_memop_write;
        bus_priv_d   <= x_mmode_loadstore;
        case? d_memop is
            when MEMOP_C.LOAD_WORD          => bus_hsize_d <= HSIZE_WORD;
            when MEMOP_C.STORE_WORD         => bus_hsize_d <= HSIZE_WORD;
            when MEMOP_C.LOAD_HALF          => bus_hsize_d <= HSIZE_HWORD;
            when MEMOP_C.LOAD_HALF_UNSIGNED => bus_hsize_d <= HSIZE_HWORD;
            when MEMOP_C.STORE_HALF         => bus_hsize_d <= HSIZE_HWORD;
            when MEMOP_C.LOAD_BYTE          => bus_hsize_d <= HSIZE_BYTE;
            when MEMOP_C.LOAD_BYTE_UNSIGNED => bus_hsize_d <= HSIZE_BYTE;
            when MEMOP_C.STORE_BYTE         => bus_hsize_d <= HSIZE_BYTE;
            when others                     => bus_hsize_d <= HSIZE_WORD;
        end case?;
        bus_aph_req_d <= x_memop_vld and not (
            x_stall_on_raw or
            x_stall_on_exclusive_overlap or
            x_loadstore_pmp_fail or
            x_trig_break or
            x_unaligned_addr or
            m_trap_enter_soon or
            ((xm_sleep_wfi_reg or xm_sleep_block_reg) and not m_sleep_stall_release)
        );
    end process BUS_REQUEST;

    -- Fences are not issued until relevant buses are quiet.
    x_stall_on_fence <= (d_fence_i and not (fence_rdy and not m_dphase_in_flight and f_frontend_pwrdown_ok)) or
                        (d_fence_d and not (fence_rdy and not m_dphase_in_flight));

    x_fence_mask <= x_trig_break or
                    m_dphase_in_flight or
                    m_trap_enter_soon or
                    ((xm_sleep_wfi_reg or xm_sleep_block_reg) and not m_sleep_stall_release);

    fence_i_vld <= d_fence_i and not x_fence_mask and f_frontend_pwrdown_ok;
    fence_d_vld <= d_fence_d and not x_fence_mask;

    -- Multiply/divide

    x_use_fast_mul <= '1' when d_aluop = ALUOP_C.MULDIV and (
        (MUL_FAST  and d_mulop = MULOP_C.MUL   ) or
        (MULH_FAST and d_mulop = MULOP_C.MULH  ) or
        (MULH_FAST and d_mulop = MULOP_C.MULHU ) or
        (MULH_FAST and d_mulop = MULOP_C.MULHSU)
    ) else '0';

    HAS_MULDIV : if EXTENSION_M generate
        signal x_muldiv_op_vld         : std_logic;
        signal x_muldiv_op_rdy         : std_logic;
        signal x_muldiv_result_vld     : std_logic;
        signal x_muldiv_result_h       : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        signal x_muldiv_result_l       : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        signal x_muldiv_posted_reg     : std_logic;
        signal x_muldiv_kill           : std_logic;
        signal x_muldiv_result_is_high : std_logic;
    begin
        MULDIV_POSTED : process(clk) is
        begin
            if rising_edge(clk) then
                if ?? rst then
                    x_muldiv_posted_reg <= '0';
                else
                    x_muldiv_posted_reg <= (x_muldiv_posted_reg or (x_muldiv_op_vld and x_muldiv_op_rdy)) and x_stall;
                end if;
            end if;
        end process MULDIV_POSTED;

        x_muldiv_kill <= m_trap_enter_soon;

        x_muldiv_op_vld <= '1' when d_aluop = ALUOP_C.MULDIV and x_use_fast_mul = '0' and
                                    (x_muldiv_posted_reg or x_stall_on_raw or x_muldiv_kill) = '0' else '0';

        muldiv : entity work.hazard3_muldiv_seq
            generic map(
                MULDIV_UNROLL => MULDIV_UNROLL,
                MUL_FAST      => MUL_FAST,
                MULH_FAST     => MULH_FAST
            )
            port map(
                clk        => clk,
                rst        => rst,
                op         => d_mulop,
                op_vld     => x_muldiv_op_vld,
                op_rdy     => x_muldiv_op_rdy,
                op_kill    => x_muldiv_kill,
                op_a       => x_rs1_bypass,
                op_b       => x_rs2_bypass,

                result_h   => x_muldiv_result_h,
                result_l   => x_muldiv_result_l,
                result_vld => x_muldiv_result_vld
            );

        x_muldiv_result_is_high <= '1' when d_mulop = MULOP_C.MULH   or
                                            d_mulop = MULOP_C.MULHSU or
                                            d_mulop = MULOP_C.MULHU  or
                                            d_mulop = MULOP_C.REMI   or
                                            d_mulop = MULOP_C.REMIU  else '0';

        x_muldiv_result <= x_muldiv_result_h when ?? x_muldiv_result_is_high else x_muldiv_result_l;
        x_stall_muldiv  <= x_muldiv_op_vld or not x_muldiv_result_vld;

        HAS_FAST_MUL : if MUL_FAST generate
            -- If MUL_FASTER is set, the multiplier produces its result
            -- combinatorially, so we never have to post a mul result to stage 3.
            signal x_issue_fast_mul : std_logic;
        begin
            x_issue_fast_mul <= x_use_fast_mul and (or d_rd) and not x_stall and not to_std_logic(MUL_FASTER);

            mul_fast_u : entity work.hazard3_mul_fast
                generic map(
                    MULH_FAST  => MULH_FAST,
                    MUL_FAST   => MUL_FAST,
                    MUL_FASTER => MUL_FASTER
                )
                port map(
                    clk        => clk,
                    rst        => rst,

                    op_vld     => x_issue_fast_mul,
                    op         => d_mulop,
                    op_a       => x_rs1_bypass,
                    op_b       => x_rs2_bypass,

                    result     => m_fast_mul_result,
                    result_vld => m_fast_mul_result_vld
                );
        end;
        else generate
            m_fast_mul_result     <= (others => '0');
            m_fast_mul_result_vld <= '0';
        end generate HAS_FAST_MUL;
    end;
    else generate
        x_muldiv_result       <= (others => '0');
        m_fast_mul_result     <= (others => '0');
        m_fast_mul_result_vld <= '0';
        x_stall_muldiv        <= '0';
    end generate HAS_MULDIV;

    -- Branch handling

    -- For JALR, the LSB of the result must be cleared by hardware
    x_jump_target     <= x_addr_sum(ADDRESS_WIDTH_C - 1 downto 1) & '0';
    x_jump_misaligned <= not to_std_logic(EXTENSION_C) and x_addr_sum(1);

    x_branch_was_predicted <= to_std_logic(BRANCH_PREDICTOR) and fd_cir_predbranch(0);
    x_branch_cmp           <= x_branch_cmp_noinvert xor x_branch_was_predicted;

    BRANCHCMP_GEN : if not FAST_BRANCHCMP generate
        x_branch_cmp_noinvert <= x_alu_cmp;
    else generate
        branchcmp_u : entity work.hazard3_branchcmp
            port map(
                cir  => fd_cir,
                op_a => x_rs1_bypass,
                op_b => x_rs2_bypass,
                cmp  => x_branch_cmp_noinvert
            );
    end generate BRANCHCMP_GEN;

    -- Be careful not to take branches whose comparisons depend on a load result
    x_jump_req_unchecked <= '1' when x_stall_on_raw = '0' and (
        d_branchcond = BRANCH_C.ALWAYS or
        (d_branchcond = BRANCH_C.ZERO     and x_branch_cmp = '0') or
        (d_branchcond = BRANCH_C.NOT_ZERO and x_branch_cmp = '1')
    ) else '0';

    x_jump_req <= x_jump_req_unchecked and not x_jump_misaligned and not x_trig_break;

    x_btb_set <= '1' when BRANCH_PREDICTOR and (
        x_jump_req_unchecked = '1' and d_addr_offs(ADDRESS_WIDTH_C - 1) = '1' and x_branch_was_predicted = '0' and
        (d_branchcond = BRANCH_C.NOT_ZERO or d_branchcond = BRANCH_C.ZERO)
    ) else '0';

    x_btb_clear <= d_fence_i or m_trap_enter_now or (
        to_std_logic(BRANCH_PREDICTOR) and x_branch_was_predicted and x_jump_req_unchecked
    );

    x_btb_set_src_addr    <= d_pc;
    x_btb_set_target_addr <= x_jump_target;
    x_btb_set_src_size    <= fd_cir_is_32bit;

    -- Memory protection

    HAVE_PMP : if PMP_REGIONS > 0 generate
        signal x_loadstore_pmp_badperm : std_logic;
    begin
        x_loadstore_pmp_fail <= x_loadstore_pmp_badperm and x_memop_vld and not debug_mode;

        -- R and W are enforced at the point the load/store address is generated,
        -- in time to mask the address-phase request. X is enforced by checking
        -- fetch addresses during fetch data phase (stage F) and promoting PMP
        -- fails to bus faults.
        pmp : entity work.hazard3_pmp
            generic map(
                PMP_REGIONS        => PMP_REGIONS,
                PMP_GRAIN          => PMP_GRAIN,
                PMP_MATCH_NAPOT    => PMP_MATCH_NAPOT,
                PMP_MATCH_TOR      => PMP_MATCH_TOR,
                PMP_HARDWIRED      => PMP_HARDWIRED,
                PMP_HARDWIRED_ADDR => PMP_HARDWIRED_ADDR,
                PMP_HARDWIRED_CFG  => PMP_HARDWIRED_CFG,
                EXTENSION_XH3PMPM  => EXTENSION_XH3PMPM
            )
            port map(
                clk                       => clk,
                rst                       => rst,

                cfg_addr                  => x_pmp_cfg_addr,
                cfg_wen                   => x_pmp_cfg_wen,
                cfg_wdata                 => x_pmp_cfg_wdata,
                cfg_rdata                 => x_pmp_cfg_rdata,

                i_addr                    => f_pmp_i_addr,
                i_m_mode                  => f_pmp_i_m_mode,
                i_kill                    => f_pmp_i_kill,

                d_addr                    => unsigned(bus_haddr_d),
                d_addr_addend_rs1         => unsigned(x_rs1_bypass),
                d_addr_addend_imm         => unsigned(d_addr_offs),
                d_addr_addend_lspair_offs => unsigned(d_lspair_offset),
                d_m_mode                  => x_mmode_loadstore,
                d_write                   => bus_hwrite_d,
                d_kill                    => x_loadstore_pmp_badperm
            );
    end;
    else generate
        x_pmp_cfg_rdata      <= (others => '0');
        x_loadstore_pmp_fail <= '0';
        f_pmp_i_kill         <= '0';
    end generate HAVE_PMP;

    -- Triggers

    HAVE_TRIGGERS : if DEBUG_SUPPORT generate
        -- Connection of .fetch_d_mode is from the wrong stage: safe because we
        -- enter/exit debug mode via exceptions, which flush the frontend.
        triggers : entity work.hazard3_triggers
            generic map(
                DEBUG_SUPPORT       => DEBUG_SUPPORT,
                BREAKPOINT_TRIGGERS => BREAKPOINT_TRIGGERS,
                U_MODE              => U_MODE,
                EXTENSION_C         => EXTENSION_C
            )
            port map(
                clk              => clk,
                rst              => rst,

                cfg_addr         => std_logic_vector(x_trig_cfg_addr),
                cfg_wen          => x_trig_cfg_wen,
                cfg_wdata        => x_trig_cfg_wdata,
                cfg_rdata        => x_trig_cfg_rdata,
                trig_m_en        => x_trig_m_en,

                fetch_addr       => std_logic_vector(f_trigger_addr),
                fetch_m_mode     => f_trigger_m_mode,
                fetch_d_mode     => debug_mode,

                event_instr_ret  => x_instr_ret,

                event_interrupt  => m_trig_event_interrupt,
                event_exception  => m_trig_event_exception,
                event_trap_cause => unsigned(m_trig_event_trap_cause),
                event_trap_enter => m_trap_enter_now,

                break_any        => f_trigger_break_any,
                break_d_mode     => f_trigger_break_d_mode,

                break_m_step     => x_trig_step_break,

                x_d_mode         => debug_mode,
                x_m_mode         => x_mmode_execution
            );
    else generate
        x_trig_cfg_rdata       <= (others => '0');
        f_trigger_break_any    <= "00";
        f_trigger_break_d_mode <= "00";
        x_trig_step_break      <= '0';
    end generate HAVE_TRIGGERS;

    -- CSRs and Trap Handling

    -- Use opcode bits directly because d_rs1 is masked when RVE is enabled:
    x_csr_wdata <= std_logic_vector(resize(unsigned(fd_cir(19 downto 15)), DATA_WIDTH_C)) when ?? d_csr_w_imm else
                   x_rs1_bypass;

    TRAP_HOLDOFF : process(clk) is
    begin
        if rising_edge(clk) then
            if ?? rst then
                xm_delay_irq_entry_on_ls_stagex_reg <= '0';
                prev_instr_was_32_bit_reg <= '0';
            else
                -- Must hold off IRQ if we are in the second cycle of an address phase or
                -- later, since at that point the load/store can't be revoked. The IRQ is
                -- taken once this load/store moves to the next stage: if another load/store
                -- is chasing down the pipeline then this is immediately suppressed by the
                -- IRQ entry, before its address phase can begin.

                -- Also hold off on AMOs, unless the AMO is transitioning to an address
                -- phase or completing. ("completing" excludes transitions to error phase.)
                xm_delay_irq_entry_on_ls_stagex_reg <= (bus_aph_req_d and not bus_aph_ready_d) or
                    (d_memop_is_amo and not (
                        (to_std_logic(x_amo_phase_reg = 3) and bus_dph_ready_d and not bus_dph_err_d) or
                        -- Read reservation failure failure also generates error
                        (to_std_logic(x_amo_phase_reg = 1) and bus_dph_ready_d and not bus_dph_err_d and bus_dph_exokay_d)
                    )) or
                    ((fence_i_vld or fence_d_vld) and not fence_rdy);

                if not x_stall then
                    prev_instr_was_32_bit_reg <= to_std_logic(df_cir_use = "10");
                end if;
            end if;
        end if;
    end process TRAP_HOLDOFF;

    x_except <= EXCEPT_C.EBREAKPOINT              when ?? x_trig_break                                               else
                EXCEPT_C.INSTRUCTION_MISALIGNED   when ?? (x_jump_req_unchecked and x_jump_misaligned)               else
                EXCEPT_C.ILLEGAL_INSTRUCTION      when ?? x_csr_illegal_access                                       else
                EXCEPT_C.STORE_ADDRESS_MISALIGNED when EXTENSION_A and x_unaligned_addr = '1' and d_memop_is_amo = '1' else
                EXCEPT_C.STORE_ADDRESS_MISALIGNED when EXTENSION_A and x_amo_phase_reg = 4 and x_unaligned_addr = '1' else
                EXCEPT_C.STORE_ACCESS_FAULT       when EXTENSION_A and x_amo_phase_reg = 4                           else
                EXCEPT_C.STORE_ADDRESS_MISALIGNED when ?? (x_unaligned_addr and x_memop_write)                       else
                EXCEPT_C.LOAD_ADDRESS_MISALIGNED  when ?? (x_unaligned_addr and not x_memop_write)                   else
                EXCEPT_C.STORE_ACCESS_FAULT       when ?? (x_loadstore_pmp_fail and (d_memop_is_amo or bus_hwrite_d)) else
                EXCEPT_C.LOAD_ACCESS_FAULT        when ?? x_loadstore_pmp_fail                                       else
                EXCEPT_C.EXCEPTION_REFETCH        when ?? x_csr_write_is_fetch_ordered                               else
                d_except;

    -- If an instruction causes an exceptional condition we do not consider it to have retired.
    x_except_counts_as_retire <= '1' when x_except = EXCEPT_C.EBREAKPOINT                   or
                                          x_except = EXCEPT_C.EXCEPTION_REFETCH             or
                                          x_except = EXCEPT_C.RETURN_FROM_M_MODE            or
                                          x_except = EXCEPT_C.ENVIRONMENT_CALL_FROM_M_MODE  or
                                          x_except = EXCEPT_C.ENVIRONMENT_CALL_FROM_U_MODE else '0';

    x_instr_ret <= '1' when (or df_cir_use) = '1' and
                            (x_except = EXCEPT_C.NO_EXCEPTION or x_except_counts_as_retire = '1') else '0';

    m_dphase_in_flight <= '1' when xm_memop_reg /= MEMOP_C.NONE and xm_memop_reg /= MEMOP_C.ATOMIC_MEM_OP else '0';

    -- Need to delay IRQ entry on sleep exit because, for deep sleep states, we
    -- can't access the bus until the power handshake has completed.
    m_delay_irq_entry <= xm_delay_irq_entry_on_ls_stagex_reg or
                         ((xm_sleep_wfi_reg or xm_sleep_block_reg) and not m_sleep_stall_release);

    m_csr_delay_irq_entry <= m_delay_irq_entry or d_uninterruptible;

    -- Inhibit CSR read/write side effects; note most stage-X exception sources
    -- are excluded as these only apply to CSR instructions.
    m_csr_access_mask_early <= m_trap_enter_soon or fd_cir_break_any;
    m_csr_access_mask       <= m_csr_access_mask_early or x_stall;

    -- *en_soon are early access strobes which are not a function of bus stall.
    -- Can generate access faults (hence traps), but do not actually perform access.
    x_csr_wen_soon <= d_csr_wen and not m_csr_access_mask_early;
    x_csr_wen      <= d_csr_wen and not m_csr_access_mask;
    x_csr_ren_soon <= d_csr_ren and not m_csr_access_mask_early;
    x_csr_ren      <= d_csr_ren and not m_csr_access_mask;

    csr_u : entity work.hazard3_csr
        generic map(
            NUMBER_OF_IRQs      => NUMBER_OF_IRQs,
            IRQ_PRIORITY_BITS   => IRQ_PRIORITY_BITS,
            IRQ_INPUTREG_BYPASS => IRQ_INPUTREG_BYPASS,
            CSR_M_MANDATORY     => CSR_M_MANDATORY,
            CSR_M_TRAP          => CSR_M_TRAP,
            CSR_COUNTER         => CSR_COUNTER,
            PMP_REGIONS         => PMP_REGIONS,
            EXTENSION_A         => EXTENSION_A,
            EXTENSION_C         => EXTENSION_C,
            EXTENSION_M         => EXTENSION_M,
            MUL_FAST            => MUL_FAST,
            MULH_FAST           => MULH_FAST,
            EXTENSION_XH3PMPM   => EXTENSION_XH3PMPM,
            EXTENSION_XH3IRQ    => EXTENSION_XH3IRQ,
            U_MODE              => U_MODE,
            DEBUG_SUPPORT       => DEBUG_SUPPORT
        )
        port map(
            clk                        => clk,
            clk_always_on              => clk_always_on,
            rst                        => rst,
            mtvec_init                 => mtvec_init,

            -- Debugger signalling
            debug_mode                 => debug_mode,
            dbg_req_halt               => dbg_req_halt,
            dbg_req_halt_on_reset      => dbg_req_halt_on_reset,
            dbg_req_resume             => dbg_req_resume,

            dbg_instr_caught_exception => dbg_instr_caught_exception,
            dbg_instr_caught_ebreak    => dbg_instr_caught_ebreak,

            dbg_data0_rdata            => dbg_data0_rdata,
            dbg_data0_wdata            => dbg_data0_wdata,
            dbg_data0_wen              => dbg_data0_wen,

            debug_dpc_wdata            => debug_dpc_wdata,
            debug_dpc_wen              => debug_dpc_wen,
            debug_dpc_rdata            => debug_dpc_rdata,

            -- CSR access port
            addr                       => unsigned(fd_cir(31 downto 20)), -- Always I-type immediate
            wdata                      => x_csr_wdata,
            wen_raw                    => d_csr_wen,
            wen_soon                   => x_csr_wen_soon,
            wen                        => x_csr_wen,
            wtype                      => d_csr_wtype,
            rdata                      => x_csr_rdata,
            ren_soon                   => x_csr_ren_soon,
            ren                        => x_csr_ren,
            illegal                    => x_csr_illegal_access,
            write_is_fetch_ordered     => x_csr_write_is_fetch_ordered,

            -- Trap signalling
            trap_addr                  => m_trap_addr,
            trap_is_irq                => m_trap_is_irq,
            trap_enter_soon            => m_trap_enter_soon,
            trap_enter_vld             => m_trap_enter_vld,
            trap_enter_rdy             => m_trap_enter_rdy,
            loadstore_dphase_pending   => m_dphase_in_flight,
            delay_irq_entry            => m_csr_delay_irq_entry,
            mepc_in                    => m_exception_return_addr,

            pwr_allow_clkgate          => m_pwr_allow_clkgate,
            pwr_allow_power_down       => m_pwr_allow_power_down,
            pwr_allow_sleep_on_block   => m_pwr_allow_sleep_on_block,
            pwr_wfi_wakeup_req         => m_wfi_wakeup_req,

            m_mode_execution           => x_mmode_execution,
            m_mode_loadstore           => x_mmode_loadstore,
            m_mode_trap_entry          => m_mmode_trap_entry,

            -- IRQ and exception requests
            irq                        => irq,
            irq_software               => soft_irq,
            irq_timer                  => timer_irq,
            except                     => xm_except_reg,
            except_to_d_mode           => xm_except_to_d_mode_reg,

            pmp_cfg_addr               => x_pmp_cfg_addr,
            pmp_cfg_wen                => x_pmp_cfg_wen,
            pmp_cfg_wdata              => x_pmp_cfg_wdata,
            pmp_cfg_rdata              => x_pmp_cfg_rdata,

            trig_cfg_addr              => x_trig_cfg_addr,
            trig_cfg_wen               => x_trig_cfg_wen,
            trig_cfg_wdata             => x_trig_cfg_wdata,
            trig_cfg_rdata             => x_trig_cfg_rdata,
            trig_m_en                  => x_trig_m_en,

            trig_event_interrupt       => m_trig_event_interrupt,
            trig_event_exception       => m_trig_event_exception,
            trig_event_trap_cause      => m_trig_event_trap_cause,

            -- Other CSR-specific signalling
            clear_excl_on_trap_exit    => m_clear_excl_on_trap_exit,
            trap_wfi                   => x_trap_wfi,
            instr_ret                  => x_instr_ret,
            mhartid_val                => mhartid_val,
            eco_version                => eco_version
        );

    -- Pipe register

    xm_rd_nxt <= xm_rd_reg       when ?? m_stall                                     else
                 (others => '0') when ?? (x_stall or d_starved or m_trap_enter_soon) else
                 d_rd;

    PIPE_REG : process(clk) is
    begin
        if rising_edge(clk) then
            if ?? rst then
                xm_memop_reg            <= MEMOP_C.NONE;
                xm_except_reg           <= EXCEPT_C.NO_EXCEPTION;
                xm_except_to_d_mode_reg <= '0';
                xm_sleep_wfi_reg        <= '0';
                xm_sleep_block_reg      <= '0';
                unblock_out_reg         <= '0';
                xm_rs1_reg              <= (others => '0');
                xm_rs2_reg              <= (others => '0');
                xm_rd_reg               <= (others => '0');
            else
                unblock_out_reg <= '0';
                if not m_stall then
                    xm_rs1_reg <= d_rs1;
                    xm_rs2_reg <= d_rs2;
                    xm_rd_reg  <= d_rd;
                    -- If some X-sourced exception has squashed the address phase, need to squash the data phase too.
                    xm_memop_reg            <= MEMOP_C.NONE when x_except /= EXCEPT_C.NO_EXCEPTION else d_memop;
                    xm_except_reg           <= x_except;
                    xm_except_to_d_mode_reg <= x_trig_break_d_mode;
                    xm_sleep_wfi_reg        <= to_std_logic(x_except = EXCEPT_C.NO_EXCEPTION) and d_sleep_wfi;
                    xm_sleep_block_reg      <= to_std_logic(x_except = EXCEPT_C.NO_EXCEPTION) and d_sleep_block;
                    unblock_out_reg         <= to_std_logic(x_except = EXCEPT_C.NO_EXCEPTION) and d_sleep_unblock;
                    -- Note the d_starved term is required because it is possible
                    -- (e.g. PMP X permission fail) to except when the frontend is
                    -- starved, and we get a bad mepc if we let this jump ahead:
                    if ?? (x_stall or d_starved or m_trap_enter_soon) then
                        -- Insert bubble
                        xm_rd_reg               <= (others => '0');
                        xm_memop_reg            <= MEMOP_C.NONE;
                        xm_except_reg           <= EXCEPT_C.NO_EXCEPTION;
                        xm_except_to_d_mode_reg <= '0';
                        xm_sleep_wfi_reg        <= '0';
                        xm_sleep_block_reg      <= '0';
                        unblock_out_reg         <= '0';
                    end if;
                elsif ?? bus_dph_err_d then
                    -- First phase of 2-phase AHB5 error response. Pass the exception along on
                    -- this cycle, and on the next cycle the trap entry will be asserted,
                    -- suppressing any load/store that may currently be in stage X.
                    if EXTENSION_A and xm_memop_reg = MEMOP_C.LOAD_RESERVED_WORD then
                        xm_except_reg <= EXCEPT_C.LOAD_ACCESS_FAULT;
                    elsif unsigned(xm_memop_reg) <= unsigned(MEMOP_C.LOAD_BYTE_UNSIGNED) then
                        xm_except_reg <= EXCEPT_C.LOAD_ACCESS_FAULT;
                    else
                        xm_except_reg <= EXCEPT_C.STORE_ACCESS_FAULT;
                    end if;
                end if;
            end if;
        end if;
    end process PIPE_REG;

    unblock_out <= unblock_out_reg;

    -- Datapath flops
    DATAPATH_REG : process(clk) is
    begin
        if rising_edge(clk) then
            if ?? rst then
                xm_result_reg     <= (others => '0');
                xm_addr_align_reg <= "00";
            else
                if m_stall = '0' and not (EXTENSION_A and x_amo_phase_reg = 3 and bus_dph_ready_d = '0') then
                    -- AMOs need special attention (of course):
                    -- - Steer captured read phase data in mw_result back through xm_result at end of AMO
                    -- - Make sure xm_result (store data) doesn't transition during stalled write dphase
                    if ?? d_csr_ren then
                        xm_result_reg <= x_csr_rdata;
                    elsif EXTENSION_A and x_amo_phase_reg = 3 then
                        xm_result_reg <= mw_result_reg;
                    elsif MUL_FASTER and x_use_fast_mul = '1' then
                        xm_result_reg <= m_fast_mul_result;
                    elsif EXTENSION_M and d_aluop = ALUOP_C.MULDIV then
                        xm_result_reg <= x_muldiv_result;
                    else
                        xm_result_reg <= x_alu_result;
                    end if;
                    xm_addr_align_reg <= x_addr_sum(1 downto 0);
                end if;
            end if;
        end if;
    end process DATAPATH_REG;

    ---------------------------------------------------------------------------
    -- Pipe Stage M

    f_jump_req        <= x_jump_req or m_trap_enter_vld;
    f_jump_target     <= m_trap_addr        when ?? m_trap_enter_vld else x_jump_target;
    f_jump_priv       <= m_mmode_trap_entry when ?? m_trap_enter_vld else x_mmode_execution;
    x_jump_not_except <= not m_trap_enter_vld;

    -- Stalls and sleep control

    -- EXCEPT_NONE clause is needed in the following sequence:
    -- - Cycle 0: hresp asserted, hready low. We set the exception to squash behind us. Bus stall high.
    -- - Cycle 1: hready high. For whatever reason, the frontend can't accept the trap address this cycle.
    -- - Cycle 2: Our dataphase has ended, so bus_dph_ready_d doesn't pulse again. m_bus_stall stuck high.
    m_bus_stall <= '1' when m_dphase_in_flight = '1' and bus_dph_ready_d = '0' and xm_except_reg = EXCEPT_C.NO_EXCEPTION and not (
        EXTENSION_A and xm_memop_reg = MEMOP_C.STORE_CONDITIONAL_WORD and mw_local_exclusive_reserved_reg = '0'
    ) else '0';

    m_stall <= m_bus_stall or
               (m_trap_enter_vld and not m_trap_enter_rdy and not m_trap_is_irq) or
               ((xm_sleep_wfi_reg or xm_sleep_block_reg) and not m_sleep_stall_release);

    -- Exception is taken against the instruction currently in M, so walk the PC
    -- back. IRQ is taken "in between" the instruction in M and the instruction
    -- in X, so set return to X program counter. Note that, if taking an
    -- exception, we know that the previous instruction to be in X (now in M)
    -- was *not* a taken branch, which is why we can just walk back the PC.
    m_exception_return_offs <= to_unsigned(0, 3) when ?? m_trap_is_irq             else
                               to_unsigned(4, 3) when ?? prev_instr_was_32_bit_reg else
                               to_unsigned(2, 3);
    m_exception_return_addr <= std_logic_vector(unsigned(d_pc) - m_exception_return_offs);

    power_ctrl : entity work.hazard3_power_ctrl
        port map(
            clk_always_on          => clk_always_on,
            rst                    => rst,

            pwrup_req              => pwrup_req,
            pwrup_ack              => pwrup_ack,
            clk_en                 => clk_en,

            allow_clkgate          => m_pwr_allow_clkgate,
            allow_power_down       => m_pwr_allow_power_down,
            allow_sleep_on_block   => m_pwr_allow_sleep_on_block,

            frontend_pwrdown_ok    => f_frontend_pwrdown_ok,

            sleeping_on_wfi        => xm_sleep_wfi_reg,
            wfi_wakeup_req         => m_wfi_wakeup_req,
            sleeping_on_block      => xm_sleep_block_reg,
            block_wakeup_req_pulse => unblock_in,
            stall_release          => m_sleep_stall_release
        );

    -- Load/store data handling

    -- Local forwarding of store data
    m_wdata <= mw_result_reg when (or mw_rd_reg) = '1' and xm_rs2_reg = mw_rd_reg and not REDUCED_BYPASS else
               xm_result_reg;

    STORE_DATA : process(all) is
    begin
        -- Replicate store data to ensure appropriate byte lane is driven
        case? xm_memop_reg is
            when MEMOP_C.STORE_HALF => bus_wdata_d <= m_wdata(15 downto 0) & m_wdata(15 downto 0);
            when MEMOP_C.STORE_BYTE => bus_wdata_d <= m_wdata(7 downto 0) & m_wdata(7 downto 0) &
                                                      m_wdata(7 downto 0) & m_wdata(7 downto 0);
            when others             => bus_wdata_d <= m_wdata;
        end case?;
    end process STORE_DATA;

    LOAD_DATA : process(all) is
    begin
        case? std_logic_vector'(xm_memop_reg & xm_addr_align_reg) is
            when MEMOP_C.LOAD_HALF          & "0-" => m_rdata_pick_sext <= std_logic_vector(resize(signed(bus_rdata_d(15 downto  0)), DATA_WIDTH_C));
            when MEMOP_C.LOAD_HALF          & "1-" => m_rdata_pick_sext <= std_logic_vector(resize(signed(bus_rdata_d(31 downto 16)), DATA_WIDTH_C));
            when MEMOP_C.LOAD_HALF_UNSIGNED & "0-" => m_rdata_pick_sext <= std_logic_vector(resize(unsigned(bus_rdata_d(15 downto  0)), DATA_WIDTH_C));
            when MEMOP_C.LOAD_HALF_UNSIGNED & "1-" => m_rdata_pick_sext <= std_logic_vector(resize(unsigned(bus_rdata_d(31 downto 16)), DATA_WIDTH_C));
            when MEMOP_C.LOAD_BYTE          & "00" => m_rdata_pick_sext <= std_logic_vector(resize(signed(bus_rdata_d( 7 downto  0)), DATA_WIDTH_C));
            when MEMOP_C.LOAD_BYTE          & "01" => m_rdata_pick_sext <= std_logic_vector(resize(signed(bus_rdata_d(15 downto  8)), DATA_WIDTH_C));
            when MEMOP_C.LOAD_BYTE          & "10" => m_rdata_pick_sext <= std_logic_vector(resize(signed(bus_rdata_d(23 downto 16)), DATA_WIDTH_C));
            when MEMOP_C.LOAD_BYTE          & "11" => m_rdata_pick_sext <= std_logic_vector(resize(signed(bus_rdata_d(31 downto 24)), DATA_WIDTH_C));
            when MEMOP_C.LOAD_BYTE_UNSIGNED & "00" => m_rdata_pick_sext <= std_logic_vector(resize(unsigned(bus_rdata_d( 7 downto  0)), DATA_WIDTH_C));
            when MEMOP_C.LOAD_BYTE_UNSIGNED & "01" => m_rdata_pick_sext <= std_logic_vector(resize(unsigned(bus_rdata_d(15 downto  8)), DATA_WIDTH_C));
            when MEMOP_C.LOAD_BYTE_UNSIGNED & "10" => m_rdata_pick_sext <= std_logic_vector(resize(unsigned(bus_rdata_d(23 downto 16)), DATA_WIDTH_C));
            when MEMOP_C.LOAD_BYTE_UNSIGNED & "11" => m_rdata_pick_sext <= std_logic_vector(resize(unsigned(bus_rdata_d(31 downto 24)), DATA_WIDTH_C));
            when MEMOP_C.LOAD_WORD          & "--" => m_rdata_pick_sext <= bus_rdata_d;
            when MEMOP_C.LOAD_RESERVED_WORD & "--" => m_rdata_pick_sext <= bus_rdata_d;
            when others                            => m_rdata_pick_sext <= (others => 'X');
        end case?;
    end process LOAD_DATA;

    M_RESULT_P : process(all) is
    begin
        if EXTENSION_A and x_amo_phase_reg = 1 then
            -- Capture AMO read data into mw_result for feeding back through the ALU.
            m_result <= bus_rdata_d;
        elsif EXTENSION_A and xm_memop_reg = MEMOP_C.STORE_CONDITIONAL_WORD then
            -- sc.w may fail due to negative response from either local or global monitor.
            -- Note the polarity of the result: 0 for success, 1 for failure.
            m_result <= (0 => not (mw_local_exclusive_reserved_reg and bus_dph_exokay_d), others => '0');
        elsif xm_memop_reg /= MEMOP_C.NONE and xm_memop_reg /= MEMOP_C.ATOMIC_MEM_OP then
            m_result <= m_rdata_pick_sext;
        elsif MUL_FAST and m_fast_mul_result_vld = '1' then
            m_result <= m_fast_mul_result;
        else
            m_result <= xm_result_reg;
        end if;
    end process M_RESULT_P;

    -- Local monitor update.
    -- - Set on a load-reserved with good response from global monitor
    -- - Cleared by any store-conditional
    -- - Cleared by non-debug-related trap exit
    LOCAL_MONITOR : process(clk) is
    begin
        if rising_edge(clk) then
            if ?? rst then
                mw_local_exclusive_reserved_reg <= '0';
            else
                if EXTENSION_A and (m_stall = '0' or bus_dph_err_d = '1') then
                    if ?? d_memop_is_amo then
                        mw_local_exclusive_reserved_reg <= '0';
                    elsif xm_memop_reg = MEMOP_C.STORE_CONDITIONAL_WORD and (bus_dph_ready_d or bus_dph_err_d) = '1' then
                        mw_local_exclusive_reserved_reg <= '0';
                    elsif xm_memop_reg = MEMOP_C.LOAD_RESERVED_WORD and bus_dph_ready_d = '1' then
                        -- In theory, the bus should never report HEXOKAY when HRESP is asserted.
                        -- Still might happen (e.g. if HEXOKAY is tied high), so mask HEXOKAY with
                        -- HRESP to be sure a failed lr.w clears the monitor.
                        mw_local_exclusive_reserved_reg <= bus_dph_exokay_d and not bus_dph_err_d;
                    end if;
                end if;
                if ?? m_clear_excl_on_trap_exit then
                    mw_local_exclusive_reserved_reg <= '0';
                end if;
            end if;
        end if;
    end process LOCAL_MONITOR;

    -- Note that exception entry prevents writeback, because the exception entry
    -- replaces the instruction in M. Interrupt entry does not prevent writeback,
    -- because the interrupt is notionally inserted in between the instruction in
    -- M and the instruction in X.
    m_reg_wen_if_nonzero <= not m_bus_stall when xm_except_reg = EXCEPT_C.NO_EXCEPTION else '0';
    m_reg_wen            <= (or xm_rd_reg) and m_reg_wen_if_nonzero;

    MW_RESULT_UPDATE : process(clk) is
    begin
        if rising_edge(clk) then
            if ?? rst then
                mw_result_reg <= (others => '0');
            elsif m_reg_wen_if_nonzero = '1' and not (EXTENSION_A and x_amo_phase_reg(1) = '1') then
                -- (don't trash the captured AMO read phase data during stage 2/3 of AMO -- we need it!)
                mw_result_reg <= m_result;
            end if;
        end if;
    end process MW_RESULT_UPDATE;

    mw_rd_nxt <= xm_rd_reg when ?? m_reg_wen_if_nonzero else mw_rd_reg;

    MW_RD_UPDATE : process(clk) is
    begin
        if rising_edge(clk) then
            if ?? rst then
                mw_rd_reg <= (others => '0');
            elsif ?? m_reg_wen_if_nonzero then
                mw_rd_reg <= xm_rd_reg;
            end if;
        end if;
    end process MW_RD_UPDATE;

    -- On downstream stall, we feed D's addresses back into regfile
    -- so that output does not change.
    x_regfile_raddr1 <= d_rs1 when ?? (x_stall and not d_starved) else f_rs1_coarse;
    x_regfile_raddr2 <= d_rs2 when ?? (x_stall and not d_starved) else f_rs2_coarse;

    regs : entity work.hazard3_regfile_1w2r
        port map(
            clk    => clk,

            raddr1 => x_regfile_raddr1,
            rdata1 => x_rdata1,
            raddr2 => x_regfile_raddr2,
            rdata2 => x_rdata2,

            waddr  => xm_rd_reg,
            wdata  => m_result,
            wen    => m_reg_wen
        );

end architecture rtl;
