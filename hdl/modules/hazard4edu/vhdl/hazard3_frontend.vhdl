library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.hazard3_constants.all;

entity hazard3_frontend is
    generic(
        PMP_REGIONS      : natural               := 0;
        EXTENSION_C      : boolean               := true;
        EXTENSION_M      : boolean               := true;
        U_MODE           : boolean               := false;
        DEBUG_SUPPORT    : boolean               := true;
        BRANCH_PREDICTOR : boolean               := true
    );
    port(
        clk                  : in  std_logic;
        rst                  : in  std_logic;

        reset_vector         : in  std_logic_vector(31 downto 0);
        -- Fetch interface
        -- addr_vld may be asserted at any time, but after assertion,
        -- neither addr nor addr_vld may change until the cycle after addr_rdy.
        -- There is no backpressure on the data interface; the front end
        -- must ensure it does not request data it cannot receive.
        -- addr_rdy and dat_vld may be functions of hready, and
        -- may not be used to compute combinational outputs.
        mem_size             : out std_logic; -- 1'b1 -> 32 bit access
        mem_addr             : out unsigned(ADDRESS_WIDTH_C - 1 downto 0);
        mem_priv             : out std_logic;
        mem_addr_vld         : out std_logic;
        mem_addr_rdy         : in  std_logic;
        mem_data             : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        mem_data_err         : in  std_logic;
        mem_data_vld         : in  std_logic;
        -- Jump/flush interface
        -- Processor may assert vld at any time. The request will not go through
        -- unless rdy is high. Processor *may* alter request during this time.
        -- Inputs must not be a function of hready.
        jump_target          : in  unsigned(ADDRESS_WIDTH_C - 1 downto 0);
        jump_priv            : in  std_logic;
        jump_target_vld      : in  std_logic;
        jump_target_rdy      : out std_logic;
        -- Interface to the branch target buffer. `src_addr` is the address of the
        -- last halfword of a taken backward branch. The frontend redirects fetch
        -- such that `src_addr` appears to be sequentially followed by `target`.
        btb_set              : in  std_logic;
        btb_set_src_addr     : in  unsigned(ADDRESS_WIDTH_C - 1 downto 0);
        btb_set_src_size     : in  std_logic;
        btb_set_target_addr  : in  unsigned(ADDRESS_WIDTH_C - 1 downto 0);
        btb_clear            : in  std_logic;
        btb_target_addr_out  : out unsigned(ADDRESS_WIDTH_C - 1 downto 0);
        -- Interface to Decode
        cir                  : out std_logic_vector(DATA_WIDTH_C - 1 downto 0); -- Current instruction register; pre-expanded to 32-bit
        cir_raw              : out std_logic_vector(DATA_WIDTH_C - 1 downto 0); -- Unexpanded instruction data
        cir_vld              : out std_logic_vector(1 downto 0); -- number of valid halfwords in CIR
        cir_use              : in  std_logic_vector(1 downto 0); -- number of halfwords D intends to consume
                                                                 -- *may* be a function of hready
        cir_err              : out std_logic_vector(1 downto 0); -- Bus error on upper/lower halfword of CIR.
        cir_predbranch       : out std_logic_vector(1 downto 0); -- Set for last halfword of a predicted-taken branch
        cir_break_any        : out std_logic; -- Set for exact match of a breakpoint address on CIR LSB
        cir_break_d_mode     : out std_logic; -- As above but specifically break to debug mode
        cir_is_32bit         : out std_logic; -- Can't be decoded from CIR due to pre-expansion
        cir_invalid_16bit    : out std_logic; -- Expanded an invalid 32-bit instruction
        cir_is_uop           : out std_logic; -- Current instruction is part of a micro-op sequence
        cir_uop_nonfinal     : out std_logic; -- ...and there are more to follow in this instruction
        cir_uop_no_pc_update : out std_logic; -- Suppress PC increment or jump (note the jump in cm.popret is not the final uop!)
        cir_uop_atomic       : out std_logic; -- Prevent IRQ entry, so intermediate states are not observed
        uop_stall            : in  std_logic;
        uop_clear            : in  std_logic;
        -- "flush_behind": do not flush the oldest instruction when accepting a
        --  jump request (but still flush younger instructions). Sometimes a
        --  stalled instruction may assert a jump request, because e.g. the stall
        --  is dependent on a bus stall signal so can't gate the request.
        cir_flush_behind     : in  std_logic;
        -- Required for regnum predecode when Zilsd is enabled:
        df_lspair_phase_next : in  std_logic;
        -- Signal to power controller that power down is safe. (When going to
        -- sleep, first the pipeline is stalled, and then the power controller
        -- waits for the frontend to naturally come to a halt before releasing
        -- its power request. This avoids manually halting the frontend.)
        pwrdown_ok           : out std_logic;
        -- Signal to delay the first instruction fetch following reset, because
        -- powerup has not yet been negotiated.
        delay_first_fetch    : in  std_logic;
        -- Provide the rs1/rs2 register numbers which will be in CIR next cycle.
        -- Coarse: valid if this instruction has a nonzero register operand.
        -- (Suitable for regfile read)
        predecode_rs1_coarse : out std_logic_vector(4 downto 0);
        predecode_rs2_coarse : out std_logic_vector(4 downto 0);
        -- Fine: like coarse, but accurate zeroing when the operand is implicit.
        -- (Suitable for bypass. Still not precise enough for stall logic.)
        predecode_rs1_fine   : out std_logic_vector(4 downto 0);
        predecode_rs2_fine   : out std_logic_vector(4 downto 0);
        -- Debugger instruction injection: instruction fetch is suppressed when in
        -- debug halt state, and the DM can then inject instructions into the last
        -- entry of the prefetch queue using the vld/rdy handshake.
        debug_mode           : in  std_logic;
        dbg_instr_data       : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        dbg_instr_data_vld   : in  std_logic;
        dbg_instr_data_rdy   : out std_logic;
        -- PMP query->kill interface for X permission checks
        pmp_i_addr           : out unsigned(ADDRESS_WIDTH_C - 1 downto 0);
        pmp_i_m_mode         : out std_logic;
        pmp_i_kill           : in  std_logic;
        -- Trigger unit query->break interface for breakpoints
        trigger_addr         : out unsigned(ADDRESS_WIDTH_C - 1 downto 0);
        trigger_m_mode       : out std_logic;
        trigger_break_any    : in  std_logic_vector(1 downto 0);
        trigger_break_d_mode : in  std_logic_vector(1 downto 0)
    );
end entity hazard3_frontend;

architecture rtl of hazard3_frontend is

    constant W_BUNDLE   : integer := 16;
    -- This is the minimum for full throughput (enough to avoid dropping data when
    -- decode stalls) and there is no significant advantage to going larger.
    constant FIFO_DEPTH : integer := 2;

    -- ============================================================================
    -- Fetch queue signals
    -- ============================================================================
    signal jump_now           : std_logic;
    signal mem_data_hwvld_reg : std_logic_vector(1 downto 0);

    -- PMP X faults are checked in parallel with the fetch (fine if executable
    -- memory is read-idempotent) and failures are promoted to bus errors:
    signal pmp_kill_fetch_dph : std_logic;
    signal mem_or_pmp_err     : std_logic;

    -- Similarly, breakpoint matches are checked during fetch data phase. These
    -- are called mem_xxx because they are the breakpoint metadata for the data
    -- coming back from memory in this dphase.
    signal mem_break_any    : std_logic_vector(1 downto 0);
    signal mem_break_d_mode : std_logic_vector(1 downto 0);

    -- Mark data as containing a predicted-taken branch instruction so that
    -- mispredicts can be recovered -- need to track both halfwords so that we
    -- can mark the entire instruction, and nothing but the instruction:
    signal mem_data_predbranch_reg : std_logic_vector(1 downto 0);

    -- Bus errors (and other metadata) travel alongside data. They cause an
    -- exception if the core decodes the instruction, but until then can be
    -- flushed harmlessly.
    signal fifo_mem_reg          : std_logic_array_t(0 to FIFO_DEPTH)(mem_data'range);
    signal fifo_err_reg          : std_logic_vector(0 to FIFO_DEPTH);
    signal fifo_break_any_reg    : std_logic_array_t(0 to FIFO_DEPTH)(1 downto 0);
    signal fifo_break_d_mode_reg : std_logic_array_t(0 to FIFO_DEPTH)(1 downto 0);
    signal fifo_predbranch_reg   : std_logic_array_t(0 to FIFO_DEPTH)(1 downto 0);
    signal fifo_valid_hw_reg     : std_logic_array_t(0 to FIFO_DEPTH)(1 downto 0);
    signal fifo_valid_reg        : std_logic_vector(0 to FIFO_DEPTH);
    signal fifo_valid_m1_reg     : std_logic_vector(0 to FIFO_DEPTH);
    signal fifo_rdata            : std_logic_vector(mem_data'range);
    signal fifo_full             : std_logic;
    signal fifo_empty            : std_logic;
    signal fifo_almost_full      : std_logic;
    signal fifo_push             : std_logic;
    signal fifo_pop              : std_logic;
    signal fifo_dbg_inject       : std_logic;

    -- ============================================================================
    -- Branch target buffer signals
    -- ============================================================================
    signal btb_src_addr         : unsigned(btb_set_src_addr'range);
    signal btb_src_size         : std_logic;
    signal btb_target_addr      : unsigned(btb_set_target_addr'range);
    signal btb_valid            : std_logic;
    signal btb_src_addr_reg     : unsigned(btb_src_addr'range);
    signal btb_src_size_reg     : std_logic;
    signal btb_target_addr_reg  : unsigned(btb_target_addr'range);
    signal btb_valid_reg        : std_logic;

    -- ============================================================================
    -- Fetch request generation signals
    -- ============================================================================
    -- Fetch addr runs ahead of the PC, in word increments.
    signal fetch_addr_reg                    : unsigned(mem_addr'range);
    signal fetch_priv_reg                    : std_logic;
    signal btb_prev_start_of_overhanging_reg : std_logic;
    signal mem_aph_hwvld_reg                 : std_logic_vector(1 downto 0);
    signal mem_addr_hold_reg                 : std_logic;

    signal btb_match_word         : std_logic;
    signal btb_src_overhanging    : std_logic;
    signal btb_jumped_beyond      : std_logic;
    signal btb_match_current_addr : std_logic;
    signal btb_match_next_addr    : std_logic;
    signal btb_match_now          : std_logic;

    -- Post-increment if jump request is going straight through
    signal jump_target_post_increment : unsigned(mem_addr'range);

    -- Combinatorially generate the address-phase request
    signal reset_holdoff_reg : std_logic;

    signal mem_addr_reg     : unsigned(mem_addr'range);
    signal mem_priv_reg     : std_logic;
    signal mem_addr_vld_reg : std_logic;

    signal fetch_stall : std_logic;

    -- ============================================================================
    -- Bus Pipeline Tracking signals
    -- ============================================================================
    -- Keep track of some useful state of the memory interface
    signal pending_fetches_reg   : unsigned(1 downto 0);
    signal ctr_flush_pending_reg : unsigned(1 downto 0);

    signal pending_fetches_next : unsigned(1 downto 0);

    signal cir_room_for_fetch : std_logic;
    signal cir_is_32bit_reg   : std_logic;

    -- ============================================================================
    -- PMP and trigger unit interfacing: query -> kill/break signals
    -- ============================================================================
    signal pmp_trigger_check_dph_addr   : unsigned(mem_addr'range);
    signal pmp_trigger_check_dph_m_mode : std_logic;
    signal check_addr_dph_reg           : unsigned(mem_addr'range);
    signal check_m_mode_dph_reg         : std_logic;

    -- ============================================================================
    -- Instruction buffer signals
    -- ============================================================================
    -- The entries ("slots") are slightly larger than 16 bits because they also
    -- contain metadata like bus errors:
    constant W_SLOT                : integer := 4 + W_BUNDLE;
    constant SLOT_BREAK_ANY_BIT    : integer := 3 + W_BUNDLE;
    constant SLOT_BREAK_D_MODE_BIT : integer := 2 + W_BUNDLE;
    constant SLOT_ERR_BIT          : integer := 1 + W_BUNDLE;
    constant SLOT_PREDBRANCH_BIT   : integer := 0 + W_BUNDLE;

    signal buf_contents_reg : std_logic_vector(3 * W_SLOT - 1 downto 0);
    signal buf_level_reg    : unsigned(cir_vld'range);
    signal cir_vld_reg      : unsigned(cir_vld'range);

    signal fetch_data_vld     : std_logic;
    signal fetch_data         : std_logic_vector(mem_data'range);
    signal fetch_data_hwvld   : std_logic_vector(1 downto 0);
    signal fetch_bus_err      : std_logic;
    signal fetch_break_any    : std_logic_vector(1 downto 0);
    signal fetch_break_d_mode : std_logic_vector(1 downto 0);
    signal fetch_predbranch   : std_logic_vector(1 downto 0);

    signal fetch_contents_hw1     : std_logic_vector(W_SLOT - 1 downto 0);
    signal fetch_contents_hw0     : std_logic_vector(W_SLOT - 1 downto 0);
    signal fetch_contents_aligned : std_logic_vector(2 * W_SLOT - 1 downto 0);

    signal buf_shifted : std_logic_vector(3 * W_SLOT - 1 downto 0);

    signal level_next_no_fetch : unsigned(1 downto 0);

    signal buf_shifted_plus_fetch : std_logic_vector(3 * W_SLOT - 1 downto 0);

    signal fetch_fill_amount : unsigned(1 downto 0);

    signal buf_level_next : unsigned(1 downto 0);
    signal buf_level_next_raw : unsigned(buf_level_next'range);

    -- ============================================================================
    -- Register number predecode signals
    -- ============================================================================
    signal next_instr          : std_logic_vector(31 downto 0);
    signal next_instr_is_32bit : std_logic;

    signal decomp_uop_step : std_logic_vector(3 downto 0);
    signal uop_ctr         : std_logic_vector(3 downto 0);
    signal uop_stall_inter : std_logic;
    signal zcmp_pushpop_rs2 : std_logic_vector(4 downto 0);
    signal zcmp_pushpop_rs1 : std_logic_vector(4 downto 0);
    signal zcmp_sa01_r1s    : std_logic_vector(4 downto 0);
    signal zcmp_sa01_r2s    : std_logic_vector(4 downto 0);
    signal zcmp_mvsa01_rs1  : std_logic_vector(4 downto 0);
    signal zcmp_mva01s_rs1  : std_logic_vector(4 downto 0);

    signal zilsd_rs2_coarse      : std_logic_vector(4 downto 0);
    signal zclsd_sd_rs2_coarse   : std_logic_vector(4 downto 0);
    signal zclsd_sdsp_rs2_coarse : std_logic_vector(4 downto 0);

    signal decomp_instr_is_32bit   : std_logic;
    signal decomp_instr_out        : std_logic_vector(31 downto 0);
    signal decomp_is_uop           : std_logic;
    signal decomp_is_final_uop     : std_logic;
    signal decomp_uop_no_pc_update : std_logic;
    signal decomp_uop_atomic       : std_logic;
    signal decomp_invalid          : std_logic;

    signal first_uop               : std_logic;
    signal uop_stall_non_first     : std_logic;
    signal uop_stall_on_repeat     : std_logic;
    signal cir_clken               : std_logic;
    signal cir_is_uop_next         : std_logic;
    signal cir_uop_nonfinal_next   : std_logic;

    signal cir_reg                  : std_logic_vector(decomp_instr_out'range);
    signal cir_invalid_16bit_reg    : std_logic;
    signal cir_is_uop_reg           : std_logic;
    signal cir_uop_nonfinal_reg     : std_logic;
    signal cir_uop_no_pc_update_reg : std_logic;
    signal cir_uop_atomic_reg       : std_logic;

begin

    jump_now         <= jump_target_vld and jump_target_rdy;
    mem_or_pmp_err   <= mem_data_err or pmp_kill_fetch_dph;

    fifo_rdata       <= fifo_mem_reg(0);
    fifo_full        <= fifo_valid_reg(FIFO_DEPTH - 1);
    fifo_empty       <= not fifo_valid_reg(0);
    fifo_almost_full <= fifo_valid_reg(FIFO_DEPTH - 2);
    fifo_dbg_inject  <= '1' when DEBUG_SUPPORT and dbg_instr_data_vld = '1' and dbg_instr_data_rdy = '1' else '0';

    BOUNDARY_CONDITION : process(all) begin
        fifo_mem_reg(FIFO_DEPTH) <= mem_data;
        fifo_predbranch_reg(FIFO_DEPTH) <= (others => '0');
        fifo_err_reg(FIFO_DEPTH) <= '0';
        fifo_break_any_reg(FIFO_DEPTH) <= (others => '0');
        fifo_break_d_mode_reg(FIFO_DEPTH) <= (others => '0');

        for i in 0 to FIFO_DEPTH loop
            fifo_valid_reg(i) <= or fifo_valid_hw_reg(i) when EXTENSION_C else fifo_valid_hw_reg(i)(0);
            if i = 0 then
                fifo_valid_m1_reg(i) <= '1';
            else
                fifo_valid_m1_reg(i) <= fifo_valid_reg(i - 1);
            end if;
        end loop;        
    end process BOUNDARY_CONDITION;

    FIFO_UPDATE : process(clk) is
    begin
        if rising_edge(clk) then
            if ?? rst then
                for i in 0 to FIFO_DEPTH - 1 loop
                    fifo_mem_reg(i) <= (others => '0');
                    fifo_predbranch_reg(i) <= (others => '0');
                    fifo_err_reg(i) <= '0';
                    fifo_break_any_reg(i) <= (others => '0');
                    fifo_break_d_mode_reg(i) <= (others => '0');
                end loop;
                fifo_valid_hw_reg <= (others => (others => '0'));
            else
                for i in 0 to FIFO_DEPTH - 1 loop
                    if ?? (fifo_pop or (fifo_push and not fifo_valid_reg(i))) then
                        fifo_mem_reg(i)          <= fifo_mem_reg(i + 1)          when ?? fifo_valid_reg(i + 1) else mem_data;
                        fifo_err_reg(i)          <= fifo_err_reg(i + 1)          when ?? fifo_valid_reg(i + 1) else mem_or_pmp_err;
                        fifo_break_any_reg(i)    <= fifo_break_any_reg(i + 1)    when ?? fifo_valid_reg(i + 1) else mem_break_any;
                        fifo_break_d_mode_reg(i) <= fifo_break_d_mode_reg(i + 1) when ?? fifo_valid_reg(i + 1) else mem_break_d_mode;
                        fifo_predbranch_reg(i)   <= fifo_predbranch_reg(i + 1)   when ?? fifo_valid_reg(i + 1) else mem_data_predbranch_reg;
                    end if;
                    fifo_valid_hw_reg(i) <= (others => '0')          when ?? jump_now                                              else
                                            fifo_valid_hw_reg(i + 1) when ?? (fifo_valid_reg(i + 1) and fifo_pop)                  else
                                            mem_data_hwvld_reg and (1 downto 0 => fifo_push)
                                                                     when ?? (fifo_valid_reg(i) and fifo_pop)                      else
                                            fifo_valid_hw_reg(i)     when ?? fifo_valid_reg(i)                                     else
                                            mem_data_hwvld_reg       when ?? (fifo_push and not fifo_pop and fifo_valid_m1_reg(i)) else
                                            (others => '0');
                end loop;
    		    -- Allow DM to inject instructions directly into the lowest-numbered
    		    -- queue entry. This mux should not extend critical path since it is
    		    -- balanced with the instruction-assembly muxes on the queue bypass
    		    -- path. Note that flush takes precedence over debug injection
    		    -- (and the debug module design must account for this)
                if ?? fifo_dbg_inject then
                    fifo_mem_reg(0) <= dbg_instr_data;
                    fifo_err_reg(0) <= '0';
                    fifo_predbranch_reg(0) <= (others => '0');
                    fifo_break_any_reg(0) <= (others => '0');
                    fifo_break_d_mode_reg(0) <= (others => '0');
                    fifo_valid_hw_reg(0) <= "00" when ?? jump_now else "11";
                end if;
                fifo_valid_hw_reg(FIFO_DEPTH) <= (others => '0');
            end if;
        end if;
    end process FIFO_UPDATE;
    
    pwrdown_ok <= (fifo_full and not jump_target_vld) or debug_mode;

    ---------------------------------------------------------------------------
    -- Branch target buffer

    HAVE_BRANCH_PREDICTOR : if BRANCH_PREDICTOR generate
        btb_src_addr    <= btb_src_addr_reg;
        btb_src_size    <= btb_src_size_reg;
        btb_target_addr <= btb_target_addr_reg;
        btb_valid       <= btb_valid_reg;

        process(clk) begin
            if rising_edge(clk) then
                if ?? rst then
                    btb_src_addr_reg <= (others => '0');
                    btb_src_size_reg <= '0';
                    btb_target_addr_reg <= (others => '0');
                    btb_valid_reg <= '0';
                else
                    if ?? btb_clear then
                        -- Clear takes precedences over set. E.g. if a taken branch is in
                        -- stage 2 and a exception is in stage 3, we must clear the BTB.
                        btb_valid_reg <= '0';
                    elsif ?? btb_set then
                        btb_src_addr_reg <= btb_set_src_addr;
                        btb_src_size_reg <= btb_set_src_size;
                        btb_target_addr_reg <= btb_set_target_addr;
                        btb_valid_reg <= '1';
                    end if;
                end if;
            end if;
        end process;
    else generate
        -- No branch prediction going on here!
        btb_src_addr <= (others => '0');
        btb_src_size <= '0';
        btb_target_addr <= (others => '0');
        btb_valid <= '0';
    end generate HAVE_BRANCH_PREDICTOR;

    -- Decode uses the target address to set the PC to the correct branch target
    -- value following a predicted-taken branch (as normally it would update PC
    -- by following an X jump request, and in this case there is none).
    --
    -- Note this assumes the BTB target has not changed by the time the predicted
    -- branch arrives at decode! This is always true because the only way for the
    -- target address to change is when an older branch is taken, which would
    -- flush the younger predicted-taken branch before it reaches decode.
    btb_target_addr_out <= btb_target_addr;

    ---------------------------------------------------------------------------
    -- Fetch request generation

    -- Fetch address runs ahead of the PC, in word increments.
    btb_match_word <= '1' when BRANCH_PREDICTOR and btb_valid = '1' and fetch_addr_reg(fetch_addr_reg'length - 1 downto 2) = btb_src_addr(btb_src_addr'length - 1 downto 2) else '0';
    
    -- Catch case where predicted-taken branch instruction extends into next word:
    btb_src_overhanging <= btb_src_size and btb_src_addr(1);

    -- Suppress case where we have jumped immediately after a word-aligned halfword-sized branch,
    -- and the jump target went into fetch_addr due to an address-phase hold:
    btb_jumped_beyond <= not btb_src_size and not btb_src_addr(1) and not mem_aph_hwvld_reg(0);

    btb_match_current_addr <= btb_match_word and not btb_src_overhanging and not btb_jumped_beyond;
    btb_match_next_addr <= btb_match_word and btb_src_overhanging;

    btb_match_now <= btb_match_current_addr or btb_prev_start_of_overhanging_reg;

    -- Post-increment if jump request is going straight through
    jump_target_post_increment <= (jump_target(jump_target'length - 1 downto 2) & "00") + 32d"4" when ?? (mem_addr_rdy and not mem_addr_hold_reg) else (jump_target(jump_target'length - 1 downto 2) & "00");
    
    process(clk) begin
        if rising_edge(clk) then
            if ?? rst then
                fetch_addr_reg <= unsigned(reset_vector);
                -- M-Mode at reset:
                fetch_priv_reg <= '1';
                btb_prev_start_of_overhanging_reg <= '0';
            else
                if ?? jump_now then
                    fetch_addr_reg <= jump_target_post_increment;
                    fetch_priv_reg <= jump_priv when U_MODE else '1';
                    btb_prev_start_of_overhanging_reg <= '0';
                elsif ?? (mem_addr_vld and mem_addr_rdy) then
                    if btb_match_now = '1' and BRANCH_PREDICTOR then
                        fetch_addr_reg <= btb_target_addr(btb_target_addr'length - 1 downto 2) & "00";
                    else
                        fetch_addr_reg <= fetch_addr_reg + 32d"4";
                    end if;
                    btb_prev_start_of_overhanging_reg <= btb_match_next_addr;
                end if;
            end if;
        end if;
    end process;

    -- Combinatorially generate the address-phase request
    process(clk) begin
        if rising_edge(clk) then
            if ?? rst then
                reset_holdoff_reg <= '1';
            else
                reset_holdoff_reg <= '0';
            end if;
        end if;
    end process;

    -- Downstream accesses are always word-sized word-aligned.
    mem_addr <= mem_addr_reg;
    mem_priv <= mem_priv_reg;
    mem_addr_vld <= mem_addr_vld_reg and not reset_holdoff_reg;
    mem_size <= '1';

    process(all) begin
        mem_addr_reg <= fetch_addr_reg;
        mem_priv_reg <= fetch_priv_reg;
        mem_addr_vld_reg <= '1';
        
        if ?? mem_addr_hold_reg then
            mem_addr_reg <= fetch_addr_reg;
        elsif ?? (jump_target_vld or reset_holdoff_reg) then
            mem_addr_reg <= jump_target(jump_target'length - 1 downto 2) & "00";
            mem_priv_reg <= jump_priv when U_MODE else '1';
        elsif DEBUG_SUPPORT and debug_mode = '1' then
            mem_addr_vld_reg <= '0';
        elsif ?? (not fetch_stall) then
            mem_addr_reg <= fetch_addr_reg;
        else
            mem_addr_vld_reg <= '0';
        end if;
    end process;

    jump_target_rdy <= not mem_addr_hold_reg;

    ---------------------------------------------------------------------------
    -- Bus Pipeline Tracking

    -- Keep track of some useful state of memory interface
    pending_fetches_next <= pending_fetches_reg + 1 when  mem_addr_vld = '1' and mem_addr_hold_reg = '0' and mem_data_vld = '0' else
                            pending_fetches_reg - 1 when (mem_addr_vld = '0' or mem_addr_hold_reg = '1') and mem_data_vld = '1' else
                            pending_fetches_reg;

    -- Using the non-registered version of pending_fetches would improve FIFO utilisation, but would
    -- create a combinatorial path from hready to address phase! This means
    -- at least a 2-word FIFP is required for full fetch throughput.
    fetch_stall <= '1' when (fifo_full = '1') or 
                            (fifo_almost_full = '1' and pending_fetches_reg /= "00") or 
                            (pending_fetches_reg > 1) 
                       else '0';
    
    -- Debugger only injects instructions when the frontend is at rest and empty.
    dbg_instr_data_rdy <= '1' when DEBUG_SUPPORT and fifo_valid_reg(0) = '0' and ctr_flush_pending_reg = "00" else '0';

    -- If fetch data is forwarded past the FIFO, ensure it is not also written to it.
    fifo_push <= '1' when    (mem_data_vld = '1') and 
                             (unsigned(ctr_flush_pending_reg) = 0) and 
                         not (cir_room_for_fetch = '1' and fifo_empty = '1') and 
                         not (DEBUG_SUPPORT and debug_mode = '1') 
                     else '0';
        
    process(clk) begin
        if rising_edge(clk) then
            if ?? rst then
                mem_addr_hold_reg <= '0';
                pending_fetches_reg <= (others => '0');
                ctr_flush_pending_reg <= (others => '0');
            else
                mem_addr_hold_reg <= mem_addr_vld and not mem_addr_rdy;
                pending_fetches_reg <= pending_fetches_next;
                if ?? jump_now then
                    ctr_flush_pending_reg <= pending_fetches_reg - 1 when ?? mem_data_vld else pending_fetches_reg;
                elsif ?? ((or ctr_flush_pending_reg) and mem_data_vld) then
                    ctr_flush_pending_reg <= ctr_flush_pending_reg - 1;
                end if;
            end if;
        end if;
    end process;

    process(clk) begin
        if rising_edge(clk) then
            if ?? rst then
                mem_data_hwvld_reg <= (others => '1');
                mem_aph_hwvld_reg <= (others => '1');
                mem_data_predbranch_reg <= (others => '0');
            else
                if not EXTENSION_C then
                    -- Without C these never leave their reset value. Assign it explicitly,
                    -- otherwise GHDL infers a latch from the reset-only assignment.
                    mem_data_hwvld_reg <= (others => '1');
                    mem_aph_hwvld_reg <= (others => '1');
                end if;
                if ?? jump_now then
                    if EXTENSION_C then
                        if ?? mem_addr_rdy then
                            mem_aph_hwvld_reg <= (others => '1');
                            mem_data_hwvld_reg <= '1' & not jump_target(1);
                        else
                            mem_aph_hwvld_reg <= '1' & not jump_target(1);
                        end if;
                    end if;
                    mem_data_predbranch_reg <= (others => '0');
                elsif ?? (mem_addr_vld and mem_addr_rdy) then
                    if EXTENSION_C then
                        -- If a predicted-taken branch instruction only spans the first
                        -- half of a word, need to flag the second half as invalid.
                        mem_data_hwvld_reg <= (mem_aph_hwvld_reg and "01") when BRANCH_PREDICTOR and btb_match_now = '1' and btb_src_addr(1) = btb_src_size else mem_aph_hwvld_reg;
                        -- Also need to take the alignment of the destination into account.
                        mem_aph_hwvld_reg <= "10" when BRANCH_PREDICTOR and btb_match_now = '1' and btb_target_addr(1) = '1' else "11";
                    end if;
                    mem_data_predbranch_reg <= "10" when BRANCH_PREDICTOR and btb_match_word = '1' and btb_src_addr(1) = '1' else
                                               "11" when BRANCH_PREDICTOR and btb_match_word = '1' and btb_src_size = '1'    else
                                               "01" when BRANCH_PREDICTOR and btb_match_word = '1'                           else
                                               "01" when BRANCH_PREDICTOR and btb_prev_start_of_overhanging_reg = '1'        else
                                               "00";
                end if;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- PMP and trigger unit interfacing: query -> kill/break

    -- Register the fetch address into stage F so that the PMP can check if in parallel
    -- with the bus data phase. Feels wasteful to have a separate register, but using
    -- the fetch_addr counter is fraught due to the way new addresses go into it or
    -- past it (depends on aphase hold)
    pmp_trigger_check_dph_addr <= check_addr_dph_reg;
    pmp_trigger_check_dph_m_mode <= check_m_mode_dph_reg;

    CHECK_REGISTER_SUPPORT : if PMP_REGIONS > 0 or DEBUG_SUPPORT generate
        -- Have check registers
        process(clk) begin
            if rising_edge(clk) then
                if ?? rst then
                    check_addr_dph_reg <= (others => '0');
                    check_m_mode_dph_reg <= '0';
                else
                    if ?? (mem_addr_vld and mem_addr_rdy) then
                        check_addr_dph_reg <= mem_addr;
                        check_m_mode_dph_reg <= mem_priv_reg;
                    end if;
                end if;
            end if;
        end process;
    else generate 
        -- No check registers
        check_addr_dph_reg <= (others => '0');
        check_m_mode_dph_reg <= '0';
    end generate CHECK_REGISTER_SUPPORT;
    
    PMP_SUPPORT : if PMP_REGIONS = 0 generate
        -- No PMP
        pmp_i_addr <= (others => '0');
        pmp_i_m_mode <= '0';
        pmp_kill_fetch_dph <= '0';
    else generate
        -- Have PMP
        pmp_i_addr <= pmp_trigger_check_dph_addr;
        pmp_i_m_mode <= pmp_trigger_check_dph_m_mode;
        pmp_kill_fetch_dph <= pmp_i_kill and not debug_mode;
    end generate PMP_SUPPORT;

    TRIGGER_SUPPORT : if not DEBUG_SUPPORT generate
        -- No Triggers
        trigger_addr <= (others => '0');
        trigger_m_mode <= '0';
        mem_break_any <= (others => '0');
        mem_break_d_mode <= (others => '0');
    else generate
        -- Have Triggers
        trigger_addr <= pmp_trigger_check_dph_addr;
        trigger_m_mode <= pmp_trigger_check_dph_m_mode;
        mem_break_any <= trigger_break_any when EXTENSION_C else '0' & trigger_break_any(0);
        mem_break_d_mode <= trigger_break_d_mode when EXTENSION_C else '0' & trigger_break_d_mode(0);
    end generate TRIGGER_SUPPORT;

    ---------------------------------------------------------------------------
    -- Instruction buffer

    -- The instruction buffer is a 3 x ~16-bit shift register:
    --
    -- * 2 x 16-bit entries form the 32-bit current instruction register (CIR)
    --   which is the processor's decode window
    --
    -- * 1 x 16-bit entry allows the decode window to be non-32-bit-aligned with
    --   respect to the 2 x 32-bit prefetch queue entries, which are always
    --   naturally aligned in memory (if fully populated).
    --
    -- The third entry should be trimmed for non-RVC configurations due to
    -- constant-folding on EXTENSION_C; it is unnecessary here because the
    -- instructions are always 32-bit-aligned.
    -- The entries ("slots") are slightly larger than 16 bits because they also contain metadata like bus errors:
    fetch_data_vld <= not fifo_empty or (mem_data_vld and not debug_mode and not (or ctr_flush_pending_reg));

    fetch_data          <= mem_data                when ?? fifo_empty else fifo_rdata;
    fetch_data_hwvld    <= mem_data_hwvld_reg      when ?? fifo_empty else fifo_valid_hw_reg(0);
    fetch_bus_err       <= mem_or_pmp_err          when ?? fifo_empty else fifo_err_reg(0);
    fetch_break_any     <= mem_break_any           when ?? fifo_empty else fifo_break_any_reg(0);
    fetch_break_d_mode  <= mem_break_d_mode        when ?? fifo_empty else fifo_break_d_mode_reg(0);
    fetch_predbranch    <= mem_data_predbranch_reg when ?? fifo_empty else fifo_predbranch_reg(0);
    
    fetch_contents_hw1 <= (
        fetch_break_any(1) &
        fetch_break_d_mode(1) &
        fetch_bus_err &
        fetch_predbranch(1) &
        fetch_data(W_BUNDLE * 2 - 1 downto W_BUNDLE)
    );
    fetch_contents_hw0 <= (
        fetch_break_any(0) &
        fetch_break_d_mode(0) &
        fetch_bus_err &
        fetch_predbranch(0) &
        fetch_data(W_BUNDLE - 1 downto 0)
    );

    fetch_contents_aligned <= fetch_contents_hw1 & fetch_contents_hw0 when fetch_data_hwvld(0) = '1' or not EXTENSION_C else
                              fetch_contents_hw1 & fetch_contents_hw1;

    -- Shift not-yet-used contents down to backfill D's consumption. We don't care
    -- about anything which is invalid or will be overlaid with fresh data, so
    -- choose these values in a way that minimises muxes.
    buf_shifted <= buf_contents_reg(3 * W_SLOT - 1 downto W_SLOT) & buf_contents_reg(3 * W_SLOT - 1 downto 2 * W_SLOT) when cir_use(1) = '1' else
                   buf_contents_reg(3 * W_SLOT - 1 downto 2 * W_SLOT) & buf_contents_reg(3 * W_SLOT - 1 downto W_SLOT) when cir_use(0) = '1' and EXTENSION_C else
                   buf_contents_reg;

    level_next_no_fetch <= buf_level_reg - unsigned(cir_use);

    -- Overlay fresh fetch data onto the shifted/recycled buffer contents. Again,
    -- if something won't be looked at, generate the cheapest possible garbage.
    cir_room_for_fetch <= '1' when (level_next_no_fetch <= 2) and (EXTENSION_C and (and fetch_data_hwvld) = '0') else
                          '1' when (level_next_no_fetch <= 1) else
                          '0';

    fifo_pop <= cir_room_for_fetch and not fifo_empty;

    buf_shifted_plus_fetch <= buf_shifted when cir_room_for_fetch = '0' else
                              fetch_contents_aligned(W_SLOT - 1 downto 0) & buf_shifted(2 * W_SLOT - 1 downto 0) when level_next_no_fetch(1) = '1' and EXTENSION_C else
                              fetch_contents_aligned & buf_shifted(W_SLOT - 1 downto 0)                          when level_next_no_fetch(0) = '1' and EXTENSION_C else
                              buf_shifted(3 * W_SLOT - 1 downto 2 * W_SLOT) & fetch_contents_aligned;

    fetch_fill_amount <= "10" when cir_room_for_fetch = '1' and fetch_data_vld = '1' and ((and fetch_data_hwvld) = '1' or not EXTENSION_C) else
                         "01" when cir_room_for_fetch = '1' and fetch_data_vld = '1' else
                         "00";

    -- 1. Evaluate the unmasked next level
    buf_level_next_raw <= "10" when jump_now = '1' and cir_flush_behind = '1' and cir_is_32bit_reg = '1' else
                          "01" when jump_now = '1' and cir_flush_behind = '1'                            else
                          "00" when jump_now = '1'                                                       else
                          level_next_no_fetch + fetch_fill_amount;

    -- 2. Apply the EXTENSION_C mask ({1'b1, |EXTENSION_C})
    buf_level_next <= buf_level_next_raw when EXTENSION_C else 
                      buf_level_next_raw and "10";

    process(clk)
    begin
        if rising_edge(clk) then
            if ?? rst then
                buf_level_reg  <= "00";
                cir_vld_reg        <= "00";
                -- Mysterious reset value ensures address buses are zero in reset
                -- (see definition of d_addr_offs in hazard3_decode)
                buf_contents_reg <= std_logic_vector(to_unsigned(3, 3 * W_SLOT));
            else
                buf_level_reg    <= buf_level_next;
                cir_vld_reg      <= buf_level_next and not ("0" & buf_level_next(1));
                buf_contents_reg <= buf_shifted_plus_fetch;
            end if;
        end if;
    end process;

    cir_vld <= std_logic_vector(cir_vld_reg);

    cir_err          <= buf_contents_reg(1 * W_SLOT + SLOT_ERR_BIT) & buf_contents_reg(0 * W_SLOT + SLOT_ERR_BIT);
    cir_predbranch   <= buf_contents_reg(1 * W_SLOT + SLOT_PREDBRANCH_BIT) & buf_contents_reg(0 * W_SLOT + SLOT_PREDBRANCH_BIT);
    cir_break_any    <= buf_contents_reg(0 * W_SLOT + SLOT_BREAK_ANY_BIT) and (or cir_vld);
    cir_break_d_mode <= buf_contents_reg(0 * W_SLOT + SLOT_BREAK_D_MODE_BIT) and (or cir_vld);

    -- ------------------------------------------------------------------------
    -- Register number predecode

    next_instr <= buf_shifted_plus_fetch(W_SLOT + W_BUNDLE - 1 downto W_SLOT) &
                  buf_shifted_plus_fetch(W_BUNDLE - 1 downto 0);

    next_instr_is_32bit <= '1' when next_instr(1 downto 0) = "11" or not EXTENSION_C else '0';

    -- Note: {4{|1'b0}} evaluates to 4'b0000
    uop_ctr <= decomp_uop_step and "0000";

    zcmp_pushpop_rs2 <= "00001" when uop_ctr = x"0" else    -- ra
                        "01000" when uop_ctr = x"1" else    -- s0
                        "01001" when uop_ctr = x"2" else    -- s1
                        std_logic_vector(to_unsigned(15, 5) + resize(unsigned(uop_ctr), 5));    -- s2-s11

    zcmp_pushpop_rs1 <= "00010" when unsigned(uop_ctr) < 13 else    -- sp
                        "00000" when unsigned(uop_ctr) = 13 else    -- zero
                        "00001" when unsigned(uop_ctr) = 14 else    -- ret
                        "00010";                                    -- sp

    zcmp_sa01_r1s <= (or next_instr(9 downto 8)) & (nor next_instr(9 downto 8)) & next_instr(9 downto 7);
    zcmp_sa01_r2s <= (or next_instr(4 downto 3)) & (nor next_instr(4 downto 3)) & next_instr(4 downto 2);

    zcmp_mvsa01_rs1 <= x"5" & uop_ctr(0);
    zcmp_mva01s_rs1 <= zcmp_sa01_r2s when uop_ctr(0) = '1' else zcmp_sa01_r1s;

    -- "coarse" because the mapping of pair (x0, x1) -> (x0, x0) is not yet applied
    zilsd_rs2_coarse      <= next_instr(24 downto 21) & (df_lspair_phase_next xor not next_instr(15));
    zclsd_sd_rs2_coarse   <= "01" & next_instr(4 downto 3) & (df_lspair_phase_next xor not next_instr(7));
    zclsd_sdsp_rs2_coarse <= next_instr(6 downto 3) & (df_lspair_phase_next xor '1');

    process(all)
        variable v_rs1_coarse : std_logic_vector(4 downto 0);
        variable v_rs2_coarse : std_logic_vector(4 downto 0);
        variable v_rs1_fine   : std_logic_vector(4 downto 0);
        variable v_rs2_fine   : std_logic_vector(4 downto 0);
    begin
        case? next_instr_is_32bit & next_instr(15 downto 0) is
            when "1----------------" => v_rs1_coarse := next_instr(19 downto 15);
            when "000------------00" => v_rs1_coarse := "00010";              -- 5'd2
            when "00-------------01" => v_rs1_coarse := next_instr(11 downto 7);
            when "0-1------------10" => v_rs1_coarse := "00010";              -- 5'd2
            when "0-00-----------10" => v_rs1_coarse := next_instr(11 downto 7);
            when others              => v_rs1_coarse := "01" & next_instr(9 downto 7);
        end case?;

        case? next_instr_is_32bit & next_instr(15 downto 0) is
            when "1--11-----0-0----" => v_rs2_coarse := next_instr(24 downto 20);
            when "1--0-------------" => v_rs2_coarse := next_instr(24 downto 20);
            when "1--10------------" => v_rs2_coarse := next_instr(24 downto 20);
            when "1--11-----1------" => v_rs2_coarse := next_instr(24 downto 20);
            when "1--11-----0-1----" => v_rs2_coarse := next_instr(24 downto 20);
            when "0--0-----------10" => v_rs2_coarse := next_instr(6 downto 2);
            when others              => v_rs2_coarse := "01" & next_instr(4 downto 2);
        end case?;

        -- The "fine" predecode targets those instructions which either:
        -- - Have an implicit zero-register operand in their expanded form (e.g. c.beqz)
        -- - Do not have a register operand on that port, but rely on the port being 0
        -- We don't care about instructions which ignore the reg ports, e.g. ebreak

        case? to_std_logic(EXTENSION_C) & next_instr is
            when '1' & "----------------" & OPCODE_C.C_LI => 
                v_rs1_fine := "00000";
            when '1' & "----------------" & OPCODE_C.C_MV =>
                if next_instr(6 downto 2) = "00000" then
                    -- c.jr has rs1 as normal
                    v_rs1_fine := v_rs1_coarse;
                else
                    -- -> add rd, x0, rs2:
                    v_rs1_fine := "00000";
                end if;
            when others => 
                v_rs1_fine := v_rs1_coarse;
        end case?;

        -- Note: the reference Verilog's c.beqz/c.bnez case items are 35 bits wide
        -- ({1'b1, 1'bz, 1'bz, 16'hzzzz, RVOPC_C_BEQZ}) while the selector is only
        -- 33 bits. The selector is zero-extended, so the leading 1'b1 never matches
        -- and rs2_fine is always rs2_coarse. Mirrored here for equivalence.
        v_rs2_fine := v_rs2_coarse;
        
        -- Drive final signals
        predecode_rs1_coarse <= v_rs1_coarse;
        predecode_rs2_coarse <= v_rs2_coarse;
        predecode_rs1_fine   <= v_rs1_fine;
        predecode_rs2_fine   <= v_rs2_fine;
    end process;

    -- ----------------------------------------------------------------------------
    -- Instruction decompression

    -- Instructions are decompressed at the end of stage 1 (fetch data phase). On
    -- ASIC, where the register file is synthesised with muxes, this puts
    -- decompression somewhat in parallel with register file read, which uses
    -- approximately decoded regnums.

    INSTRUCTION_DECOMPRESSION: if not EXTENSION_C generate
        -- No decompression; instructions decoded directly from prefetch buffer
        process(all) begin
            cir_reg <= (buf_contents_reg(W_SLOT + W_BUNDLE - 1 downto W_SLOT) &
                    buf_contents_reg(W_BUNDLE - 1 downto 0)) or x"00000003";
            cir_is_32bit_reg         <= '1';
            cir_invalid_16bit_reg    <= nand buf_contents_reg(1 downto 0);
            cir_is_uop_reg           <= '0';
            cir_uop_nonfinal_reg     <= '0';
            cir_uop_no_pc_update_reg <= '0';
            cir_uop_atomic_reg       <= '0';
        end process;

        decomp_uop_step <= x"0";

        -- Tie unused signals to zero
        decomp_instr_is_32bit <= '0';  
        decomp_instr_out <= (others => '0'); 
        decomp_is_uop <= '0';          
        decomp_is_final_uop <= '0';    
        decomp_uop_no_pc_update <= '0';
        decomp_uop_atomic <= '0';      
        decomp_invalid <= '0';
        first_uop <= '0';            
        uop_stall_non_first <= '0';  
        uop_stall_on_repeat <= '0';  
        cir_clken <= '0';            
        cir_is_uop_next <= '0';      
        cir_uop_nonfinal_next <= '0';

    else generate
        -- Perform actual instruction decompression
        
        first_uop <= '1' when decomp_uop_step = x"0" else '0';
        
        -- Ensure the first uop goes straight through, as it is registered into CIR:
        uop_stall_non_first <= '1' when buf_level_next = "00" and first_uop = '1' else
                               '0' when first_uop = '1' else
                               uop_stall;

        -- Ensure the uop counter stops at 0 after rolling over once:
        uop_stall_on_repeat <= '1' when cir_is_uop = '1' and cir_uop_nonfinal = '0' and cir_use = "00" else '0';
        uop_stall_inter <= uop_stall_non_first or uop_stall_on_repeat;

        decomp : entity work.hazard3_instr_decompress
            generic map (
                EXTENSION_C      => EXTENSION_C,
                EXTENSION_M      => EXTENSION_M
            )
            port map (
                instr_in                  => next_instr,

                instr_is_32bit             => decomp_instr_is_32bit,
                instr_out                  => decomp_instr_out,

                instr_out_is_uop           => decomp_is_uop,
                instr_out_is_final_uop     => decomp_is_final_uop,
                instr_out_uop_no_pc_update => decomp_uop_no_pc_update,
                instr_out_uop_atomic       => decomp_uop_atomic,
                instr_out_uop_stall        => uop_stall_inter,
                instr_out_uop_clear        => uop_clear,
                df_uop_step                => decomp_uop_step,

                invalid                    => decomp_invalid
            );

        cir_clken <= '1' when cir_vld = "00" or (cir_vld(1) = '0' and (and buf_contents_reg(1 downto 0)) = '1') or cir_use /= "00" else '0';

        cir_is_uop_next <= '1' when decomp_is_uop = '1' and buf_level_next /= "00" else '0';
        cir_uop_nonfinal_next <= '1' when cir_is_uop_next = '1' and decomp_is_final_uop = '0' else '0';

        process(clk) begin
            if rising_edge(clk) then
                if ?? rst then
                    cir_reg                  <= x"00000003";
                    cir_is_32bit_reg         <= '0';
                    cir_invalid_16bit_reg    <= '0';
                    cir_is_uop_reg           <= '0';
                    cir_uop_nonfinal_reg     <= '0';
                    cir_uop_no_pc_update_reg <= '0';
                    cir_uop_atomic_reg       <= '0';
                else
                    if cir_clken = '1' then
                        cir_reg                  <= decomp_instr_out or x"00000003";
                        cir_is_32bit_reg         <= decomp_instr_is_32bit;
                        cir_invalid_16bit_reg    <= decomp_invalid;
                        -- |1'b0 equivalent boolean expressions
                        cir_is_uop_reg           <= '0' and not uop_clear and cir_is_uop_next;
                        cir_uop_nonfinal_reg     <= '0' and not uop_clear and cir_uop_nonfinal_next;
                        cir_uop_no_pc_update_reg <= '0' and not uop_clear and decomp_uop_no_pc_update;
                        cir_uop_atomic_reg       <= '0' and not uop_clear and decomp_uop_atomic;
                    end if;
                end if;
            end if;
        end process;

    end generate;

    cir_raw <= buf_contents_reg(W_SLOT + W_BUNDLE - 1 downto W_SLOT) &
               buf_contents_reg(W_BUNDLE - 1 downto 0);
    cir <= cir_reg;
    cir_is_32bit <= cir_is_32bit_reg;
    cir_invalid_16bit <= cir_invalid_16bit_reg;
    cir_is_uop <= cir_is_uop_reg;
    cir_uop_nonfinal <= cir_uop_nonfinal_reg;
    cir_uop_no_pc_update <= cir_uop_no_pc_update_reg;
    cir_uop_atomic <= cir_uop_atomic_reg;

end architecture rtl;
