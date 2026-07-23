library ieee;
use ieee.std_logic_1164.all;

entity synchroFlop is
  port ( clockIn  : in  std_logic;
         clockOut : in  std_logic;
         reset    : in  std_logic;
         D        : in  std_logic;
         Q        : out std_logic);
end synchroFlop;

architecture platformIndependant of synchroFlop is

  signal s_stateReg  : std_logic_vector( 2 downto 0 );
  signal s_stateNext : std_logic_vector( 2 downto 0 );
  signal s_reset0    : std_logic;

begin
  Q                       <= s_stateReg(2);
  s_reset0                <= reset or s_stateReg(1);
  s_stateNext(2 downto 1) <= s_stateReg(1 downto 0);
  s_stateNext(0)          <= s_stateReg(0) or D;
  
  makeState0 : process( clockIn, s_reset0 ) is
  begin
    if (s_reset0 = '1') then s_stateReg(0) <= '0';
    elsif (rising_edge( clockIn )) then s_stateReg(0) <= s_stateNext(0);
    end if;
  end process makeState0;
  
  makeState21 : process( clockOut, reset ) is
  begin
    if (reset = '1') then s_stateReg(2 downto 1) <= "00";
    elsif (rising_edge( clockOut )) then s_stateReg(2 downto 1) <= s_stateNext(2 downto 1);
    end if;
  end process makeState21;
end platformIndependant;
