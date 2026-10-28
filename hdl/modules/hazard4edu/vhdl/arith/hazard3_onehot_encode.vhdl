library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.ceil;
use ieee.math_real.log2;

use work.hazard3_constants.all;

entity hazard3_onehot_encode is
    generic(
        -- Width of the Request - Total number of input lines to monitor
        REQUEST_WIDTH_C : positive := 16
    );
    port(
        -- Request (MUST BE a one-hot encoded input vector)
        req : in  std_logic_vector(REQUEST_WIDTH_C - 1 downto 0);
        -- Grant (encoded binary output)
        gnt : out std_logic_vector(clog2(REQUEST_WIDTH_C) - 1 downto 0)
    );
end entity hazard3_onehot_encode;

architecture rtl of hazard3_onehot_encode is

begin

    process(all) is
        variable grant : std_logic_vector(gnt'range);
    begin
        grant := (others => '0');
        for i in 0 to REQUEST_WIDTH_C - 1 loop
            if req(i) = '1' then
                grant := grant or std_logic_vector(to_unsigned(i, grant'length));
            end if;
        end loop;

        gnt <= grant;
    end process;

end architecture rtl;
