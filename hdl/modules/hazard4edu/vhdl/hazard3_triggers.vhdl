library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.ceil;
use ieee.math_real.log2;

use work.hazard3_constants.all;

entity hazard3_triggers is
    generic(
        -- Support for run/halt and instruction injection from any external
        -- Debug Module, support for Debug Mode, and Debug Mode CSR.
        -- Requires: CSR_M_MANDATORY, CSR_M_TRAP
        DEBUG_SUPPORT       : boolean := FALSE;
        -- Number of triggers which support type=2 execute=1 (but not store/load=1,
        -- i.e. not a watchpoint).
        -- Requires: DEBUG_SUPPORT
        BREAKPOINT_TRIGGERS : natural := 0;
        U_MODE              : boolean := FALSE;
        EXTENSION_C         : boolean := TRUE
    );
    port(
        clk              : in  std_logic;
        rst_n            : in  std_logic;
        -- Config interface passed through CSR block
        cfg_addr         : in  std_logic_vector(11 downto 0);
        cfg_wen          : in  std_logic;
        cfg_wdata        : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        cfg_rdata        : out std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        -- Global trigger-to-M-mode enabled from tcontrol
        trig_m_en        : in  std_logic;
        -- Fetch address query from stage F
        fetch_addr       : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        fetch_m_mode     : in  std_logic;
        fetch_d_mode     : in  std_logic;
        -- Trap trigger events from stage X
        event_instr_ret  : in  std_logic;
        -- Trap trigger events from stage M
        event_interrupt  : in  std_logic;
        event_exception  : in  std_logic;
        event_trap_cause : in  unsigned(3 downto 0);
        event_trap_enter : in  std_logic;
        -- F-aligned break request (for each halfword of word-sized word-aligned fetch)
        break_any        : out std_logic_vector(1 downto 0);
        break_d_mode     : out std_logic_vector(1 downto 0);
        -- X-aligned step break request (to M-mode only)
        break_m_step     : out std_logic;
        -- Stage-X debug mode flag, for CSR protection (may or may not be the same as the query debug mode flag)
        x_d_mode         : in  std_logic;
        -- Stage-X M-mode flag, for enables on interrupt / exception triggers
        x_m_mode         : in  std_logic
    );
end entity hazard3_triggers;

architecture rtl of hazard3_triggers is

    constant TRIGGER_INDEX_COUNT       : natural  := BREAKPOINT_TRIGGERS;
    constant TRIGGER_INDEX_INTERRUPT   : natural  := BREAKPOINT_TRIGGERS + 1;
    constant TRIGGER_INDEX_EXCEPTION   : natural  := BREAKPOINT_TRIGGERS + 2;
    constant NUMBER_OF_TRIGGERS        : natural  := BREAKPOINT_TRIGGERS + 3;
    constant NUMBER_OF_BREAKPOINT_REGS : positive := maximum(1, BREAKPOINT_TRIGGERS);

    -- Configuration State
    constant W_TRIGGER_SELECT : positive := integer(ceil(log2(real(NUMBER_OF_TRIGGERS))));

    type trigger_module_t is record
        TSELECT : std_logic_vector(11 downto 0);
        TDATA1 : std_logic_vector(11 downto 0);
        TDATA2 : std_logic_vector(11 downto 0);
        TDATA3 : std_logic_vector(11 downto 0);
        TINFO : std_logic_vector(11 downto 0);
        TCONTROL : std_logic_vector(11 downto 0);
        MCONTEXT : std_logic_vector(11 downto 0);
    end record;

    constant TRIGMODULE_C : trigger_module_t := (
        TSELECT  => 12x"7A0",
        TDATA1   => 12x"7A1",
        TDATA2   => 12x"7A2",
        TDATA3   => 12x"7A3",
        TINFO    => 12x"7A4",
        TCONTROL => 12x"7A5",
        MCONTEXT => 12x"7A8"
    );

    -- Note tdata1 and mcontrol are the same CSR. tdata1 refers to the universal
    -- fields (type/dmode) and mcontrol refers to those fields specific to
    -- type=2 (address/data match), the only trigger type we implement.

    -- State for instruction address match triggers (breakpoints).
    signal bp_tdata1_dmode_reg  : std_logic_vector(NUMBER_OF_BREAKPOINT_REGS-1 downto 0);
    signal mcontrol_action_reg  : std_logic_vector(NUMBER_OF_BREAKPOINT_REGS-1 downto 0);
    signal mcontrol_m_reg       : std_logic_vector(NUMBER_OF_BREAKPOINT_REGS-1 downto 0);
    signal mcontrol_u_reg       : std_logic_vector(NUMBER_OF_BREAKPOINT_REGS-1 downto 0);
    signal mcontrol_execute_reg : std_logic_vector(NUMBER_OF_BREAKPOINT_REGS-1 downto 0);
    type bp_tdata2_t is array (NUMBER_OF_BREAKPOINT_REGS-1 downto 0) of std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal bp_tdata2_reg : bp_tdata2_t;

    -- State for instruction count trigger
    -- (hardwired: count=1 dmode=0 action=0; Debug mode single step is already available via dcsr)
    signal icount_m_reg : std_logic;
    signal icount_u_reg : std_logic;

    -- State for interrupt trigger
    -- (hardwired: action=1; M-mode trap-on-trap is useless as you lose the original trap state)
    signal trigger_irq_m_reg : std_logic;
    signal trigger_irq_u_reg : std_logic;
    signal trigger_irq_dmode_reg : std_logic;
    signal trigger_irq_cause_reg : std_logic_vector(15 downto 0);

    constant IMPLEMENTED_IRQ_CAUSES : std_logic_vector(15 downto 0) := (
        "0000" &    -- reserved
        '1' &       -- meip
        "000" &     -- reserved / unimplemented
        '1' &       -- mtip
        "000" &     -- reserved / unimplemented
        '1' &       -- msip
        "000"       -- reserved / unimplemented
    );

    -- State for exception trigger
    -- (hardwired: action=1; M-mode trap-on-trap is useless as you loose the original trap state)
    signal trigger_exception_m_reg : std_logic;
    signal trigger_exception_u_reg : std_logic;
    signal trigger_exception_dmode_reg : std_logic;
    signal trigger_exception_cause_reg : std_logic_vector(15 downto 0);

    constant IMPLEMENTED_EXCEPTION_CAUSES : std_logic_vector(15 downto 0) := (
        "0000" &
        '1' &
        "00" &
        to_std_logic(U_MODE) &
        '1' &
        '1' &
        '1' &
        '1' &
        '0' &
        '1' &
        '1' &
        to_std_logic(not EXTENSION_C)
    );

    constant NUMBER_OF_TRIGGERS_PADDED : natural := 2 ** integer(ceil(log2(real(NUMBER_OF_TRIGGERS))));
    signal tselect_reg : std_logic_vector(W_TRIGGER_SELECT-1 downto 0);
    signal tselect_match : std_logic_vector(NUMBER_OF_TRIGGERS_PADDED-1 downto 0);

    type tdata_rdata_t is array (NUMBER_OF_TRIGGERS_PADDED-1 downto 0) of std_logic_vector(DATA_WIDTH_C-1 downto 0);
    signal tdata1_rdata, tdata2_rdata, tinfo_rdata : tdata_rdata_t;
    signal exception_trigger_match : std_logic;
    signal interrupt_trigger_match : std_logic;
    signal break_ie_reg : std_logic;
    signal step_break_enabled : std_logic;
    signal break_on_step_reg : std_logic;

    signal breakpoint_enabled : std_logic_vector(NUMBER_OF_BREAKPOINT_REGS-1 downto 0);
    signal breakpoint_match : std_logic_vector(NUMBER_OF_BREAKPOINT_REGS-1 downto 0);
    signal want_m_mode_break : std_logic_vector(NUMBER_OF_BREAKPOINT_REGS-1 downto 0);
    signal want_m_mode_break_hw0 : std_logic_vector(NUMBER_OF_BREAKPOINT_REGS-1 downto 0);
    signal want_m_mode_break_hw1 : std_logic_vector(NUMBER_OF_BREAKPOINT_REGS-1 downto 0);
    signal want_d_mode_break : std_logic_vector(NUMBER_OF_BREAKPOINT_REGS-1 downto 0);
    signal want_d_mode_break_hw0 : std_logic_vector(NUMBER_OF_BREAKPOINT_REGS-1 downto 0);
    signal want_d_mode_break_hw1 : std_logic_vector(NUMBER_OF_BREAKPOINT_REGS-1 downto 0);

begin
    assert DEBUG_SUPPORT or BREAKPOINT_TRIGGERS = 0
    report "BREAKPOINT_TRIGGERS /= 0 requires DEBUG_SUPPORT"
    severity failure;

    NO_TRIGGERS : if not DEBUG_SUPPORT generate
        cfg_rdata    <= (others => '0');
        break_any    <= "00";
        break_d_mode <= "00";
        break_m_step <= '0';
    end generate NO_TRIGGERS;

    HAVE_TRIGGERS : if DEBUG_SUPPORT generate
        -- Line 482-490
        -- Break flags to front end (tag the current fetch dphase as containing a breakpoint)
        break_any       <= ( ((or want_m_mode_break_hw1) or (or want_d_mode_break_hw1) or break_ie_reg) &
                             ((or want_m_mode_break_hw0) or (or want_d_mode_break_hw0) or break_ie_reg) )
                            when BREAKPOINT_TRIGGERS > 0 else "00";                
        break_d_mode    <= ( ((or want_d_mode_break_hw1) or break_ie_reg) &
                             ((or want_d_mode_break_hw0) or break_ie_reg) )
                            when BREAKPOINT_TRIGGERS > 0 else "00";
        break_m_step    <= break_on_step_reg;

        with cfg_addr select
            cfg_rdata <=
                (DATA_WIDTH_C-1 downto W_TRIGGER_SELECT => '0') & tselect_reg when TRIGMODULE_C.TSELECT,
                tdata1_rdata(to_integer(unsigned(tselect_reg)))               when TRIGMODULE_C.TDATA1,
                tdata2_rdata(to_integer(unsigned(tselect_reg)))               when TRIGMODULE_C.TDATA2,
                tinfo_rdata(to_integer(unsigned(tselect_reg)))                when TRIGMODULE_C.TINFO,
                (others => '0')                                               when others;


        -- -----------------------------------------------------------------------------------------
        -- Configuration write port
        -- L168-270
        tselect_match <= std_logic_vector(to_unsigned(1, NUMBER_OF_TRIGGERS_PADDED)) sll to_integer(unsigned(tselect_reg));
        CFG_UPDATE : process(clk, rst_n) is
        begin
            if rst_n = '0' then
                tselect_reg <= (others => '0');
                icount_m_reg <= '0';
                icount_u_reg <= '0';
                trigger_irq_m_reg <= '0';
                trigger_irq_u_reg <= '0';
                trigger_irq_dmode_reg <= '0';
                trigger_irq_cause_reg <= (others => '0');
                trigger_exception_m_reg <= '0';
                trigger_exception_u_reg <= '0';
                trigger_exception_dmode_reg <= '0';
                trigger_exception_cause_reg <= (others => '0');
                bp_tdata1_dmode_reg <= (others => '0');
                mcontrol_action_reg <= (others => '0');
                mcontrol_m_reg <= (others => '0');
                mcontrol_u_reg <= (others => '0');
                mcontrol_execute_reg <= (others => '0');
                bp_tdata2_reg <= (others => (others => '0'));
            elsif rising_edge(clk) then
                if cfg_wen = '1' and cfg_addr = TRIGMODULE_C.TSELECT then

                    tselect_reg <= cfg_wdata(W_TRIGGER_SELECT - 1 downto 0);

                elsif cfg_wen = '1' and cfg_addr = TRIGMODULE_C.TDATA1 then

                    if tselect_match(TRIGGER_INDEX_COUNT) = '1' then
                        -- This trigger does not implement a dmode bit, as Debug-mode
                        -- break on single-step is already provided by dcsr.step
                        icount_m_reg <= cfg_wdata(9);
                        icount_u_reg <= cfg_wdata(6) and to_std_logic(U_MODE);
                    end if;
                    if tselect_match(TRIGGER_INDEX_INTERRUPT) = '1' and (trigger_irq_dmode_reg and (not x_d_mode)) = '0' then
                        trigger_irq_dmode_reg <= cfg_wdata(27);
                        trigger_irq_m_reg <= cfg_wdata(9);
                        trigger_irq_u_reg <= cfg_wdata(6) and to_std_logic(U_MODE);
                    end if;
                    if tselect_match(TRIGGER_INDEX_EXCEPTION) = '1' and (trigger_exception_dmode_reg and (not x_d_mode)) = '0' then
                        trigger_exception_dmode_reg <= cfg_wdata(27);
                        trigger_exception_m_reg <= cfg_wdata(9);
                        trigger_exception_u_reg <= cfg_wdata(6) and to_std_logic(U_MODE);
                    end if;
                    for i in 0 to BREAKPOINT_TRIGGERS - 1 loop
                        if tselect_match(i) = '1' and (bp_tdata1_dmode_reg(i) and (not x_d_mode)) = '0' then
                            if x_d_mode = '1' then
                                bp_tdata1_dmode_reg(i) <= cfg_wdata(27);
                            end if;
                            mcontrol_action_reg(i) <= cfg_wdata(12);
                            mcontrol_m_reg(i) <= cfg_wdata(6);
                            mcontrol_u_reg(i) <= cfg_wdata(3) and to_std_logic(U_MODE);
                            mcontrol_execute_reg(i) <= cfg_wdata(2);
                        end if;
                    end loop;
                    
                elsif cfg_wen = '1' and cfg_addr = TRIGMODULE_C.TDATA2 then

                    if tselect_match(TRIGGER_INDEX_INTERRUPT) = '1' and (trigger_irq_dmode_reg and (not x_d_mode)) = '0' then
                        trigger_irq_cause_reg <= cfg_wdata(15 downto 0) and IMPLEMENTED_IRQ_CAUSES;
                    end if;

                    if tselect_match(TRIGGER_INDEX_EXCEPTION) = '1' and (trigger_exception_dmode_reg and (not x_d_mode)) = '0' then
                        trigger_exception_cause_reg <= cfg_wdata(15 downto 0) and IMPLEMENTED_EXCEPTION_CAUSES;
                    end if;

                    for i in 0 to BREAKPOINT_TRIGGERS - 1 loop
                        if tselect_match(i) = '1' and (bp_tdata1_dmode_reg(i) and (not x_d_mode)) = '0' then
                            bp_tdata2_reg(i) <= cfg_wdata(DATA_WIDTH_C - 1 downto 2) & 
                                                (cfg_wdata(1) and to_std_logic(EXTENSION_C)) & 
                                                '0';
                        end if;
                    end loop;

                end if;

                -- Clear instruction count enables when stepping triggers
                if (x_d_mode = '1' or event_trap_enter = '1') and break_on_step_reg = '1' then
                    icount_m_reg <= '0';
                    icount_u_reg <= '0';
                end if;

                if BREAKPOINT_TRIGGERS = 0 then
                    bp_tdata1_dmode_reg(0) <= '0';
                    mcontrol_action_reg(0) <= '0';
                    mcontrol_m_reg(0) <= '0';
                    mcontrol_u_reg(0) <= '0';
                    mcontrol_execute_reg(0) <= '0';
                    bp_tdata2_reg(0) <= (others => '0');
                end if;
            end if;
        end process CFG_UPDATE;
        

        -- -----------------------------------------------------------------------------------------
        -- Configuration read port
        GENERATE_PADDED_RDATA : process (all) is 
        begin
            tdata1_rdata <= (others => (others => '0'));
            tdata2_rdata <= (others => (others => '0'));
            tinfo_rdata <= (others => 32d"1" sll 0);

            -- Breakpoints are the first n triggers
            for i in 0 to BREAKPOINT_TRIGGERS - 1 loop
                tdata1_rdata(i) <= (
                    x"2" &                            -- type = address/data match
                    bp_tdata1_dmode_reg(i) &
                    6x"0" &                          -- maskmax = 0, exact match only
                    '0' &                               -- hit = 0, not implemented
                    '0' &                               -- select = 0, address match only
                    '0' &                               -- timing = 0, trigger before execution
                    "00" &                              -- sizelo = 0, unsized
                    (3x"0" & mcontrol_action_reg(i)) &  -- action = 0/1, break to M-mode/D-mode
                    '0' &                               -- chain = 0, chaining is useless for exact matches
                    x"0" &                            -- match = 0, exact match only
                    mcontrol_m_reg(i) &
                    '0' &
                    '0' &                               -- s = 0, no S-mode
                    mcontrol_u_reg(i) &
                    mcontrol_execute_reg(i) &
                    '0' &                               -- store = 0, this is not a watchpoint
                    '0'                                 -- load = 0, this is not a watchpoint
                );
                tdata2_rdata(i) <= bp_tdata2_reg(i);
                tinfo_rdata(i) <= 32d"1" sll 2;         -- type = 2, address / data match
            end loop;

            -- Instruction count triggers
            tdata1_rdata(TRIGGER_INDEX_COUNT) <= (
                x"3"&           -- type = instruction count
                '0' &           -- dmode = 0 (debug mode already has dcsr.step)
                "00" &          -- reserved
                '0' &           -- hit = 0
                14d"1" &        -- count = 1, single-step only
                icount_m_reg &
                '0' &           -- reserved
                '0' &           -- s = 0, no S-mode
                icount_u_reg &
                6x"0"           -- action = 0, break to M-mode
            );
            tinfo_rdata(TRIGGER_INDEX_COUNT) <= 32d"1" sll 3;

            -- Interrupt trigger
            tdata1_rdata(TRIGGER_INDEX_INTERRUPT) <= (
                x"4" &                      -- type = interrupt
                trigger_irq_dmode_reg &
                '0' &                       -- hit = 0
                16d"0" &                    -- reserved
                trigger_irq_m_reg &
                '0' &                       -- reserved
                '0' &                       -- s = 0, no S-mode
                trigger_irq_u_reg &
                6d"1"                       -- action = 1, break to Debug mode (if dmode = 1)
            );
            tdata2_rdata(TRIGGER_INDEX_INTERRUPT) <= (
                16d"0" &
                (trigger_irq_cause_reg and IMPLEMENTED_IRQ_CAUSES)
            );
            tinfo_rdata(TRIGGER_INDEX_INTERRUPT) <= 32d"1" sll 4;

            -- Exception trigger
            tdata1_rdata(TRIGGER_INDEX_EXCEPTION) <= (
                x"5" &                          -- type = exception
                trigger_exception_dmode_reg &
                '0' &                           -- hit = 0
                16d"0" &                        -- reserved
                trigger_exception_m_reg &
                '0' &                           -- reserved
                '0' &                           -- s = 0, no S-mode
                trigger_exception_u_reg &
                6d"1"                           -- action = 1, break to Debug (if dmode = 1)
            );
            tdata2_rdata(TRIGGER_INDEX_EXCEPTION) <= (
                16d"0" &
                (trigger_exception_cause_reg and IMPLEMENTED_EXCEPTION_CAUSES)
            );
            tinfo_rdata(TRIGGER_INDEX_EXCEPTION) <= 32d"1" sll 5;
        end process GENERATE_PADDED_RDATA;
        

        -- -----------------------------------------------------------------------------------------
        -- Interrupt/exception trigger logic
        -- Ignore tcontrol.mte as these triggers never target M-mode.
        -- Line 384-411
        exception_trigger_match <= (not x_d_mode) and trigger_exception_dmode_reg and 
                                   trigger_exception_m_reg and event_exception and 
                                   trigger_exception_cause_reg(to_integer(event_trap_cause)) and 
                                   IMPLEMENTED_EXCEPTION_CAUSES(to_integer(event_trap_cause)) 
                                        when x_m_mode = '1' else
                                   (not x_d_mode) and trigger_exception_dmode_reg and
                                   trigger_exception_u_reg and event_exception and
                                   trigger_exception_cause_reg(to_integer(event_trap_cause)) and
                                   IMPLEMENTED_EXCEPTION_CAUSES(to_integer(event_trap_cause));
        interrupt_trigger_match <= (not x_d_mode) and trigger_irq_dmode_reg and
                                   trigger_irq_m_reg and event_interrupt and
                                   trigger_irq_cause_reg(to_integer(event_trap_cause)) and
                                   IMPLEMENTED_IRQ_CAUSES(to_integer(event_trap_cause))
                                        when x_m_mode = '1' else
                                    (not x_d_mode) and trigger_irq_dmode_reg and
                                   trigger_irq_u_reg and event_interrupt and
                                   trigger_irq_cause_reg(to_integer(event_trap_cause)) and
                                   IMPLEMENTED_IRQ_CAUSES(to_integer(event_trap_cause));
        process(clk, rst_n) is
        begin
            if rst_n = '0' then
                break_ie_reg <= '0';
            elsif rising_edge(clk) then
                break_ie_reg <= (not x_d_mode) and (break_ie_reg or exception_trigger_match or interrupt_trigger_match);
            end if; 
        end process;

        -- -----------------------------------------------------------------------------------------
        -- Instruction count trigger logic (single-steo under M-mode control)
        -- Line 413-432
        step_break_enabled <= trig_m_en and (not x_d_mode) and icount_m_reg when x_m_mode = '1' else
                              trig_m_en and (not x_d_mode) and icount_u_reg;
        
        -- L422
        process(clk, rst_n) is
        begin
            if rst_n = '0' then
                break_on_step_reg <= '0';
            elsif rising_edge(clk) then
                -- Note icount triggers differ from dcsr.step in that they ignore exceptions,
                -- only triggering on retired instructions.
                break_on_step_reg <= (not (x_d_mode or event_trap_enter)) and 
                                     (break_on_step_reg or (event_instr_ret and step_break_enabled));
            end if;
        end process;


        -- -----------------------------------------------------------------------------------------
        -- Breakpoint trigger logic

        -- To reduce the fanin of jump and load/store gating in stage X, the address
        -- lookup is in stage F (fetch data phase). We check *fetch addresses*, not
        -- program counter values. Fetches are always word-sized and word-aligned.
        --
        -- To ensure it is safe to do this, non-debug-mode writes to the TDATA1 and
        -- TDATA2 CSRs cause a prefetch flush, to maintain write-to-fetch ordering.
        --
        -- It's possible for different breakpoints to match different halfwords of the
        -- fetch word. The trigger unit must report both matches separately, because
        -- it is not known at this point where the instruction boundaries are (we
        -- don't have the instruction data yet).
        -- Line 460-478
        MATCH_PC : for i in 0 to NUMBER_OF_BREAKPOINT_REGS-1 generate
            -- Detect breakpoints
            breakpoint_enabled(i) <= mcontrol_execute_reg(i) and (not fetch_d_mode) and mcontrol_m_reg(i) when fetch_m_mode = '1' else
                                     mcontrol_execute_reg(i) and (not fetch_d_mode) and mcontrol_u_reg(i);
            breakpoint_match(i) <= '1' when breakpoint_enabled(i) = '1' and fetch_addr = (bp_tdata2_reg(i)(DATA_WIDTH_C-1 downto 2) & "00") else '0';
            -- Decide the type of break implied by the trip
            want_d_mode_break(i) <= breakpoint_match(i) and mcontrol_action_reg(i) and bp_tdata1_dmode_reg(i);
            want_m_mode_break(i) <= breakpoint_match(i) and (not mcontrol_action_reg(i)) and trig_m_en;
            -- Report seperately for each halfword, so the frontend can pass this through the prefetch buffer.
            -- A breakpoint exception is taken when the first halfword of an instruction (of any size) is flagged
            -- with a breakpoint, implying an exact match.
            want_d_mode_break_hw0(i) <= want_d_mode_break(i) and (not bp_tdata2_reg(i)(1));
            want_d_mode_break_hw1(i) <= want_d_mode_break(i) and bp_tdata2_reg(i)(1);
            want_m_mode_break_hw0(i) <= want_m_mode_break(i) and (not bp_tdata2_reg(i)(1));
            want_m_mode_break_hw1(i) <= want_m_mode_break(i) and bp_tdata2_reg(i)(1);
        end generate MATCH_PC;
        
    end generate HAVE_TRIGGERS;
end architecture rtl;
