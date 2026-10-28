library ieee;

use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.hazard3_constants.all;

entity hazard3_csr is 
    generic (
        -- Number of external IRQs. Note that if EXTENSION_XH3IRQ (IRQ Controller) is disabled, then
        -- multiple external interrupts are OR'd into mip.meip
        NUMBER_OF_IRQs      : integer range 1 to MAX_NUMBER_OF_IRQ_C         := 8;
        IRQ_PRIORITY_BITS   : integer range 0 to 4                           := 0;
        IRQ_INPUTREG_BYPASS : boolean_vector(NUMBER_OF_IRQs - 1 downto 0)    := (others => FALSE);
        CSR_M_MANDATORY     : boolean                                        := TRUE;
        CSR_M_TRAP          : boolean                                        := TRUE;
        CSR_COUNTER         : boolean                                        := TRUE;
        PMP_REGIONS         : natural                                        := 0;
        EXTENSION_A         : boolean                                        := TRUE;
        EXTENSION_C         : boolean                                        := TRUE;
        EXTENSION_M         : boolean                                        := TRUE;
        MUL_FAST            : boolean                                        := TRUE;
        MULH_FAST           : boolean                                        := TRUE;
        EXTENSION_XH3PMPM   : boolean                                        := TRUE;
        EXTENSION_XH3IRQ    : boolean                                        := TRUE;
        U_MODE              : boolean                                        := FALSE;
        DEBUG_SUPPORT       : boolean                                        := TRUE
    );
    port (
        clk             : in std_logic;
        clk_always_on   : in std_logic;
        rst             : in std_logic;
        mtvec_init      : in std_logic_vector(31 downto 0);

        -- Debug Signalling
        debug_mode : out std_logic;

        dbg_req_halt                : in  std_logic;
        dbg_req_halt_on_reset       : in  std_logic;
        dbg_req_resume              : in  std_logic;
        dbg_instr_caught_exception  : out std_logic;
        dbg_instr_caught_ebreak     : out std_logic;

        dbg_data0_rdata : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        dbg_data0_wdata : out std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        dbg_data0_wen   : out std_logic;

        debug_dpc_wdata : out std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        debug_dpc_wen   : out std_logic;
        debug_dpc_rdata : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);

	    -- Read port is combinatorial.
	    -- Write port is synchronous, and write effects will be observed on the next clock cycle.
	    -- The *_soon strobes are versions which the core does not gate with its stall signal.
	    -- These are needed because:
	    -- - Core stall is a function of bus stall
	    -- - Illegal CSR accesses produce trap entry
	    -- - Trap entry (not necessarily caused by CSR access) gates outgoing bus accesses
	    -- - Through-paths from e.g. hready to htrans are problematic for timing/implementation
        addr                    : in  unsigned(CSR_ADDRESS_WIDTH_C - 1 downto 0);
        wdata                   : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        wen                     : in  std_logic;
        wen_soon                : in  std_logic; -- wen will be asserted once some stall condition clears
        wen_raw                 : in  std_logic; -- raw, ungated instruction decode signal, for D-mode regs
        wtype                   : in  std_logic_vector(1 downto 0);
        rdata                   : out std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        ren                     : in  std_logic;
        ren_soon                : in  std_logic; -- ren will be asserted once some stall condition clears
        illegal                 : out std_logic;
        write_is_fetch_ordered  : out std_logic;

	    -- Trap signalling
	    -- *We* tell the core that we are taking a trap, and where to, based on:
	    -- - Synchronous exception inputs from the core
	    -- - External IRQ signals
	    -- - Masking etc based on the state of CSRs like mie
	    --
	    -- We do this by raising trap_enter_vld, and keeping it raised until trap_enter_rdy
	    -- goes high. trap_addr has the absolute value of trap target address.
	    -- Once trap_enter_vld && _rdy, mepc_in is copied to mepc, and other trap state is set.
	    --
	    -- Note that an exception input can go away, e.g. if the pipe gets flushed. In this
	    -- case we lower trap_enter_vld.
        trap_addr       : out std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        trap_is_irq     : out std_logic;
        trap_enter_vld  : out std_logic;
        trap_enter_rdy  : in  std_logic;
	    -- True when we are about to trap, but are waiting for an excepting or
	    -- potentially-excepting instruction to clear M first. The instruction in X
	    -- is suppressed, X PC does not increment but still tracks exception
	    -- addresses.
        trap_enter_soon : out std_logic;
	    -- We need to know about load/stores in data phase because their exception
	    -- status is still unknown, so fence them off before entering debug mode.
        loadstore_dphase_pending : in std_logic;
	    -- Asserted when the instruction in stage 2 can't be squashed (e.g. to
	    -- keep an AHB address phase stable), or instruction fetch request can't
	    -- be issued (e.g. waiting for wake from wfi state).
        delay_irq_entry : in std_logic;
        mepc_in         : in std_logic_vector(DATA_WIDTH_C - 1 downto 0);

        -- Power Control Signalling
        pwr_allow_clkgate           : out std_logic;
        pwr_allow_power_down        : out std_logic;
        pwr_allow_sleep_on_block    : out std_logic;
        pwr_wfi_wakeup_req          : out std_logic;

        -- Each of these may be performed at a different privilege level from the others:
        m_mode_execution  : out std_logic;
        m_mode_trap_entry : out std_logic;
        m_mode_loadstore  : out std_logic;

        -- Exceptions must *not* be a function of bus stall
        except           : in std_logic_vector(EXCEPTION_WIDTH_C - 1 downto 0);
        except_to_d_mode : in std_logic;

        -- Level-sensitive interrupt sources
        irq             : in std_logic_vector(NUMBER_OF_IRQs - 1 downto 0);
        irq_software    : in std_logic;
        irq_timer       : in std_logic;

        -- PMP config interface
        pmp_cfg_addr  : out unsigned(CSR_ADDRESS_WIDTH_C - 1 downto 0);
        pmp_cfg_wen   : out std_logic;
        pmp_cfg_wdata : out std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        pmp_cfg_rdata : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);

        -- Trigger config interface 
        trig_cfg_addr  : out unsigned(CSR_ADDRESS_WIDTH_C - 1 downto 0);
        trig_cfg_wen   : out std_logic;
        trig_cfg_wdata : out std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        trig_cfg_rdata : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        trig_m_en      : out std_logic;

        -- Interrupt / exception trigger events 
        trig_event_interrupt  : out std_logic;
        trig_event_exception  : out std_logic;
        trig_event_trap_cause : out std_logic_vector(3 downto 0);

        -- Other CSR-specific signalling
        clear_excl_on_trap_exit : out std_logic;
        trap_wfi                : out std_logic;
        instr_ret               : in  std_logic;
        mhartid_val             : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        eco_version             : in  std_logic_vector(3 downto 0)
    );
end entity hazard3_csr;

architecture rtl of hazard3_csr is

    constant H3MISA_STANDARD_LENGTH : std_logic_vector(DATA_WIDTH_C - 1 downto 0) := 32d"77";
    constant H3MISA_CUSTOM_LENGTH   : std_logic_vector(DATA_WIDTH_C - 1 downto 0) := 32d"5";

    constant MISA_VAL : std_logic_vector(DATA_WIDTH_C - 1 downto 0) := (
        2d"1"   & -- MXL: 32bit
        4d"0"   & -- WLRL
        2d"0"   & -- Z, Y, no
        '1'     & -- X is always due to (at least) Xh3misa
        2d"0"   & -- V, W, no
        to_std_logic(U_MODE) &
        7d"0"   & -- T..N, no
        to_std_logic(EXTENSION_M) &
        3d"0"   & -- L..J, no
        '1'     & -- RVI base ISA
        3d"0"   & -- H, G, F, no
        '0'     & -- RVE base ISA
        1d"0"   & -- D, no
        to_std_logic(EXTENSION_C) &
        1d"0"   & -- B, no
        to_std_logic(EXTENSION_A)
    );

    constant EXTENSION_ZMMUL : boolean :=  EXTENSION_M;
    constant EXTENSION_ZKT   : boolean := not (EXTENSION_M and not (MUL_FAST and MULH_FAST));
    constant EXTENSION_I     : boolean := TRUE;

    constant H3MISA_STANDARD_EXTENSION : std_logic_array_t(0 to 3)(DATA_WIDTH_C - 1 downto 0) := (
        0 => (
            12 => to_std_logic(EXTENSION_M),
            8 => to_std_logic(EXTENSION_I),
            2 => to_std_logic(EXTENSION_C),
            0 => to_std_logic(EXTENSION_A),
            others => '0'),
        1 => (
            14 => to_std_logic(EXTENSION_ZKT),
            others => '0'),
        2 => (
            12 => to_std_logic(EXTENSION_ZMMUL),
            2 => to_std_logic(EXTENSION_C),
            others => '0'),
        others => (others => '0')
    );

    constant H3MISA_CUSTOM_EXTENSIONS : std_logic_array_t(0 to 7)(DATA_WIDTH_C - 1 downto 0) := (
        0 => (24 => to_std_logic(CSR_M_MANDATORY), others => '0'),
        1 => (24 => to_std_logic(EXTENSION_XH3IRQ), others => '0'),
        2 => (24 => to_std_logic(EXTENSION_XH3PMPM), others => '0'),
        others => (others => '0')
    );

    constant C_SHIFT : integer := 2 - to_integer(unsigned(std_logic_vector'("00" & to_std_logic(EXTENSION_C))));
    constant DEBUG_DPC_MASK : std_logic_vector(DATA_WIDTH_C - 1 downto 0) :=  x"FFFF_FFFF" sll C_SHIFT;

    signal wdata_update     : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal enter_debug_mode : std_logic;
    signal exit_debug_mode  : std_logic;
    signal debug_mode_reg   : std_logic;
    signal m_mode_reg       : std_logic;
    signal wen_m_mode       : std_logic;
    signal ren_m_mode       : std_logic;
    
    signal debug_suppresses_trap_update : std_logic;
    signal trapreg_update : std_logic;
    signal trapreg_update_enter : std_logic;
    signal trapreg_update_exit : std_logic;

    signal mstatus_mpie_reg : std_logic;
    signal mstatus_mie_reg  : std_logic;
    signal mstatus_mpp_reg  : std_logic;
    signal mstatus_mprv_reg : std_logic;
    signal mstatus_tw_reg   : std_logic;

    signal mscratch_reg     : std_logic_vector(DATA_WIDTH_C - 1 downto 0);

    signal mtvec_reg         : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal mtvec             : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal irq_vector_enable : std_logic;

    signal mepc_reg           : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal mie_reg            : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal meicontext_clearts : std_logic;

    signal mip : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal mcause_irq_reg   : std_logic;
    signal mcause_code_reg  : std_logic_vector(3 downto 0);
    signal mcause_irq_next  : std_logic;
    signal mcause_code_next : std_logic_vector(3 downto 0);

    signal mimpid_rdata : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    
    signal irq_ctrl_rdata : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal external_irq_pending : std_logic;
    signal trap_entry_is_eirq : std_logic;
    signal external_irq_pending_reg : std_logic;

    signal h3misa_information : std_logic_array_t(0 to 1)(DATA_WIDTH_C - 1 downto 0);
    signal h3misa_rdata       : std_logic_vector(DATA_WIDTH_C - 1 downto 0);

    signal mcountinhibit_cy_reg  : std_logic;
    signal mcountinhibit_ir_reg  : std_logic;
    signal mcycleh_reg           : unsigned(DATA_WIDTH_C - 1 downto 0);
    signal mcycle_reg            : unsigned(DATA_WIDTH_C - 1 downto 0);
    signal minstreth_reg         : unsigned(DATA_WIDTH_C - 1 downto 0);
    signal minstret_reg          : unsigned(DATA_WIDTH_C - 1 downto 0);
    signal mcycle_stopped        : std_logic;
    signal minstret_stopped      : std_logic;
    signal mcycleh_or_mcycle     : boolean;
    signal minstreth_or_minstret : boolean;

    signal mcounteren_cy_reg    : std_logic;
    signal mcounteren_tm_reg    : std_logic;
    signal mcounteren_ir_reg    : std_logic;

    signal dcsr_ebreakm_reg     : std_logic;
    signal dcsr_ebreaku_reg     : std_logic;
    signal dcsr_step_reg        : std_logic;
    signal dcsr_cause_reg       : std_logic_vector(2 downto 0);
    signal dcause_next          : std_logic_vector(2 downto 0);

    signal tcontrol_mte_reg     : std_logic;
    signal tcontrol_mpte_reg    : std_logic;

    signal decode_match : std_logic;
    signal match_drw    : std_logic;
    signal match_mrw    : std_logic;
    signal match_mro    : std_logic;
    signal match_uro    : std_logic;

    signal have_just_reset_reg              : std_logic;
    signal step_halt_req_reg                : std_logic;
    signal dbg_req_resume_prev_reg          : std_logic;
    signal dbg_req_halt_prev_reg            : std_logic;
    signal dbg_req_halt_on_reset_sticky_reg : std_logic;
    signal pending_dbg_resume_prev_reg      : std_logic;
    signal pending_dbg_resume               : std_logic;
    signal step_event                       : std_logic;

    signal exception_req_any             : std_logic;
    signal halt_delayed_by_exception     : std_logic;
    signal want_halt_except              : std_logic;
    signal want_halt_irq_if_no_exception : std_logic;
    signal want_halt_irq                 : std_logic;
    signal trap_is_debug_entry           : std_logic;

    signal irq_software_reg : std_logic;
    signal irq_timer_reg    : std_logic;
    signal irq_active       : std_logic;
    signal standard_irq_num : std_logic_vector(3 downto 0);
    signal mcause_irq_num   : std_logic_vector(3 downto 0);
    signal vector_sel       : std_logic_vector(3 downto 0);

begin

    debug_mode <= debug_mode_reg;
    pwr_allow_clkgate <= '0';
    pwr_allow_power_down <= '0';
    pwr_allow_sleep_on_block <= '0';

    ----------------------------------------------------------------------------
    -- CSR state + update logic
    ----------------------------------------------------------------------------
    
    -- Generic update logic for write/set/clear of an entire CSR:
    wdata_update <= rdata and not wdata when wtype = CSR_WTYPE.C else
                    rdata or      wdata when wtype = CSR_WTYPE.S else
                    wdata;
    
    process(clk) is
    begin
        if rising_edge(clk) then
            if ?? rst then
                debug_mode_reg <= '0';
            else
                debug_mode_reg <= (debug_mode_reg and not exit_debug_mode) or enter_debug_mode;
            end if;
        end if;
    end process;

    -- Core execution state, 1 -> M-mode, 0 -> U-mode (if implemented)
    wen_m_mode <= wen and (m_mode_reg or debug_mode_reg);
    ren_m_mode <= ren and (m_mode_reg or debug_mode_reg);

    ---------------------------------------------------------------------------
    -- Standard trap handling CSRs
    debug_suppresses_trap_update <= to_std_logic(DEBUG_SUPPORT) and (debug_mode_reg or enter_debug_mode);
    trapreg_update <= trap_enter_vld and trap_enter_rdy and not debug_suppresses_trap_update;
    trapreg_update_enter <= trapreg_update and to_std_logic(except /= EXCEPT_C.RETURN_FROM_M_MODE) and to_std_logic(except /= EXCEPT_C.EXCEPTION_REFETCH);
    trapreg_update_exit <= trapreg_update and to_std_logic(except = EXCEPT_C.RETURN_FROM_M_MODE);

    -- Local monitor flag cleared on trap exit (but not on debug-mode exit, to
    -- permit stepping through LR/SC sequences):
    clear_excl_on_trap_exit <= trapreg_update_exit;

    -- Spec text from priv-1.12:
    -- "An MRET or SRET instruction is used to return from a trap in M-mode or
    --  S-mode respectively. When executing an xRET instruction, supposing xPP
    --  holds the value y, xIE is set to xPIE; the privilege mode is changed to
    --  y; xPIE is set to 1; and xPP is set to the least-privileged supported
    --  mode (U if U-mode is implemented, else M). If xPP=M, xRET also sets
    --  MPRV=0."
    process(clk) begin
        if rising_edge(clk) then
            if ?? rst then
                m_mode_reg <= '1';
                mstatus_mpie_reg <= '0';
                mstatus_mie_reg <= '0';
                mstatus_mpp_reg <= '1';
                mstatus_mprv_reg <= '0';
                mstatus_tw_reg <= '0';
            else
                if not CSR_M_TRAP then
                    m_mode_reg <= '1';
                    mstatus_mpie_reg <= '0';
                    mstatus_mie_reg <= '0';
                    mstatus_mpp_reg <= '1';
                    mstatus_mprv_reg <= '0';
                    mstatus_tw_reg <= '0';
                else
                    if ?? trapreg_update_exit then
                        mstatus_mpie_reg <= '1';
                        mstatus_mie_reg <= mstatus_mpie_reg;
                        if U_MODE then
                            m_mode_reg <= mstatus_mpp_reg;
                            mstatus_mpp_reg <= '0';
                            if ?? (not mstatus_mpp_reg) then
                                mstatus_mprv_reg <= '0';
                            end if;
                        end if;
                    elsif ?? trapreg_update_enter then
                        mstatus_mpie_reg <= mstatus_mie_reg;
                        mstatus_mie_reg <= '0';
                        if U_MODE then
                            m_mode_reg <= '1';
                            mstatus_mpp_reg <= m_mode_reg;
                        end if;
                    elsif wen_m_mode = '1' and addr = CSR_ADDRESSES.MACHINE_TRAP_SETUP.MSTATUS then
                        mstatus_mpie_reg <= wdata_update(7);
                        mstatus_mie_reg <= wdata_update(3);
                        mstatus_mprv_reg <= wdata_update(17);
                        -- Not only the MSB of MPP is implemented. It reads back as 11 or 00.
                        mstatus_mpp_reg <= wdata_update(12) or not to_std_logic(U_MODE);
                        mstatus_tw_reg <= wdata_update(21) and to_std_logic(U_MODE);
                    elsif wen_raw = '1' and debug_mode_reg = '1' and addr = CSR_ADDRESSES.D_MODE.DCSR and U_MODE and DEBUG_SUPPORT then
                        -- Debugger can change/observe core state directly through
                        -- DCSR.PRV (this does not affect debugger operation, as all
                        -- operations have effective level of M-mode while the core
                        -- is halted for debug.)
                        m_mode_reg <= wdata_update(1);
                    end if;
                    if not U_MODE then
                        -- Explicitly tie-off to constant
                        m_mode_reg <= '1';
                        mstatus_mpp_reg <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Trap all U-mode WFIs if timeout bit is set. Note that the debug spec
    -- says "The `wfi` instruction acts as a `nop`" during program buffer
    -- execution, and nops do not trap, so in debug mode we allow WFIs but
    -- immediately wake them.
    trap_wfi <= mstatus_tw_reg and not (debug_mode_reg or m_mode_reg);

    process(clk) begin
        if rising_edge(clk) then
            if ?? rst then
                mscratch_reg <= (others => '0');
            else
                if not CSR_M_TRAP then
                    mscratch_reg <= (others => '0');
                else
                    if wen_m_mode = '1' and addr = CSR_ADDRESSES.MACHINE_TRAP_HANDLING.MSCRATCH then
                        mscratch_reg <= wdata_update;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Trap vector base
    mtvec <= mtvec_reg and x"FFFF_FFFC";
    irq_vector_enable <= mtvec_reg(0);

    process(clk) begin
        if rising_edge(clk) then
            if ?? rst then
                mtvec_reg <= mtvec_init;
            else
                if not CSR_M_TRAP then
                    mtvec_reg <= mtvec_init;
                else
                    if wen_m_mode = '1' and addr = CSR_ADDRESSES.MACHINE_TRAP_SETUP.MTVEC then
                        mtvec_reg <= (wdata_update and MTVEC_WRITE_MASK_C) or (mtvec_reg and not MTVEC_WRITE_MASK_C);
                    end if;
                end if;
            end if;
        end if;
    end process;

    process(clk) is
        constant MEPC_MASK : std_logic_vector(mepc_reg'range) := (ADDRESS_WIDTH_C - 1 downto 2 => '1') & to_std_logic(EXTENSION_C) & '0';
    begin
        if rising_edge(clk) then
            if ?? rst then
                mepc_reg <= (others => '0');
            else
                if not CSR_M_TRAP then
                    mepc_reg <= (others => '0');
                else
                    if ?? trapreg_update_enter then
                        mepc_reg <= mepc_in and MEPC_MASK;
                    elsif wen_m_mode = '1' and addr = CSR_ADDRESSES.MACHINE_TRAP_HANDLING.MEPC then
                        mepc_reg <= wdata_update and MEPC_MASK;
                    end if;
                end if;
            end if;
        end if;
    end process;

    process(clk) is
        constant MIE_WMASK : std_logic_vector(mie_reg'range) := x"0000_0888"; -- meie, mtie, msie
    begin
        if rising_edge(clk) then
            if ?? rst then
                mie_reg <= (others => '0');
            else
                if not CSR_M_TRAP then
                    mie_reg <= (others => '0');
                else
                    if wen_m_mode = '1' and addr = CSR_ADDRESSES.MACHINE_TRAP_SETUP.MIE then
                        mie_reg <= (wdata_update and MIE_WMASK) or (mie_reg and not MIE_WMASK);
                    elsif wen_m_mode = '1' and addr = CSR_ADDRESSES.CUSTOM_M_MODE.MEICONTEXT then
                        -- meicontext.clearts/mtiesave/msiesave can be used to clear and
    			        -- save standard timer and soft IRQ enables, simultaneously with
    			        -- saving external interrupt context.
                        mie_reg(7) <= (mie_reg(7) or wdata_update(3)) and not meicontext_clearts;
                        mie_reg(3) <= (mie_reg(3) or wdata_update(2)) and not meicontext_clearts;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Trap cause registers. The non-constant bits can be written by software, and
    -- update automatically on trap entry. The `code` field need only be large
    -- enough to support causes that will be set by hardware, in our case 4 bits.
    -- (Note this is different to scause which always has a hard minimum of 5
    -- bits.)
    process(clk) begin
        if rising_edge(clk) then
            if ?? rst then
                mcause_irq_reg <= '0';
                mcause_code_reg <= (others => '0');
            else
                if not CSR_M_TRAP then
                    mcause_irq_reg <= '0';
                    mcause_code_reg <= (others => '0');
                else
                    if ?? trapreg_update_enter then
                        mcause_irq_reg <= mcause_irq_next;
                        mcause_code_reg <= mcause_code_next;
                    elsif wen_m_mode = '1' and addr = CSR_ADDRESSES.MACHINE_TRAP_HANDLING.MCAUSE then
                        mcause_irq_reg <= wdata_update(31);
                        mcause_code_reg <= wdata_update(3 downto 0);
                    end if;
                end if;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Standard identification CSRs
    -- MIMPID Records the RTL release version. Change it with each release manually.

    -- Note the eco_version field is connected externally -- on ASIC this may be
    -- connected to tie cells so it can be incremented following a metal ECO.
    mimpid_rdata <= RTL_MIMPID.PRERELEASE &
                    "000" &
                    RTL_MIMPID.MAJOR &
                    RTL_MIMPID.MINOR &
                    RTL_MIMPID.PATCH &
                    eco_version &
                    x"0";

    ---------------------------------------------------------------------------
    -- Custom external IRQ controller

    trap_entry_is_eirq <= '1' when mcause_irq_next = '1' and mcause_code_next = x"b" else '0';

    HAVE_IRQ_CONTROLLER : if EXTENSION_XH3IRQ generate
        irq_ctrl : entity work.hazard3_irq_ctrl
            generic map(
                NUMBER_OF_IRQs      => NUMBER_OF_IRQs,
                IRQ_PRIORITY_BITS   => IRQ_PRIORITY_BITS,
                IRQ_INPUTREG_BYPASS => IRQ_INPUTREG_BYPASS
            )
            port map(
                clk                  => clk,
                clk_always_on        => clk_always_on,
                rst                  => rst,
                addr                 => addr,
                wtype                => wtype,
                wen_m_mode           => wen_m_mode,
                ren_m_mode           => ren_m_mode,
                wdata_raw            => wdata,
                wdata                => wdata_update,
                rdata                => irq_ctrl_rdata,
                trapreg_update_enter => trapreg_update_enter,
                trapreg_update_exit  => trapreg_update_exit,
                trap_entry_is_eirq   => trap_entry_is_eirq,
                meicontext_clearts   => meicontext_clearts,
                mie_mtie             => mie_reg(7),
                mie_msie             => mie_reg(3),
                irq                  => irq,
                external_irq_pending => external_irq_pending
            );
    else generate

        process(clk_always_on) begin
            if rising_edge(clk_always_on) then
                if ?? rst then
                    external_irq_pending_reg <= '0';
                else
                    external_irq_pending_reg <= or irq;
                end if;
            end if;
        end process;

        irq_ctrl_rdata <= (others => '0');
        meicontext_clearts <= '0';
        external_irq_pending <= external_irq_pending_reg;

    end generate HAVE_IRQ_CONTROLLER;
    
    ---------------------------------------------------------------------------
    -- Custom identification CSRs
    
    h3misa_information(1) <= H3MISA_CUSTOM_LENGTH;
    h3misa_information(0) <= H3MISA_STANDARD_LENGTH;

    h3misa_rdata <= H3MISA_STANDARD_EXTENSION(to_integer(unsigned(wdata(1 downto 0))))      when ?? (not wdata(10)) else
                    h3misa_information(to_integer(unsigned(std_logic_vector'("00" & wdata(0)))))   when ?? (not wdata(8))  else
                    H3MISA_CUSTOM_EXTENSIONS(to_integer(unsigned(wdata(2 downto 0))));

    ---------------------------------------------------------------------------
    -- Counters

    mcycleh_or_mcycle <= addr = CSR_ADDRESSES.PERFORMANCE_COUNTERS.MCYCLEH or addr = CSR_ADDRESSES.PERFORMANCE_COUNTERS.MCYCLE;
    minstreth_or_minstret <= addr = CSR_ADDRESSES.PERFORMANCE_COUNTERS.MINSTRETH or addr = CSR_ADDRESSES.PERFORMANCE_COUNTERS.MINSTRET;

    mcycle_stopped <= mcountinhibit_cy_reg or debug_mode_reg or (wen_m_mode and to_std_logic(mcycleh_or_mcycle));
    minstret_stopped <= mcountinhibit_ir_reg or debug_mode_reg or (wen_m_mode and to_std_logic(minstreth_or_minstret));

    process(clk) begin
        if rising_edge(clk) then
            if ?? rst then
                mcycle_reg <= (others => '0');
                mcycleh_reg <= (others => '0');
                minstret_reg <= (others => '0');
                minstreth_reg <= (others => '0');
                mcountinhibit_cy_reg <= '1';
                mcountinhibit_ir_reg <= '1';
            else
                if CSR_COUNTER then
                    if ?? (not mcycle_stopped) then
                        (mcycleh_reg, mcycle_reg) <= (mcycleh_reg & mcycle_reg) + 1;
                    end if;
                    if ?? (instr_ret and not minstret_stopped) then
                        (minstreth_reg, minstret_reg) <= (minstreth_reg & minstret_reg) + 1;
                    end if;
                    if ?? wen_m_mode then
                        case to_integer(addr) is
                            when CSR_ADDRESSES.PERFORMANCE_COUNTERS.MCYCLEH   => mcycleh_reg <= unsigned(wdata_update);
                            when CSR_ADDRESSES.PERFORMANCE_COUNTERS.MCYCLE    => mcycle_reg <= unsigned(wdata_update);
                            when CSR_ADDRESSES.PERFORMANCE_COUNTERS.MINSTRETH => minstreth_reg <= unsigned(wdata_update);
                            when CSR_ADDRESSES.PERFORMANCE_COUNTERS.MINSTRET  => minstret_reg <= unsigned(wdata_update);
                            when CSR_ADDRESSES.PERFORMANCE_COUNTERS.MCOUNTINHIBIT => 
                                mcountinhibit_cy_reg <= wdata_update(0);
                                mcountinhibit_ir_reg <= wdata_update(2);
                            when others => null;
                        end case;   
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Note we still implement tm, even though the time/timeh CSRs are
    -- unimplemented. The tm bit provides a standard way to configure whether
    -- M-mode software permits the trapped access to reach the timer registers.
    -- (This is in fact required by the RVM-CSI platform spec.)
    process(clk) begin
        if rising_edge(clk) then
            if ?? rst then
                mcounteren_cy_reg <= '0';
                mcounteren_ir_reg <= '0';
                mcounteren_tm_reg <= '0';
            else
                -- Written (with zeros) even without counters or U-mode: a register that is only
                -- assigned in the reset branch would be inferred as a latch by GHDL
                if wen_m_mode = '1' and addr = CSR_ADDRESSES.MACHINE_TRAP_SETUP.MCOUNTEREN then
                    mcounteren_cy_reg <= wdata_update(0) and to_std_logic(CSR_COUNTER and U_MODE);
                    mcounteren_tm_reg <= wdata_update(1) and to_std_logic(CSR_COUNTER and U_MODE);
                    mcounteren_ir_reg <= wdata_update(2) and to_std_logic(CSR_COUNTER and U_MODE);
                end if;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Debug-mode CSRs

    -- The following DCSR bits are read/writable as normal:
    -- - ebreakm (bit 15)
    -- - ebreaku (bit 12) if U-mode is supported
    -- - step (bit 2)
    -- The following are read-only volatile:
    -- - cause (bits 8:6)
    -- All others are hardwired constants.
    process(clk) begin
        if rising_edge(clk) then
            if ?? rst then
                dcsr_ebreakm_reg <= '0';
                dcsr_ebreaku_reg <= '0';
                dcsr_step_reg <= '0';
                dcsr_cause_reg <= (others => '0');
            else
                if DEBUG_SUPPORT then
                    if debug_mode_reg = '1' and wen_raw = '1' and addr = CSR_ADDRESSES.D_MODE.DCSR then
                        dcsr_ebreakm_reg <= wdata_update(15);
                        dcsr_ebreaku_reg <= wdata_update(12) when U_MODE else '0';
                        dcsr_step_reg <= wdata_update(2);
                    end if;
                    if ?? enter_debug_mode then
                        dcsr_cause_reg <= dcause_next;
                    end if;
                else
                    dcsr_ebreakm_reg <= '0';
                    dcsr_ebreaku_reg <= '0';
                    dcsr_step_reg <= '0';
                    dcsr_cause_reg <= (others => '0');
                end if;
            end if;
        end if;
    end process;

    -- DPC is mapped to the real PC in the decode module. We set it to the
    -- exception return address when entering Debug Mode, and whilst in Debug
    -- Mode we can write to it as though it were a CSR. Note only IALIGN'd values
    -- can be written to dpc.
    debug_dpc_wdata <= (wdata_update and DEBUG_DPC_MASK) when ?? debug_mode_reg else (mepc_in and DEBUG_DPC_MASK);
    debug_dpc_wen <= (wen_raw and to_std_logic(addr = CSR_ADDRESSES.D_MODE.DPC)) when ?? debug_mode_reg else enter_debug_mode;

    dbg_data0_wdata <= wdata;
    dbg_data0_wen <= debug_mode and wen_raw and to_std_logic(addr = CSR_ADDRESSES.D_MODE.DMDATA0);

    process(clk) begin
        if rising_edge(clk) then
            if ?? rst then
                tcontrol_mpte_reg <= '0';
                tcontrol_mte_reg <= '0';
            else
                if DEBUG_SUPPORT then
                    if wen_m_mode = '1' and addr = CSR_ADDRESSES.TRIGGER_MODULE.TCONTROL then
                        tcontrol_mpte_reg <= wdata_update(7);
                        tcontrol_mte_reg <= wdata_update(3);
                    elsif ?? trapreg_update_enter then
                        tcontrol_mte_reg <= '0';
                        tcontrol_mpte_reg <= tcontrol_mte_reg;
                    elsif ?? trapreg_update_exit then
                        tcontrol_mte_reg <= tcontrol_mpte_reg;
                    end if;
                else
                    tcontrol_mpte_reg <= '0';
                    tcontrol_mte_reg <= '0';
                end if;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Read port + detect addressing of unmapped CSRs
    ---------------------------------------------------------------------------
    match_drw <= debug_mode_reg when DEBUG_SUPPORT else '0';
    match_mrw <= m_mode_reg or debug_mode_reg;
    match_mro <= (m_mode_reg or debug_mode_reg) and not wen_soon;
    match_uro <= not wen_soon when U_MODE else '0';

    process(all) begin
        decode_match <= '0';
        rdata <= (others => '0');
        pmp_cfg_wen <= '0';
        trig_cfg_wen <= '0';

        case to_integer(addr) is
            -------------------------------------------------------------------
            -- Mandatory CSRs
            when CSR_ADDRESSES.MACHINE_TRAP_SETUP.MISA =>
                if CSR_M_MANDATORY then
                    decode_match <= match_mrw;
                    rdata <= MISA_VAL;
                end if;
            when CSR_ADDRESSES.MACHINE_INFO.MVENDORID => 
                if CSR_M_MANDATORY then
                    decode_match <= match_mro;
                    rdata <= MVENDORID_C;
                end if;
            when CSR_ADDRESSES.MACHINE_INFO.MARCHID => 
                if CSR_M_MANDATORY then
                    decode_match <= match_mro;
                    rdata <= MARCHID_C;
                end if;
            when CSR_ADDRESSES.MACHINE_INFO.MIMPID => 
                if CSR_M_MANDATORY then
                    decode_match <= match_mro;
                    rdata <= mimpid_rdata;
                end if;
            when CSR_ADDRESSES.MACHINE_INFO.MHARTID => 
                if CSR_M_MANDATORY then
                    decode_match <= match_mro;
                    rdata <= mhartid_val;
                end if;
            when CSR_ADDRESSES.MACHINE_INFO.MCONFIGPTR => 
                if CSR_M_MANDATORY then
                    decode_match <= match_mro;
                    rdata <= MCONFIGPTR_C;
                end if;
            when CSR_ADDRESSES.MACHINE_TRAP_SETUP.MSTATUS => 
                if CSR_M_MANDATORY or CSR_M_TRAP then
                    decode_match <= match_mrw;
                    rdata <= (
                         21 => mstatus_tw_reg,
                         17 => mstatus_mprv_reg,
                         12 => mstatus_mpp_reg,
                         11 => mstatus_mpp_reg,
                         7 => mstatus_mpie_reg,
                         3 => mstatus_mie_reg,
                        others => '0'
                    );
                end if;
            when CSR_ADDRESSES.MACHINE_TRAP_SETUP.MSTATUSH => 
                if CSR_M_MANDATORY or CSR_M_TRAP then
                    decode_match <= match_mrw;
                end if;
            when CSR_ADDRESSES.OTHER_STANDARD_M_MODE.MENVCFG | CSR_ADDRESSES.OTHER_STANDARD_M_MODE.MENVCFGH => 
                if U_MODE then
                    decode_match <= match_mrw;
                end if;
            -------------------------------------------------------------------
            -- Trap-handling CSRs
            when CSR_ADDRESSES.MACHINE_TRAP_HANDLING.MSCRATCH => 
                if CSR_M_MANDATORY and CSR_M_TRAP then
                    decode_match <= match_mrw;
                    rdata <= mscratch_reg;
                end if;
            when CSR_ADDRESSES.MACHINE_TRAP_HANDLING.MEPC => 
                if CSR_M_TRAP then
                    decode_match <= match_mrw;
                    rdata <= mepc_reg;
                end if;
            when CSR_ADDRESSES.MACHINE_TRAP_HANDLING.MCAUSE => 
                if CSR_M_TRAP then
                    decode_match <= match_mrw;
                    rdata <= (
                        31 => mcause_irq_reg,
                        3 downto 0 => mcause_code_reg(3 downto 0),
                        others => '0'
                    );
                end if;
            when CSR_ADDRESSES.MACHINE_TRAP_HANDLING.MTVAL => 
                if CSR_M_TRAP then
                    decode_match <= match_mrw;
                end if;
            when CSR_ADDRESSES.MACHINE_TRAP_SETUP.MIE => 
                if CSR_M_TRAP then
                    decode_match <= match_mrw;
                    rdata <= mie_reg;
                end if;
            when CSR_ADDRESSES.MACHINE_TRAP_HANDLING.MIP => 
                if CSR_M_TRAP then
                    decode_match <= match_mrw;
                    rdata <= mip;
                end if;
            when CSR_ADDRESSES.MACHINE_TRAP_SETUP.MTVEC => 
                if CSR_M_TRAP then
                    decode_match <= match_mrw;
                    rdata <= (
                        31 downto 2 => mtvec(DATA_WIDTH_C - 1 downto 2),
                        0 => irq_vector_enable,
                        others => '0'
                    );
                end if;
            -------------------------------------------------------------------
            -- Counter CSRs
            when CSR_ADDRESSES.PERFORMANCE_COUNTERS.MHPMCOUNTER3  to CSR_ADDRESSES.PERFORMANCE_COUNTERS.MHPMCOUNTER31  | 
                 CSR_ADDRESSES.PERFORMANCE_COUNTERS.MHPMCOUNTER3H to CSR_ADDRESSES.PERFORMANCE_COUNTERS.MHPMCOUNTER31H |
                 CSR_ADDRESSES.PERFORMANCE_COUNTERS.MHPMEVENT3    to CSR_ADDRESSES.PERFORMANCE_COUNTERS.MHPMEVENT31   =>
                if CSR_COUNTER then
                    decode_match <= match_mrw;
                end if;
            when CSR_ADDRESSES.PERFORMANCE_COUNTERS.MCOUNTINHIBIT => 
                if CSR_COUNTER then
                    decode_match <= match_mrw;
                    rdata <= (
                        2 => mcountinhibit_ir_reg,
                        0 => mcountinhibit_cy_reg,
                        others => '0'
                    );
                end if;
            when CSR_ADDRESSES.PERFORMANCE_COUNTERS.MCYCLE => 
                if CSR_COUNTER then
                    decode_match <= match_mrw;
                    rdata <= std_logic_vector(mcycle_reg);
                end if;
            when CSR_ADDRESSES.PERFORMANCE_COUNTERS.MINSTRET => 
                if CSR_COUNTER then
                    decode_match <= match_mrw;
                    rdata <= std_logic_vector(minstret_reg);
                end if;
            when CSR_ADDRESSES.PERFORMANCE_COUNTERS.MCYCLEH => 
                if CSR_COUNTER then
                    decode_match <= match_mrw;
                    rdata <= std_logic_vector(mcycleh_reg);
                end if;
            when CSR_ADDRESSES.PERFORMANCE_COUNTERS.MINSTRETH => 
                if CSR_COUNTER then
                    decode_match <= match_mrw;
                    rdata <= std_logic_vector(minstreth_reg);
                end if;
            when CSR_ADDRESSES.MACHINE_TRAP_SETUP.MCOUNTEREN =>
                if CSR_COUNTER and U_MODE then
                    decode_match <= match_mrw;
                    rdata <= (
                        2 => mcounteren_ir_reg,
                        1 => mcounteren_tm_reg,
                        0 => mcounteren_cy_reg,
                        others => '0'
                    );
                end if;
            -------------------------------------------------------------------
            -- PNP CSRs (bridge to PNP config interface)
            when CSR_ADDRESSES.MACHINE_MEMORY_PROTECTION.PMPCFG0 to CSR_ADDRESSES.MACHINE_MEMORY_PROTECTION.PMPCFG3 => 
                if PMP_REGIONS > 0 then
                    decode_match <= match_mrw;
                    pmp_cfg_wen <= match_mrw and wen;
                    rdata <= pmp_cfg_rdata;
                end if;
            when CSR_ADDRESSES.MACHINE_MEMORY_PROTECTION.PMPADDR0 to CSR_ADDRESSES.MACHINE_MEMORY_PROTECTION.PMPADDR15 => 
                if PMP_REGIONS > 0 then
                    decode_match <= match_mrw;
                    pmp_cfg_wen <= match_mrw and wen;
                    rdata <= pmp_cfg_rdata;
                end if;
            -------------------------------------------------------------------
            -- U-mode CSRs
            when CSR_ADDRESSES.U_MODE.CYCLE => 
                if CSR_COUNTER then
                    decode_match <= match_uro when ?? mcounteren_cy_reg else match_mro;
                    rdata <= std_logic_vector(mcycle_reg);
                end if;
            when CSR_ADDRESSES.U_MODE.CYCLEH => 
                if CSR_COUNTER then
                    decode_match <= match_uro when ?? mcounteren_cy_reg else match_mro;
                    rdata <= std_logic_vector(mcycleh_reg);
                end if;
            when CSR_ADDRESSES.U_MODE.INSTRET => 
                if CSR_COUNTER then
                    decode_match <= match_uro when ?? mcounteren_ir_reg else match_mro;
                    rdata <= std_logic_vector(minstret_reg);
                end if;
            when CSR_ADDRESSES.U_MODE.INSTRETH => 
                if CSR_COUNTER then
                    decode_match <= match_uro when ?? mcounteren_ir_reg else match_mro;
                    rdata <= std_logic_vector(minstreth_reg);
                end if;
            -------------------------------------------------------------------
            -- Trigger Module CSRs
            when CSR_ADDRESSES.TRIGGER_MODULE.TSELECT | CSR_ADDRESSES.TRIGGER_MODULE.TDATA1 | 
                 CSR_ADDRESSES.TRIGGER_MODULE.TDATA2 | CSR_ADDRESSES.TRIGGER_MODULE.TINFO => 
                if DEBUG_SUPPORT then
                    decode_match <= match_mrw;
                    trig_cfg_wen <= match_mrw and wen;
                    rdata <= trig_cfg_rdata;
                end if;
            when CSR_ADDRESSES.TRIGGER_MODULE.TDATA3 => 
                if DEBUG_SUPPORT then
                    decode_match <= match_mrw;
                    rdata <= 32x"0";
                end if;
            when CSR_ADDRESSES.TRIGGER_MODULE.TCONTROL => 
                if DEBUG_SUPPORT then
                    decode_match <= match_mrw;
                    rdata <= (
                        7 => tcontrol_mpte_reg,
                        3 => tcontrol_mte_reg,
                        others => '0'
                    );
                end if;
            -------------------------------------------------------------------
            -- Debug CSRs
            when CSR_ADDRESSES.D_MODE.DCSR => 
                if DEBUG_SUPPORT then
                    decode_match <= match_drw;
                    rdata <= (
                        31 downto 28 => x"4",       -- xdebugver = 4, for 0.13.2 debug spec
                        15 => dcsr_ebreakm_reg,
                        12 => dcsr_ebreaku_reg,
                        10 => '1',                   -- stopcount = 1, no counter increment in debug mode
                        9 => '1',                   -- stoptime = 1, core-local timer increment in debug mode
                        8 downto 6 => dcsr_cause_reg,
                        2 => dcsr_step_reg,
                        1 => m_mode_reg,
                        0 => m_mode_reg,
                        others => '0'
                    );
                end if;
            when CSR_ADDRESSES.D_MODE.DPC => 
                if DEBUG_SUPPORT then
                    decode_match <= match_drw;
                    rdata <= debug_dpc_rdata;
                end if;
            when CSR_ADDRESSES.D_MODE.DMDATA0 => 
                if DEBUG_SUPPORT then
                    decode_match <= match_drw;
                    rdata <= dbg_data0_rdata;
                end if;
            -------------------------------------------------------------------
            -- Custom CSRs
            when CSR_ADDRESSES.CUSTOM_M_MODE.PMPCFGM0 => 
                if PMP_REGIONS > 0 and EXTENSION_XH3PMPM then
                    decode_match <= match_mrw;
                    pmp_cfg_wen <= match_mrw and wen;
                    rdata <= pmp_cfg_rdata;
                end if;
            when CSR_ADDRESSES.CUSTOM_M_MODE.MEIEA to CSR_ADDRESSES.CUSTOM_M_MODE.MEICONTEXT => 
                if CSR_M_TRAP and EXTENSION_XH3IRQ then
                    decode_match <= match_mrw;
                    rdata <= irq_ctrl_rdata;
                end if;
            when CSR_ADDRESSES.CUSTOM_M_MODE.H3MISA => 
                if CSR_M_MANDATORY then
                    decode_match <= match_mrw;
                    rdata <= h3misa_rdata;
                end if;
            when others => null;
        end case;        
    end process;

    illegal <= (wen_soon or ren_soon) and not decode_match;
    
    write_is_fetch_ordered <= '1' when wen_raw = '1' and debug_mode = '0' and (
        ((PMP_REGIONS > 0) and (
            (addr >= CSR_ADDRESSES.MACHINE_MEMORY_PROTECTION.PMPADDR0 and
             addr <= CSR_ADDRESSES.MACHINE_MEMORY_PROTECTION.PMPADDR15) or
            (addr >= CSR_ADDRESSES.MACHINE_MEMORY_PROTECTION.PMPCFG0 and
             addr <= CSR_ADDRESSES.MACHINE_MEMORY_PROTECTION.PMPCFG3)
        )) or
        (DEBUG_SUPPORT and (
            addr = CSR_ADDRESSES.TRIGGER_MODULE.TDATA1 or
            addr = CSR_ADDRESSES.TRIGGER_MODULE.TDATA2 or
            addr = CSR_ADDRESSES.TRIGGER_MODULE.TCONTROL
        ))
        ) else '0';
    
    ---------------------------------------------------------------------------
    -- Debug run/halt
    pending_dbg_resume <= debug_mode_reg and (pending_dbg_resume_prev_reg or dbg_req_resume_prev_reg);

    -- Note exception entry is also considered a step -- in this case we are
    -- supposed to take the trap and then break to debug mode before executing the
    -- first trap instruction. *IRQ* entry does not occur when step is 1 (because
    -- we hardwire dcsr.stepie to 0)
    step_event <= instr_ret or (trap_enter_vld and trap_enter_rdy);

    process(clk_always_on) begin
        if rising_edge(clk_always_on) then
            if ?? rst then
                dbg_req_halt_prev_reg <= '0';
            else
                dbg_req_halt_prev_reg <= dbg_req_halt when DEBUG_SUPPORT else '0';
            end if;
        end if;
    end process;

    process(clk) begin
        if rising_edge(clk) then
            if ?? rst then
                have_just_reset_reg <= to_std_logic(DEBUG_SUPPORT);
                dbg_req_halt_on_reset_sticky_reg <= '0';
                step_halt_req_reg <= '0';
                dbg_req_resume_prev_reg <= '0';
                pending_dbg_resume_prev_reg <= '0';
            else
                if DEBUG_SUPPORT then
                    have_just_reset_reg <= '0';

    		        -- One-cycle delay on assertion of reset halt req is harmless because
    		        -- of a matching delay on the first instruction fetch (reset_holdoff).
                    if ?? (have_just_reset_reg and dbg_req_halt_on_reset) then
                        dbg_req_halt_on_reset_sticky_reg <= '1';
                    elsif ?? enter_debug_mode then
                        dbg_req_halt_on_reset_sticky_reg <= '0';
                    end if;

                    dbg_req_resume_prev_reg <= dbg_req_resume;

                    if ?? debug_mode_reg then
                        step_halt_req_reg <= '0';
                    elsif ?? (dcsr_step_reg and step_event) then
                        step_halt_req_reg <= '1';
                    end if;

                    pending_dbg_resume_prev_reg <= pending_dbg_resume;

                else
                    have_just_reset_reg <= to_std_logic(DEBUG_SUPPORT);
                    dbg_req_halt_on_reset_sticky_reg <= '0';
                    step_halt_req_reg <= '0';
                    dbg_req_resume_prev_reg <= '0';
                    pending_dbg_resume_prev_reg <= '0';
                end if;
            end if;
        end if;
    end process;

    -- We can enter the halted state in an IRQ-like manner (squeeze in between the
    -- instructions in stage 2 and stage 3) or in an exception-like manner
    -- (replace the instruction in stage 3).
    --
    -- Halt request and step-break are IRQ-like. We need to be careful when a halt
    -- request lines up with an instruction in M which either has generated an
    -- exception (e.g. an ecall) or may yet generate an exception (a load). In
    -- this case the correct thing to do is to:
    --
    -- - Squash whatever instruction may be in X, and inhibit X PC increment
    -- - Wait until after the exception entry is taken (or the load/store
    --   completes successfully)
    -- - Immediately trigger an IRQ-like debug entry.
    --
    -- This ensures the debugger sees mcause/mepc set correctly, with dpc pointing
    -- to the handler entry point, if the instruction excepts.

    halt_delayed_by_exception <= exception_req_any or loadstore_dphase_pending;
    want_halt_except <= '1' when DEBUG_SUPPORT and debug_mode_reg = '0' and (
                            (dcsr_ebreakm_reg = '1' and m_mode_reg = '1' and except = EXCEPT_C.EBREAKPOINT) or
                            (dcsr_ebreaku_reg = '1' and m_mode_reg = '0' and except = EXCEPT_C.EBREAKPOINT) or
                            (except_to_d_mode = '1'                      and except = EXCEPT_C.EBREAKPOINT))
                            else '0';

    -- Note exception-like causes (trigger, ebreak) are higher priority than
    -- IRQ-like.
    --
    -- We must mask halt_req with delay_irq_entry (true on cycle 2 and beyond of
    -- load/store address phase) because at that point we can't suppress the bus
    -- access. Others are fine because they are never mid-instruction in stage 2.
    want_halt_irq_if_no_exception <= '1' when DEBUG_SUPPORT and debug_mode_reg = '0' and want_halt_except = '0' and (
                                            (dbg_req_halt_prev_reg = '1' and delay_irq_entry = '0') or 
                                            dbg_req_halt_on_reset_sticky_reg = '1' or step_halt_req_reg = '1')
                                        else '0';
              
    -- Exception (or potential exception due to load/store) in M delays halt
    -- entry. The halt intention still blocks X, so we can't get blocked forever
    -- by a string of load/stores. This is just here to get sequencing between an
    -- exception (or potential exception) in M, and debug mode entry.
    want_halt_irq <= want_halt_irq_if_no_exception and not halt_delayed_by_exception;
                  
    dcause_next <= 3x"2" when except = EXCEPT_C.EBREAKPOINT and except_to_d_mode = '1' else
                   3x"1" when except = EXCEPT_C.EBREAKPOINT                            else
                   3x"3" when ?? (dbg_req_halt_prev_reg or dbg_req_halt_on_reset)      else
                   3x"4";

    trap_is_debug_entry <= '1' when DEBUG_SUPPORT and debug_mode_reg = '0' and (want_halt_irq = '1' or want_halt_except = '1') else '0';
    enter_debug_mode <= trap_is_debug_entry and trap_enter_rdy;
    exit_debug_mode <= debug_mode_reg and pending_dbg_resume and trap_enter_rdy;
    
    -- Report back to DM instruction injector to tell it its instruction sequence
    -- has finished (ebreak) or crashed out
    dbg_instr_caught_ebreak <= '1' when debug_mode_reg = '1' and trap_enter_rdy = '1' and except = EXCEPT_C.EBREAKPOINT else '0';

    -- Note we exclude ebreak from here regardless of dcsr.ebreakm, since we are
    -- already in debug mode at this point
    dbg_instr_caught_exception <= '1' when debug_mode_reg = '1' and except /= EXCEPT_C.NO_EXCEPTION and except /= EXCEPT_C.EBREAKPOINT and trap_enter_rdy = '1' else '0';

    ---------------------------------------------------------------------------
    -- Trap request generation
    process(clk_always_on) begin
        if rising_edge(clk_always_on) then
            if ?? rst then
                irq_software_reg <= '0';
                irq_timer_reg <= '0';
            else
                irq_software_reg <= irq_software;
                irq_timer_reg <= irq_timer;
            end if;
        end if;
    end process;

    mip <= (
        11 => external_irq_pending,
        7 => irq_timer_reg,
        3 => irq_software_reg,
        others => '0'
    );

    irq_active <= or (mip and mie_reg) and (mstatus_mie_reg or not m_mode_reg) and not dcsr_step_reg;

    -- WFI clear respects individual interrupt enables but ignores mstatus.mie.
    -- Additionally, wfi is treated as a nop during single-stepping and D-mode.
    -- Note that the IRQs and debug halt request input registers are clocked by
    -- clk_always_on, so that a wakeup can be generated when asleep. Note also
    -- that want_halt_irq_if_no_exception can be masked while asleep, so also
    -- feed in the raw halt request as a wakeup source.
    pwr_wfi_wakeup_req <= or(mip and mie_reg) or dcsr_step_reg or debug_mode_reg or want_halt_irq_if_no_exception or dbg_req_halt_prev_reg;

    -- Priority order from priv spec: external > software > timer
    standard_irq_num <= 4d"11" when ?? (mip(11) and mie_reg(11)) else
                        4d"3"  when ?? (mip(3) and mie_reg(3))   else
                        4d"7"  when ?? (mip(7) and mie_reg(7))   else
                        4d"0";
    
    -- EBREAK may be treated as halt-to-debugger or regular M-mode exception, depending on dcsr.ebreakm
    exception_req_any <= '1' when (except /= EXCEPT_C.NO_EXCEPTION) and not (
                                    (except = EXCEPT_C.EBREAKPOINT) and ((m_mode_reg = '1' and dcsr_ebreakm_reg = '1') or (m_mode_reg = '0' and dcsr_ebreaku_reg = '1'))
                                  ) else '0';
                
    mcause_irq_num <= standard_irq_num when ?? irq_active else x"0";
    vector_sel <= mcause_irq_num when ?? (irq_vector_enable and not exception_req_any) else x"0";

    -- Note in the refetch case we're relying on the aliasing of dpc and pc
    -- (The intent is to fetch the sequentially-next instruction again)
    trap_addr <= mepc_reg           when except = EXCEPT_C.RETURN_FROM_M_MODE   else
                 debug_dpc_rdata    when except = EXCEPT_C.EXCEPTION_REFETCH    else
                 debug_dpc_rdata    when ?? pending_dbg_resume                  else
                 mtvec or (26d"0" & vector_sel & "00");

    -- Check for exception-like or IRQ-like trap entry; any debug mode entry takes
    -- priority over any regular trap.
    trap_is_irq <= not want_halt_except when DEBUG_SUPPORT and (want_halt_except = '1' or want_halt_irq = '1') else 
                   not exception_req_any;

    -- When there is a loadstore dphase pending, we block off the IRQ trap
    -- request, but still assert the trap_enter_soon flag. This blocks issue of
    -- further load/stores which have not yet been locked into aphase, so the IRQ
    -- can eventually go through. It's not safe to enter an IRQ when a dphase is
    -- in progress, because that dphase could subsequently except, and sample the
    -- IRQ vector PC instead of the load/store instruction PC.
    trap_enter_vld <= '1' when (
        (CSR_M_TRAP and (
            (exception_req_any = '1') or 
            (delay_irq_entry = '0' and debug_mode = '0' and irq_active = '1' and loadstore_dphase_pending = '0')
        )) or
        (DEBUG_SUPPORT and (
            (delay_irq_entry = '0' and want_halt_irq = '1') or 
            (want_halt_except = '1') or 
            (pending_dbg_resume = '1')
        ))
    ) else '0';

    trap_enter_soon <= '1' when (
        (trap_enter_vld = '1') or
        (DEBUG_SUPPORT and (want_halt_irq_if_no_exception = '1')) or
        (delay_irq_entry = '0' and debug_mode = '0' and irq_active = '1' and loadstore_dphase_pending = '1')
    ) else '0';

    mcause_irq_next <= not exception_req_any;
    mcause_code_next <= except when ?? exception_req_any else mcause_irq_num;

    -- Report trap entry to trigger unit
    trig_event_exception <= '1' when DEBUG_SUPPORT and trapreg_update_enter = '1' and trap_is_irq = '0' else '0';
    trig_event_interrupt <= '1' when DEBUG_SUPPORT and trapreg_update_enter = '1' and trap_is_irq = '1' else '0';
    trig_event_trap_cause <= mcause_code_next when DEBUG_SUPPORT else x"0";

    ---------------------------------------------------------------------------
    -- Privilege state outputs
    pmp_cfg_addr <= addr;
    pmp_cfg_wdata <= wdata_update;
    trig_cfg_addr <= addr;
    trig_cfg_wdata <= wdata_update;
    trig_m_en <= tcontrol_mte_reg;
    m_mode_execution <= '1' when not U_MODE else debug_mode_reg or m_mode_reg;
    m_mode_trap_entry <= '1'             when not U_MODE                           else
                         mstatus_mpp_reg when except = EXCEPT_C.RETURN_FROM_M_MODE else
                         '1';
    m_mode_loadstore <= '1'             when not U_MODE          else 
                        '1'             when debug_mode_reg      else
                        mstatus_mpp_reg when ?? mstatus_mprv_reg else
                        m_mode_reg;


end architecture;