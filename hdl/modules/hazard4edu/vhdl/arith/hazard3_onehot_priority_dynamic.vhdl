library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.ceil;
use ieee.math_real.log2;

entity hazard3_onehot_priority_dynamic is
    generic(
        REQUEST_WIDTH_C         : positive := 8;
        N_PRIORITIES_C          : positive := 2;
        -- If 1, numerically highest level has greatest priority. Otherwise, numerically lowest wins.
        PRIORITY_HIGHEST_WINS_C : boolean  := TRUE;
        -- If 1, highest-numbered request at the highest priority level wins the tiebreak. Otherwise, lowest-numbered.
        TIEBREAK_HIGHEST_WINS_C : boolean  := FALSE;
        -- Do not modify
        PRIORITY_WIDTH_C        : positive := integer(ceil(log2(real(N_PRIORITIES_C)))) -- do not modify
    );
    port(
        pri : in  std_logic_vector(REQUEST_WIDTH_C * PRIORITY_WIDTH_C - 1 downto 0);
        req : in  std_logic_vector(REQUEST_WIDTH_C - 1 downto 0);
        gnt : out std_logic_vector(REQUEST_WIDTH_C - 1 downto 0)
    );
end entity hazard3_onehot_priority_dynamic;

architecture rtl of hazard3_onehot_priority_dynamic is

    type strat_array_t is array (0 to N_PRIORITIES_C - 1) of std_logic_vector(REQUEST_WIDTH_C - 1 downto 0);

    signal stratified_requests         : strat_array_t;
    signal level_has_request           : std_logic_vector(N_PRIORITIES_C - 1 downto 0);
    signal active_layer_select         : std_logic_vector(N_PRIORITIES_C - 1 downto 0);
    signal requests_from_highest_layer : std_logic_vector(REQUEST_WIDTH_C - 1 downto 0);

begin

    -- 1. Stratify requests according to their level
    process(all) is
        variable v_level_has_reqquest : std_logic_vector(N_PRIORITIES_C - 1 downto 0);
        variable v_pri_slice          : integer range 0 to REQUEST_WIDTH_C * PRIORITY_WIDTH_C - 1;
    begin
        v_level_has_reqquest := (others => '0');

        for i in 0 to N_PRIORITIES_C - 1 loop
            for j in 0 to REQUEST_WIDTH_C - 1 loop
                v_pri_slice := to_integer(unsigned(pri(PRIORITY_WIDTH_C * (j + 1) - 1 downto PRIORITY_WIDTH_C * j)));

                if req(j) = '1' and v_pri_slice = i then
                    stratified_requests(i)(j) <= '1';
                    v_level_has_reqquest(i)   := '1';
                else
                    stratified_requests(i)(j) <= '0';
                end if;
            end loop;
        end loop;

        level_has_request <= v_level_has_reqquest;
    end process;

    -- 2. Select the highest level with active requests
    priority_select_layer : entity work.hazard3_onehot_priority
        generic map(
            REQUEST_WIDTH_C => N_PRIORITIES_C,
            HIGHEST_WINS    => PRIORITY_HIGHEST_WINS_C
        )
        port map(
            req => level_has_request,
            gnt => active_layer_select
        );

    -- 3. Mask only those requests at this level
    process(all)
        variable v_requests_from_highest_layer : std_logic_vector(REQUEST_WIDTH_C - 1 downto 0);
    begin
        v_requests_from_highest_layer := (others => '0');
        
        for i in 0 to N_PRIORITIES_C - 1 loop
            if ?? active_layer_select(i) then
                v_requests_from_highest_layer := v_requests_from_highest_layer or stratified_requests(i);
            end if;
        end loop;
        
        requests_from_highest_layer <= v_requests_from_highest_layer;
    end process;

    -- 4. Do a standard priority select on those requests as a tie break
    priority_select_tiebreak : entity work.hazard3_onehot_priority
        generic map(
            REQUEST_WIDTH_C => REQUEST_WIDTH_C,
            HIGHEST_WINS    => TIEBREAK_HIGHEST_WINS_C
        )
        port map(
            req => requests_from_highest_layer,
            gnt => gnt
        );
    

end architecture rtl;
