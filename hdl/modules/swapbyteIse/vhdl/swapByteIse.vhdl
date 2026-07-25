library ieee;
use ieee.std_logic_1164.all;

entity swapByte is
  generic ( customId : std_logic_vector( 6 downto 0 ) := "0000000";
            W_DATA   : integer := 32 ); -- Important: for this ISE W_DATA must be 32!
  port ( ci_id     : in  std_logic_vector(6 downto 0);
         ci_start  : in  std_logic;
         ci_dataa  : in  std_logic_vector(W_DATA-1 downto 0);
         ci_datab  : in  std_logic_vector(W_DATA-1 downto 0);
         ci_done   : out std_logic;
         ci_result : out std_logic_vector(W_DATA-1 downto 0));
end swapByte;

architecture behave of swapByte is

  signal s_isMyCustomInstruction : std_logic;
  signal s_swappedData           : std_logic_vector( 31 DOWNTO 0 );

begin
  s_isMyCustomInstruction <= ci_start when ci_id = customId else '0';
  s_swappedData <= ci_dataa(7 downto 0)&ci_dataa(15 downto 8)&
                   ci_dataa(23 downto 16)&ci_dataa(31 downto 24) when ci_datab(0) = '0' else
                   ci_dataa(23 downto 16)&ci_dataa(31 downto 24)&
                   ci_dataa(7 downto 0)&ci_dataa(15 downto 8);
  ci_done   <= s_isMyCustomInstruction;
  ci_result <= s_swappedData when s_isMyCustomInstruction = '1' else (others => '0');
end behave;
