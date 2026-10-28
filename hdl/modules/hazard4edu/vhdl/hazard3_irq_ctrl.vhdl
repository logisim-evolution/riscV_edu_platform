library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.numeric_std_unsigned.all;
use ieee.math_real.all;

use work.hazard3_constants.all;

entity hazard3_irq_ctrl is
    generic(
        -- Number of external IRQs. Note that if EXTENSION_XH3IRQ (IRQ Controller) is disabled, then
        -- multiple external interrupts are OR'd into mip.meip
        NUMBER_OF_IRQs      : integer range 1 to MAX_NUMBER_OF_IRQ_C  := 8;
        -- Number of priority bits implemented for each interrupt in meipra, if EXTENSION_XH3IRQ is enabled.
        -- The number of distinct levels is (1 << IRQ_PRIORITY_BITS), min. 0, max. 4. Note that multiple
        -- priority levels with a large number of IRQs will have a severe effect on timing.
        IRQ_PRIORITY_BITS   : integer range 0 to 4                  := 0;
        -- Disable the input registers on the external interrupts, to reduce latency by one cycle. Can
        -- be applied on an IRQ-by-IRQ basis. Ignored if EXTENSION_HX3IRQ is disabled.
        IRQ_INPUTREG_BYPASS : boolean_vector(NUMBER_OF_IRQs - 1 downto 0) := (others => FALSE)
    );
    port(
        clk           : in std_logic;
        clk_always_on : in std_logic;
        rst           : in std_logic;

        -- CSR interface
        addr        : in  unsigned(CSR_ADDRESS_WIDTH_C - 1 downto 0);
        wtype       : in  std_logic_vector(1 downto 0);
        wen_m_mode  : in  std_logic;
        ren_m_mode  : in  std_logic;
        wdata_raw   : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        wdata       : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        rdata       : out std_logic_vector(DATA_WIDTH_C - 1 downto 0);

        -- Trap entry/exit signals for context update
        trapreg_update_enter : in std_logic;
        trapreg_update_exit  : in std_logic;
        trap_entry_is_eirq   : in std_logic;

        -- Interface for clearing and saving mie.mtie/msie via meicontext
        meicontext_clearts   : out std_logic;
        mie_mtie             : in  std_logic;
        mie_msie             : in  std_logic;

        -- External IRQ inputs
        irq                  : in std_logic_vector(NUMBER_OF_IRQs - 1 downto 0);

        -- mip.meip
        external_irq_pending : out std_logic
    );
end entity hazard3_irq_ctrl;

architecture rtl of hazard3_irq_ctrl is

    -- Helper function to replicate a std_logic_vector N times
    function replicate_vector(vector : std_logic_vector; count : natural) return std_logic_vector is
        variable result : std_logic_vector(vector'length * count - 1 downto 0);
    begin
        for i in 0 to count - 1 loop
            result(vector'length * (i + 1) - 1 downto vector'length * i) := vector;
        end loop;
        return result;
    end function replicate_vector;
    
    constant IRQ_PRIORITY_MASK      : std_logic_vector(3 downto 0)  := not (x"F" srl IRQ_PRIORITY_BITS);
    constant IRQ_INDEX_BITS         : integer                       := clog2(MAX_NUMBER_OF_IRQ_C);

    -- IRQ register (potentially bypassed)
    signal irq_reg                  : std_logic_vector(NUMBER_OF_IRQs - 1 downto 0);

    -- CSR Write stuff
    signal meinext_irq              : std_logic_vector(IRQ_INDEX_BITS - 1 downto 0);
    signal meinext_noirq            : std_logic;
    signal eirq_highest_priority    : std_logic_vector(3 downto 0);

    -- IRQ array register
    signal meiea_reg                : std_logic_vector(NUMBER_OF_IRQs - 1 downto 0);
    signal meifa_reg                : std_logic_vector(NUMBER_OF_IRQs - 1 downto 0);
    signal meipra_reg               : std_logic_vector(NUMBER_OF_IRQs * 4 - 1 downto 0);

    -- Padded Vectors for CSR readout
    signal meiea_rdata              : std_logic_vector(MAX_NUMBER_OF_IRQ_C - 1 downto 0);
    signal meifa_rdata              : std_logic_vector(MAX_NUMBER_OF_IRQ_C - 1 downto 0);
    signal meipra_rdata             : std_logic_vector(MAX_NUMBER_OF_IRQ_C * 4 - 1 downto 0);

    signal meicontext_pppreempt_reg : std_logic_vector(3 downto 0);
    signal meicontext_ppreempt_reg  : std_logic_vector(3 downto 0);
    signal meicontext_preempt_reg   : std_logic_vector(4 downto 0);
    signal meicontext_noirq_reg     : std_logic;
    signal meicontext_irq_reg       : std_logic_vector(IRQ_INDEX_BITS - 1 downto 0);
    signal meicontext_mreteirq_reg  : std_logic;
    signal preempt_level_next       : std_logic_vector(4 downto 0);

    -- External interrupt logic
    signal meipa                        : std_logic_vector(NUMBER_OF_IRQs - 1 downto 0);
    signal meipa_rdata                  : std_logic_vector(MAX_NUMBER_OF_IRQ_C - 1 downto 0);
    signal eirq_active_above_preempt    : std_logic_vector(NUMBER_OF_IRQs - 1 downto 0);
    signal eirq_active_above_ppreempt   : std_logic_vector(NUMBER_OF_IRQs - 1 downto 0);

    signal highest_eirq_oneshot : std_logic_vector(NUMBER_OF_IRQs - 1 downto 0);
    signal meinext_irq_unmasked : std_logic_vector(IRQ_INDEX_BITS - 1 downto 0);
    signal pri_dynamic_calc     : std_logic_vector(4 * NUMBER_OF_IRQs - 1 downto 0);
    signal meinext_irq_unmasked_nopad : std_logic_vector(clog2(NUMBER_OF_IRQs) - 1 downto 0);

begin

    -- ------------------------------------------------------------------------
    -- IRQ input flops
    --
    -- Register external IRQ signals (mainly to avoid a through-path from IRQs to
    -- bus request signals). Always clocked, as it's used to generate a wakeup.
    -- Input registers can be removed on a per-IRQ basis, but this should be done
    -- with care as it does create a through-path from the IRQ to the bus.
    IRQ_INPUT_FF : for i in 0 to NUMBER_OF_IRQs - 1 generate
        BYPASS : if IRQ_INPUTREG_BYPASS(i) generate
            irq_reg(i) <= irq(i);
        else generate
            IRQ_FF : process(clk_always_on) is
            begin
                if rising_edge(clk_always_on) then
                    if ?? rst then
                        irq_reg(i) <= '0';
                    else
                        irq_reg(i) <= irq(i);
                    end if;
                end if;
            end process IRQ_FF;
        end generate BYPASS;
    end generate IRQ_INPUT_FF;
    
    -- ----------------------------------------------------------------------------
    -- CSR write
    meiea_rdata <= resize(meiea_reg, meiea_rdata'length);
    meifa_rdata <= resize(meifa_reg, meifa_rdata'length);
    meipra_rdata <= resize(meipra_reg, meipra_rdata'length);

    UPDATE_IRQ_REG_ARRAYS : process(clk) is
        variable i_vec : signed(IRQ_INDEX_BITS - 1 downto 0);
    begin
        if rising_edge(clk) then
            if ?? rst then
                meiea_reg <= (others => '0');
                meifa_reg <= (others => '0');
                meipra_reg <= (others => '0');
            else
                for i in 0 to NUMBER_OF_IRQs - 1 loop
                    i_vec := to_signed(i, IRQ_INDEX_BITS);

                    -- CSR write update. Note raw wdata is used for array indexing
                    -- Necessary for correctness, and also avoid a loop with rdata.
                    if wen_m_mode = '1' and addr = CSR_ADDRESSES.CUSTOM_M_MODE.MEIEA and 
                       signed(wdata_raw(4 downto 0)) = i_vec(IRQ_INDEX_BITS - 1 downto 4) then
                        meiea_reg(i) <= wdata(16 + (i mod 16));
                    end if;
                    if wen_m_mode = '1' and addr = CSR_ADDRESSES.CUSTOM_M_MODE.MEIFA and 
                       signed(wdata_raw(4 downto 0)) = i_vec(IRQ_INDEX_BITS - 1 downto 4) then
                        meifa_reg(i) <= wdata(16 + (i mod 16));
                    end if;
                    if wen_m_mode = '1' and addr = CSR_ADDRESSES.CUSTOM_M_MODE.MEIPRA and 
                       signed(wdata_raw(6 downto 0)) = i_vec(IRQ_INDEX_BITS - 1 downto 2) then
                        meipra_reg(4 * i + 3 downto 4 * i) <= wdata(16 + 4 * (i mod 4) + 3 downto 16 + 4 * (i mod 4)) and IRQ_PRIORITY_MASK;
                    end if;

                    -- Clear IRQ force when the corresponding IRQ is sampled from meinext
                    -- (so that an IRQ can be posted *once* without modifying the ISR source)
                    if meinext_irq = std_logic_vector(i_vec) and ren_m_mode = '1' and 
                       addr = CSR_ADDRESSES.CUSTOM_M_MODE.MEINEXT and meinext_noirq = '0' then
                        meifa_reg(i) <= '0';
                    end if;
                end loop;            
            end if;
        end if;
    end process UPDATE_IRQ_REG_ARRAYS;
    
    preempt_level_next <= 5x"10" when meinext_noirq = '1' else shift_left(5d"1", 4 - IRQ_PRIORITY_BITS) + resize(eirq_highest_priority, 5);
        
    process(clk) is
    begin
        if rising_edge(clk) then
            if ?? rst then
                meicontext_pppreempt_reg <= (others => '0');
                meicontext_ppreempt_reg <= (others => '0');
                meicontext_preempt_reg <= (others => '0');
                meicontext_noirq_reg <= '1';
                meicontext_irq_reg <= (others => '0');
                meicontext_mreteirq_reg <= '0';
            else
                if trapreg_update_enter = '1' then
                    if trap_entry_is_eirq = '1' then
                        -- Priority save. Note the MSB of preempt needn't be saved, since
                        -- when it is set, preemption is impossible, so we won't be here.
                        meicontext_pppreempt_reg <= meicontext_ppreempt_reg and IRQ_PRIORITY_MASK;
                        meicontext_ppreempt_reg <= meicontext_preempt_reg(3 downto 0) and IRQ_PRIORITY_MASK;
                        -- Setting preempt isn't strictly necessary, since an updating read
                        -- of meinext ought to be performed before re-enabling IRQs via 
                        -- mstatus.mie, but it seems the least surprising thing to do:
                        meicontext_preempt_reg <= preempt_level_next and ('1' & IRQ_PRIORITY_MASK);
                        meicontext_mreteirq_reg <= '1';
                    else
                        meicontext_mreteirq_reg <= '0';
                    end if;
                elsif trapreg_update_exit = '1' then
                    meicontext_mreteirq_reg <= '0';
                    if meicontext_mreteirq_reg = '1' then
                        -- Priority restore
                        meicontext_pppreempt_reg <= (others => '0');
                        meicontext_ppreempt_reg <= meicontext_pppreempt_reg and IRQ_PRIORITY_MASK;
                        meicontext_preempt_reg <= '0' & (meicontext_ppreempt_reg and IRQ_PRIORITY_MASK);
                    end if;
                elsif wen_m_mode = '1' and addr = CSR_ADDRESSES.CUSTOM_M_MODE.MEICONTEXT then
                    meicontext_pppreempt_reg <= wdata(31 downto 28) and IRQ_PRIORITY_MASK;
                    meicontext_ppreempt_reg <= wdata(27 downto 24) and IRQ_PRIORITY_MASK;
                    meicontext_preempt_reg <= wdata(20 downto 16) and ('1' & IRQ_PRIORITY_MASK);
                    meicontext_noirq_reg <= wdata(15);
                    meicontext_irq_reg <= wdata(12 downto 4);
                    meicontext_mreteirq_reg <= wdata(0);
                elsif wen_m_mode = '1' and addr = CSR_ADDRESSES.CUSTOM_M_MODE.MEINEXT and wdata(0) = '1' then
                    -- Interrupt has been sampled, with the update request set, so update
                    -- the context (including preemption level) appropriately.
                    meicontext_preempt_reg <= preempt_level_next and ('1' & IRQ_PRIORITY_MASK);
                    meicontext_noirq_reg <= meinext_noirq;
                    meicontext_irq_reg <= meinext_irq;
                end if;
            end if;
        end if;        
    end process;

    meicontext_clearts <= '1' when wen_m_mode = '1' and
                                   wtype /= CSR_WTYPE.C and
                                   addr = CSR_ADDRESSES.CUSTOM_M_MODE.MEICONTEXT and
                                   wdata_raw(1) = '1'
                              else '0';

    -- ----------------------------------------------------------------------------
    -- External interrupt logic
    --
    -- Trap request is asserted when there is an interrupt at or above our current
    -- preemption level. meinext displays interrupts at or above our *previous*
    -- preemption level: this masking helps avoid re-taking IRQs in frames that you
    -- have preempted. 
    
    meipa <= irq_reg or meifa_reg;
    meipa_rdata <= (MAX_NUMBER_OF_IRQ_C - 1 downto NUMBER_OF_IRQs => '0') & meipa;

    EIRQ_COMPARE : for i in 0 to NUMBER_OF_IRQs - 1 generate
        eirq_active_above_preempt(i) <= meipa(i) and meiea_reg(i) and 
                                        to_std_logic(resize(meipra_reg(i * 4 + 3 downto i * 4), 5) >= meicontext_preempt_reg);
        eirq_active_above_ppreempt(i) <= meipa(i) and meiea_reg(i) and
                                        to_std_logic(meipra_reg(i * 4 + 3 downto i * 4) >= meicontext_ppreempt_reg);
    end generate EIRQ_COMPARE;

    external_irq_pending <= or eirq_active_above_preempt;
    meinext_noirq <= not (or eirq_active_above_ppreempt);

    -- Two things remaining to calculate:
    --
    -- - What is the IRQ number of the highest-priority pending IRQ that is above
    --   meicontext.ppreempt
    -- - What is the priority of that IRQ
    --
    -- In the second case we can relax the calculation to ignore ppreempt, since it
    -- only needs to be valid if such an IRQ exists. Currently we choose to reuse
    -- the same priority selector (possibly longer critpath while saving area), but
    -- we could use a second priority selector that ignores ppreempt masking.
    pri_dynamic_calc <= meipra_reg(4 * NUMBER_OF_IRQs - 1 downto 0) and replicate_vector(IRQ_PRIORITY_MASK, NUMBER_OF_IRQs);
    EIRQ_PRIORITY_U : entity work.hazard3_onehot_priority_dynamic
        generic map(
            REQUEST_WIDTH_C         => NUMBER_OF_IRQs,
            N_PRIORITIES_C          => 16,
            PRIORITY_HIGHEST_WINS_C => TRUE,
            TIEBREAK_HIGHEST_WINS_C => FALSE
        )
        port map(
            pri => pri_dynamic_calc,
            req => eirq_active_above_ppreempt,
            gnt => highest_eirq_oneshot
    );

    -- The process below uses the variable to prevent a combinational feedback loop
    -- in the ghdl-synthesized output. Using a variable to 'buffer' the intermediate
    -- solves the previous issue.
    GET_HIGHEST_EIRQ_PRIORITY : process(all) is
        variable highest_priority : std_logic_vector(3 downto 0);
    begin
        highest_priority := x"0";
        for i in 0 to NUMBER_OF_IRQs - 1 loop
            highest_priority := highest_priority or (
                meipra_reg(4 * i + 3 downto i * 4) and (3 downto 0 => highest_eirq_oneshot(i))
            );
        end loop;        
        eirq_highest_priority <= highest_priority;
    end process GET_HIGHEST_EIRQ_PRIORITY;
    
    EIRQ_ENCODE_U : entity work.hazard3_onehot_encode
        generic map(
            REQUEST_WIDTH_C => NUMBER_OF_IRQs
        )
        port map(
            req => highest_eirq_oneshot,
            gnt => meinext_irq_unmasked_nopad
    );

    ENCODE_EIRQ_NO_PADDING : if clog2(NUMBER_OF_IRQs) = clog2(MAX_NUMBER_OF_IRQ_C) generate
        meinext_irq_unmasked <= meinext_irq_unmasked_nopad;
    else generate --ENCODE_EIRQ_PADDED
        meinext_irq_unmasked <= resize(meinext_irq_unmasked_nopad, IRQ_INDEX_BITS);
    end generate ENCODE_EIRQ_NO_PADDING;
    
    -- It is unnecessary to mask meinext_irq based on meinext_noirq because:
    -- - The value of the CSR field is unimportant when noirq is set
    -- - There are no IRQ inputs to the priority selector when there
    --   are no IRQs, so result is already 0.
    meinext_irq <= meinext_irq_unmasked;
    
    -- ------------------------------------------------------------------------
    -- CSR read
    CSR_READ : process(all) is
        variable index_5bit : integer range 0 to 512;   -- 2^5 * 16
        variable index_7bit : integer range 0 to 2048;  -- 2^7 * 16
    begin
        -- Pre-calculating the index for the different cases, as it is otherwise quite ugly code
        index_5bit := to_integer(unsigned(wdata_raw(4 downto 0))) * 16;
        index_7bit := to_integer(unsigned(wdata_raw(6 downto 0))) * 16;

        rdata <= (others => '0');

        case to_integer(addr) is
            when CSR_ADDRESSES.CUSTOM_M_MODE.MEIEA =>
                rdata <= meiea_rdata(index_5bit + 15 downto index_5bit) & 16d"0";
            when CSR_ADDRESSES.CUSTOM_M_MODE.MEIPA => 
                rdata <= meipa_rdata(index_5bit + 15 downto index_5bit) & 16d"0";
            when CSR_ADDRESSES.CUSTOM_M_MODE.MEIFA => 
                rdata <= meifa_rdata(index_5bit + 15 downto index_5bit) & 16d"0";
            when CSR_ADDRESSES.CUSTOM_M_MODE.MEIPRA => 
                rdata <= meipra_rdata(index_7bit + 15 downto index_7bit) & 16d"0";
            when CSR_ADDRESSES.CUSTOM_M_MODE.MEINEXT => 
                rdata <= meinext_noirq & 20d"0" & meinext_irq & "00";
            when CSR_ADDRESSES.CUSTOM_M_MODE.MEICONTEXT => 
                rdata <= (
                    meicontext_pppreempt_reg &
                    meicontext_ppreempt_reg &
                    "000" &
                    meicontext_preempt_reg &
                    meicontext_noirq_reg &
                    "00" &
                    meicontext_irq_reg &
                    (mie_mtie and meicontext_clearts) &
                    (mie_msie and meicontext_clearts) &
                    '0' &
                    meicontext_mreteirq_reg
                );
            when others => rdata <= (others => '0');
        end case;
        
    end process CSR_READ;
    
    
end architecture rtl;
