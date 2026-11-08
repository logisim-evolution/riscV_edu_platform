library ieee;
use ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

entity sramLutRam is
  generic( nrOfAddressBits : integer := 5;
           nrOfDataBits    : integer := 32 );
  port ( clock        : in  std_logic;
         writeEnable  : in  std_logic;
         writeAddress : in  unsigned( nrOfAddressBits - 1 downto 0 );
         readAddress  : in  unsigned( nrOfAddressBits - 1 downto 0 );
         writeData    : in  std_logic_vector( nrOfDataBits - 1 downto 0 );
         readData     : out std_logic_vector( nrOfDataBits - 1 downto 0 ));
end sramLutRam;

architecture platformIndependent of sramLutRam is

  type memoryType is array( (2**nrOfAddressBits) - 1 downto 0 ) of std_logic_vector( nrOfDataBits - 1 downto 0 );
  
  signal s_memory : memoryType;

begin

  readData <= s_memory(to_integer(readAddress));

  makeRam : process( clock) is
  begin
    if (rising_edge( clock )) then
      if (writeEnable = '1') then 
        s_memory(to_integer(writeAddress)) <= writeData;
      end if;
    end if;
  end process makeRam;
end platformIndependent;

