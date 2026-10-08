library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.hazard3_constants.all;

entity hazard3_mul_fast is
    generic(
        MULH_FAST  : boolean;
        MUL_FAST   : boolean;
        MUL_FASTER : boolean;
        RISCV_FORMAL_ALTOPS : boolean := FALSE
    );
    port(
        clk        : in  std_logic;
        rst_n      : in  std_logic;
        op         : in  std_logic_vector(MULOP_WIDTH_C - 1 downto 0);
        op_vld     : in  std_logic;
        op_a       : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        op_b       : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        result     : out std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        result_vld : out std_logic
    );
end entity hazard3_mul_fast;

architecture rtl of hazard3_mul_fast is

    signal result_valid_reg               : std_logic;
    signal op_a_reg, op_b_reg             : unsigned(DATA_WIDTH_C - 1 downto 0);
    signal op_reg                         : std_logic_vector(MULOP_WIDTH_C - 1 downto 0);
    signal is_op_a_signed, is_op_b_signed : std_logic;
    signal op_a_sign, op_b_sign           : std_logic;
    signal op_a_sext, op_b_sext           : unsigned(2 * DATA_WIDTH_C - 1 downto 0);
    signal result_full                    : std_logic_vector(2 * DATA_WIDTH_C - 1 downto 0);

begin

    -- Sanity-checks:
    assert not (MULH_FAST and not MUL_FAST)
        report "MULH_FAST requires that MUL_FAST is also set."
        severity FAILURE;

    assert not (MUL_FASTER and not MUL_FAST)
        report "MUL_FASTER requires that MUL_FAST is also set."
        severity FAILURE;

    -- Latency of this module is 1:
    REG_VALID : process(clk, rst_n) is
    begin
        if rst_n = '0' then
            result_valid_reg <= '0';
        elsif rising_edge(clk) then
            result_valid_reg <= op_vld;
        end if;
    end process REG_VALID;
    result_vld <= result_valid_reg;

    ----------------------------------------------------------------------------
    MUL_ONLY : if not MULH_FAST generate
        -- Fast MUL only

        -- This pipestage is folded into the front of the DSP tiles on UP5k. Note the
        -- intention is to register the bypassed core regs at the end of X (since
        -- bypass is quite slow), then perform multiply combinatorially in stage M,
        -- and mux into MW result register.

        OP_PASSTHROUGH : if MUL_FASTER generate
            op_a_reg <= unsigned(op_a);
            op_b_reg <= unsigned(op_b);
        else generate
            process(clk)
            begin
                if rising_edge(clk) and op_vld = '1' then
                    op_a_reg <= unsigned(op_a);
                    op_b_reg <= unsigned(op_b);
                end if;
            end process;
        end generate OP_PASSTHROUGH;

        -- This should be inferred as 3 DSP tiles on UP5k:
        --
        -- 1. Register then multiply a[15: 0] and b[15: 0]
        -- 2. Register then multiply a[31:16] and b[15: 0], then directly add output of 1
        -- 3. Register then multiply a[15: 0] and b[31:16], then directly add output of 2
        --
        -- So there is quite a long path (1x 16-bit multiply, then 2x 16-bit add). On
        -- other platforms you may just end up with a pile of gates.
        FORMAL_EQUIV_32MUL : if RISCV_FORMAL_ALTOPS generate

            result <= std_logic_vector(op_a_reg + op_b_reg) xor x"5876_063E" when result_vld = '1'
                                                                             else x"DEAD_BEEF";

        else generate
            
            result <= std_logic_vector(resize(op_a_reg * op_b_reg, DATA_WIDTH_C));

        end generate FORMAL_EQUIV_32MUL;
        

    end generate MUL_ONLY;

    MUL_AND_MULH : if MULH_FAST generate
        -- Fast MUL/MULH/MULHU/MULHSU

        OP_PASSTHROUGH_OR_REGSTER : if MUL_FASTER generate
            op_a_reg <= unsigned(op_a);
            op_b_reg <= unsigned(op_b);
            op_reg   <= op;
        else generate
            process(clk)
            begin
                if rising_edge(clk) and op_vld = '1' then
                    op_a_reg <= unsigned(op_a);
                    op_b_reg <= unsigned(op_b);
                    op_reg   <= op;
                end if;
            end process;
        end generate OP_PASSTHROUGH_OR_REGSTER;

        is_op_a_signed <= '1' when op_reg = MULOP_C.MULH or op_reg = MULOP_C.MULHSU else '0';
        is_op_b_signed <= '1' when op_reg = MULOP_C.MULH else '0';

        op_a_sign <= is_op_a_signed and op_a_reg(DATA_WIDTH_C - 1);
        op_b_sign <= is_op_b_signed and op_b_reg(DATA_WIDTH_C - 1);

        --op_a_sext <= (DATA_WIDTH_C - 1 downto 0 => op_a_reg, others => op_a_sign);
        --op_b_sext <= (DATA_WIDTH_C - 1 downto 0 => op_b_reg, others => op_b_sign);
        op_a_sext <= (2 * DATA_WIDTH_C - 1 downto DATA_WIDTH_C => op_a_sign) & op_a_reg;
        op_b_sext <= (2 * DATA_WIDTH_C - 1 downto DATA_WIDTH_C => op_b_sign) & op_b_reg;

        -- Formal equivalence check with a 64-bit multiplier at the end takes ages!
        -- I just want to see if the thing is wired correctly, and Hazard3 seems to do
        -- something like that for the same reason.
        -- This means, a lot of signals up to line 108 are not checked, including
        -- the `else generate` below. Manual verification needed here!
        FORMAL_EQUIV_64MUL : if RISCV_FORMAL_ALTOPS generate
            
            EQUIV_CHECK_SIMPLE : with op_reg select
                result <=
                    std_logic_vector(op_a_reg + op_b_reg) xor x"F658_3FB7" when MULOP_C.MULH,
                    std_logic_vector(op_a_reg - op_b_reg) xor x"ECFB_E137" when MULOP_C.MULHSU,
                    std_logic_vector(op_a_reg + op_b_reg) xor x"949C_E5E8" when MULOP_C.MULHU,
                    std_logic_vector(op_a_reg + op_b_reg) xor x"5876_063E" when MULOP_C.MUL,                    
                    x"DEAD_BEEF" when others;

        else generate

            result_full <= std_logic_vector(resize(op_a_sext * op_b_sext, 2 * DATA_WIDTH_C));
            result <= result_full(DATA_WIDTH_C - 1 downto 0) when op_reg = MULOP_C.MUL else
                      result_full(2 * DATA_WIDTH_C - 1 downto DATA_WIDTH_C);

        end generate FORMAL_EQUIV_64MUL;
    end generate MUL_AND_MULH;

end architecture rtl;
