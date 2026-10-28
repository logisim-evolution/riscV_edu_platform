library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.hazard3_constants.all;

-- Physical memory protection unit
entity hazard3_pmp is
    generic(
        -- Number of physical memory protection regions, or 0 for no PMP.
        PMP_REGIONS        : natural := 0;
        -- "G" parameter in the privileged spec. Minimum PMP region size is
        -- 1 << (G + 2) bytes. If G > 0, PMPCFG.A can not be set to NA4.
        -- If G > 1, the G - 1 LSBs of pmpaddr are read-only-0 when PMPCFG.A is
        -- OFF, and read-only-1 when PMPCFG.A is NAPOT.
        PMP_GRAIN          : natural := 0;
        -- Enable PMP support for the NAPOT (and NA4 if G == 0) matching modes.
        -- If disabled, attempting to select these modes sets the region to OFF.
        PMP_MATCH_NAPOT    : boolean := TRUE;
        -- Enable PMP support for the TOR (top-of-range) matching mode.
        PMP_MATCH_TOR      : boolean := FALSE;
        -- If a bit is 1, the corresponding region's pmpaddr and pmpcfg registers
        -- are read-only. PMP_GRAIN is ignored on hardwired regions.
        PMP_HARDWIRED      : std_logic_vector(maximum(PMP_REGIONS, 1) - 1 downto 0)      := (others => '0');
        -- Values of pmpaddr registers whose PMP_HARDWIRED bits are set to 1 (32 bits per region)
        PMP_HARDWIRED_ADDR : std_logic_vector(32 * maximum(PMP_REGIONS, 1) - 1 downto 0) := (others => '0');
        -- Values of pmpcfg registers whose PMP_HARDWIRED bits are set to 1 (8 bits per region)
        PMP_HARDWIRED_CFG  : std_logic_vector(8 * maximum(PMP_REGIONS, 1) - 1 downto 0)  := (others => '0');
        -- PMPCFGMx CSRs to enforce PMP regions in M-mode without locking
        EXTENSION_XH3PMPM  : boolean := TRUE
    );
    port(
        clk                       : in  std_logic;
        rst                       : in  std_logic;
        -- Config interface passed through CSR block
        cfg_addr                  : in  unsigned(CSR_ADDRESS_WIDTH_C - 1 downto 0);
        cfg_wen                   : in  std_logic;
        cfg_wdata                 : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        cfg_rdata                 : out std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        -- Fetch address query
        i_addr                    : in  unsigned(ADDRESS_WIDTH_C - 1 downto 0);
        i_m_mode                  : in  std_logic;
        i_kill                    : out std_logic;
        -- Load/store address query
        d_addr                    : in  unsigned(ADDRESS_WIDTH_C - 1 downto 0);
        -- Broken out separately for carry-save:
        d_addr_addend_rs1         : in  unsigned(ADDRESS_WIDTH_C - 1 downto 0);
        d_addr_addend_imm         : in  unsigned(ADDRESS_WIDTH_C - 1 downto 0);
        d_addr_addend_lspair_offs : in  unsigned(ADDRESS_WIDTH_C - 1 downto 0);
        d_m_mode                  : in  std_logic;
        d_write                   : in  std_logic;
        d_kill                    : out std_logic
    );
end entity hazard3_pmp;

architecture rtl of hazard3_pmp is

    constant PMP_A_NAPOT : std_logic_vector(1 downto 0) := "11";
    constant PMP_A_NA4   : std_logic_vector(1 downto 0) := "10";
    constant PMP_A_TOR   : std_logic_vector(1 downto 0) := "01";
    constant PMP_A_OFF   : std_logic_vector(1 downto 0) := "00";

    -- Which values are supported in A field (unsupported are mapped to OFF),
    -- indexed by the A value:
    constant PMP_A_SUPPORTED : boolean_vector(3 downto 0) := (
        3 => PMP_MATCH_NAPOT,
        2 => PMP_MATCH_NAPOT and PMP_GRAIN = 0,
        1 => PMP_MATCH_TOR,
        0 => TRUE
    );

    constant PMPCFG0  : csr_addr_t := CSR_ADDRESSES.MACHINE_MEMORY_PROTECTION.PMPCFG0;
    constant PMPADDR0 : csr_addr_t := CSR_ADDRESSES.MACHINE_MEMORY_PROTECTION.PMPADDR0;
    constant PMPCFGM0 : csr_addr_t := CSR_ADDRESSES.CUSTOM_M_MODE.PMPCFGM0;

    -- Address register contains bits 33:2 of the address (to support 16 GiB
    -- physical address space). We don't implement bits 33 or 32.
    constant W_PMPADDR : natural := ADDRESS_WIDTH_C - 2;

    -- Mask with the n least-significant bits set, i.e. ~(~30'h0 << n).
    -- Returns all-zeroes for n <= 0.
    function low_ones(n : integer) return std_logic_vector is
        variable result : std_logic_vector(W_PMPADDR - 1 downto 0) := (others => '0');
    begin
        for k in result'range loop
            if k < n then
                result(k) := '1';
            end if;
        end loop;
        return result;
    end function low_ones;

begin

    PMP_SUPPORT : if PMP_REGIONS = 0 generate
        -- This should already be stubbed out in the core, but use a generate here
        -- too so that elaborating this entity with a region count of 0 is harmless.
        cfg_rdata <= (others => '0');
        i_kill    <= '0';
        d_kill    <= '0';

    else generate
        -- Whether a region's configuration is writable; this is non-trivial when TOR
        -- is supported because locking region i + 1 can also lock region i.
        signal region_locked : std_logic_vector(PMP_REGIONS - 1 downto 0);

        signal pmpcfg_l_reg : std_logic_vector(PMP_REGIONS - 1 downto 0);
        signal pmpcfg_a_reg : std_logic_array_t(0 to PMP_REGIONS - 1)(1 downto 0);
        signal pmpcfg_x_reg : std_logic_vector(PMP_REGIONS - 1 downto 0);
        signal pmpcfg_w_reg : std_logic_vector(PMP_REGIONS - 1 downto 0);
        signal pmpcfg_r_reg : std_logic_vector(PMP_REGIONS - 1 downto 0);

        signal pmpaddr_reg  : std_logic_array_t(0 to PMP_REGIONS - 1)(W_PMPADDR - 1 downto 0);

        -- Hazard3 extension for applying PMP regions to M-mode without locking.
        -- Different from ePMP mseccfg.rlb: low-numbered regions may be locked for
        -- security reasons, but higher-numbered regions should still be available
        -- for other purposes e.g. stack guarding, peripheral emulation
        signal pmpcfg_m_reg : std_logic_vector(PMP_REGIONS - 1 downto 0);

        signal pmp_region_is_tor : std_logic_vector(PMP_REGIONS - 1 downto 0);

        signal d_match_napot : std_logic_vector(PMP_REGIONS - 1 downto 0);
        signal i_match_napot : std_logic_vector(PMP_REGIONS - 1 downto 0);
        signal d_match_tor   : std_logic_vector(PMP_REGIONS - 1 downto 0);
        signal i_match_tor   : std_logic_vector(PMP_REGIONS - 1 downto 0);

        signal d_m : std_logic; -- Hazard3 extension (M-mode without locking)
        signal d_l : std_logic;
        signal d_r : std_logic;
        signal d_w : std_logic;

        signal i_m : std_logic; -- Hazard3 extension (M-mode without locking)
        signal i_l : std_logic;
        signal i_x : std_logic;
    begin

        ---------------------------------------------------------------------------
        -- Config registers and read/write interface

        CFG_UPDATE : process(clk)
            variable v_byte : natural;
        begin
            if rising_edge(clk) then
                if ?? rst then
                    for i in 0 to PMP_REGIONS - 1 loop
                        if PMP_HARDWIRED(i) = '1' then
                            pmpcfg_l_reg(i) <= PMP_HARDWIRED_CFG(8 * i + 7);
                            pmpcfg_a_reg(i) <= PMP_HARDWIRED_CFG(8 * i + 4 downto 8 * i + 3);
                            pmpcfg_x_reg(i) <= PMP_HARDWIRED_CFG(8 * i + 2);
                            pmpcfg_w_reg(i) <= PMP_HARDWIRED_CFG(8 * i + 1);
                            pmpcfg_r_reg(i) <= PMP_HARDWIRED_CFG(8 * i + 0);
                            pmpaddr_reg(i)  <= PMP_HARDWIRED_ADDR(32 * i + W_PMPADDR - 1 downto 32 * i);
                        else
                            pmpcfg_l_reg(i) <= '0';
                            pmpcfg_a_reg(i) <= PMP_A_OFF;
                            pmpcfg_x_reg(i) <= '0';
                            pmpcfg_w_reg(i) <= '0';
                            pmpcfg_r_reg(i) <= '0';
                            -- G - 1 LSBs are ones when PMP_GRAIN > 1 (low_ones yields zero otherwise)
                            pmpaddr_reg(i)  <= low_ones(PMP_GRAIN - 1);
                        end if;
                    end loop;
                    pmpcfg_m_reg <= (others => '0');
                else
                    if ?? cfg_wen then
                        for i in 0 to PMP_REGIONS - 1 loop
                            -- Bit offset of this region's byte within its pmpcfg register
                            v_byte := (i mod 4) * 8;
                            if cfg_addr = to_unsigned(PMPCFG0 + i / 4, cfg_addr'length) and region_locked(i) = '0' then
                                if PMP_HARDWIRED(i) = '1' then
                                    -- Keep tied to hardwired value (but still make the "register" sensitive to clk)
                                    pmpcfg_l_reg(i) <= PMP_HARDWIRED_CFG(8 * i + 7);
                                    pmpcfg_a_reg(i) <= PMP_HARDWIRED_CFG(8 * i + 4 downto 8 * i + 3);
                                    pmpcfg_x_reg(i) <= PMP_HARDWIRED_CFG(8 * i + 2);
                                    pmpcfg_w_reg(i) <= PMP_HARDWIRED_CFG(8 * i + 1);
                                    pmpcfg_r_reg(i) <= PMP_HARDWIRED_CFG(8 * i + 0);
                                    pmpaddr_reg(i)  <= PMP_HARDWIRED_ADDR(32 * i + W_PMPADDR - 1 downto 32 * i);
                                else
                                    pmpcfg_l_reg(i) <= cfg_wdata(v_byte + 7);
                                    pmpcfg_x_reg(i) <= cfg_wdata(v_byte + 2);
                                    pmpcfg_w_reg(i) <= cfg_wdata(v_byte + 1);
                                    pmpcfg_r_reg(i) <= cfg_wdata(v_byte + 0);
                                    -- Unsupported A values are mapped to OFF (it's a WARL field).
                                    if PMP_A_SUPPORTED(to_integer(unsigned(cfg_wdata(v_byte + 4 downto v_byte + 3)))) then
                                        pmpcfg_a_reg(i) <= cfg_wdata(v_byte + 4 downto v_byte + 3);
                                    else
                                        pmpcfg_a_reg(i) <= PMP_A_OFF;
                                    end if;
                                end if;
                            end if;
                            if cfg_addr = to_unsigned(PMPADDR0 + i, cfg_addr'length) and region_locked(i) = '0' then
                                -- This implements one bit too many when G > 0 and only
                                -- PMP_MATCH_TOR is enabled, however that bit is ignored for
                                -- both rdata and address matching, so should be trimmed.
                                -- (low_ones yields zero unless PMP_GRAIN > 1)
                                pmpaddr_reg(i) <= cfg_wdata(W_PMPADDR - 1 downto 0) or low_ones(PMP_GRAIN - 1);
                            end if;
                        end loop;
                        if cfg_addr = to_unsigned(PMPCFGM0, cfg_addr'length) then
                            if EXTENSION_XH3PMPM then
                                pmpcfg_m_reg <= cfg_wdata(PMP_REGIONS - 1 downto 0) and not PMP_HARDWIRED;
                            else
                                pmpcfg_m_reg <= (others => '0');
                            end if;
                        end if;
                    end if;
                end if;
            end if;
        end process CFG_UPDATE;

        CFG_READ : process(all)
            variable v_rdata : std_logic_vector(cfg_rdata'range);
            variable v_byte  : natural;
        begin
            v_rdata := (others => '0');
            for i in 0 to PMP_REGIONS - 1 loop
                v_byte := (i mod 4) * 8;
                if cfg_addr = to_unsigned(PMPCFG0 + i / 4, cfg_addr'length) then
                    v_rdata(v_byte + 7 downto v_byte) := pmpcfg_l_reg(i) &
                                                         "00" &
                                                         pmpcfg_a_reg(i) &
                                                         pmpcfg_x_reg(i) &
                                                         pmpcfg_w_reg(i) &
                                                         pmpcfg_r_reg(i);
                elsif cfg_addr = to_unsigned(PMPADDR0 + i, cfg_addr'length) then
                    if PMP_GRAIN >= 2 and pmpcfg_a_reg(i)(1) = '1' then
                        -- Bits G-2:0 read back as all-ones when A is NA4 or NAPOT.
                        v_rdata(W_PMPADDR - 1 downto 0) := pmpaddr_reg(i) or low_ones(PMP_GRAIN - 1);
                    elsif PMP_GRAIN >= 1 and pmpcfg_a_reg(i)(1) = '0' then
                        -- Bits G-1:0 read back as all-zeroes when A is OFF or TOR.
                        v_rdata(W_PMPADDR - 1 downto 0) := pmpaddr_reg(i) and not low_ones(PMP_GRAIN);
                    else
                        v_rdata(W_PMPADDR - 1 downto 0) := pmpaddr_reg(i);
                    end if;
                end if;
            end loop;
            if cfg_addr = to_unsigned(PMPCFGM0, cfg_addr'length) then
                v_rdata := (others => '0');
                if EXTENSION_XH3PMPM then
                    v_rdata(PMP_REGIONS - 1 downto 0) := pmpcfg_m_reg;
                end if;
            end if;
            cfg_rdata <= v_rdata;
        end process CFG_READ;

        ---------------------------------------------------------------------------
        -- Region locking rules

        CHECK_REGION_IS_TOR : for i in 0 to PMP_REGIONS - 1 generate
            pmp_region_is_tor(i) <= '1' when PMP_MATCH_TOR and pmpcfg_a_reg(i) = PMP_A_TOR else '0';
        end generate CHECK_REGION_IS_TOR;

        region_locked <= pmpcfg_l_reg or ((pmpcfg_l_reg and pmp_region_is_tor) srl 1);

        ---------------------------------------------------------------------------
        -- Match addresses against regions

        NAPOT_SUPPORT : if PMP_MATCH_NAPOT generate
            -- Decode PMPCFGx.A and PMPADDRx into a 32-bit address mask and address
            signal match_mask : std_logic_array_t(0 to PMP_REGIONS - 1)(ADDRESS_WIDTH_C - 1 downto 0);
            signal match_addr : std_logic_array_t(0 to PMP_REGIONS - 1)(ADDRESS_WIDTH_C - 1 downto 0);
        begin
            -- Encoding: (noting ADDR is a 4-byte address, not a word address):
            -- CFG.A |  ADDR    | Region size
            -- ------+----------+------------
            -- NA4   | y..yyyyy | 4 bytes
            -- NAPOT | y..yyyy0 | 8 bytes
            -- NAPOT | y..yyy01 | 16 bytes
            -- NAPOT | y..yy011 | 32 bytes
            -- NAPOT | y..y0111 | 64 bytes
            -- etc.
            --
            -- So, with the exception of NA4, the rule is to check all bits more
            -- significant than the least-significant 0 bit.
            DECODE_MATCH_MASK_ADDR : process(all)
                variable v_mask : std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0);
            begin
                for i in 0 to PMP_REGIONS - 1 loop
                    if pmpcfg_a_reg(i)(0) = '0' then
                        v_mask := (others => '1');
                        v_mask(1 downto 0) := "00";
                    else
                        -- Bits 1:0 are always 0. Bit 2 is 0 because NAPOT is at least 8 bytes.
                        v_mask := (others => '0');
                        for j in 3 to ADDRESS_WIDTH_C - 1 loop
                            v_mask(j) := v_mask(j - 1) or not pmpaddr_reg(i)(j - 3);
                        end loop;
                    end if;
                    match_mask(i) <= v_mask;
                    match_addr(i) <= (pmpaddr_reg(i) & "00") and v_mask;
                end loop;
            end process DECODE_MATCH_MASK_ADDR;

            -- We check only the least-addressed byte of each access. See later
            -- comments for an argument as to why this is sufficient.
            CHECK_NAPOT_MATCH : for i in 0 to PMP_REGIONS - 1 generate
                d_match_napot(i) <= '1' when pmpcfg_a_reg(i)(1) = '1' and
                                             (std_logic_vector(d_addr) and match_mask(i)) = match_addr(i) else '0';
                i_match_napot(i) <= '1' when pmpcfg_a_reg(i)(1) = '1' and
                                             (std_logic_vector(i_addr) and match_mask(i)) = match_addr(i) else '0';
            end generate CHECK_NAPOT_MATCH;

        else generate
            d_match_napot <= (others => '0');
            i_match_napot <= (others => '0');
        end generate NAPOT_SUPPORT;

        TOR_SUPPORT : if PMP_MATCH_TOR generate
            signal watermark  : std_logic_array_t(0 to PMP_REGIONS - 1)(ADDRESS_WIDTH_C - 1 downto 0);
            signal d_addr_sum : unsigned(ADDRESS_WIDTH_C - 1 downto 0);
            signal d_lt       : std_logic_vector(PMP_REGIONS - 1 downto 0);
            signal i_lt       : std_logic_vector(PMP_REGIONS - 1 downto 0);
            signal d_prev_ge  : std_logic_vector(PMP_REGIONS - 1 downto 0);
            signal i_prev_ge  : std_logic_vector(PMP_REGIONS - 1 downto 0);
        begin
            -- Bring terms in separately to try to encourage adder merging
            d_addr_sum <= d_addr_addend_rs1 + d_addr_addend_imm + d_addr_addend_lspair_offs;

            COMPARE : for i in 0 to PMP_REGIONS - 1 generate
                watermark(i) <= (pmpaddr_reg(i) and not low_ones(PMP_GRAIN)) & "00";
                d_lt(i) <= '1' when d_addr_sum < unsigned(watermark(i)) else '0';
                i_lt(i) <= '1' when i_addr     < unsigned(watermark(i)) else '0';
            end generate COMPARE;

            d_prev_ge <= not (d_lt sll 1);
            i_prev_ge <= not (i_lt sll 1);

            MATCH : for i in 0 to PMP_REGIONS - 1 generate
                d_match_tor(i) <= d_lt(i) and d_prev_ge(i) and to_std_logic(pmpcfg_a_reg(i) = PMP_A_TOR);
                i_match_tor(i) <= i_lt(i) and i_prev_ge(i) and to_std_logic(pmpcfg_a_reg(i) = PMP_A_TOR);
            end generate MATCH;

        else generate
            d_match_tor <= (others => '0');
            i_match_tor <= (others => '0');
        end generate TOR_SUPPORT;

        ---------------------------------------------------------------------------
        -- Decode permissions from matches

        -- For load/stores we assume any non-naturally-aligned transfers trigger a
        -- misaligned load/store/AMO exception, so we only need to decode the PMP
        -- attribute for the first byte of the access. Note the spec gives us freedom
        -- to report *either* a load/store/AMO access fault (mcause = 5, 7) or a
        -- load/store/AMO alignment fault (mcause = 4, 6), in the case that both
        -- happen, and we choose alignment fault in this case.
        CHECK_D_MATCH : process(all)
            variable v_m : std_logic;
            variable v_l : std_logic;
            variable v_r : std_logic;
            variable v_w : std_logic;
        begin
            v_m := '0';
            v_l := '0';
            v_r := '0';
            v_w := '0';
            -- Lowest-numbered match wins, so work down from the top. This should be
            -- inferred as a priority mux structure (cascade mux).
            for i in PMP_REGIONS - 1 downto 0 loop
                if ?? (d_match_napot(i) or d_match_tor(i)) then
                    v_m := pmpcfg_m_reg(i);
                    v_l := pmpcfg_l_reg(i);
                    v_r := pmpcfg_r_reg(i);
                    v_w := pmpcfg_w_reg(i);
                end if;
            end loop;
            d_m <= v_m;
            d_l <= v_l;
            d_r <= v_r;
            d_w <= v_w;
        end process CHECK_D_MATCH;

        -- Instructions work similarly because we check *fetches*, not instructions.
        -- Fetch is always word-sized word-aligned. The spec permits this:
        --
        -- "On some implementations, misaligned loads, stores, and instruction fetches
        --  may also be decomposed into multiple accesses, some of which may succeed
        --  before an access-fault exception occurs."
        --
        -- Hazard3 separately checks the naturally-aligned fetches that occur in the
        -- course of fetching a non-naturally-aligned instruction. This means
        -- instruction fetch spanning two different regions which both grant X
        -- permission *is* permitted, unlike the RP2350 version of Hazard3.
        CHECK_I_MATCH : process(all)
            variable v_m : std_logic;
            variable v_l : std_logic;
            variable v_x : std_logic;
        begin
            v_m := '0';
            v_l := '0';
            v_x := '0';
            for i in PMP_REGIONS - 1 downto 0 loop
                if ?? (i_match_napot(i) or i_match_tor(i)) then
                    v_m := pmpcfg_m_reg(i);
                    v_l := pmpcfg_l_reg(i);
                    v_x := pmpcfg_x_reg(i);
                end if;
            end loop;
            i_m <= v_m;
            i_l <= v_l;
            i_x <= v_x;
        end process CHECK_I_MATCH;

        ---------------------------------------------------------------------------
        -- Access rules

        -- M-mode gets to ignore protections, unless the lock or M-mode bit is set.
        d_kill <= (not d_m_mode or d_l or d_m) and (
                  (not d_write and not d_r) or
                  (    d_write and not d_w)
        );

        i_kill <= (not i_m_mode or i_l or i_m) and not i_x;

    end generate PMP_SUPPORT;

end architecture rtl;
