library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.hazard3_constants.all;

entity hazard3_alu is
    generic(
        EXTENSION_A : boolean
    );
    port(
        aluop  : in  std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        op_a   : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        op_b   : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        result : out std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        cmp    : out std_logic
    );
end entity hazard3_alu;

architecture rtl of hazard3_alu is

    signal extension_A_enabled : std_logic;

    signal bitwise_operation : std_logic_vector(DATA_WIDTH_C - 1 downto 0);

    signal subtraction            : std_logic;
    signal invert_operand_b       : std_logic;
    signal operand_b_inverted     : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal sum_of_a_and_b         : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal xor_of_a_and_b         : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal comparison_is_unsigned : std_logic;
    signal a_is_less_than_b       : std_logic;
    signal shift_result           : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal shift_right_nleft      : std_logic;
    signal arithmetic_shift       : std_logic;

begin

    extension_A_enabled <= '1' when EXTENSION_A else '0';

    subtraction <= '1' when aluop /= ALUOP_C.ADD else '0';

    invert_operand_b   <= '1' when subtraction = '1' and not (aluop = ALUOP_C.AND_OP or aluop = ALUOP_C.OR_OP or aluop = ALUOP_C.XOR_OP or aluop = ALUOP_C.RS2) else
                          '0';
    operand_b_inverted <= op_b xor (DATA_WIDTH_C - 1 downto 0 => invert_operand_b);

    sum_of_a_and_b <= std_logic_vector(unsigned(op_a) + unsigned(operand_b_inverted) + resize(unsigned'(0 => subtraction), DATA_WIDTH_C));
    xor_of_a_and_b <= op_a xor op_b;

    comparison_is_unsigned <= '1' when aluop = ALUOP_C.LTU else '0';

    a_is_less_than_b <= sum_of_a_and_b(DATA_WIDTH_C - 1) when op_a(DATA_WIDTH_C - 1) = op_b(DATA_WIDTH_C - 1) else
                        op_b(DATA_WIDTH_C - 1)           when comparison_is_unsigned = '1'                    else
                        op_a(DATA_WIDTH_C - 1);

    cmp <= or xor_of_a_and_b when aluop = ALUOP_C.SUB else a_is_less_than_b;

    -- ----------------------------------------------------------------------------
    -- Separate units for shift, ctz etc

    shift_right_nleft <= '1' when aluop = ALUOP_C.SRL_OP or aluop = ALUOP_C.SRA_OP else '0';
    arithmetic_shift  <= '1' when aluop = ALUOP_C.SRA_OP else '0';

    barrel_shifter_instance : entity work.hazard3_shift_barrel
        port map(
            din         => op_a,
            shamt       => op_b(4 downto 0),
            right_nleft => shift_right_nleft,
            arith       => arithmetic_shift,
            dout        => shift_result
        );

    -- ----------------------------------------------------------------------------
    -- Output mux, with simple operations inline
    -- iCE40: We can implement all bitwise ops with 1 LUT4/bit total, since each
    -- result bit uses only two operand bits. Much better than feeding each into
    -- main mux tree. Doesn't matter for big-LUT FPGAs or for implementations with
    -- bitmanip extensions enabled.
    -- L72-L81
    process(all) is
    begin
        if aluop(1 downto 0) = ALUOP_C.AND_OP(1 downto 0) then
            bitwise_operation <= op_a and operand_b_inverted;
        elsif aluop(1 downto 0) = ALUOP_C.OR_OP(1 downto 0) then
            bitwise_operation <= op_a or operand_b_inverted;
        elsif aluop(1 downto 0) = ALUOP_C.XOR_OP(1 downto 0) then
            bitwise_operation <= op_a xor operand_b_inverted;
        elsif aluop(1 downto 0) = ALUOP_C.RS2(1 downto 0) then
            bitwise_operation <= operand_b_inverted;
        else
            bitwise_operation <= (others => 'X');
        end if;
    end process;

    -- L83-L101
    process(all) is
    begin
        case? (extension_A_enabled & aluop) is
            when '-' & ALUOP_C.ADD    |
                 '-' & ALUOP_C.SUB    => result <= sum_of_a_and_b;
            when '-' & ALUOP_C.LT     |
                 '-' & ALUOP_C.LTU    => result <= (0 => a_is_less_than_b, others => '0');
            when '-' & ALUOP_C.SRL_OP |
                 '-' & ALUOP_C.SRA_OP | 
                 '-' & ALUOP_C.SLL_OP => result <= shift_result;
            -- A Extension:
            when '1' & ALUOP_C.MAX    | 
                 '1' & ALUOP_C.MAXU   => result <= op_b when a_is_less_than_b = '1' else op_a;
            when '1' & ALUOP_C.MIN    | 
                 '1' & ALUOP_C.MINU   => result <= op_a when a_is_less_than_b = '1' else op_b;
            when others          => result <= bitwise_operation;
        end case?;

    end process;

end architecture rtl;
