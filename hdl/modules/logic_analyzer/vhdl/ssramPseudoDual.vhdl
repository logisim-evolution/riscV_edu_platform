library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity ssramPseudoDual is
  generic( BITWIDTH   : integer := 32;
           NR_ENTRIES : integer := 512);
  port ( clock        : in  std_logic;
         writeEnable  : in  std_logic;
         writeAddress : in  std_logic_vector(integer(ceil(log2(real(NR_ENTRIES)))) - 1 downto 0);
         writeData    : in  std_logic_vector(BITWIDTH - 1 downto 0);
         readAddress  : in  std_logic_vector(integer(ceil(log2(real(NR_ENTRIES)))) - 1 downto 0);
         readData     : out std_logic_vector(BITWIDTH - 1 downto 0));
end entity ssramPseudoDual;

architecture noPlatformSpecific of ssramPseudoDual is

  type ramType is array(NR_ENTRIES-1 downto 0) of std_logic_vector(BITWIDTH - 1 downto 0);
  
  signal memory : ramType;

begin

  memproc : process ( clock ) is
  begin
    if (rising_edge(clock)) then
      if (writeEnable = '1') then
        memory(to_integer(unsigned(writeAddress))) <= writeData;
      end if;
      readData <= memory(to_integer(unsigned(readAddress)));
    end if;
  end process memproc;

end architecture noPlatformSpecific;
