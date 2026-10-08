library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.hazard3_constants.all;

entity hazard3_shift_barrel is
    port(
        din         : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        shamt       : in  std_logic_vector(SHIFT_AMOUNT_WIDTH_C - 1 downto 0);
        right_nleft : in  std_logic;
        arith       : in  std_logic;
        dout        : out std_logic_vector(DATA_WIDTH_C - 1 downto 0)
    );
end entity hazard3_shift_barrel;

architecture rtl of hazard3_shift_barrel is
begin

    process(all) is
        variable data_in_reversed  : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        variable shift_accumulator : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        variable sign_extension    : std_logic;
    begin
        -- Input reversal for right shift
        input_reversal : for i in 0 to DATA_WIDTH_C - 1 loop
            if ?? right_nleft then
                data_in_reversed(i) := din(DATA_WIDTH_C - 1 - i);
            else
                data_in_reversed(i) := din(i);
            end if;
        end loop input_reversal;

        -- Compute sign extension bit
        sign_extension := arith and data_in_reversed(0);

        -- Actual shifting is done here using a barrel shifter
        shift_accumulator := data_in_reversed;
        barrel_shifter : for i in 0 to SHIFT_AMOUNT_WIDTH_C - 1 loop
            if ?? shamt(i) then
                shift_accumulator := shift_accumulator(DATA_WIDTH_C - 1 - 2 ** i downto 0) & (2 ** i - 1 downto 0 => sign_extension);
            end if;
        end loop barrel_shifter;

        -- Output reversal to the output port
        output_reversal : for i in 0 to DATA_WIDTH_C - 1 loop
            if ?? right_nleft then
                dout(i) <= shift_accumulator(DATA_WIDTH_C - 1 - i);
            else
                dout(i) <= shift_accumulator(i);
            end if;
        end loop output_reversal;
    end process;

end architecture rtl;
