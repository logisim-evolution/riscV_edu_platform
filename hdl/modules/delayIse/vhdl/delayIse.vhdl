library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.log2;
use ieee.math_real.ceil;

entity delayIse is
  generic ( refferenceClockFrequencyInHz : integer := 12000000;
            customInstructionId          : std_logic_vector( 6 downto 0 );
            W_DATA                       : integer := 64  );
  port ( clock           : in  std_logic;
         refferenceClock : in  std_logic;
         reset           : in  std_logic; -- active high
         ci_id           : in  std_logic_vector(6 downto 0);
         ci_start        : in  std_logic;
         ci_dataa        : in  std_logic_vector(W_DATA-1 downto 0);
         ci_datab        : in  std_logic_vector(W_DATA-1 downto 0);
         ci_done         : out std_logic;
         ci_result       : out std_logic_vector(W_DATA-1 downto 0));
end delayIse;

architecture plaformIndependant of delayIse is

  -- This module implements a blocking delay element, where ci_dataa
  -- presents the nr. of micro-seconds to wait. In case ci_dataa == 0
  -- no delay is done.

  constant tickReloadValue : integer := refferenceClockFrequencyInHz / 1000000;
  constant nrOfBits : integer := integer(ceil(log2(real(tickReloadValue))));
  constant zeroVector : std_logic_vector( W_DATA-1 downto 0 ) := (others => '0');

  signal s_isMyCi           : std_logic;
  signal s_done_reg         : std_logic;
  signal s_tickCounterReg   : unsigned( nrOfBits - 1 downto 0 );
  signal s_tickCounterNext  : unsigned( nrOfBits - 1 downto 0 );
  signal s_resetTickCounter : std_logic;
  signal s_microSecTick     : std_logic;
  signal s_tickCounterZero  : std_logic;
  signal s_resetUSync       : std_logic;
  signal s_delayCountReg    : unsigned( W_DATA-1 downto 0 );
  signal s_delayCountNext   : unsigned( W_DATA-1 downto 0 );
  signal s_supressDoneReg   : std_logic;
  signal s_delayCountZero   : std_logic;
  signal s_delayCountOne    : std_logic;
  signal s_doneNext         : std_logic;
  signal s_doneReg          : std_logic;
  
  component synchroFlop is
    port ( clockIn  : in  std_logic;
           clockOut : in  std_logic;
           reset    : in  std_logic;
           D        : in  std_logic;
           Q        : out std_logic);
  end component;

begin
  -- Here we define the control signals
  s_isMyCi <= ci_start when ci_id = customInstructionId else '0';
  
  -- Here we define the tick generator that generates a
  -- micro-second tick based on the clock.
  s_tickCounterZero <= '1' when s_tickCounterReg = to_unsigned(0, nrOfBits) else '0';
  s_tickCounterNext <= to_unsigned( tickReloadValue - 1, nrOfBits) when reset = '1' or
                                                                        s_tickCounterZero = '1' or
                                                                        s_resetTickCounter = '1' else
                       s_tickCounterReg - to_unsigned(1 , nrOfBits);
  s_resetUSync      <= reset or s_isMyCi;
  
  makeTickCounterReg : process ( refferenceClock ) is
  begin
    if (rising_edge( refferenceClock )) then
      s_tickCounterReg <= s_tickCounterNext;
    end if;
  end process makeTickCounterReg;
  
  rsync : synchroFlop
    port map ( clockIn  => clock,
               clockOut => refferenceClock,
               reset    => reset,
               D        => s_isMyCi,
               Q        => s_resetTickCounter );
 
  usync : synchroFlop
    port map ( clockIn  => refferenceClock,
               clockOut => clock,
               reset    => s_resetUSync,
               D        => s_tickCounterZero,
               Q        => s_microSecTick );

  -- here we define the main counter
  s_delayCountZero <= '1' when s_delayCountReg = to_unsigned(0, W_DATA) else '0';
  s_delayCountOne  <= '1' when s_delayCountReg = to_unsigned(1, W_DATA) else '0';
  s_delayCountNext <= (others => '0') when reset = '1' else
                      unsigned( ci_dataa ) when s_isMyCi = '1' and ci_datab(1) = '0' else
                      s_delayCountReg - to_unsigned(1, W_DATA) when s_microSecTick = '1' and s_delayCountZero = '0' else s_delayCountReg;
  ci_result <= std_logic_vector(s_delayCountReg) when s_doneReg = '1' else (others => '0');
  
  makeCounterRegs : process ( clock ) is
  begin
    if (rising_edge( clock )) then 
      if (reset = '1' or s_delayCountZero = '1') then s_supressDoneReg <= '0';
      elsif (s_isMyCi = '1' and ci_datab(1) = '1') then s_supressDoneReg <= '1';
      end if;
      s_delayCountReg <= s_delayCountNext;
    end if;
  end process makeCounterRegs;

  -- Here we define the done signal
  s_doneNext <= '1' when ((s_isMyCi = '1' and ci_dataa = zeroVector) or
                          (s_isMyCi = '1' and ci_datab(0) = '1') or
                          (s_microSecTick = '1' and s_delayCountOne = '1' and s_supressDoneReg = '0')) else '0';
  ci_done <= s_doneReg;
  
  makeDoneReg : process ( clock ) is
  begin
    if (rising_edge( clock )) then
      s_doneReg <= s_doneNext;
    end if;
  end process makeDoneReg;
end plaformIndependant;
