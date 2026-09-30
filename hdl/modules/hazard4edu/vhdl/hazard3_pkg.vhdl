library ieee;
use ieee.std_logic_1164.all;

package hazard3_constants is

    constant DATA_WIDTH_C         : integer := 32;
    constant ALUOP_WIDTH_C        : integer := 6;
    constant SHIFT_AMOUNT_WIDTH_C : integer := 5;
    constant MULOP_WIDTH_C        : integer := 3;

    type alu_ops_t is record
        ADD     : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        SUB     : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        LT      : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        LTU     : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        AND_OP  : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        OR_OP   : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        XOR_OP  : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        SRL_OP  : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        SRA_OP  : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        SLL_OP  : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        MULDIV  : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        RS2     : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        SHXADD  : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        CLZ     : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        CPOP    : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        CTZ     : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        ANDN    : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        ORN     : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        XNOR_OP : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        MAX     : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        MAXU    : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        MIN     : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        MINU    : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        ORC_B   : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        REV8    : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        ROTL    : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        ROTR    : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        SEXT_B  : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        SEXT_H  : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        ZEXT_H  : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        CLMUL   : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
    end record;

    type mul_ops_t is record
        MUL    : std_logic_vector(MULOP_WIDTH_C - 1 downto 0);
        MULH   : std_logic_vector(MULOP_WIDTH_C - 1 downto 0);
        MULHSU : std_logic_vector(MULOP_WIDTH_C - 1 downto 0);
        MULHU  : std_logic_vector(MULOP_WIDTH_C - 1 downto 0);
        DIV    : std_logic_vector(MULOP_WIDTH_C - 1 downto 0);
        DIVU   : std_logic_vector(MULOP_WIDTH_C - 1 downto 0);
        REMI   : std_logic_vector(MULOP_WIDTH_C - 1 downto 0);
        REMIU  : std_logic_vector(MULOP_WIDTH_C - 1 downto 0);
    end record;

    constant ALUOP_C : alu_ops_t := (
        ADD     => 6x"00",
        SUB     => 6x"01",
        LT      => 6x"02",
        LTU     => 6x"04",
        AND_OP  => 6x"06",
        OR_OP   => 6x"07",
        XOR_OP  => 6x"08",
        SRL_OP  => 6x"09",
        SRA_OP  => 6x"0A",
        SLL_OP  => 6x"0B",
        MULDIV  => 6x"0C",
        RS2     => 6x"0D",
        SHXADD  => 6x"20",
        CLZ     => 6x"23",
        CPOP    => 6x"24",
        CTZ     => 6x"25",
        ANDN    => 6x"26",
        ORN     => 6x"27",
        XNOR_OP => 6x"28",
        MAX     => 6x"29",
        MAXU    => 6x"2A",
        MIN     => 6x"2B",
        MINU    => 6x"2C",
        ORC_B   => 6x"2D",
        REV8    => 6x"2E",
        ROTL    => 6x"2F",
        ROTR    => 6x"30",
        SEXT_B  => 6x"31",
        SEXT_H  => 6x"32",
        ZEXT_H  => 6x"33",
        CLMUL   => 6x"34"
    );

    constant MULOP_C : mul_ops_t := (
        MUL    => 3x"0",
        MULH   => 3x"1",
        MULHSU => 3x"2",
        MULHU  => 3x"3",
        DIV    => 3x"4",
        DIVU   => 3x"5",
        REMI   => 3x"6",
        REMIU  => 3x"7"
    );

end package hazard3_constants;
