library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sevenSegmentUpdate is
  generic( segmentId : integer );
  port( currentValue   : in  std_logic_vector( 7 downto 0 );
        dataIn         : in  std_logic_vector(31 downto 0 );
        functionSelect : in  std_logic_vector( 2 downto 0 );
        newValue       : out std_logic_vector( 7 downto 0 ));
end entity sevenSegmentUpdate;

architecture platformIndependant of sevenSegmentUpdate is

  constant c_segmentID : std_logic_vector( 2 downto 0 ) := std_logic_vector(to_unsigned(segmentId, 3));

  signal s_selectedData : std_logic_vector( 3 downto 0 );

begin
  s_selectedData <= dataIn( ((segmentId + 1) * 4) - 1 downto (segmentId *4));
  
  makeNewValue : process ( functionSelect, dataIn, s_selectedData, currentValue ) is
  begin
    case (functionSelect) is
      when "000" |
           "001" |
           "010" |
           "011"       => if (to_integer(unsigned(functionSelect)) = segmentId) then newValue <= dataIn( 7 downto 0 );
                                                                                else newValue <= currentValue;
                          end if;
      when "100"       => case (s_selectedData) is
                            when "0000" => newValue <= currentValue(7)&"0111111";
                            when "0001" => newValue <= currentValue(7)&"0000110";
                            when "0010" => newValue <= currentValue(7)&"1011011";
                            when "0011" => newValue <= currentValue(7)&"1001111";
                            when "0100" => newValue <= currentValue(7)&"1100110";
                            when "0101" => newValue <= currentValue(7)&"1101101";
                            when "0110" => newValue <= currentValue(7)&"1111101";
                            when "0111" => newValue <= currentValue(7)&"0000111";
                            when "1000" => newValue <= currentValue(7)&"1111111";
                            when "1001" => newValue <= currentValue(7)&"1101111";
                            when "1010" => newValue <= currentValue(7)&"1110111";
                            when "1011" => newValue <= currentValue(7)&"1111100";
                            when "1100" => newValue <= currentValue(7)&"0111001";
                            when "1101" => newValue <= currentValue(7)&"1011110";
                            when "1110" => newValue <= currentValue(7)&"1111001";
                            when others => newValue <= currentValue(7)&"1110001";
                          end case;
      when "101"       => case (s_selectedData) is
                            when "0000" => newValue <= currentValue(7)&"0111111";
                            when "0001" => newValue <= currentValue(7)&"0000110";
                            when "0010" => newValue <= currentValue(7)&"1011011";
                            when "0011" => newValue <= currentValue(7)&"1001111";
                            when "0100" => newValue <= currentValue(7)&"1100110";
                            when "0101" => newValue <= currentValue(7)&"1101101";
                            when "0110" => newValue <= currentValue(7)&"1111101";
                            when "0111" => newValue <= currentValue(7)&"0000111";
                            when "1000" => newValue <= currentValue(7)&"1111111";
                            when "1001" => newValue <= currentValue(7)&"1101111";
                            when others => newValue <= currentValue(7)&"0000000";
                          end case;
      when "110"       => newValue <= dataIn(segmentId)&currentValue(6 downto 0);
      when others      => newValue <= currentValue;
    end case;
  end process makeNewValue;
end architecture platformIndependant;
