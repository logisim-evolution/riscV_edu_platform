library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.all;

package hazard3_constants is

    -- ========================================================================
    -- Top Level Constants 
    -- ========================================================================

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
    constant MAX_NUMBER_OF_IRQ_C        : integer := 512;
    constant CSR_ADDRESS_WIDTH_C        : integer := 12;
    constant MTVEC_WRITE_MASK_C         : std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0) := x"FFFF_FFFD";

    -- JEDEC JEP106-compliant vendor ID, left 0 when not implemented or non-commercial implementation.
    constant MVENDORID_C                : std_logic_vector(DATA_WIDTH_C - 1 downto 0) := 32x"0";
    -- Architecture ID of this processor / core (left 0 as it doesn't match the Hazard3 fully anymore)
    constant MARCHID_C                  : std_logic_vector(DATA_WIDTH_C - 1 downto 0) := 32d"27";
    -- Pointer to configuration structure blob, or all zeros (WORD aligned)
    constant MCONFIGPTR_C               : std_logic_vector(DATA_WIDTH_C - 1 downto 0) := 32x"0";

    -- ========================================================================
    -- Record Type Declarations (Nested Hierarchy)
    -- ========================================================================

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

    type csr_access_types_t is record
        W : std_logic_vector(1 downto 0);
        S : std_logic_vector(1 downto 0);
        C : std_logic_vector(1 downto 0);
    end record;

    subtype csr_addr_t is natural range 0 to 16#FFF#;

    -- Machine Information Registers (Read-Only)
    type addresses_csr_machine_info_t is record
        MVENDORID   : csr_addr_t;   -- Vendor ID
        MARCHID     : csr_addr_t;   -- Architecture ID
        MIMPID      : csr_addr_t;   -- Implementation ID
        MHARTID     : csr_addr_t;   -- Hardware thread ID
        MCONFIGPTR  : csr_addr_t;   -- Pointer to configuration data structures
    end record;

    -- Machine Trap Setup (Read/Write)
    type addresses_csr_machine_trap_setup_t is record
        MSTATUS     : csr_addr_t;   -- Machine status register
        MSTATUSH    : csr_addr_t;   -- As of priv-1.12 this must be present even if tied 0
        MISA        : csr_addr_t;   -- ISA and extensions
        MEDELEG     : csr_addr_t;   -- Machine exception delegation register
        MIDELEG     : csr_addr_t;   -- Machine interrupt delegation register
        MIE         : csr_addr_t;   -- Machine interrupt-enable register
        MTVEC       : csr_addr_t;   -- Machine trap-handler base address
        MCOUNTEREN  : csr_addr_t;   -- Machine counter enable
    end record;

    -- Machine Trap Handling (Read/Write)
    type addresses_csr_machine_trap_handling_t is record
        MSCRATCH    : csr_addr_t;   -- Scratch register for machine trap handlers
        MEPC        : csr_addr_t;   -- Machine exception program counter
        MCAUSE      : csr_addr_t;   -- Machine trap cause
        MTVAL       : csr_addr_t;   -- Machine bad address or instruction
        MIP         : csr_addr_t;   -- Machine interrupt pending
    end record;

    -- Machine Memory Protection (Read/Write)
    type addresses_csr_machine_memory_protection_t is record
        PMPCFG0     : csr_addr_t;   -- Physical memory protection configuration
        PMPCFG1     : csr_addr_t;   -- Physical memory protection configuration, RV32 only
        PMPCFG2     : csr_addr_t;   -- Physical memory protection configuration
        PMPCFG3     : csr_addr_t;   -- Physical memory protection configuration, RV32 only
        PMPADDR0    : csr_addr_t;   -- Physical memory protection address register
        PMPADDR1    : csr_addr_t;   -- Physical memory protection address register
        PMPADDR2    : csr_addr_t;   -- Physical memory protection address register
        PMPADDR3    : csr_addr_t;   -- Physical memory protection address register
        PMPADDR4    : csr_addr_t;   -- Physical memory protection address register
        PMPADDR5    : csr_addr_t;   -- Physical memory protection address register
        PMPADDR6    : csr_addr_t;   -- Physical memory protection address register
        PMPADDR7    : csr_addr_t;   -- Physical memory protection address register
        PMPADDR8    : csr_addr_t;   -- Physical memory protection address register
        PMPADDR9    : csr_addr_t;   -- Physical memory protection address register
        PMPADDR10   : csr_addr_t;   -- Physical memory protection address register
        PMPADDR11   : csr_addr_t;   -- Physical memory protection address register
        PMPADDR12   : csr_addr_t;   -- Physical memory protection address register
        PMPADDR13   : csr_addr_t;   -- Physical memory protection address register
        PMPADDR14   : csr_addr_t;   -- Physical memory protection address register
        PMPADDR15   : csr_addr_t;   -- Physical memory protection address register
        MSECCFG     : csr_addr_t;
        MSECCFGH    : csr_addr_t;
    end record;

    -- Performance Counters (Read/Write)
    type addresses_csr_performance_counters_t is record
        MCYCLE          : csr_addr_t;   -- Raw cycles since start of day
        MINSTRET        : csr_addr_t;   -- Instruction retire count since start of day
        MHPMCOUNTER3    : csr_addr_t;   -- WARL (we tie to 0)
        MHPMCOUNTER4    : csr_addr_t;   -- WARL (we tie to 0)
        MHPMCOUNTER5    : csr_addr_t;   -- WARL (we tie to 0)
        MHPMCOUNTER6    : csr_addr_t;   -- WARL (we tie to 0)
        MHPMCOUNTER7    : csr_addr_t;   -- WARL (we tie to 0)
        MHPMCOUNTER8    : csr_addr_t;   -- WARL (we tie to 0)
        MHPMCOUNTER9    : csr_addr_t;   -- WARL (we tie to 0)
        MHPMCOUNTER10   : csr_addr_t;   -- WARL (we tie to 0)
        MHPMCOUNTER11   : csr_addr_t;   -- WARL (we tie to 0)
        MHPMCOUNTER12   : csr_addr_t;   -- WARL (we tie to 0)
        MHPMCOUNTER13   : csr_addr_t;   -- WARL (we tie to 0)
        MHPMCOUNTER14   : csr_addr_t;   -- WARL (we tie to 0)
        MHPMCOUNTER15   : csr_addr_t;   -- WARL (we tie to 0)
        MHPMCOUNTER16   : csr_addr_t;   -- WARL (we tie to 0)
        MHPMCOUNTER17   : csr_addr_t;   -- WARL (we tie to 0)
        MHPMCOUNTER18   : csr_addr_t;   -- WARL (we tie to 0)
        MHPMCOUNTER19   : csr_addr_t;   -- WARL (we tie to 0)
        MHPMCOUNTER20   : csr_addr_t;   -- WARL (we tie to 0)
        MHPMCOUNTER21   : csr_addr_t;   -- WARL (we tie to 0)
        MHPMCOUNTER22   : csr_addr_t;   -- WARL (we tie to 0)
        MHPMCOUNTER23   : csr_addr_t;   -- WARL (we tie to 0)
        MHPMCOUNTER24   : csr_addr_t;   -- WARL (we tie to 0)
        MHPMCOUNTER25   : csr_addr_t;   -- WARL (we tie to 0)
        MHPMCOUNTER26   : csr_addr_t;   -- WARL (we tie to 0)
        MHPMCOUNTER27   : csr_addr_t;   -- WARL (we tie to 0)
        MHPMCOUNTER28   : csr_addr_t;   -- WARL (we tie to 0)
        MHPMCOUNTER29   : csr_addr_t;   -- WARL (we tie to 0)
        MHPMCOUNTER30   : csr_addr_t;   -- WARL (we tie to 0)
        MHPMCOUNTER31   : csr_addr_t;   -- WARL (we tie to 0)
        MCYCLEH         : csr_addr_t;   -- High halves of each counter
        MINSTRETH       : csr_addr_t;
        MHPMCOUNTER3H   : csr_addr_t;
        MHPMCOUNTER4H   : csr_addr_t;
        MHPMCOUNTER5H   : csr_addr_t;
        MHPMCOUNTER6H   : csr_addr_t;
        MHPMCOUNTER7H   : csr_addr_t;
        MHPMCOUNTER8H   : csr_addr_t;
        MHPMCOUNTER9H   : csr_addr_t;
        MHPMCOUNTER10H  : csr_addr_t;
        MHPMCOUNTER11H  : csr_addr_t;
        MHPMCOUNTER12H  : csr_addr_t;
        MHPMCOUNTER13H  : csr_addr_t;
        MHPMCOUNTER14H  : csr_addr_t;
        MHPMCOUNTER15H  : csr_addr_t;
        MHPMCOUNTER16H  : csr_addr_t;
        MHPMCOUNTER17H  : csr_addr_t;
        MHPMCOUNTER18H  : csr_addr_t;
        MHPMCOUNTER19H  : csr_addr_t;
        MHPMCOUNTER20H  : csr_addr_t;
        MHPMCOUNTER21H  : csr_addr_t;
        MHPMCOUNTER22H  : csr_addr_t;
        MHPMCOUNTER23H  : csr_addr_t;
        MHPMCOUNTER24H  : csr_addr_t;
        MHPMCOUNTER25H  : csr_addr_t;
        MHPMCOUNTER26H  : csr_addr_t;
        MHPMCOUNTER27H  : csr_addr_t;
        MHPMCOUNTER28H  : csr_addr_t;
        MHPMCOUNTER29H  : csr_addr_t;
        MHPMCOUNTER30H  : csr_addr_t;
        MHPMCOUNTER31H  : csr_addr_t;
        MCOUNTINHIBIT   : csr_addr_t;   -- Count inhibit register for mcycle/minstret
        MHPMEVENT3      : csr_addr_t;   -- WARL (we tie to 0)
        MHPMEVENT4      : csr_addr_t;   -- WARL (we tie to 0)
        MHPMEVENT5      : csr_addr_t;   -- WARL (we tie to 0)
        MHPMEVENT6      : csr_addr_t;   -- WARL (we tie to 0)
        MHPMEVENT7      : csr_addr_t;   -- WARL (we tie to 0)
        MHPMEVENT8      : csr_addr_t;   -- WARL (we tie to 0)
        MHPMEVENT9      : csr_addr_t;   -- WARL (we tie to 0)
        MHPMEVENT10     : csr_addr_t;   -- WARL (we tie to 0)
        MHPMEVENT11     : csr_addr_t;   -- WARL (we tie to 0)
        MHPMEVENT12     : csr_addr_t;   -- WARL (we tie to 0)
        MHPMEVENT13     : csr_addr_t;   -- WARL (we tie to 0)
        MHPMEVENT14     : csr_addr_t;   -- WARL (we tie to 0)
        MHPMEVENT15     : csr_addr_t;   -- WARL (we tie to 0)
        MHPMEVENT16     : csr_addr_t;   -- WARL (we tie to 0)
        MHPMEVENT17     : csr_addr_t;   -- WARL (we tie to 0)
        MHPMEVENT18     : csr_addr_t;   -- WARL (we tie to 0)
        MHPMEVENT19     : csr_addr_t;   -- WARL (we tie to 0)
        MHPMEVENT20     : csr_addr_t;   -- WARL (we tie to 0)
        MHPMEVENT21     : csr_addr_t;   -- WARL (we tie to 0)
        MHPMEVENT22     : csr_addr_t;   -- WARL (we tie to 0)
        MHPMEVENT23     : csr_addr_t;   -- WARL (we tie to 0)
        MHPMEVENT24     : csr_addr_t;   -- WARL (we tie to 0)
        MHPMEVENT25     : csr_addr_t;   -- WARL (we tie to 0)
        MHPMEVENT26     : csr_addr_t;   -- WARL (we tie to 0)
        MHPMEVENT27     : csr_addr_t;   -- WARL (we tie to 0)
        MHPMEVENT28     : csr_addr_t;   -- WARL (we tie to 0)
        MHPMEVENT29     : csr_addr_t;   -- WARL (we tie to 0)
        MHPMEVENT30     : csr_addr_t;   -- WARL (we tie to 0)
        MHPMEVENT31     : csr_addr_t;   -- WARL (we tie to 0)
    end record;

    -- Other Standard M-Mode CSRs
    type addresses_csr_other_standard_m_mode_t is record
        MENVCFG     : csr_addr_t;
        MENVCFGH    : csr_addr_t;
    end record;

    -- Custom M-Mode CSRs
    type addresses_csr_custom_m_mode_t is record
        PMPCFGM0    : csr_addr_t;   -- Make PMP regions M-mode without locking
        MEIEA       : csr_addr_t;   -- External interrupt pending array
        MEIPA       : csr_addr_t;   -- External interrupt enable array
        MEIFA       : csr_addr_t;   -- External interrupt force array
        MEIPRA      : csr_addr_t;   -- External interrupt priority array
        MEINEXT     : csr_addr_t;   -- Next external interrupt
        MEICONTEXT  : csr_addr_t;   -- External interrupt context register
        MSLEEP      : csr_addr_t;   -- M-mode sleep control register
        H3MISA      : csr_addr_t;   -- Hazard3 M-mode ISA identification register
    end record;

    -- U-Mode CSRs
    type addresses_csr_u_mode_t is record
        CYCLE       : csr_addr_t;
        TIME        : csr_addr_t;
        INSTRET     : csr_addr_t;
        CYCLEH      : csr_addr_t;
        TIMEH       : csr_addr_t;
        INSTRETH    : csr_addr_t;
        SLEEP       : csr_addr_t;   -- U-mode subset of M-mode sleep control
    end record;

    -- Trigger Module CSRs
    type addresses_csr_trigger_module_t is record
        TSELECT     : csr_addr_t;
        TDATA1      : csr_addr_t;
        TDATA2      : csr_addr_t;
        TDATA3      : csr_addr_t;
        TINFO       : csr_addr_t;
        TCONTROL    : csr_addr_t;
        MCONTEXT    : csr_addr_t;
    end record;

    -- D-Mode CSRs
    type addresses_csr_d_mode_t is record
        DCSR        : csr_addr_t;
        DPC         : csr_addr_t;
        DMDATA0     : csr_addr_t;   -- Custom read/write
    end record;

    -- Master CSR Addresses Record Type
    type csr_addresses_t is record
        MACHINE_INFO              : addresses_csr_machine_info_t;               -- Machine Information Registers (Read-Only)
        MACHINE_TRAP_SETUP        : addresses_csr_machine_trap_setup_t;         -- Machine Trap Setup (Read/Write)
        MACHINE_TRAP_HANDLING     : addresses_csr_machine_trap_handling_t;      -- Machine Trap Handling (Read/Write)
        MACHINE_MEMORY_PROTECTION : addresses_csr_machine_memory_protection_t;  -- Machine Memory Protection (Read/Write)
        PERFORMANCE_COUNTERS      : addresses_csr_performance_counters_t;       -- Performance Counters (Read/Write)
        OTHER_STANDARD_M_MODE     : addresses_csr_other_standard_m_mode_t;      -- Other Standard M-Mode CSRs
        CUSTOM_M_MODE             : addresses_csr_custom_m_mode_t;              -- Custom M-Mode CSRs
        U_MODE                    : addresses_csr_u_mode_t;                     -- U-Mode CSRs
        TRIGGER_MODULE            : addresses_csr_trigger_module_t;             -- Trigger Module CSRs
        D_MODE                    : addresses_csr_d_mode_t;                     -- D-Mode CSRs
    end record;

    type mimpid_rtl_t is record
        PRERELEASE : std_logic_vector(0 downto 0);
        MAJOR      : std_logic_vector(3 downto 0);
        MINOR      : std_logic_vector(7 downto 0);
        PATCH      : std_logic_vector(7 downto 0);
    end record;

    -- ========================================================================
    -- Constant Initialization
    -- ========================================================================

    -- MIMPID records the release version. To be updated
    -- manually with every release!
    constant RTL_MIMPID : mimpid_rtl_t  := (
        PRERELEASE => 1d"0",
        MAJOR      => 4d"1",
        MINOR      => 8d"1",
        PATCH      => 8d"1"
    );

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
        LR_W       => "00010--00000-----010-----0101111",
        SC_W       => "00011------------010-----0101111",
        AMO        => "-----------------010-----0101111",
        CSRRW      => "-----------------001-----1110011",
        CSRRS      => "-----------------010-----1110011",
        CSRRC      => "-----------------011-----1110011",
        CSRRWI     => "-----------------101-----1110011",
        CSRRSI     => "-----------------110-----1110011",
        CSRRCI     => "-----------------111-----1110011",
        FENCE      => "------------00000000000000001111",
        ECALL      => "00000000000000000000000001110011",
        MRET       => "00110000001000000000000001110011",
        WFI        => "00010000010100000000000001110011",
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

    constant CSR_WTYPE : csr_access_types_t := (
        W => "00",
        S => "01",
        C => "10"
    );

    constant CSR_ADDRESSES : csr_addresses_t := (
        MACHINE_INFO => (
            MVENDORID       => 16#F11#,
            MARCHID         => 16#F12#,
            MIMPID          => 16#F13#,
            MHARTID         => 16#F14#,
            MCONFIGPTR      => 16#F15#
        ),
        MACHINE_TRAP_SETUP => (
            MSTATUS         => 16#300#,
            MSTATUSH        => 16#310#,
            MISA            => 16#301#,
            MEDELEG         => 16#302#,
            MIDELEG         => 16#303#,
            MIE             => 16#304#,
            MTVEC           => 16#305#,
            MCOUNTEREN      => 16#306#
        ),
        MACHINE_TRAP_HANDLING => (
            MSCRATCH        => 16#340#,
            MEPC            => 16#341#,
            MCAUSE          => 16#342#,
            MTVAL           => 16#343#,
            MIP             => 16#344#
        ),
        MACHINE_MEMORY_PROTECTION => (
            PMPCFG0         => 16#3A0#,
            PMPCFG1         => 16#3A1#,
            PMPCFG2         => 16#3A2#,
            PMPCFG3         => 16#3A3#,
            PMPADDR0        => 16#3B0#,
            PMPADDR1        => 16#3B1#,
            PMPADDR2        => 16#3B2#,
            PMPADDR3        => 16#3B3#,
            PMPADDR4        => 16#3B4#,
            PMPADDR5        => 16#3B5#,
            PMPADDR6        => 16#3B6#,
            PMPADDR7        => 16#3B7#,
            PMPADDR8        => 16#3B8#,
            PMPADDR9        => 16#3B9#,
            PMPADDR10       => 16#3BA#,
            PMPADDR11       => 16#3BB#,
            PMPADDR12       => 16#3BC#,
            PMPADDR13       => 16#3BD#,
            PMPADDR14       => 16#3BE#,
            PMPADDR15       => 16#3BF#,
            MSECCFG         => 16#747#,
            MSECCFGH        => 16#757#
        ),
        PERFORMANCE_COUNTERS => (
            MCYCLE          => 16#B00#,
            MINSTRET        => 16#B02#,
            MHPMCOUNTER3    => 16#B03#,
            MHPMCOUNTER4    => 16#B04#,
            MHPMCOUNTER5    => 16#B05#,
            MHPMCOUNTER6    => 16#B06#,
            MHPMCOUNTER7    => 16#B07#,
            MHPMCOUNTER8    => 16#B08#,
            MHPMCOUNTER9    => 16#B09#,
            MHPMCOUNTER10   => 16#B0A#,
            MHPMCOUNTER11   => 16#B0B#,
            MHPMCOUNTER12   => 16#B0C#,
            MHPMCOUNTER13   => 16#B0D#,
            MHPMCOUNTER14   => 16#B0E#,
            MHPMCOUNTER15   => 16#B0F#,
            MHPMCOUNTER16   => 16#B10#,
            MHPMCOUNTER17   => 16#B11#,
            MHPMCOUNTER18   => 16#B12#,
            MHPMCOUNTER19   => 16#B13#,
            MHPMCOUNTER20   => 16#B14#,
            MHPMCOUNTER21   => 16#B15#,
            MHPMCOUNTER22   => 16#B16#,
            MHPMCOUNTER23   => 16#B17#,
            MHPMCOUNTER24   => 16#B18#,
            MHPMCOUNTER25   => 16#B19#,
            MHPMCOUNTER26   => 16#B1A#,
            MHPMCOUNTER27   => 16#B1B#,
            MHPMCOUNTER28   => 16#B1C#,
            MHPMCOUNTER29   => 16#B1D#,
            MHPMCOUNTER30   => 16#B1E#,
            MHPMCOUNTER31   => 16#B1F#,
            MCYCLEH         => 16#B80#,
            MINSTRETH       => 16#B82#,
            MHPMCOUNTER3H   => 16#B83#,
            MHPMCOUNTER4H   => 16#B84#,
            MHPMCOUNTER5H   => 16#B85#,
            MHPMCOUNTER6H   => 16#B86#,
            MHPMCOUNTER7H   => 16#B87#,
            MHPMCOUNTER8H   => 16#B88#,
            MHPMCOUNTER9H   => 16#B89#,
            MHPMCOUNTER10H  => 16#B8A#,
            MHPMCOUNTER11H  => 16#B8B#,
            MHPMCOUNTER12H  => 16#B8C#,
            MHPMCOUNTER13H  => 16#B8D#,
            MHPMCOUNTER14H  => 16#B8E#,
            MHPMCOUNTER15H  => 16#B8F#,
            MHPMCOUNTER16H  => 16#B90#,
            MHPMCOUNTER17H  => 16#B91#,
            MHPMCOUNTER18H  => 16#B92#,
            MHPMCOUNTER19H  => 16#B93#,
            MHPMCOUNTER20H  => 16#B94#,
            MHPMCOUNTER21H  => 16#B95#,
            MHPMCOUNTER22H  => 16#B96#,
            MHPMCOUNTER23H  => 16#B97#,
            MHPMCOUNTER24H  => 16#B98#,
            MHPMCOUNTER25H  => 16#B99#,
            MHPMCOUNTER26H  => 16#B9A#,
            MHPMCOUNTER27H  => 16#B9B#,
            MHPMCOUNTER28H  => 16#B9C#,
            MHPMCOUNTER29H  => 16#B9D#,
            MHPMCOUNTER30H  => 16#B9E#,
            MHPMCOUNTER31H  => 16#B9F#,
            MCOUNTINHIBIT   => 16#320#,
            MHPMEVENT3      => 16#323#,
            MHPMEVENT4      => 16#324#,
            MHPMEVENT5      => 16#325#,
            MHPMEVENT6      => 16#326#,
            MHPMEVENT7      => 16#327#,
            MHPMEVENT8      => 16#328#,
            MHPMEVENT9      => 16#329#,
            MHPMEVENT10     => 16#32A#,
            MHPMEVENT11     => 16#32B#,
            MHPMEVENT12     => 16#32C#,
            MHPMEVENT13     => 16#32D#,
            MHPMEVENT14     => 16#32E#,
            MHPMEVENT15     => 16#32F#,
            MHPMEVENT16     => 16#330#,
            MHPMEVENT17     => 16#331#,
            MHPMEVENT18     => 16#332#,
            MHPMEVENT19     => 16#333#,
            MHPMEVENT20     => 16#334#,
            MHPMEVENT21     => 16#335#,
            MHPMEVENT22     => 16#336#,
            MHPMEVENT23     => 16#337#,
            MHPMEVENT24     => 16#338#,
            MHPMEVENT25     => 16#339#,
            MHPMEVENT26     => 16#33A#,
            MHPMEVENT27     => 16#33B#,
            MHPMEVENT28     => 16#33C#,
            MHPMEVENT29     => 16#33D#,
            MHPMEVENT30     => 16#33E#,
            MHPMEVENT31     => 16#33F#
        ),
        OTHER_STANDARD_M_MODE => (
            MENVCFG         => 16#30a#,
            MENVCFGH        => 16#31a#
        ),
        CUSTOM_M_MODE => (
            PMPCFGM0        => 16#BD0#,
            MEIEA           => 16#BE0#,
            MEIPA           => 16#BE1#,
            MEIFA           => 16#BE2#,
            MEIPRA          => 16#BE3#,
            MEINEXT         => 16#BE4#,
            MEICONTEXT      => 16#BE5#,
            MSLEEP          => 16#BF0#,
            H3MISA          => 16#BF1#
        ),
        U_MODE => (
            CYCLE           => 16#C00#,
            TIME            => 16#C01#,
            INSTRET         => 16#C02#,
            CYCLEH          => 16#C80#,
            TIMEH           => 16#C81#,
            INSTRETH        => 16#C82#,
            SLEEP           => 16#8F0#
        ),
        TRIGGER_MODULE => (
            TSELECT         => 16#7A0#,
            TDATA1          => 16#7A1#,
            TDATA2          => 16#7A2#,
            TDATA3          => 16#7A3#,
            TINFO           => 16#7A4#,
            TCONTROL        => 16#7A5#,
            MCONTEXT        => 16#7A8#
        ),
        D_MODE => (
            DCSR            => 16#7B0#,
            DPC             => 16#7B1#,
            DMDATA0         => 16#BFF#
        )
    );

    -- ========================================================================
    -- Custom Functions
    -- ========================================================================

    function to_std_logic(value : boolean) return std_logic;

    function clog2(value : integer) return natural;

    type std_logic_array_t is array (natural range <>) of std_logic_vector;

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

    function clog2(value : integer)
        return natural is
    begin
        return natural(ceil(log2(real(value))));
    end function clog2;

end package body hazard3_constants;

