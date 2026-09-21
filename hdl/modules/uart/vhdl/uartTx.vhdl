library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uartTx is
   port( clock           : in  std_logic;
         reset           : in  std_logic;
         baudRateX2tick  : in  std_logic;
         controlReg      : in  std_logic_vector( 6 downto 0 );
         fifoData        : in  std_logic_vector( 7 downto 0 );
         fifoEmpty       : in  std_logic;
         fifoReadAck     : out std_logic;
         uartTxLine      : out std_logic;
         busy            : out std_logic);
end entity uartTx;

architecture platformIndependent of uartTx is

  type STATE_TYPE is ( IDLE, LOAD, SHIFT );
  
  signal s_stateMachineReg, s_stateMachineNext                     : STATE_TYPE;
  signal s_xorStage1                                               : std_logic_vector( 3 downto 0 );
  signal s_mux1, s_mux2                                            : std_logic;
  signal s_xorStage2                                               : std_logic_vector( 1 downto 0 );
  signal s_xorStage3, s_parityBit                                  : std_logic;
  signal s_bitDoneReg, s_bitDoneNext                               : std_logic;
  signal s_loadShifter, s_shiftOnePosition                         : std_logic;
  signal s_shifterLoadValue, s_shiftReg, s_shiftNext               : std_logic_vector( 9 downto 0 );
  signal s_halfBitCountReg, s_halfBitLoadValue, s_halfBitCountNext : unsigned( 4 downto 0 );

begin
  busy <= '0' when s_stateMachineReg = IDLE else '1';

  -- here we define the parity
  s_mux1         <= fifoData(6) when controlReg(0) = '0' else s_xorStage1(3);
  s_xorStage2(1) <= s_xorStage1(2) xor s_mux1;
  s_xorStage2(0) <= s_xorStage1(0) xor s_xorStage1(1);
  s_xorStage3    <= s_mux2 xor s_xorStage2(0);
  s_parityBit    <= '1' when controlReg(3) = '0' else
                    not(controlReg(4)) when controlReg(5) = '1' else
                    not(s_xorStage3 xor controlReg(4));
  genXor1 : for n in 3 downto 0 generate
    s_xorStage1(n) <= fifoData(n*2) xor fifoData((n*2) + 1);
  end generate genXor1;
  
  makeMux2 : process ( controlReg, fifoData, s_xorStage1 ) is
  begin
    case (controlReg( 1 downto 0 )) is
      when "00"   => s_mux2 <= fifoData(4);
      when "01"   => s_mux2 <= s_xorStage1(2);
      when others => s_mux2 <= s_xorStage2(1);
    end case;
  end process makeMux2;
  
  -- here we define the shifter
  s_bitDoneNext         <= '0' when reset = '1' or s_stateMachineReg /= SHIFT else s_bitDoneReg xor baudRateX2tick;
  s_loadShifter         <= baudRateX2tick when s_stateMachineReg = LOAD else '0';
  s_shiftOnePosition    <= s_bitDoneReg and baudRateX2tick;
  s_shiftNext           <= "11"&X"FF" when reset = '1' else
                           s_shifterLoadValue when s_loadShifter = '1' else
                           s_shiftReg(8 downto 0)&"1" when s_shiftOnePosition = '1' else s_shiftReg;
  s_shifterLoadValue(9) <= '0';
  s_shifterLoadValue(8) <= fifoData(0);
  s_shifterLoadValue(7) <= fifoData(1);
  s_shifterLoadValue(6) <= fifoData(2);
  s_shifterLoadValue(5) <= fifoData(3);
  s_shifterLoadValue(4) <= fifoData(4);
  s_shifterLoadValue(3) <= s_parityBit when controlReg( 1 downto 0 ) = "00" else fifoData(5);
  s_shifterLoadValue(2) <= s_parityBit when controlReg( 1 downto 0 ) = "01" else 
                           fifoData(6) when controlReg(1) = '1' else '1';
  s_shifterLoadValue(1) <= s_parityBit when controlReg( 1 downto 0 ) = "10" else 
                           fifoData(7) when controlReg( 1 downto 0 ) = "11" else '1';
  s_shifterLoadValue(0) <= s_parityBit when controlReg( 1 downto 0 ) = "11" else '1';
  
  makeShiftRegs : process ( clock ) is
  begin
    if (rising_edge( clock )) then
      s_bitDoneReg <= s_bitDoneNext;
      s_shiftReg   <= s_shiftNext;
      fifoReadAck  <= s_loadShifter;
      if (reset = '1') then uartTxLine <= '1';
                       else uartTxLine <= s_shiftReg(9) and not controlReg(6);
      end if;
    end if;
  end process makeShiftRegs;
  
  -- here we define the half bit counter
  s_halfBitCountNext <= "00000" when reset = '1' else
                        s_halfBitLoadValue when s_stateMachineReg = LOAD and baudRateX2tick = '1' else
                        s_halfBitCountReg when s_halfBitCountReg = "00000" and baudRateX2tick = '0' else
                        s_halfBitCountReg - to_unsigned(1, 5);
  
  makeHalfBitReg : process( clock ) is
  begin
    if (rising_edge(clock)) then
      s_halfBitCountReg <= s_halfBitCountNext;
    end if;
  end process makeHalfBitReg;
  
  makeHalfBitLoad : process ( controlReg ) is
  begin
    case (controlReg(3 downto 0)) is
      when X"0"   => s_halfBitLoadValue <= to_unsigned(14, 5);
      when X"1"   => s_halfBitLoadValue <= to_unsigned(16, 5);
      when X"2"   => s_halfBitLoadValue <= to_unsigned(18, 5);
      when X"3"   => s_halfBitLoadValue <= to_unsigned(20, 5);
      when X"4"   => s_halfBitLoadValue <= to_unsigned(15, 5);
      when X"5"   => s_halfBitLoadValue <= to_unsigned(18, 5);
      when X"6"   => s_halfBitLoadValue <= to_unsigned(20, 5);
      when X"7"   => s_halfBitLoadValue <= to_unsigned(22, 5);
      when X"8"   => s_halfBitLoadValue <= to_unsigned(16, 5);
      when X"9"   => s_halfBitLoadValue <= to_unsigned(18, 5);
      when X"A"   => s_halfBitLoadValue <= to_unsigned(20, 5);
      when X"B"   => s_halfBitLoadValue <= to_unsigned(22, 5);
      when X"C"   => s_halfBitLoadValue <= to_unsigned(17, 5);
      when X"D"   => s_halfBitLoadValue <= to_unsigned(20, 5);
      when X"E"   => s_halfBitLoadValue <= to_unsigned(22, 5);
      when others => s_halfBitLoadValue <= to_unsigned(24, 5);
    end case;
  end process makeHalfBitLoad;
  
  -- here we define the state machine
  makeStateNext : process(s_stateMachineReg, fifoEmpty, baudRateX2tick, s_halfBitCountReg) is
  begin
    case (s_stateMachineReg) is
      when IDLE   => if (fifoEmpty = '0') then s_stateMachineNext <= LOAD;
                                          else s_stateMachineNext <= IDLE;
                     end if;
      when LOAD   => if (baudRateX2tick = '1') then s_stateMachineNext <= SHIFT;
                                               else s_stateMachineNext <= LOAD;
                     end if;
      when SHIFT  => if (s_halfBitCountReg = to_unsigned(1,5) and fifoEmpty = '1') then s_stateMachineNext <= IDLE;
                     elsif (s_halfBitCountReg = to_unsigned(1,5) and fifoEmpty = '0') then s_stateMachineNext <= LOAD;
                                                                                      else s_stateMachineNext <= SHIFT;
                     end if;
      when others => s_stateMachineNext <= IDLE;
    end case;
  end process makeStateNext;
  
  makeStateReg : process ( clock ) is
  begin
    if (rising_edge(clock)) then
      if (reset = '1') then s_stateMachineReg <= IDLE;
                       else s_stateMachineReg <= s_stateMachineNext;
      end if;
    end if;
  end process makeStateReg;

end architecture platformIndependent;
