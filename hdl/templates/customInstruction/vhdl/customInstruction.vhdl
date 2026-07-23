library ieee;
use ieee.std_logic_1164.all;

entity customInstruction is
  generic( customId : std_logic_vector(6 downto 0) := "0000000";
           W_DATA   : integer := 32 ); -- see hazard3 for value
  port ( clock     : in  std_logic;
         reset     : in  std_logic; -- active high
         ci_id     : in  std_logic_vector(6 downto 0);
         ci_start  : in  std_logic;
         ci_dataa  : in  std_logic_vector(W_DATA-1 downto 0);
         ci_datab  : in  std_logic_vector(W_DATA-1 downto 0);
         ci_done   : out std_logic;
         ci_result : out std_logic_vector(W_DATA-1 downto 0));
end entity customInstruction;
