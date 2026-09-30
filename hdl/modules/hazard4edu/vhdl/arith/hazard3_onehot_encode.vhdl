library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.ceil;
use ieee.math_real.log2;

entity hazard3_onehot_encode is
    generic(
        -- Width of the Request - Total number of input lines to monitor
        REQUEST_WIDTH_C : positive := 16;
        -- Width of Grant
        GRANT_WIDTH_C   : positive := integer(ceil(log2(real(REQUEST_WIDTH_C)))) -- do not modify
    );
    port(
        -- Request (MUST BE a one-hot encoded input vector)
        req : in  std_logic_vector(REQUEST_WIDTH_C - 1 downto 0);
        -- Grant (encoded binary output)
        gnt : out std_logic_vector(GRANT_WIDTH_C - 1 downto 0)
    );
end entity hazard3_onehot_encode;

architecture rtl of hazard3_onehot_encode is

begin

    process(all) is
        variable grant : std_logic_vector(GRANT_WIDTH_C - 1 downto 0);
    begin
        grant := (others => '0');
        for i in 0 to REQUEST_WIDTH_C - 1 loop
            if req(i) = '1' then
                grant := grant or std_logic_vector(to_unsigned(i, GRANT_WIDTH_C));
            end if;
        end loop;

        gnt <= grant;
    end process;

end architecture rtl;
