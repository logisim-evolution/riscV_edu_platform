library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity baudGenerator is
   port( clock           : in  std_logic;
         clock_50MHz     : in  std_logic;
         reset           : in  std_logic;
         baudDivisor     : in  std_logic_vector( 15 downto 0 );
         baudRateX16Tick : out std_logic;
         baudRateX2Tick  : out std_logic);
end entity baudGenerator;

architecture behav of baudGenerator is

  signal s_counterReg      : unsigned(15 downto 0);
  signal s_counterNext     : unsigned(15 downto 0);
  signal s_counterResetReg : std_logic;
  signal s_counterLoad     : std_logic;
  signal s_baudDivReg      : unsigned( 2 downto 0);
  signal s_baudDivNext     : unsigned( 2 downto 0);
  signal s_baudDivIsZero   : std_logic;
  signal s_baudRateX16Tick : std_logic;
  signal s_baudRateX2Tick  : std_logic;
  
begin
  s_counterLoad     <= '1' when s_counterReg(15 downto 1) = to_unsigned(0, 15) else '0';
  s_counterNext     <= unsigned(baudDivisor) when reset = '1' or s_counterLoad = '1' else s_counterReg - to_unsigned(1, 16);
  s_baudDivNext     <= to_unsigned(7, 3) when reset = '1' else
                       s_baudDivReg - to_unsigned(1, 3) when s_counterLoad = '1' else s_baudDivReg;
  s_baudDivIsZero   <= '1' when s_baudDivReg = to_unsigned(0, 3) else '0';
  s_baudRateX16Tick <= s_counterLoad and not(s_counterResetReg);
  s_baudRateX2Tick  <= s_counterLoad and s_baudDivIsZero and not(s_counterResetReg);
  
  makeFlops : process( clock_50MHz )
  begin
    if (rising_edge( clock_50MHz )) then
      s_counterResetReg <= reset;
      s_counterReg      <= s_counterNext;
      s_baudDivReg      <= s_baudDivNext;
    end if;
  end process makeFlops;
  
  baud16 : entity work.synchroFlop(platformIndependant)
    port map ( clockIn  => clock_50MHz,
               clockOut => clock,
               reset    => reset,
               D        => s_baudRateX16Tick,
               Q        => baudRateX16Tick);

  baud2 : entity work.synchroFlop(platformIndependant)
    port map ( clockIn  => clock_50MHz,
               clockOut => clock,
               reset    => reset,
               D        => s_baudRateX2Tick,
               Q        => baudRateX2Tick);
end architecture behav;
