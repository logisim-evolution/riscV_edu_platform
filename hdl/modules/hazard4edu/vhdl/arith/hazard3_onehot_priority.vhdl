library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hazard3_onehot_priority is
    generic(
        -- Width of the Request - Total number of input lines to monitor
        REQUEST_WIDTH_C : positive := 16;
        HIGHEST_WINS    : boolean  := FALSE
    );
    port(
        req : in  std_logic_vector(REQUEST_WIDTH_C - 1 downto 0);
        gnt : out std_logic_vector(REQUEST_WIDTH_C - 1 downto 0)
    );
end entity hazard3_onehot_priority;

architecture rtl of hazard3_onehot_priority is
begin

    process(all) is
        variable bit_already_found : boolean;
    begin
        gnt               <= (others => '0');
        bit_already_found := FALSE;

        for i in 0 to REQUEST_WIDTH_C - 1 loop
            if HIGHEST_WINS then
                -- OneHot priority search from top to bottom
                if req(REQUEST_WIDTH_C - 1 - i) = '1' and not bit_already_found then
                    gnt(REQUEST_WIDTH_C - 1 - i) <= '1';
                    bit_already_found            := TRUE;
                end if;
            else
                -- OneHot priority search from bottom to top
                if req(i) = '1' and not bit_already_found then
                    gnt(i)            <= '1';
                    bit_already_found := TRUE;
                end if;
            end if;
        end loop;

    end process;

end architecture rtl;
