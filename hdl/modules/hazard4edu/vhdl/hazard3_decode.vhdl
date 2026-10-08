library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.hazard3_constants.all;

entity hazard3_decode is
    generic(
        RESET_VECTOR     : unsigned(31 downto 0) := x"0000_0000";
        EXTENSION_A      : boolean                       := true;
        EXTENSION_C      : boolean                       := true;
        EXTENSION_E      : boolean                       := true;
        EXTENSION_M      : boolean                       := true;
        CSR_M_MANDATORY  : boolean                       := true;
        CSR_M_TRAP       : boolean                       := true;
        CSR_COUNTER      : boolean                       := false;
        U_MODE           : boolean                       := false;
        DEBUG_SUPPORT    : boolean                       := false;
        BRANCH_PREDICTOR : boolean                       := false
    );
    port(
        clk                     : in  std_logic;
        rst_n                   : in  std_logic;

        fd_cir                  : in  std_logic_vector(31 downto 0);
        fd_cir_err              : in  std_logic_vector(1 downto 0);
        fd_cir_predbranch       : in  std_logic_vector(1 downto 0);
        fd_cir_vld              : in  std_logic_vector(1 downto 0);
        fd_cir_is_32bit         : in  std_logic;
        fd_cir_invalid_16bit    : in  std_logic;
        fd_cir_is_uop           : in  std_logic;
        fd_cir_uop_nonfinal     : in  std_logic;
        fd_cir_uop_no_pc_update : in  std_logic;
        fd_cir_uop_atomic       : in  std_logic;

        df_cir_use              : out std_logic_vector(1 downto 0);
        df_cir_flush_behind     : out std_logic;

        df_uop_stall            : out std_logic;
        df_uop_clear            : out std_logic;
        df_lspair_phase_next    : out std_logic;

        d_pc                    : out std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0);

        debug_mode              : in  std_logic;
        m_mode                  : in  std_logic;
        trap_wfi                : in  std_logic;

        debug_dpc_wdata         : in  std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0);
        debug_dpc_wen           : in  std_logic;
        debug_dpc_rdata         : out std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0);

        d_starved               : out std_logic;
        x_stall                 : in  std_logic;
        f_jump_now              : in  std_logic;
        x_jump_not_except       : in  std_logic;
        f_jump_target           : in  std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0);
        d_btb_target_addr       : in  std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0);

        d_imm                   : out std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        d_rs1                   : out std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
        d_rs2                   : out std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
        d_rd                    : out std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
        d_funct3_32b            : out std_logic_vector(2 downto 0);
        d_funct7_32b            : out std_logic_vector(6 downto 0);
        d_alusrc_a              : out std_logic_vector(ALU_SOURCE_WIDTH_C - 1 downto 0);
        d_alusrc_b              : out std_logic_vector(ALU_SOURCE_WIDTH_C - 1 downto 0);
        d_aluop                 : out std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
        d_memop                 : out std_logic_vector(MEMOP_WIDTH_C - 1 downto 0);
        d_mulop                 : out std_logic_vector(MULOP_WIDTH_C - 1 downto 0);
        d_csr_ren               : out std_logic;
        d_csr_wen               : out std_logic;
        d_csr_wtype             : out std_logic_vector(1 downto 0);
        d_csr_w_imm             : out std_logic;
        d_branchcond            : out std_logic_vector(BRANCH_CONDITION_WIDTH_C - 1 downto 0);
        d_addr_offs             : out std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0);
        d_addr_is_regoffs       : out std_logic;
        d_except                : out std_logic_vector(EXCEPTION_WIDTH_C - 1 downto 0);
        d_sleep_wfi             : out std_logic;
        d_sleep_block           : out std_logic;
        d_sleep_unblock         : out std_logic;
        d_no_pc_increment       : out std_logic;
        d_uninterruptible       : out std_logic;
        d_lspair_offset         : out std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0);
        d_fence_i               : out std_logic;
        d_fence_d               : out std_logic
    );
end entity;

architecture rtl of hazard3_decode is
    
    constant HAVE_CSR    : boolean := CSR_M_MANDATORY or CSR_M_TRAP or CSR_COUNTER;
    constant REGISTER_X0 : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0) := 5d"0";
    
    signal d_instr : std_logic_vector(31 downto 0);
    signal d_invalid_32bit : std_logic;
    signal d_invalid : std_logic;
    
    signal d_imm_i : std_logic_vector(31 downto 0);
    signal d_imm_s : std_logic_vector(31 downto 0);
    signal d_imm_b : std_logic_vector(31 downto 0);
    signal d_imm_u : std_logic_vector(31 downto 0);
    signal d_imm_j : std_logic_vector(31 downto 0);

    signal d_except_instr_bus_fault : std_logic;
    signal d_stall                  : std_logic;
    signal fd_cir_vld_non_zero      : std_logic;
    signal fd_cir_vld_larger_one    : std_logic;

    signal jump_caused_by_d  : std_logic;
    signal assert_cir_lock   : std_logic;
    signal finished_cir_lock : std_logic;
    signal deassert_cir_lock : std_logic;
    signal cir_lock_prev_reg : std_logic;
    signal cir_lock          : std_logic;

    signal pc_reg                   : unsigned(ADDRESS_WIDTH_C - 1 downto 0);
    signal pc_seq_next              : unsigned(ADDRESS_WIDTH_C - 1 downto 0);
    signal partial_predicted_branch : std_logic;
    signal predicted_branch         : std_logic;
    signal hold_pc_on_cir_lock      : std_logic;
    signal update_pc_on_cir_unlock  : std_logic;
    signal branch_offs              : std_logic_vector(ADDRESS_WIDTH_C - 1 downto 0);

    signal raw_rs1              : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
    signal raw_rs2              : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
    signal raw_rd               : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
    signal raw_imm              : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal raw_alusrc_a         : std_logic_vector(ALU_SOURCE_WIDTH_C - 1 downto 0);
    signal raw_alusrc_b         : std_logic_vector(ALU_SOURCE_WIDTH_C - 1 downto 0);
    signal raw_aluop            : std_logic_vector(ALUOP_WIDTH_C - 1 downto 0);
    signal raw_memop            : std_logic_vector(MEMOP_WIDTH_C - 1 downto 0);
    signal raw_mulop            : std_logic_vector(MULOP_WIDTH_C - 1 downto 0);
    signal raw_csr_ren          : std_logic;
    signal raw_csr_wen          : std_logic;
    signal raw_csr_wtype        : std_logic_vector(1 downto 0);
    signal raw_csr_w_imm        : std_logic;
    signal raw_branchcond       : std_logic_vector(BRANCH_CONDITION_WIDTH_C - 1 downto 0);
    signal raw_addr_is_regoffs  : std_logic;
    signal raw_except           : std_logic_vector(EXCEPTION_WIDTH_C - 1 downto 0);
    signal raw_sleep_wfi        : std_logic;
    signal raw_sleep_block      : std_logic;
    signal raw_sleep_unblock    : std_logic;
    signal raw_fence_i          : std_logic;
    signal raw_fence_d          : std_logic;

begin

    d_instr <= fd_cir or (30d"0" & not to_std_logic(EXTENSION_C) & not to_std_logic(EXTENSION_C));
    d_invalid <= fd_cir_invalid_16bit or d_invalid_32bit;

    -- Signal to null the mepc offset when taking an exception on this
    -- instruction (because uops in a sequence *which can except*, so excluding
    -- the final sp adjust on popret/popretz, will all have the same PC as the
    -- next uop, which will be in stage 2 when they take their exception)
    d_no_pc_increment <= fd_cir_uop_nonfinal;
    df_uop_stall <= x_stall or d_starved;

    -- Note !df_cir_flush_behind because the jump in cm.popret/popretz is the
    -- *penultimate* instruction: we execute the stack adjustment in the fetch
    -- bubble to save a cycle, still need to finish the uop sequence.
    --
    -- The sp adjust cannot generate an exception (it's an `add` with the same
    -- PMP.X and breakpoint comparison results as earlier uops) and interrupts are
    -- suppressed for this part of the sequence.
    df_uop_clear <= f_jump_now and not df_cir_flush_behind;

    -- Decode various immediate formats
    d_imm_i <= ((31 downto 11 => d_instr(31)), d_instr(30 downto 20));
    d_imm_s <= ((31 downto 11 => d_instr(31)), d_instr(30 downto 25), d_instr(11 downto 7));
    d_imm_b <= ((31 downto 12 => d_instr(31)), d_instr(7), d_instr(30 downto 25), d_instr(11 downto 8), '0');
    d_imm_u <= (d_instr(31 downto 12), (others => '0'));
    d_imm_j <= ((31 downto 20 => d_instr(31)), d_instr(19 downto 12), d_instr(20), d_instr(30 downto 21), '0');

    -- -------------------------------------------------------------------------
    -- PC/CIR control
    -- Must not flag bus error for a valid 16-bit instruction *followed by* an error,
    -- because instruction fetch errors are speculative, and can be flushed by e.g. 
    -- a branch instruction. Note that 16 LSBs must be valid for us to know an instruction;s
    -- size.
    fd_cir_vld_non_zero <= '1' when fd_cir_vld /= "00" else '0';
    fd_cir_vld_larger_one <= '1' when fd_cir_vld /= "00" and fd_cir_vld /= "01" else '0';
    d_except_instr_bus_fault <= (fd_cir_vld_non_zero and fd_cir_err(0)) or
                                (fd_cir_vld_larger_one and fd_cir_is_32bit and fd_cir_err(1));
    d_starved <= not (or fd_cir_vld) or (fd_cir_vld(0) and fd_cir_is_32bit);
    d_stall <= x_stall or d_starved or fd_cir_uop_nonfinal;
    df_cir_use <= 2x"0" when d_starved = '1' or d_stall = '1' else
                  2x"2" when fd_cir_is_32bit = '1' else 2x"1";
    
    -- CIR Locking is required if we successfully assert a jump request, but
    -- decode is stalled. It is not possible to gate the jump request if the
    -- stall depends on bus stall (as this would create a through-path from bus
    -- stall to bus request) so instead we instruct the frontend to preserve the
    -- stalled instruction when flushing, and fill in behind it.
    --
    -- Once the stall clears, the stalled instruction can execute its remaining
    -- side effects e.g. writing a link value to the register file.
    jump_caused_by_d <= f_jump_now and x_jump_not_except;
    assert_cir_lock <= jump_caused_by_d and d_stall;

    -- CIR lock ends naturally when an instruction (not just uop) graduates to the
    -- next stage:
    finished_cir_lock <= not d_stall;

    -- CIR lock can meet an untimely end due to trap entry. One way to reach this
    -- is a dphase load fault on the final load in a cm.popret: here the `ret`
    -- issues a fetch address while stalled on the first dphase cycle, then is
    -- flushed by trap on second cycle.
    deassert_cir_lock <= finished_cir_lock or (f_jump_now and not x_jump_not_except);

    cir_lock <= (cir_lock_prev_reg and not deassert_cir_lock) or assert_cir_lock;
    df_cir_flush_behind <= assert_cir_lock and not cir_lock_prev_reg;
    process(clk, rst_n) is
    begin
        if rst_n = '0' then
            cir_lock_prev_reg <= '0';
        elsif rising_edge(clk) then
            cir_lock_prev_reg <= cir_lock;
        end if;
    end process;
    
    pc_seq_next <= pc_reg + 32d"4" when fd_cir_is_32bit = '1' else pc_reg + 32d"2";
    d_pc <= std_logic_vector(pc_reg);
    debug_dpc_rdata <= std_logic_vector(pc_reg);

    -- Frontend should mark the whole instruction, and nothing but the
    -- instruction, as a predicted branch. This goes wrong when we execute the
    -- address containing the predicted branch twice with different 16-bit
    -- alignments (!). We need to issue a branch-to-self to get back on a linear
    -- path, otherwise PC and CIR will diverge and we will misexecute.
    partial_predicted_branch <= (not d_starved) and to_std_logic(BRANCH_PREDICTOR) and fd_cir_is_32bit and (xor fd_cir_predbranch);
    predicted_branch <= to_std_logic(BRANCH_PREDICTOR) and fd_cir_predbranch(0);

    -- Generally locking takes place on a stalled jump/branch, which may need the
    -- original PC available to produce a link address when it unstalls. An
    -- exception to this is jumps in micro-op sequences: in this case the jump is
    -- the penultimate instruction in the sequence (ret before addi sp) and we
    -- need to capture the pc mid-uop-sequence.
    hold_pc_on_cir_lock <= assert_cir_lock and not (fd_cir_is_uop and (not fd_cir_uop_no_pc_update) and (not x_stall));
    update_pc_on_cir_unlock <= cir_lock_prev_reg and finished_cir_lock and (not fd_cir_uop_no_pc_update);

    process(clk, rst_n) is
    begin
        if rst_n = '0' then
            pc_reg <= RESET_VECTOR;
        elsif rising_edge(clk) then
            if debug_dpc_wen = '1' then
                pc_reg <= unsigned(debug_dpc_wdata);
            elsif debug_mode = '1' then
                pc_reg <= pc_reg;
            elsif (f_jump_now = '1' and hold_pc_on_cir_lock = '0') or update_pc_on_cir_unlock = '1' then
                pc_reg <= unsigned(f_jump_target);
            elsif (f_jump_now = '0' and fd_cir_uop_nonfinal = '1' and fd_cir_uop_no_pc_update = '0' and x_stall = '0') then
                -- End of previously stalled jr uop in cm.popret and cm.popretz:
                -- safe to update PC as next instruction (addi sp) cannot trap.
                pc_reg <= unsigned(f_jump_target);
            elsif d_stall = '0' and cir_lock = '0' then
                -- If this instruction is a predicted-taken branch (and has not
                -- generated a mispredict recovery jump) then set the PC to the
                -- prediction target instead of the sequenyially next PC
                if predicted_branch = '1' then
                    pc_reg <= unsigned(d_btb_target_addr);
                else
                    pc_reg <= pc_seq_next;
                end if;
            end if;
        end if;
    end process;

    branch_offs <= 32d"2" when fd_cir_is_32bit = '0' and predicted_branch = '1' else
                   32d"4" when fd_cir_is_32bit = '1' and predicted_branch = '1' else
                   d_imm_b;
    
    process(all) is
    begin
        case? (to_std_logic(EXTENSION_A) & d_instr(6 downto 2)) is
            when "-_11011" => d_addr_offs <= d_imm_j;     -- JAL
            when "-_11000" => d_addr_offs <= branch_offs; -- Branches
            when "-_01000" => d_addr_offs <= d_imm_s;     -- Store
            when "-_11001" => d_addr_offs <= d_imm_i;     -- JALR
            when "-_00000" => d_addr_offs <= d_imm_i;     -- Loads
            when "1_01011" => d_addr_offs <= 32d"0";      -- Atomics
            when others => d_addr_offs <= x"XXXX_XXXX";
        end case?;
        if partial_predicted_branch = '1' then
            d_addr_offs <= 32d"0";
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- Track phase of load/store pair instructions (Zilsd and Zclsd)

    -- This could be shared with uop_ctr (for Zcmp) but the two are fundamentally
    -- different: Zcmp has 16-bit instructions which expand to sequences of
    -- 32-bit, whereas Zilsd has multi-phase 32-bit instructions and Zclsd has
    -- direct 16-bit aliases of those instructions. Therefore it's cleaner to
    -- separate the phasing from the decompression for Zilsd/Zclsd.
    df_lspair_phase_next <= '0';
    d_lspair_offset <= 32d"0";

    ----------------------------------------------------------------------------
    -- Decode X controls

    process(all) is
    begin
        raw_rs1 <= d_instr(19 downto 15);
        raw_rs2 <= d_instr(24 downto 20);
        raw_rd <= d_instr(11 downto 7);
        raw_imm <= d_imm_i;
        raw_alusrc_a <= ALUSRCA_C.RS1;
        raw_alusrc_b <= ALUSRCB_C.RS2;
        raw_aluop <= ALUOP_C.ADD;
        raw_memop <= MEMOP_C.NONE;
        raw_mulop <= MULOP_C.MUL;
        raw_csr_ren <= '0';
        raw_csr_wen <= '0';
        raw_csr_wtype <= TODO;
        raw_csr_w_imm <= '0';
        raw_branchcond <= BRANCH_C.NEVER;
        raw_addr_is_regoffs <= '0';
        raw_except <= EXCEPT_C.NO_EXCEPTION;
        raw_sleep_wfi <= '0';
        raw_sleep_block <= '0';
        raw_sleep_unblock <= '0';
        raw_fence_i <= '0';
        raw_fence_d <= '0';
        -- Note this funct3/funct7 are valid only for 32-bit instructions. They
        -- are useful for clusters of related ALU ops, such as sh*add, clmul.
        d_funct3_32b <= fd_cir(14 downto 12);
        d_funct7_32b <= fd_cir(31 downto 25);

        d_invalid_32bit <= '0';

        case? d_instr is
            when OPCODE_C.BEQ => 
                d_invalid_32bit <= to_std_logic(DEBUG_SUPPORT) and debug_mode;
                raw_rd <= REGISTER_X0;
                raw_aluop <= ALUOP_C.SUB;
                raw_branchcond <= BRANCH_C.ZERO;
            when OPCODE_C.BNE => 
                d_invalid_32bit <= to_std_logic(DEBUG_SUPPORT) and debug_mode;
                raw_rd <= REGISTER_X0;
                raw_aluop <= ALUOP_C.SUB;
                raw_branchcond <= BRANCH_C.NOT_ZERO;
            when OPCODE_C.BLT => 
                d_invalid_32bit <= to_std_logic(DEBUG_SUPPORT) and debug_mode;
                raw_rd <= REGISTER_X0;
                raw_aluop <= ALUOP_C.LT;
                raw_branchcond <= BRANCH_C.NOT_ZERO;
            when OPCODE_C.BGE => 
                d_invalid_32bit <= to_std_logic(DEBUG_SUPPORT) and debug_mode;
                raw_rd <= REGISTER_X0;
                raw_aluop <= ALUOP_C.LT;
                raw_branchcond <= BRANCH_C.ZERO;
            when OPCODE_C.BLTU =>
                d_invalid_32bit <= to_std_logic(DEBUG_SUPPORT) and debug_mode;
                raw_rd <= REGISTER_X0;
                raw_aluop <= ALUOP_C.LTU;
                raw_branchcond <= BRANCH_C.NOT_ZERO;
            when OPCODE_C.BGEU => 
                d_invalid_32bit <= to_std_logic(DEBUG_SUPPORT) and debug_mode;
                raw_rd <= REGISTER_X0;
                raw_aluop <= ALUOP_C.LTU;
                raw_branchcond <= BRANCH_C.ZERO;
            when OPCODE_C.JALR => 
                d_invalid_32bit <= to_std_logic(DEBUG_SUPPORT) and debug_mode;
                raw_branchcond <= BRANCH_C.ALWAYS;
                raw_addr_is_regoffs <= '1';
                raw_rs2 <= REGISTER_X0;
                raw_aluop <= ALUOP_C.ADD;
                raw_alusrc_a <= ALUSRCA_C.PC;
                raw_alusrc_b <= ALUSRCB_C.IMM;
                raw_rs1 <= REGISTER_X0;
                if fd_cir_is_32bit = '1' then
                    raw_imm <= 32d"4";
                else
                    raw_imm <= 32d"2";
                end if;
            when OPCODE_C.JAL => 
                d_invalid_32bit <= to_std_logic(DEBUG_SUPPORT) and debug_mode;
                raw_branchcond <= BRANCH_C.ALWAYS;
                raw_rs1 <= REGISTER_X0;
                raw_rs2 <= REGISTER_X0;
                raw_aluop <= ALUOP_C.ADD;
                raw_alusrc_a <= ALUSRCA_C.PC;
                raw_alusrc_b <= ALUSRCB_C.IMM;
                if fd_cir_is_32bit = '1' then
                    raw_imm <= 32d"4";
                else
                    raw_imm <= 32d"2";
                end if;
            when others => null;
        end case?;
        
    end process;


end architecture;
