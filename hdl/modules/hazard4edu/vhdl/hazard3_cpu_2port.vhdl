library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.hazard3_constants.all;

-- Dual-ported top level file for Hazard3 CPU. This file instantiates the
-- Hazard3 core, and interfaces its instruction fetch and load/store signals
-- to a pair of AHB5 master ports.
entity hazard3_cpu_2port is
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

        -- AHB5 Instruction fetch port
        i_haddr     : out std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0);
        i_hwrite    : out std_logic;
        i_htrans    : out std_logic_vector(1 downto 0);
        i_hsize     : out std_logic_vector(2 downto 0);
        i_hburst    : out std_logic_vector(2 downto 0);
        i_hprot     : out std_logic_vector(3 downto 0);
        i_hmastlock : out std_logic;
        i_hmaster   : out std_logic_vector(7 downto 0);
        i_hready    : in  std_logic;
        i_hresp     : in  std_logic;
        i_hwdata    : out std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        i_hrdata    : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);

        -- AHB5 Load/Store port
        d_haddr     : out std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0);
        d_hwrite    : out std_logic;
        d_htrans    : out std_logic_vector(1 downto 0);
        d_hsize     : out std_logic_vector(2 downto 0);
        d_hburst    : out std_logic_vector(2 downto 0);
        d_hprot     : out std_logic_vector(3 downto 0);
        d_hmastlock : out std_logic;
        d_hmaster   : out std_logic_vector(7 downto 0);
        d_hexcl     : out std_logic;
        d_hready    : in  std_logic;
        d_hresp     : in  std_logic;
        d_hexokay   : in  std_logic;
        d_hwdata    : out std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        d_hrdata    : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);

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

        -- Optional debug system bus access patch-through
        dbg_sbus_addr  : in  std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0);
        dbg_sbus_write : in  std_logic;
        dbg_sbus_size  : in  std_logic_vector(1 downto 0);
        dbg_sbus_vld   : in  std_logic;
        dbg_sbus_rdy   : out std_logic;
        dbg_sbus_err   : out std_logic;
        dbg_sbus_wdata : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        dbg_sbus_rdata : out std_logic_vector(DATA_WIDTH_C - 1 downto 0);

        -- Identification CSR values
        mhartid_val : in std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        eco_version : in std_logic_vector(3 downto 0);

        -- Level-sensitive interrupt sources
        irq       : in std_logic_vector(NUMBER_OF_IRQs - 1 downto 0); --> mip.meip
        soft_irq  : in std_logic;                                     --> mip.msip
        timer_irq : in std_logic                                      --> mip.mtip
    );
end entity hazard3_cpu_2port;

architecture rtl of hazard3_cpu_2port is

    constant HTRANS_IDLE : std_logic_vector(1 downto 0) := "00";
    constant HTRANS_NSEQ : std_logic_vector(1 downto 0) := "10";

    -- ============================================================================
    -- Processor core signals
    -- ============================================================================
    -- Instruction fetch signals
    signal core_aph_req_i   : std_logic;
    signal core_aph_panic_i : std_logic;
    signal core_aph_ready_i : std_logic;
    signal core_dph_ready_i : std_logic;
    signal core_dph_err_i   : std_logic;

    signal core_haddr_i : std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0);
    signal core_hsize_i : std_logic_vector(2 downto 0);
    signal core_priv_i  : std_logic;
    signal core_rdata_i : std_logic_vector(DATA_WIDTH_C - 1 downto 0);

    -- Load/store signals
    signal core_aph_req_d    : std_logic;
    signal core_aph_excl_d   : std_logic;
    signal core_aph_ready_d  : std_logic;
    signal core_dph_ready_d  : std_logic;
    signal core_dph_err_d    : std_logic;
    signal core_dph_exokay_d : std_logic;

    signal core_haddr_d  : std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0);
    signal core_hsize_d  : std_logic_vector(2 downto 0);
    signal core_priv_d   : std_logic;
    signal core_hwrite_d : std_logic;
    signal core_wdata_d  : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal core_rdata_d  : std_logic_vector(DATA_WIDTH_C - 1 downto 0);

    signal dphase_active_i_reg : std_logic;
    -- ============================================================================
    -- Arbitration state machine signals
    -- ============================================================================
    signal bus_gnt_d : std_logic;
    signal bus_gnt_s : std_logic;

    signal bus_hold_aph_reg     : std_logic;
    -- Grants of the previous cycle: (1) load/store, (0) system bus
    signal bus_gnt_ds_prev_reg  : std_logic_vector(1 downto 0);
    signal bus_active_dph_d_reg : std_logic;
    signal bus_active_dph_s_reg : std_logic;

begin

    ---------------------------------------------------------------------------
    -- Processor core

    core : entity work.hazard3_core
        generic map(
            EXTENSION_A         => EXTENSION_A,
            EXTENSION_C         => EXTENSION_C,
            EXTENSION_M         => EXTENSION_M,
            EXTENSION_XH3IRQ    => EXTENSION_XH3IRQ,
            EXTENSION_XH3PMPM   => EXTENSION_XH3PMPM,
            CSR_M_MANDATORY     => CSR_M_MANDATORY,
            CSR_M_TRAP          => CSR_M_TRAP,
            CSR_COUNTER         => CSR_COUNTER,
            U_MODE              => U_MODE,
            PMP_REGIONS         => PMP_REGIONS,
            PMP_GRAIN           => PMP_GRAIN,
            PMP_MATCH_NAPOT     => PMP_MATCH_NAPOT,
            PMP_MATCH_TOR       => PMP_MATCH_TOR,
            PMP_HARDWIRED       => PMP_HARDWIRED,
            PMP_HARDWIRED_ADDR  => PMP_HARDWIRED_ADDR,
            PMP_HARDWIRED_CFG   => PMP_HARDWIRED_CFG,
            DEBUG_SUPPORT       => DEBUG_SUPPORT,
            BREAKPOINT_TRIGGERS => BREAKPOINT_TRIGGERS,
            NUMBER_OF_IRQs      => NUMBER_OF_IRQs,
            IRQ_PRIORITY_BITS   => IRQ_PRIORITY_BITS,
            IRQ_INPUTREG_BYPASS => IRQ_INPUTREG_BYPASS,
            REDUCED_BYPASS      => REDUCED_BYPASS,
            MULDIV_UNROLL       => MULDIV_UNROLL,
            MUL_FAST            => MUL_FAST,
            MUL_FASTER          => MUL_FASTER,
            MULH_FAST           => MULH_FAST,
            FAST_BRANCHCMP      => FAST_BRANCHCMP,
            BRANCH_PREDICTOR    => BRANCH_PREDICTOR
        )
        port map(
            clk                        => clk,
            clk_always_on              => clk_always_on,
            rst                        => rst,
            reset_vector               => reset_vector,
            mtvec_init                 => mtvec_init,

            pwrup_req                  => pwrup_req,
            pwrup_ack                  => pwrup_ack,
            clk_en                     => clk_en,
            unblock_out                => unblock_out,
            unblock_in                 => unblock_in,

            bus_aph_req_i              => core_aph_req_i,
            bus_aph_panic_i            => core_aph_panic_i,
            bus_aph_ready_i            => core_aph_ready_i,
            bus_dph_ready_i            => core_dph_ready_i,
            bus_dph_err_i              => core_dph_err_i,
            bus_haddr_i                => core_haddr_i,
            bus_hsize_i                => core_hsize_i,
            bus_priv_i                 => core_priv_i,
            bus_rdata_i                => core_rdata_i,

            bus_aph_req_d              => core_aph_req_d,
            bus_aph_excl_d             => core_aph_excl_d,
            bus_aph_ready_d            => core_aph_ready_d,
            bus_dph_ready_d            => core_dph_ready_d,
            bus_dph_err_d              => core_dph_err_d,
            bus_dph_exokay_d           => core_dph_exokay_d,
            bus_haddr_d                => core_haddr_d,
            bus_hsize_d                => core_hsize_d,
            bus_priv_d                 => core_priv_d,
            bus_hwrite_d               => core_hwrite_d,
            bus_wdata_d                => core_wdata_d,
            bus_rdata_d                => core_rdata_d,

            fence_i_vld                => fence_i_vld,
            fence_d_vld                => fence_d_vld,
            fence_rdy                  => fence_rdy,

            dbg_req_halt               => dbg_req_halt,
            dbg_req_halt_on_reset      => dbg_req_halt_on_reset,
            dbg_req_resume             => dbg_req_resume,
            dbg_halted                 => dbg_halted,
            dbg_running                => dbg_running,
            dbg_data0_rdata            => dbg_data0_rdata,
            dbg_data0_wdata            => dbg_data0_wdata,
            dbg_data0_wen              => dbg_data0_wen,
            dbg_instr_data             => dbg_instr_data,
            dbg_instr_data_vld         => dbg_instr_data_vld,
            dbg_instr_data_rdy         => dbg_instr_data_rdy,
            dbg_instr_caught_exception => dbg_instr_caught_exception,
            dbg_instr_caught_ebreak    => dbg_instr_caught_ebreak,

            mhartid_val                => mhartid_val,
            eco_version                => eco_version,

            irq                        => irq,
            soft_irq                   => soft_irq,
            timer_irq                  => timer_irq
        );

    ---------------------------------------------------------------------------
    -- Instruction port
    
    i_haddr <= core_haddr_i;
    i_htrans <= HTRANS_NSEQ when ?? core_aph_req_i else HTRANS_IDLE;
    i_hsize <= core_hsize_i;

    process(clk) begin
        if rising_edge(clk) then
            if ?? rst then
                dphase_active_i_reg <= '0';
            else
                dphase_active_i_reg <= core_aph_req_i when ?? i_hready else dphase_active_i_reg;
            end if;
        end if;
    end process;

    core_aph_ready_i <= i_hready and core_aph_req_i;
    core_dph_ready_i <= i_hready and dphase_active_i_reg;
    core_dph_err_i   <= i_hready and dphase_active_i_reg and i_hresp;

    core_rdata_i <= i_hrdata;

    i_hwrite <= '0';
    i_hburst <= 3d"0";
    i_hmastlock <= '0';
    i_hmaster <= x"00";
    i_hwdata <= (others => '0');

    i_hprot <= "00" &        -- Noncacheable/nonbufferable
               core_priv_i & -- Privileged or Normal as per core state
               '0';          -- Instruction access

    -- ----------------------------------------------------------------------------
    -- Load/store port

    -- The debug module has optional System Bus Access support, which can be muxed
    -- into the processor's D port here (or connected to a standalone AHB shim).
    -- This confers absolutely no advantage for debugger bus throughput, but
    -- allows the debugger to access the bus with minimal disturbance to the
    -- processor.

    -- clk_always_on is used because SBA may access the bus through this arbiter
    -- whilst the core is asleep (same is not true for I-side interface)

    process(clk_always_on) begin
        if rising_edge(clk_always_on) then
            if ?? rst then
                bus_hold_aph_reg <= '0';
                bus_gnt_ds_prev_reg <= (others => '0');
            else
                bus_hold_aph_reg <= d_htrans(1) and not d_hready and not d_hresp;
                bus_gnt_ds_prev_reg <= bus_gnt_d & bus_gnt_s;
            end if;
        end if;
    end process;

    bus_gnt_d <= bus_gnt_ds_prev_reg(1) when ?? bus_hold_aph_reg                            else
                 '1'                    when ?? core_aph_req_d                              else
                 '0'                    when ?? (dbg_sbus_vld and not bus_active_dph_s_reg) else
                 '0';
    
    bus_gnt_s <= bus_gnt_ds_prev_reg(0) when ?? bus_hold_aph_reg                            else
                 '0'                    when ?? core_aph_req_d                              else
                 '1'                    when ?? (dbg_sbus_vld and not bus_active_dph_s_reg) else
                 '0';

    process(clk_always_on) begin
        if rising_edge(clk_always_on) then
            if ?? rst then
                bus_active_dph_d_reg <= '0';
                bus_active_dph_s_reg <= '0';
            elsif ?? d_hready then
                bus_active_dph_d_reg <= bus_gnt_d;
                bus_active_dph_s_reg <= bus_gnt_s;
            end if;
        end if;
    end process;

    d_htrans <= HTRANS_NSEQ when ?? (bus_gnt_d or bus_gnt_s) else HTRANS_IDLE;

    d_haddr  <= dbg_sbus_addr         when ?? bus_gnt_s else core_haddr_d;
    d_hwrite <= dbg_sbus_write        when ?? bus_gnt_s else core_hwrite_d;
    d_hsize  <= ('0' & dbg_sbus_size) when ?? bus_gnt_s else core_hsize_d;
    d_hexcl  <= '0'                   when ?? bus_gnt_s else core_aph_excl_d;

    d_hprot <= "00" & (bus_gnt_s or core_priv_d) & '1';

    d_hwdata <= dbg_sbus_wdata when ?? bus_active_dph_s_reg else core_wdata_d;

    -- D-side errors are reported even when not ready, so that the core can make
    -- use of the two-phase error response to cleanly squash a second load/store
    -- chasing the faulting one down the pipeline.
    core_aph_ready_d  <= d_hready and bus_gnt_d;
    core_dph_ready_d  <= bus_active_dph_d_reg and d_hready;
    core_dph_err_d    <= bus_active_dph_d_reg and d_hresp;
    core_dph_exokay_d <= bus_active_dph_d_reg and d_hexokay;
    core_rdata_d      <= d_hrdata;

    dbg_sbus_err   <= bus_active_dph_s_reg and d_hresp;
    dbg_sbus_rdy   <= bus_active_dph_s_reg and d_hready;
    dbg_sbus_rdata <= d_hrdata;

    d_hburst <= 3d"0";
    d_hmastlock <= '0';
    d_hmaster <= x"01" when ?? bus_gnt_s else x"00";
    
end architecture rtl;
