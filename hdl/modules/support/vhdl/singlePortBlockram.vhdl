library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity singlePortBlockRam is
  generic ( nrOfAddressBits : integer := 4;
            nrOfDataBits    : integer := 8);
  port ( clock       : in  std_logic;
         writeEnable : in  std_logic;
         address     : in  std_logic_vector( nrOfAddressBits-1 downto 0 );
         dataIn      : in  std_logic_vector( nrOfDataBits-1 downto 0 );
         dataOut     : out std_logic_vector( nrOfDataBits-1 downto 0 ));
end entity singlePortBlockRam;

architecture platformindependent of singlePortBlockRam is

  type MEMTYPE is array((2**nrOfAddressBits)-1 downto 0) of std_logic_vector( nrOfDataBits-1 downto 0 );
  
  signal s_mem : MEMTYPE;

begin

  makeMem : process ( clock ) is
  begin
    if (rising_edge(clock)) then
      if (writeEnable = '1') then s_mem(to_integer(unsigned(address))) <= dataIn;
      end if;
      dataOut <= s_mem(to_integer(unsigned(address)));
    end if;
  end process makeMem;

end architecture platformindependent;
