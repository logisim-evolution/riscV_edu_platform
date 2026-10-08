library ieee;
use ieee.std_logic_1164.all;

package hazard3_constants is

    constant DATA_WIDTH_C               : integer := 32;
    constant ADDRESS_WIDTH_C            : integer := 32;
    constant ALUOP_WIDTH_C              : integer := 6;
    constant SHIFT_AMOUNT_WIDTH_C       : integer := 5;
    constant MULOP_WIDTH_C              : integer := 3;
    constant COMPRESSED_INSTR_WIDTH_C   : integer := 16;
    constant INSTRUCTION_WIDTH_C        : integer := 32;
    constant REGISTER_ADDRESS_WIDTH_C   : integer := 5;
    constant BRANCH_CONDITION_WIDTH_C   : integer := 2;
    constant EXCEPTION_WIDTH_C          : integer := 4;
    constant ALU_SOURCE_WIDTH_C         : integer := 1;
    constant MEMOP_WIDTH_C              : integer := 5;

    type alu_operations_t is record
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

    type mul_operations_t is record
        MUL    : std_logic_vector(MULOP_WIDTH_C - 1 downto 0);
        MULH   : std_logic_vector(MULOP_WIDTH_C - 1 downto 0);
        MULHSU : std_logic_vector(MULOP_WIDTH_C - 1 downto 0);
        MULHU  : std_logic_vector(MULOP_WIDTH_C - 1 downto 0);
        DIV    : std_logic_vector(MULOP_WIDTH_C - 1 downto 0);
        DIVU   : std_logic_vector(MULOP_WIDTH_C - 1 downto 0);
        REMI   : std_logic_vector(MULOP_WIDTH_C - 1 downto 0);
        REMIU  : std_logic_vector(MULOP_WIDTH_C - 1 downto 0);
    end record;

    type opcode_constants_t is record
        C_ADDI4SPN : std_logic_vector(COMPRESSED_INSTR_WIDTH_C - 1 downto 0);
        C_LW       : std_logic_vector(COMPRESSED_INSTR_WIDTH_C - 1 downto 0);
        C_SW       : std_logic_vector(COMPRESSED_INSTR_WIDTH_C - 1 downto 0);
        C_ADDI     : std_logic_vector(COMPRESSED_INSTR_WIDTH_C - 1 downto 0);
        C_JAL      : std_logic_vector(COMPRESSED_INSTR_WIDTH_C - 1 downto 0);
        C_J        : std_logic_vector(COMPRESSED_INSTR_WIDTH_C - 1 downto 0);
        C_LI       : std_logic_vector(COMPRESSED_INSTR_WIDTH_C - 1 downto 0);
        C_LUI      : std_logic_vector(COMPRESSED_INSTR_WIDTH_C - 1 downto 0);
        C_SRLI     : std_logic_vector(COMPRESSED_INSTR_WIDTH_C - 1 downto 0);
        C_SRAI     : std_logic_vector(COMPRESSED_INSTR_WIDTH_C - 1 downto 0);
        C_ANDI     : std_logic_vector(COMPRESSED_INSTR_WIDTH_C - 1 downto 0);
        C_SUB      : std_logic_vector(COMPRESSED_INSTR_WIDTH_C - 1 downto 0);
        C_XOR      : std_logic_vector(COMPRESSED_INSTR_WIDTH_C - 1 downto 0);
        C_OR       : std_logic_vector(COMPRESSED_INSTR_WIDTH_C - 1 downto 0);
        C_AND      : std_logic_vector(COMPRESSED_INSTR_WIDTH_C - 1 downto 0);
        C_BEQZ     : std_logic_vector(COMPRESSED_INSTR_WIDTH_C - 1 downto 0);
        C_BNEZ     : std_logic_vector(COMPRESSED_INSTR_WIDTH_C - 1 downto 0);
        C_SLLI     : std_logic_vector(COMPRESSED_INSTR_WIDTH_C - 1 downto 0);
        C_MV       : std_logic_vector(COMPRESSED_INSTR_WIDTH_C - 1 downto 0);
        C_ADD      : std_logic_vector(COMPRESSED_INSTR_WIDTH_C - 1 downto 0);
        C_LWSP     : std_logic_vector(COMPRESSED_INSTR_WIDTH_C - 1 downto 0);
        C_SWSP     : std_logic_vector(COMPRESSED_INSTR_WIDTH_C - 1 downto 0);
        C_MUL      : std_logic_vector(COMPRESSED_INSTR_WIDTH_C - 1 downto 0);
        ADDI       : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        JALR       : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        JAL        : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        LUI        : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        SLLI       : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        SRLI       : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        SRAI       : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        ANDI       : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        ADD        : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        SUB        : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        AND_OP     : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        OR_OP      : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        XOR_OP     : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        LW         : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        SW         : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        MUL        : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        BEQ        : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        BNE        : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        BLT        : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        BGE        : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        BLTU       : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        BGEU       : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        AUIPC      : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        SLTI       : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        SLTIU      : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        XORI       : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        ORI        : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        SLL32      : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        SLT        : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        SLTU       : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        SRL32      : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        SRA32      : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        LB         : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        LH         : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        LBU        : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        LHU        : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        SB         : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        SH         : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        LR_W       : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        SC_W       : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        AMO        : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        CSRRW      : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        CSRRS      : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        CSRRC      : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        CSRRWI     : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        CSRRSI     : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        CSRRCI     : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        FENCE      : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        ECALL      : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        MRET       : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        WFI        : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        FENCE_I    : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        EBREAK     : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        MULH       : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        MULHSU     : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        MULHU      : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        DIV        : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        DIVU       : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        REM_OP     : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        REMU       : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        AMOSWAP_W  : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        AMOADD_W   : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        AMOXOR_W   : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        AMOAND_W   : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        AMOOR_W    : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        AMOMIN_W   : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        AMOMAX_W   : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        AMOMINU_W  : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
        AMOMAXU_W  : std_logic_vector(INSTRUCTION_WIDTH_C - 1 downto 0);
    end record;

    type exception_constants_t is record
        NO_EXCEPTION                    : std_logic_vector(EXCEPTION_WIDTH_C - 1 downto 0);
        INSTRUCTION_MISALIGNED          : std_logic_vector(EXCEPTION_WIDTH_C - 1 downto 0);
        INSTRUCTION_FAULT               : std_logic_vector(EXCEPTION_WIDTH_C - 1 downto 0);
        ILLEGAL_INSTRUCTION             : std_logic_vector(EXCEPTION_WIDTH_C - 1 downto 0);
        EBREAKPOINT                     : std_logic_vector(EXCEPTION_WIDTH_C - 1 downto 0);
        LOAD_ADDRESS_MISALIGNED         : std_logic_vector(EXCEPTION_WIDTH_C - 1 downto 0);
        LOAD_ACCESS_FAULT               : std_logic_vector(EXCEPTION_WIDTH_C - 1 downto 0);
        STORE_ADDRESS_MISALIGNED        : std_logic_vector(EXCEPTION_WIDTH_C - 1 downto 0);
        STORE_ACCESS_FAULT              : std_logic_vector(EXCEPTION_WIDTH_C - 1 downto 0);
        ENVIRONMENT_CALL_FROM_U_MODE    : std_logic_vector(EXCEPTION_WIDTH_C - 1 downto 0);
        RETURN_FROM_M_MODE              : std_logic_vector(EXCEPTION_WIDTH_C - 1 downto 0);
        ENVIRONMENT_CALL_FROM_M_MODE    : std_logic_vector(EXCEPTION_WIDTH_C - 1 downto 0);
        EXCEPTION_REFETCH               : std_logic_vector(EXCEPTION_WIDTH_C - 1 downto 0);
    end record;

    type memory_operation_constants_t is record
        LOAD_WORD               : std_logic_vector(MEMOP_WIDTH_C - 1 downto 0);
        LOAD_HALF               : std_logic_vector(MEMOP_WIDTH_C - 1 downto 0);
        LOAD_BYTE               : std_logic_vector(MEMOP_WIDTH_C - 1 downto 0);
        LOAD_HALF_UNSIGNED      : std_logic_vector(MEMOP_WIDTH_C - 1 downto 0);
        LOAD_BYTE_UNSIGNED      : std_logic_vector(MEMOP_WIDTH_C - 1 downto 0);
        STORE_WORD              : std_logic_vector(MEMOP_WIDTH_C - 1 downto 0);
        STORE_HALF              : std_logic_vector(MEMOP_WIDTH_C - 1 downto 0);
        STORE_BYTE              : std_logic_vector(MEMOP_WIDTH_C - 1 downto 0);
        LOAD_RESERVED_WORD      : std_logic_vector(MEMOP_WIDTH_C - 1 downto 0);
        STORE_CONDITIONAL_WORD  : std_logic_vector(MEMOP_WIDTH_C - 1 downto 0);
        ATOMIC_MEM_OP           : std_logic_vector(MEMOP_WIDTH_C - 1 downto 0);
        NONE                    : std_logic_vector(MEMOP_WIDTH_C - 1 downto 0);
    end record;

    type branch_conditions_t is record
        NEVER       : std_logic_vector(BRANCH_CONDITION_WIDTH_C - 1 downto 0);
        ALWAYS      : std_logic_vector(BRANCH_CONDITION_WIDTH_C - 1 downto 0);
        ZERO        : std_logic_vector(BRANCH_CONDITION_WIDTH_C - 1 downto 0);
        NOT_ZERO    : std_logic_vector(BRANCH_CONDITION_WIDTH_C - 1 downto 0);
    end record;

    type alu_source_a is record
        RS1 : std_logic_vector(ALU_SOURCE_WIDTH_C - 1 downto 0);
        PC  : std_logic_vector(ALU_SOURCE_WIDTH_C - 1 downto 0);
    end record;

    type alu_source_b is record
        RS2 : std_logic_vector(ALU_SOURCE_WIDTH_C - 1 downto 0);
        IMM : std_logic_vector(ALU_SOURCE_WIDTH_C - 1 downto 0);
    end record;

    constant ALUOP_C : alu_operations_t := (
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

    constant MULOP_C : mul_operations_t := (
        MUL    => 3x"0",
        MULH   => 3x"1",
        MULHSU => 3x"2",
        MULHU  => 3x"3",
        DIV    => 3x"4",
        DIVU   => 3x"5",
        REMI   => 3x"6",
        REMIU  => 3x"7"
    );

    constant OPCODE_C : opcode_constants_t := (
        C_ADDI4SPN => "000-----------00",
        C_LW       => "010-----------00",
        C_SW       => "110-----------00",
        C_ADDI     => "000-----------01",
        C_JAL      => "001-----------01",
        C_J        => "101-----------01",
        C_LI       => "010-----------01",
        C_LUI      => "011-----------01",
        C_SRLI     => "100000--------01",
        C_SRAI     => "100001--------01",
        C_ANDI     => "100-10--------01",
        C_SUB      => "100011---00---01",
        C_XOR      => "100011---01---01",
        C_OR       => "100011---10---01",
        C_AND      => "100011---11---01",
        C_BEQZ     => "110-----------01",
        C_BNEZ     => "111-----------01",
        C_SLLI     => "0000----------10",
        C_MV       => "1000----------10",
        C_ADD      => "1001----------10",
        C_LWSP     => "010-----------10",
        C_SWSP     => "110-----------10",
        C_MUL      => "100111---10---01",
        ADDI       => "-----------------000-----0010011",
        JALR       => "-----------------000-----1100111",
        JAL        => "-------------------------1101111",
        LUI        => "-------------------------0110111",
        SLLI       => "0000000----------001-----0010011",
        SRLI       => "0000000----------101-----0010011",
        SRAI       => "0100000----------101-----0010011",
        ANDI       => "-----------------111-----0010011",
        ADD        => "0000000----------000-----0110011",
        SUB        => "0100000----------000-----0110011",
        AND_OP     => "0000000----------111-----0110011",
        OR_OP      => "0000000----------110-----0110011",
        XOR_OP     => "0000000----------100-----0110011",
        LW         => "-----------------010-----0000011",
        SW         => "-----------------010-----0100011",
        BEQ        => "-----------------000-----1100011",
        BNE        => "-----------------001-----1100011",
        MUL        => "0000001----------000-----0110011",
        BLT        => "-----------------100-----1100011",
        BGE        => "-----------------101-----1100011",
        BLTU       => "-----------------110-----1100011",
        BGEU       => "-----------------111-----1100011",
        AUIPC      => "-------------------------0010111",
        SLTI       => "-----------------010-----0010011",
        SLTIU      => "-----------------011-----0010011",
        XORI       => "-----------------100-----0010011",
        ORI        => "-----------------110-----0010011",
        SLL32      => "0000000----------001-----0110011",
        SLT        => "0000000----------010-----0110011",
        SLTU       => "0000000----------011-----0110011",
        SRL32      => "0000000----------101-----0110011",
        SRA32      => "0100000----------101-----0110011",
        LB         => "-----------------000-----0000011",
        LH         => "-----------------001-----0000011",
        LBU        => "-----------------100-----0000011",
        LHU        => "-----------------101-----0000011",
        SB         => "-----------------000-----0100011",
        SH         => "-----------------001-----0100011",
        LR_W       => "00010------------010-----0101111",
        SC_W       => "00011------------010-----0101111",
        AMO        => "-----------------010-----0101111",
        CSRRW      => "-----------------001-----1110011",
        CSRRS      => "-----------------010-----1110011",
        CSRRC      => "-----------------011-----1110011",
        CSRRWI     => "-----------------101-----1110011",
        CSRRSI     => "-----------------110-----1110011",
        CSRRCI     => "-----------------111-----1110011",
        FENCE      => "-----------------000-----0001111",
        ECALL      => x"00000073",
        MRET       => x"30200073",
        WFI        => x"10500073",
        FENCE_I    => "00000000000000000001000000001111",
        EBREAK     => "00000000000100000000000001110011",
        MULH       => "0000001----------001-----0110011",
        MULHSU     => "0000001----------010-----0110011",
        MULHU      => "0000001----------011-----0110011",
        DIV        => "0000001----------100-----0110011",
        DIVU       => "0000001----------101-----0110011",
        REM_OP     => "0000001----------110-----0110011",
        REMU       => "0000001----------111-----0110011",
        AMOSWAP_W  => "00001------------010-----0101111",
        AMOADD_W   => "00000------------010-----0101111",
        AMOXOR_W   => "00100------------010-----0101111",
        AMOAND_W   => "01100------------010-----0101111",
        AMOOR_W    => "01000------------010-----0101111",
        AMOMIN_W   => "10000------------010-----0101111",
        AMOMAX_W   => "10100------------010-----0101111",
        AMOMINU_W  => "11000------------010-----0101111",
        AMOMAXU_W  => "11100------------010-----0101111"
    );

    constant EXCEPT_C : exception_constants_t := (
        NO_EXCEPTION                    => x"F",
        INSTRUCTION_MISALIGNED          => x"0",
        INSTRUCTION_FAULT               => x"1",
        ILLEGAL_INSTRUCTION             => x"2",
        EBREAKPOINT                     => x"3",
        LOAD_ADDRESS_MISALIGNED         => x"4",
        LOAD_ACCESS_FAULT               => x"5",
        STORE_ADDRESS_MISALIGNED        => x"6",
        STORE_ACCESS_FAULT              => x"7",
        ENVIRONMENT_CALL_FROM_U_MODE    => x"8",
        RETURN_FROM_M_MODE              => x"A",
        ENVIRONMENT_CALL_FROM_M_MODE    => x"B",
        EXCEPTION_REFETCH               => x"E"
    );

    constant MEMOP_C : memory_operation_constants_t := (
        LOAD_WORD               => 5x"00",
        LOAD_HALF               => 5x"01",
        LOAD_BYTE               => 5x"02",
        LOAD_HALF_UNSIGNED      => 5x"03",
        LOAD_BYTE_UNSIGNED      => 5x"04",
        STORE_WORD              => 5x"05",
        STORE_HALF              => 5x"06",
        STORE_BYTE              => 5x"07",
        LOAD_RESERVED_WORD      => 5x"08",
        STORE_CONDITIONAL_WORD  => 5x"09",
        ATOMIC_MEM_OP           => 5x"0A",
        NONE                    => 5x"10"
    );

    constant BRANCH_C : branch_conditions_t := (
        NEVER       => "00",
        ALWAYS      => "01",
        ZERO        => "10",
        NOT_ZERO    => "11"
    );

    constant ALUSRCA_C : alu_source_a  := (
        RS1 => "0",
        PC  => "1"
    );

    constant ALUSRCB_C : alu_source_b  := (
        RS2 => "0",
        IMM => "1"
    );

    function to_std_logic(value : boolean) return std_logic;    
    

end package hazard3_constants;

package body hazard3_constants is
    function to_std_logic(value : boolean)
        return std_logic is
    begin
        if value then
            return '1';
        else
            return '0';
        end if;
    end function to_std_logic;
    
end package body hazard3_constants;

