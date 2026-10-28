library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.hazard3_constants.all;

entity hazard3_power_ctrl is
    port(
        clk_always_on   : in std_logic;
        rst             : in std_logic;

	    -- 4-phase (Gray code) req/ack handshake for requesting and releasing
	    -- power+clock enable on non-processor hardware, e.g. the bus fabric. This
	    -- can also be used for an external controller to gate the processor's clk
	    -- input, rather than the clk_en signal below.
        pwrup_req : out std_logic;
        pwrup_ack : in  std_logic;

	    -- Top-level clock enable for an optional clock gate on the processor's clk
	    -- input (but not clk_always_on, which clocks this module and the IRQ input
	    -- flops). This allows the processor to clock-gate when sleeping. It's
	    -- acceptable for the clock gate cell to have one cycle of delay when
	    -- clk_en changes.
        clk_en : out std_logic;

        -- Power state controls form CSRs
        allow_clkgate        : in std_logic;
        allow_power_down     : in std_logic;
        allow_sleep_on_block : in std_logic;

        -- Signal from frontend that it has stalled against the WFI pipeline
        -- stall, and we are now clear to enter a deep sleep state
        frontend_pwrdown_ok : in std_logic;

        sleeping_on_wfi        : in  std_logic;
        wfi_wakeup_req         : in  std_logic;
        sleeping_on_block      : in  std_logic;
        block_wakeup_req_pulse : in  std_logic;
        stall_release          : out std_logic
    );
end entity hazard3_power_ctrl;

architecture rtl of hazard3_power_ctrl is

    subtype W_STATE is natural range 1 downto 0;
    constant S_AWAKE        : std_logic_vector(W_STATE) := 2x"0";
    constant S_ENTER_ASLEEP : std_logic_vector(W_STATE) := 2x"1";
    constant S_ASLEEP       : std_logic_vector(W_STATE) := 2x"2";
    constant S_ENTER_AWAKE  : std_logic_vector(W_STATE) := 2x"3";

    signal state_reg            : std_logic_vector(W_STATE);
    signal block_wakeup_req_reg : std_logic;
    signal pwrup_req_reg        : std_logic;
    signal clk_en_reg           : std_logic;
    signal stall_release_reg    : std_logic;
    signal active_wake_req      : std_logic;

begin

    active_wake_req <= (sleeping_on_block and (block_wakeup_req_reg or wfi_wakeup_req)) or
                       (sleeping_on_wfi and wfi_wakeup_req);
    pwrup_req <= pwrup_req_reg;
    clk_en <= clk_en_reg;
    stall_release <= stall_release_reg;
        
    -- Note: We assert our power up request during reset, and *assume* that the power
    -- up ackowledge is also high at reset. If this is a problem, extend the core reset.
    process(clk_always_on) begin
        if rising_edge(clk_always_on) then
            if ?? rst then
                state_reg <= S_AWAKE;
                pwrup_req_reg <= '1';
                clk_en_reg <= '1';
                stall_release_reg <= '0';
            else
                stall_release_reg <= '0';

                case state_reg is
                    when S_AWAKE => 
                        if ?? (sleeping_on_wfi or sleeping_on_block) then
                            if ?? stall_release_reg then
                                -- The last cycle of an ongoing which we have just released.
                                -- Sit tight, this instruction will move down the pipeline at
                                -- the end of this cycle. (There is an assertion that this
                                -- doesn't happen twice.)
                                state_reg <= S_AWAKE;
                            elsif ?? active_wake_req then
                                -- Skip deep sleep if it would immediately fall through.
                                stall_release_reg <= '1';
                            elsif ?? ((allow_power_down or allow_clkgate) and (sleeping_on_wfi or allow_sleep_on_block)) then
                                if ?? frontend_pwrdown_ok then
                                    pwrup_req_reg <= not allow_power_down;
                                    clk_en_reg <= not allow_clkgate;
                                    state_reg <= S_ENTER_ASLEEP when ?? allow_power_down else S_ASLEEP;
                                else
                                    -- Stay awake until it is safe to power down (i.e. until
                                    -- our instruction fetch goes quiet).
                                    state_reg <= S_AWAKE;
                                end if;
                            else
                                -- No power state change. Just sit with the pipeline stalled.
                                state_reg <= S_AWAKE;
                            end if;
                        end if;
                    when S_ENTER_ASLEEP => 
                        if ?? (not pwrup_ack) then
                            state_reg <= S_ASLEEP;
                        end if;
                    when S_ASLEEP => 
                        if ?? active_wake_req then
                            pwrup_req_reg <= '1';
                            clk_en_reg <= '1';
                            -- Still go through the enter state for non-power-down wakeup,
                            -- in case the clock gate cell has a 1 cycle delay.
                            state_reg <= S_ENTER_AWAKE;
                        end if;
                    when S_ENTER_AWAKE => 
                        if ?? (pwrup_ack or not allow_power_down) then
                            state_reg <= S_AWAKE;
                            stall_release_reg <= '1';
                        end if;
                    when others => state_reg <= S_AWAKE;
                end case;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Pulse => level for block wakeup
    -- Unblock signal is sticky: a prior unblock with no block since will cause
    -- the next block to immediately fall through.

    process(clk_always_on) begin
        if rising_edge(clk_always_on) then
            if ?? rst then
                block_wakeup_req_reg <= '0';
            else
                block_wakeup_req_reg <= (block_wakeup_req_reg and not (sleeping_on_block and stall_release_reg)) or block_wakeup_req_pulse;
            end if;
        end if;
    end process;

end architecture rtl;
