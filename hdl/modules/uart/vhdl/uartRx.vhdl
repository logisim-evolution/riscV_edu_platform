library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uartRx is
  port( clock           : in  std_logic;
        reset           : in  std_logic;
        baudRateX16Tick : in  std_logic;
        uartRxLine      : in  std_logic;
        fifoFull        : in  std_logic;
        controlReg      : in  std_logic_vector( 5 downto 0 );
        fifoData        : out std_logic_vector( 7 downto 0 );
        fifoWe          : out std_logic;
        frameError      : out std_logic;
        breakDetected   : out std_logic;
        parityError     : out std_logic;
        overrunError    : out std_logic);
end entity uartRx;

architecture platformindependent of uartRx is

  type STATETYPE is ( IDLE, INIT, RECEIVE, WRITE );
  
  signal s_stateMachineReg, s_stateMachineNext      : STATETYPE;
  signal s_rxPipeReg                                : std_logic_vector( 2 downto 0 );
  signal s_filteredRxReg, s_filteredRxDelayReg      : std_logic;
  signal s_trigger                                  : std_logic_vector( 3 downto 0 );
  signal s_rxNegEdge                                : std_logic;
  signal s_baudCounterReg, s_baudCounterNext        : unsigned( 3 downto 0 );
  signal s_bitCounterReg, s_bitCounterNext          : unsigned( 3 downto 0 );
  signal s_bitCounterLoadValue                      : unsigned( 3 downto 0 );
  signal s_shiftReg, s_shiftNext                    : std_logic_vector(10 downto 0 );
  signal s_dataBits                                 : std_logic_vector( 7 downto 0 );
  signal s_sampleTick, s_doShift                    : std_logic;
  signal s_bitCounterSelect                         : std_logic_vector( 2 downto 0 );
  signal s_isBreak, s_frameErrorReg, s_breakReg     : std_logic;
  signal s_overrunReg, s_parityErrorReg, s_delayReg : std_logic;
  signal s_dataOutReg                               : std_logic_vector( 7 downto 0 );
  signal s_xorStage1                                : std_logic_vector( 3 downto 0 );
  signal s_xorStage2                                : std_logic_vector( 1 downto 0 );
  signal s_dataParity, s_8BitBreak, s_7BitBreak     : std_logic;
  signal s_6BitBreak, s_5BitBreak, s_parity         : std_logic;
  signal s_parityError                              : std_logic;

begin

  -- here the rx filter is defined
  s_trigger   <= uartRxLine & s_rxPipeReg;
  s_rxNegEdge <= s_filteredRxDelayReg and not( s_filteredRxReg );
  
  makeRxRegs : process( clock ) is
  begin
    if (rising_edge( clock )) then
      if (reset = '1') then
        s_rxPipeReg          <= "111";
        s_filteredRxDelayReg <= '1';
        s_filteredRxReg      <= '1';
      else
        s_filteredRxDelayReg <= s_filteredRxReg;
        if (baudRateX16Tick = '1') then 
          s_rxPipeReg <= s_rxPipeReg( 1 downto 0 ) & uartRxLine;
          if (s_trigger = X"0") then s_filteredRxReg <= '0';
          elsif (s_trigger = X"F") then s_filteredRxReg <= '1';
          end if;
        end if;
      end if;
    end if;
  end process makeRxRegs;

  -- here the shift register is defined
  s_baudCounterNext <= (others => '0') when reset = '1' or s_stateMachineReg = INIT else
                       s_baudCounterReg + to_unsigned(1, 4) when s_stateMachineReg = RECEIVE and baudRateX16Tick = '1' else s_baudCounterReg;
  s_sampleTick      <= baudRateX16Tick when s_baudCounterReg = to_unsigned(7, 4) else '0';
  s_doShift         <= '0' when s_bitCounterReg = to_unsigned(0, 4) else s_sampleTick;
  s_bitCounterNext  <= (others => '0') when reset = '1' else
                       s_bitCounterLoadValue when s_stateMachineReg = INIT else
                       s_bitCounterReg - to_unsigned(1 , 4) when s_doShift = '1' else s_bitCounterReg;
  s_shiftNext       <= (others => '0') when reset = '1' else
                       s_filteredRxReg & s_shiftReg( 10 downto 1 ) when s_doShift = '1' else s_shiftReg;
  
  makeShiftRegs : process( clock ) is
  begin
    if (rising_edge( clock )) then
      s_baudCounterReg  <= s_baudCounterNext;
      s_bitCounterReg   <= s_bitCounterNext;
      s_shiftReg        <= s_shiftNext;
    end if;
  end process makeShiftRegs;
  
  makeShiftValues : process ( s_bitCounterSelect, s_shiftReg ) is
  begin
    case (s_bitCounterSelect) is
      when "000"  => s_bitCounterLoadValue <= to_unsigned(7, 4);
                     s_dataBits            <= "000"&s_shiftReg(9 downto 5);
      when "001"  => s_bitCounterLoadValue <= to_unsigned(8, 4);
                     s_dataBits            <= "00"&s_shiftReg(9 downto 4);
      when "010"  => s_bitCounterLoadValue <= to_unsigned(9, 4);
                     s_dataBits            <= "0"&s_shiftReg(9 downto 3);
      when "011"  => s_bitCounterLoadValue <= to_unsigned(10, 4);
                     s_dataBits            <= s_shiftReg(9 downto 2);
      when "100"  => s_bitCounterLoadValue <= to_unsigned(8, 4);
                     s_dataBits            <= "000"&s_shiftReg(8 downto 4);
      when "101"  => s_bitCounterLoadValue <= to_unsigned(9, 4);
                     s_dataBits            <= "00"&s_shiftReg(8 downto 3);
      when "110"  => s_bitCounterLoadValue <= to_unsigned(10, 4);
                     s_dataBits            <= "0"&s_shiftReg(8 downto 2);
      when others => s_bitCounterLoadValue <= to_unsigned(11, 4);
                     s_dataBits            <= s_shiftReg(8 downto 1);
    end case;
  end process makeShiftValues;

  -- here the stat machine is defined
  makeNextState : process( s_stateMachineReg, s_rxNegEdge, s_bitCounterReg ) is
  begin
    case (s_stateMachineReg) is
      when IDLE    => if (s_rxNegEdge = '1') then s_stateMachineNext <= INIT;
                                             else s_stateMachineNext <= IDLE;
                      end if;
      when INIT    => s_stateMachineNext <= RECEIVE;
      when RECEIVE => if (s_bitCounterReg = to_unsigned(0, 4)) then s_stateMachineNext <= WRITE;
                                                               else s_stateMachineNext <= RECEIVE;
                      end if;
      when others  => s_stateMachineNext <= IDLE;
    end case;
  end process makeNextState;
    
  makeStateReg : process( clock ) is
  begin
    if (rising_edge( clock )) then
      if (reset = '1') then s_stateMachineReg <= IDLE;
                       else s_stateMachineReg <= s_stateMachineNext;
      end if;
    end if;
  end process makeStateReg;

  -- here all data related signals are defined
  frameError    <= s_frameErrorReg;
  breakDetected <= s_breakReg;
  overrunError  <= s_overrunReg;
  parityError   <= s_parityErrorReg;
  fifoData      <= s_dataOutReg;
  
  s_xorStage2(0) <= s_xorStage1(1) xor s_xorStage1(0);
  s_xorStage2(1) <= s_xorStage1(3) xor s_xorStage1(2);
  s_dataParity   <= s_xorStage2(1) xor s_xorStage2(0);
  s_8BitBreak    <= '1' when s_shiftReg( 10 downto 1 ) = "00"&X"00" else '0';
  s_7BitBreak    <= '1' when s_shiftReg( 10 downto 2 ) = "0"&X"00" else '0';
  s_6BitBreak    <= '1' when s_shiftReg( 10 downto 3 ) =  X"00" else '0';
  s_5BitBreak    <= '1' when s_shiftReg( 10 downto 4 ) = "000"&X"0" else '0';
  s_parity       <= s_shiftReg(9) xnor controlReg(4);
  s_parityError  <= (s_parity xor s_dataParity) and controlReg(3)
                      when controlReg(5) = '1' else
                    s_parity and controlReg(3);
  
  makeBreak : process( controlReg, s_5BitBreak, s_6BitBreak, s_7BitBreak, s_8BitBreak ) is
  begin
    case (controlReg( 1 downto 0 )) is
      when "00"   => s_isBreak <= s_5BitBreak;
      when "01"   => s_isBreak <= s_6BitBreak;
      when "10"   => s_isBreak <= s_7BitBreak;
      when others => s_isBreak <= s_8BitBreak;
    end case;
  end process makeBreak;
  
  genXor1 : for n in 3 downto 0 generate
    s_xorStage1(n) <= s_dataBits(n*2) xor s_dataBits(n*2 + 1);
  end generate genXor1;
  
  makeDataFlops : process ( clock ) is
  begin
    if (rising_edge( clock )) then
      if (reset = '1') then
        s_frameErrorReg  <= '0';
        s_breakReg       <= '0';
        s_overrunReg     <= '0';
        s_parityErrorReg <= '0';
        s_dataOutReg     <= (others => '0');
        s_delayReg       <= '0';
        fifoWe           <= '0';
      else
        fifoWe           <= s_delayReg and not( s_overrunReg );
        if (s_stateMachineReg = WRITE) then
          s_frameErrorReg  <= s_shiftReg(10) or s_isBreak;
          s_breakReg       <= s_isBreak;
          s_overrunReg     <= fifoFull and not( s_isBreak );
          s_parityErrorReg <= s_parityError;
          s_dataOutReg     <= s_dataBits;
          s_delayReg       <= '1';
                                       else
          s_delayReg       <= '0';
        end if;
      end if;
    end if;
  end process makeDataFlops;
end architecture platformindependent;
