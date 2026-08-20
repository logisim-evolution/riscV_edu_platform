library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity switches is
  generic ( DataBits    : integer := 32;  -- must be 32 for this module
            AddrBits    : integer := 32;  -- must be > 5 for this module
            BaseAddress : std_logic_vector := std_logic_vector(to_unsigned(0,32)));
  port ( CLK_I    : in  std_logic;
         RST_I    : in  std_logic;
         DAT_I    : in  std_logic_vector( DataBits-1 downto 0 );
         DAT_O    : out std_logic_vector( DataBits-1 downto 0 );
         -- TAGD_I and TAGD_O are not implemented
         ACK_O    : out std_logic;
         ADDR_I   : in  std_logic_vector( AddrBits-1 downto 0 );
         CYC_I    : in  std_logic;
         ERR_O    : out std_logic;
         -- LOCK_I is not used in this module
         -- RTY_I is not implemented
         SEL_I    : in  std_logic_vector( (DataBits/8)-1 downto 0 );
         STB_I    : in  std_logic;
         -- TGA_O and TGC_O are not implemented
         WE_I     : in  std_logic;
         CTI_I    : in  std_logic_vector( 2 downto 0 ); -- Registered feedback
         -- BTE_I is not used in this module
         
         -- here the interface signals are defined
         oneKHzTick : in  std_logic;
         irqDip     : out std_logic;
         irqJoy     : out std_logic;
         nButtons   : in  std_logic_vector( 4 downto 0 );
         nDipSwitch : in  std_logic_vector( 7 downto 0 );
         nJoystick  : in  std_logic_vector( 4 downto 0 )); 
end entity switches;

architecture platformIndependant of switches is

  signal s_dipSwitchPressedIrqMaskReg                    : std_logic_vector( 7 downto 0 );
  signal s_dipSwitchReleasedIrqMaskReg                   : std_logic_vector( 7 downto 0 );
  signal s_joystickPressedIrqMaskReg                     : std_logic_vector( 9 downto 0 );
  signal s_joystickReleasedIrqMaskReg                    : std_logic_vector( 9 downto 0 );
  signal s_irqDipReg, s_irqJoyReg                        : std_logic_vector( 1 downto 0 );
  signal s_dipswitchPressedIrqs, s_dipSwitchReleasedIrqs : std_logic_vector( 7 downto 0 );
  signal s_joystickPressedIrqs, s_joystickReleasedIrqs   : std_logic_vector( 9 downto 0 );
  signal s_clearAllIrqMasks                              : std_logic;
  signal s_weDipSwitchPressedIrqMask                     : std_logic;
  signal s_weDipSwitchReleasedIrqMask                    : std_logic;
  signal s_clearDipSwitchPressedIrqs                     : std_logic;
  signal s_clearDipSwitchReleasedIrqMask                 : std_logic;
  signal s_weJoystickPressedIrqMask                      : std_logic;
  signal s_weJoystickReleasedIrqMask                     : std_logic;
  signal s_clearJoystickPressedIrqs                      : std_logic;
  signal s_clearJoystickReleasedIrqMask                  : std_logic;
  signal s_countActiveReg, s_startCount, s_stopCount     : std_logic;
  signal s_delayCounterReg                               : unsigned( 31 downto 0 );
  signal s_dipswitchState                                : std_logic_vector( 7 downto 0 );
  signal s_joystickState                                 : std_logic_vector( 9 downto 0 );
  signal ackReg, errorReg, weReg, reReg                  : std_logic;
  signal dataInReg                                       : std_logic_vector( 31 downto 0 );
  signal indexReg                                        : std_logic_vector( 2 downto 0 );
  signal isMyTransaction, isCorrectTransaction           : std_logic;

begin
  isMyTransaction      <= CYC_I and STB_I when ADDR_I(AddrBits-1 downto 5) = BaseAddress(AddrBits-1 downto 5) else '0';
  isCorrectTransaction <= isMyTransaction when CTI_I = "000" and SEL_I = X"F" else '0';
  ERR_O                <= errorReg;
  ACK_O                <= ackReg;
  
  makeBusRegs : process ( CLK_I ) is
  begin
    if (rising_edge( CLK_I )) then
      if (RST_I = '1') then
        ackReg    <= '0';
        errorReg  <= '0';
        weReg     <= '0';
        reReg     <= '0';
        indexReg  <= (others => '0');
        dataInReg <= (others => '0');
                       else
        ackReg    <= not( ackReg ) and isCorrectTransaction;
        errorReg  <= not( errorReg ) and isMyTransaction and not( isCorrectTransaction );
        weReg     <= not( ackReg ) and isCorrectTransaction and WE_I;
        reReg     <= not( ackReg ) and isCorrectTransaction and not( WE_I );
        if (ackReg = '0' and isCorrectTransaction = '1') then
          indexReg  <= ADDR_I( 4 downto 2 );
          dataInReg <= DAT_I;
        end if;
      end if;
    end if;
  end process makeBusRegs;
  
  makeDataOut : process ( indexReg, s_dipswitchState, s_dipswitchPressedIrqs, s_dipSwitchReleasedIrqs,
                          s_joystickState, s_joystickPressedIrqs, s_joystickReleasedIrqs, s_delayCounterReg ) is
  begin
    case (indexReg) is
      when "000"  => DAT_O <= X"000000"&s_dipswitchState;
      when "001"  => DAT_O <= X"000000"&s_dipswitchPressedIrqs;
      when "010"  => DAT_O <= X"000000"&s_dipSwitchReleasedIrqs;
      when "011"  => DAT_O <= "00"&X"00000"&s_joystickState;
      when "100"  => DAT_O <= "00"&X"00000"&s_joystickPressedIrqs;
      when "101"  => DAT_O <= "00"&X"00000"&s_joystickReleasedIrqs;
      when "110"  => DAT_O <= std_logic_vector(s_delayCounterReg);
      when others => DAT_O <= (others => '0');
    end case;
  end process makeDataOut;
  
  -- here we define the IRQ enable masks
  s_clearAllIrqMasks              <= weReg when indexReg = "111" else '0';
  s_weDipSwitchPressedIrqMask     <= weReg when indexReg = "001" else '0';
  s_weDipSwitchReleasedIrqMask    <= weReg when indexReg = "010" else '0';
  s_clearDipSwitchPressedIrqs     <= reReg when indexReg = "111" or indexReg = "001" else '0';
  s_clearDipSwitchReleasedIrqMask <= reReg when indexReg = "111" or indexReg = "010" else '0';
  s_weJoystickPressedIrqMask      <= weReg when indexReg = "100" else '0';
  s_weJoystickReleasedIrqMask     <= weReg when indexReg = "101" else '0';
  s_clearJoystickPressedIrqs      <= reReg when indexReg = "111" or indexReg = "100" else '0';
  s_clearJoystickReleasedIrqMask  <= reReg when indexReg = "111" or indexReg = "101" else '0';
  irqDip                          <= s_irqDipReg(0);
  irqJoy                          <= s_irqJoyReg(0);
  
  makeIrqRegs : process ( CLK_I ) is
  begin
    if (rising_edge( CLK_I )) then
      if (RST_I = '1' or s_clearAllIrqMasks = '1') then
        s_dipSwitchPressedIrqMaskReg  <= (others => '0');
        s_dipSwitchReleasedIrqMaskReg <= (others => '0');
        s_joystickPressedIrqMaskReg   <= (others => '0');
        s_joystickReleasedIrqMaskReg  <= (others => '0');
      else
        if (s_weDipSwitchPressedIrqMask = '1') then s_dipSwitchPressedIrqMaskReg <= dataInReg( 7 downto 0 );
        end if;
        if (s_weDipSwitchReleasedIrqMask = '1') then s_dipSwitchReleasedIrqMaskReg <= dataInReg( 7 downto 0 );
        end if;
        if (s_weJoystickPressedIrqMask = '1') then s_joystickPressedIrqMaskReg <= dataInReg( 9 downto 0 );
        end if;
        if (s_weJoystickReleasedIrqMask = '1') then s_joystickReleasedIrqMaskReg <= dataInReg( 9 downto 0 );
        end if;
      end if;
      if (s_dipswitchPressedIrqs /= X"00" or s_dipSwitchReleasedIrqs /= X"00") then s_irqDipReg(0) <= '1';
                                                                               else s_irqDipReg(0) <= '0';
      end if;
      s_irqDipReg(1) <= not( RST_I ) and s_irqDipReg(0);
      if (s_joystickPressedIrqs /= "00"&X"00" or s_joystickReleasedIrqs /= "00"&X"00") then s_irqJoyReg(0) <= '1';
                                                                                       else s_irqJoyReg(0) <= '0';
      end if;
      s_irqJoyReg(1) <= not( RST_I ) and s_irqJoyReg(0);
    end if;
  end process makeIrqRegs;

  -- here we define the irq response delay counter
  s_startCount <= (s_irqDipReg(0) and not (s_irqDipReg(1))) or
                  (s_irqJoyReg(0) and not (s_irqJoyReg(1)));
  s_stopCount  <= (s_irqDipReg(1) and not (s_irqDipReg(0))) or
                  (s_irqJoyReg(1) and not (s_irqJoyReg(0)));
  
  makeDelayCount : process ( CLK_I ) is
  begin
    if (rising_edge( CLK_I )) then
      if (RST_I = '1' or s_stopCount = '1') then 
        s_countActiveReg <= '0';
                                            else 
        s_countActiveReg <= s_countActiveReg or s_startCount;
      end if;
      if (RST_I = '1' or s_startCount = '1') then 
        s_delayCounterReg <= (others => '0');
      elsif (s_delayCounterReg(31) = '0' and s_countActiveReg = '1') then
        s_delayCounterReg <= s_delayCounterReg + to_unsigned(1, 32);
      end if; 
    end if;
  end process makeDelayCount;
  
  -- here we insert the anti-dender modules
  genDips : for n in 7 downto 0 generate
    dipsw : entity work.debouncerWithIrq(behave)
      port map ( clock            => CLK_I,
                 reset            => RST_I,
                 nButtonIn        => nDipSwitch(n),
                 scanTick         => oneKHzTick,
                 enablePressIrq   => s_dipSwitchPressedIrqMaskReg(n),
                 enableReleaseIrq => s_dipSwitchReleasedIrqMaskReg(n),
                 resetPressIrq    => s_clearDipSwitchPressedIrqs,
                 resetReleaseIrq  => s_clearDipSwitchReleasedIrqMask,
                 pressIrq         => s_dipswitchPressedIrqs(n),
                 releaseIrq       => s_dipSwitchReleasedIrqs(n),
                 currentState     => s_dipswitchState(n));

  end generate genDips;

  genSwitches : for n in 5 downto 0 generate
    joystick : entity work.debouncerWithIrq(behave)
      port map ( clock            => CLK_I,
                 reset            => RST_I,
                 nButtonIn        => nJoystick(n),
                 scanTick         => oneKHzTick,
                 enablePressIrq   => s_joystickPressedIrqMaskReg(n),
                 enableReleaseIrq => s_joystickReleasedIrqMaskReg(n),
                 resetPressIrq    => s_clearJoystickPressedIrqs,
                 resetReleaseIrq  => s_clearJoystickReleasedIrqMask,
                 pressIrq         => s_joystickPressedIrqs(n),
                 releaseIrq       => s_joystickReleasedIrqs(n),
                 currentState     => s_joystickState(n));
    buttons : entity work.debouncerWithIrq(behave)
      port map ( clock            => CLK_I,
                 reset            => RST_I,
                 nButtonIn        => nButtons(n),
                 scanTick         => oneKHzTick,
                 enablePressIrq   => s_joystickPressedIrqMaskReg(n+5),
                 enableReleaseIrq => s_joystickReleasedIrqMaskReg(n+5),
                 resetPressIrq    => s_clearJoystickPressedIrqs,
                 resetReleaseIrq  => s_clearJoystickReleasedIrqMask,
                 pressIrq         => s_joystickPressedIrqs(n+5),
                 releaseIrq       => s_joystickReleasedIrqs(n+5),
                 currentState     => s_joystickState(n+5));
  end generate genSwitches;

end architecture platformIndependant;
