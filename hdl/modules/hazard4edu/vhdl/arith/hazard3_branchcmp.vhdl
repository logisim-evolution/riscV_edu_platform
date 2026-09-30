library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.hazard3_constants.all;

entity hazard3_branchcmp is
    port(
        cir  : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        op_a : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        op_b : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        cmp  : out std_logic
    );
end entity hazard3_branchcmp;

architecture rtl of hazard3_branchcmp is

signal difference      : unsigned(DATA_WIDTH_C - 1 downto 0);
signal compare_is_unsigned : std_logic;
signal a_is_less_than_b    : std_logic;
signal a_not_equal_b        : std_logic;

begin

    difference <= unsigned(op_a) - unsigned(op_b);

    -- funct3 instruction
    -- ------------------
    -- 000    BEQ
    -- 001    BNE
    -- 100    BLT
    -- 101    BGE
    -- 110    BLTU
    -- 111    BGEU

    compare_is_unsigned <= cir(13);

    a_is_less_than_b <= difference(DATA_WIDTH_C-1) when op_a(DATA_WIDTH_C-1) = op_b(DATA_WIDTH_C-1) else
                        op_b(DATA_WIDTH_C-1)       when compare_is_unsigned = '1'                   else
                        op_a(DATA_WIDTH_C-1);

    a_not_equal_b <= '1' when op_a /= op_b else '0';

    cmp <= a_is_less_than_b when cir(14) = '1' else a_not_equal_b;
    
end architecture rtl;
