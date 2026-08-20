library ieee;
use ieee.std_logic_1164.all;

entity debouncerWithIrq is
  port ( clock            : in  std_logic;
         reset            : in  std_logic;
         nButtonIn        : in  std_logic;
         scanTick         : in  std_logic;
         enablePressIrq   : in  std_logic;
         enableReleaseIrq : in  std_logic;
         resetPressIrq    : in  std_logic;
         resetReleaseIrq  : in  std_logic;
         pressIrq         : out std_logic;
         releaseIrq       : out std_logic;
         currentState     : out std_logic);
end debouncerWithIrq;

architecture behave of debouncerWithIrq is

  signal s_shiftRegisterReg, s_shiftRegisterNext : std_logic_vector( 3 downto 0 );
  signal s_pressIrqReg, s_releaseIrqReg          : std_logic;
  signal s_pressDetected, s_releaseDetected      : std_logic;

begin
  -- To debounce and prevent metastability we use a 4-bit shift register
  s_shiftRegisterNext(0) <= '0' when reset = '1' else
                            not(nButtonIn) when scanTick = '1' else s_shiftRegisterReg(0);
  s_shiftRegisterNext(3 downto 1) <= "000" when reset = '1' else
                                     s_shiftRegisterReg(2 downto 0);
  currentState <= s_shiftRegisterReg(3);
  
  makeShiftReg : process ( clock ) is
  begin
    if (rising_edge( clock )) then
      s_shiftRegisterReg <= s_shiftRegisterNext;
    end if;
  end process makeShiftReg;

  -- here we do the irq handling
  s_releaseDetected <= s_shiftRegisterReg(3) and not(s_shiftRegisterReg(2));
  s_pressDetected   <= s_shiftRegisterReg(2) and not(s_shiftRegisterReg(3));
  
  makeIrqReg : process ( clock ) is
  begin
    if (rising_edge( clock )) then
      if (reset = '1' or resetPressIrq = '1') then
        s_pressIrqReg <= '0';
                                              else
        s_pressIrqReg <= s_pressIrqReg or (s_pressDetected and enablePressIrq);
      end if;
      if (reset = '1' or resetReleaseIrq = '1') then
        s_releaseIrqReg <= '0';
                                                else
        s_releaseIrqReg <= s_releaseIrqReg or (s_releaseDetected and enableReleaseIrq);
      end if;
    end if;
  end process makeIrqReg;
end behave;
