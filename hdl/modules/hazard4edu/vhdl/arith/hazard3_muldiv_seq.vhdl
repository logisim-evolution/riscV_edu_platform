library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.hazard3_constants.all;

entity hazard3_muldiv_seq is
    generic(
        MULDIV_UNROLL : positive := 1;
        MUL_FAST      : boolean;
        MULH_FAST     : boolean
    );
    port(
        clk        : in  std_logic;
        rst_n      : in  std_logic;
        op         : in  std_logic_vector(MULOP_WIDTH_C - 1 downto 0);
        op_vld     : in  std_logic;
        op_rdy     : out std_logic;
        op_kill    : in  std_logic;
        op_a       : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        op_b       : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        result_h   : out std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        result_l   : out std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        result_vld : out std_logic
    );
end entity hazard3_muldiv_seq;

architecture rtl of hazard3_muldiv_seq is

    -- Registers and internal signals:
    signal op_r               : std_logic_vector(MULOP_WIDTH_C - 1 downto 0);
    signal accum              : std_logic_vector(2 * DATA_WIDTH_C - 1 downto 0);
    signal op_b_r             : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal op_a_neg_r         : std_logic;
    signal op_b_neg_r         : std_logic;
    
    -- Integer counter replaces $clog2(XLEN + 1)
    -- Range extends into negative to safely allow subtraction below zero
    signal ctr                : integer range -MULDIV_UNROLL to DATA_WIDTH_C;
    
    signal sign_preadj_done   : std_logic;
    signal sign_postadj_done  : std_logic;
    signal sign_postadj_carry : std_logic;

    -- Combinational ALU outputs
    signal accum_next         : std_logic_vector(2 * DATA_WIDTH_C - 1 downto 0);
    signal neg_l_borrow       : std_logic;

    -- Decode flags
    signal op_a_signed        : std_logic;
    signal op_b_signed        : std_logic;
    signal op_a_neg           : std_logic;
    signal op_b_neg           : std_logic;

    -- Non-divide parts of the circuit should be constant-folded if all the MUL
    -- operations are handled by the fast multiplier
    signal is_div             : std_logic;
    
    signal op_signs_differ    : std_logic;
    signal do_postadj         : std_logic;

    -- Controls for modifying sign of all/part of accumulator
    signal accum_neg_l        : std_logic;
    signal accum_inv_h        : std_logic;
    signal accum_incr_h       : std_logic;
    signal b_is_nonzero       : std_logic;

begin

    assert (to_unsigned(MULDIV_UNROLL, DATA_WIDTH_C) and to_unsigned(MULDIV_UNROLL - 1, DATA_WIDTH_C)) = 0
        report "MULDIV_UNROLL must be a positive power of 2"
        severity FAILURE;
    
-- -------------------------------------------------------------------------
    -- Operation decode & sign adjustment flags
    -- -------------------------------------------------------------------------
    op_a_signed <= '1' when (op_r = MULOP_C.MULH or op_r = MULOP_C.MULHSU or op_r = MULOP_C.DIV or op_r = MULOP_C.REMI) else '0';
    op_b_signed <= '1' when (op_r = MULOP_C.MULH or op_r = MULOP_C.DIV or op_r = MULOP_C.REMI) else '0';

    op_a_neg <= '1' when (op_a_signed = '1' and accum(DATA_WIDTH_C - 1) = '1') else '0';
    op_b_neg <= '1' when (op_b_signed = '1' and op_b_r(DATA_WIDTH_C - 1) = '1') else '0';

    is_div <= '1' when (op_r(2) = '1' or (MUL_FAST and MULH_FAST)) else '0';
    
    b_is_nonzero <= '1' when unsigned(op_b_r) /= 0 else '0';
    op_signs_differ <= op_a_neg_r xor op_b_neg_r;
    
    do_postadj <= '1' when (ctr = 0 and sign_postadj_done = '0') else '0';

    accum_neg_l <= '1' when (sign_preadj_done = '0' and op_a_neg = '1') or
                            (do_postadj = '1' and sign_postadj_carry = '0' and op_signs_differ = '1' and not (is_div = '1' and b_is_nonzero = '0'))
                       else '0';

    accum_incr_h <= '1' when (do_postadj = '1' and is_div = '1' and op_a_neg_r = '1') or
                             (do_postadj = '1' and is_div = '0' and op_signs_differ = '1' and sign_postadj_carry = '1') 
                        else '0';

    accum_inv_h  <= '1' when (do_postadj = '1' and is_div = '1' and op_a_neg_r = '1') or
                             (do_postadj = '1' and is_div = '0' and op_signs_differ = '1' and sign_postadj_carry = '0') 
                        else '0';

    process(all)
        variable v_accum      : std_logic_vector(2 * DATA_WIDTH_C - 1 downto 0);
        variable v_addend     : std_logic_vector(2 * DATA_WIDTH_C - 1 downto 0);
        variable v_shift_tmp  : std_logic_vector(2 * DATA_WIDTH_C - 1 downto 0);
        variable v_addsub_tmp : unsigned(2 * DATA_WIDTH_C - 1 downto 0);
        variable v_temp_sub   : unsigned(DATA_WIDTH_C downto 0);
        variable v_temp_upper : unsigned(DATA_WIDTH_C - 1 downto 0);
    begin
        v_accum := accum;
        
        -- Multiply/divide iteration layers
        for i in 0 to MULDIV_UNROLL - 1 loop
            -- {is_div && |op_b_r, op_b_r, {XLEN-1{1'b0}}}
            v_addend := (2 * DATA_WIDTH_C - 1 => (is_div and b_is_nonzero), others => '0');
            v_addend(2 * DATA_WIDTH_C - 2 downto DATA_WIDTH_C - 1) := op_b_r;

            if is_div = '1' then
                v_shift_tmp := v_accum;
            else
                v_shift_tmp := '0' & v_accum(2 * DATA_WIDTH_C - 1 downto 1);
            end if;

            v_addsub_tmp := unsigned(v_shift_tmp) + unsigned(v_addend);

            if is_div = '1' then
                if v_addsub_tmp(2 * DATA_WIDTH_C - 1) = '0' then
                    v_accum := std_logic_vector(v_addsub_tmp);
                else
                    v_accum := v_shift_tmp;
                end if;
                v_accum := v_accum(2 * DATA_WIDTH_C - 2 downto 0) & not v_addsub_tmp(2 * DATA_WIDTH_C - 1);
            else
                if v_accum(0) = '1' then
                    v_accum := std_logic_vector(v_addsub_tmp);
                else
                    v_accum := v_shift_tmp;
                end if;
            end if;
        end loop;

        neg_l_borrow <= '0';
        
        -- Alternative path for negation of all/part of accumulator[cite: 4]
        if accum_neg_l = '1' then
            v_temp_sub   := unsigned('0' & not accum(DATA_WIDTH_C - 1 downto 0)) + 1;
            neg_l_borrow <= v_temp_sub(DATA_WIDTH_C);
            v_accum(DATA_WIDTH_C - 1 downto 0) := std_logic_vector(v_temp_sub(DATA_WIDTH_C - 1 downto 0));
        end if;
        
        if accum_incr_h = '1' or accum_inv_h = '1' then
            v_temp_upper := unsigned(accum(2 * DATA_WIDTH_C - 1 downto DATA_WIDTH_C) xor (DATA_WIDTH_C - 1 downto 0 => accum_inv_h)) + unsigned'(0 => accum_incr_h);
            v_accum(2 * DATA_WIDTH_C - 1 downto DATA_WIDTH_C) := std_logic_vector(v_temp_upper);
        end if;

        accum_next <= v_accum;
    end process;

    -- -------------------------------------------------------------------------
    -- Main State Machine
    -- -------------------------------------------------------------------------
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            ctr                <= 0;
            sign_preadj_done   <= '1';
            sign_postadj_done  <= '1';
            sign_postadj_carry <= '0';
            op_r               <= (others => '0');
            op_a_neg_r         <= '0';
            op_b_neg_r         <= '0';
            op_b_r             <= (others => '0');
            accum              <= (others => '0');

        elsif rising_edge(clk) then
            if op_kill = '1' or (op_vld = '1' and op_rdy = '1') then
                -- Initialize circuit[cite: 4]
                if op_vld = '1' then ctr <= DATA_WIDTH_C; else ctr <= 0; end if;
                sign_preadj_done   <= not op_vld;
                sign_postadj_done  <= not op_vld;
                sign_postadj_carry <= '0';
                op_r               <= op;
                op_b_r             <= op_b;
                accum              <= (2 * DATA_WIDTH_C - 1 downto DATA_WIDTH_C => '0') & op_a;

            elsif sign_preadj_done = '0' then
                op_a_neg_r       <= op_a_neg;
                op_b_neg_r       <= op_b_neg;
                sign_preadj_done <= '1';
                
                if accum_neg_l = '1' or (op_b_neg xor is_div) = '1' then
                    if accum_neg_l = '1' then
                        accum(DATA_WIDTH_C - 1 downto 0) <= accum_next(DATA_WIDTH_C - 1 downto 0);
                    end if;
                    if (op_b_neg xor is_div) = '1' then
                        op_b_r <= std_logic_vector(-signed(op_b_r));
                    end if;
                else
                    ctr   <= ctr - MULDIV_UNROLL;
                    accum <= accum_next;
                end if;

            elsif ctr > 0 then
                ctr   <= ctr - MULDIV_UNROLL;
                accum <= accum_next;

            elsif sign_postadj_done = '0' or sign_postadj_carry = '1' then
                sign_postadj_done <= '1';
                
                if accum_inv_h = '1' or accum_incr_h = '1' then
                    accum(2 * DATA_WIDTH_C - 1 downto DATA_WIDTH_C) <= accum_next(2 * DATA_WIDTH_C - 1 downto DATA_WIDTH_C);
                end if;
                if accum_neg_l = '1' then
                    accum(DATA_WIDTH_C - 1 downto 0) <= accum_next(DATA_WIDTH_C - 1 downto 0);
                    if is_div = '0' then
                        sign_postadj_carry <= neg_l_borrow;
                        sign_postadj_done  <= not neg_l_borrow;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- -------------------------------------------------------------------------
    -- Outputs
    -- -------------------------------------------------------------------------
    op_rdy <= '1' when (ctr <= 0 and accum_neg_l = '0' and accum_incr_h = '0' and accum_inv_h = '0') else '0';
    result_vld <= op_rdy;
    
    result_h <= accum(2 * DATA_WIDTH_C - 1 downto DATA_WIDTH_C);
    result_l <= accum(DATA_WIDTH_C - 1 downto 0);

end architecture rtl;
