library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity logicAnalyserCore is
  port ( CLK_I           : in  std_logic;
         RST_I           : in  std_logic; -- system reset
         resetCore       : in  std_logic; -- logic analyser reset (start a new capture)
         
         tappedWires     : in  std_logic_vector( 63 downto 0 );
         
         postTrigSamples : in  std_logic_vector( 8 downto 0 );
         seqLen          : in  std_logic_vector( 1 downto 0 );
         comparator0     : in  std_logic_vector( 2 downto 0 );
         comparator1     : in  std_logic_vector( 2 downto 0 );
         comparator2     : in  std_logic_vector( 2 downto 0 );
         comparator3     : in  std_logic_vector( 2 downto 0 );
         mask0           : in  std_logic_vector( 63 downto 0 );
         mask1           : in  std_logic_vector( 63 downto 0 );
         mask2           : in  std_logic_vector( 63 downto 0 );
         mask3           : in  std_logic_vector( 63 downto 0 );
         reference0      : in  std_logic_vector( 63 downto 0 );
         reference1      : in  std_logic_vector( 63 downto 0 );
         reference2      : in  std_logic_vector( 63 downto 0 );
         reference3      : in  std_logic_vector( 63 downto 0 );
         done            : out std_logic;
         startAddress    : out std_logic_vector( 8 downto 0 );
         
         readAddress     : in  std_logic_vector( 8 downto 0 );
         dataLow         : out std_logic_vector( 31 downto 0 );
         dataHigh        : out std_logic_vector( 31 downto 0 ));
end entity logicAnalyserCore;

architecture platformIndependant of logicAnalyserCore is

  type STATE_TYPE is (RESET, ACTIVE, FINISH, IDLE);
  constant ANY     : std_logic_vector( 2 downto 0 ) := "000";
  constant EQ      : std_logic_vector( 2 downto 0 ) := "001";
  constant LESS    : std_logic_vector( 2 downto 0 ) := "010";
  constant GREATER : std_logic_vector( 2 downto 0 ) := "011";
  
  signal currentState          : STATE_TYPE;
  signal validSampleReg        : std_logic_vector( 1 downto 0 );
  signal writeAddress          : unsigned( 8 downto 0 );
  signal resetCounter          : unsigned( 8 downto 0 );
  signal endCounter            : unsigned( 8 downto 0 );
  signal tappedWiresReg        : std_logic_vector( 63 downto 0 );
  signal tappedWiresDelayedReg : std_logic_vector( 63 downto 0 );
  signal trigShift             : std_logic_vector( 9 downto 0 );
  signal trigFound             : std_logic;
  signal ramWriteAddress       : std_logic_vector( 8 downto 0 );
  signal ramWriteEnable        : std_logic;

begin
  -- here we define some control signals
  ramWriteAddress <= std_logic_vector(resetCounter) when currentState = RESET else std_logic_vector(writeAddress);
  ramWriteEnable  <= '1' when currentState = RESET else validSampleReg(1);
  
  -- to not influence the tapped wires, we first latch them
  makeSamples : process ( CLK_I ) is
  begin
    if (RST_I = '1' or resetCore = '1') then
      tappedWiresReg        <= (others => '0');
      tappedWiresDelayedReg <= (others => '0');
      validSampleReg        <= (others => '0');
    elsif (currentState = ACTIVE or currentState = FINISH) then
      tappedWiresReg        <= tappedWires;
      tappedWiresDelayedReg <= tappedWiresReg;
      validSampleReg        <= validSampleReg(0)&'1';
    else
      tappedWiresReg        <= (others => '0');
      tappedWiresDelayedReg <= tappedWiresReg;
      validSampleReg        <= validSampleReg(0)&'0';
    end if;
  end process makeSamples;

  -- here we define the trigger
  makeTrigger : process ( seqLen, trigShift ) is
  begin
    case (seqLen) is
      when "01"   => trigFound <= trigShift(2) and trigShift(1);
      when "10"   => trigFound <= trigShift(5) and trigShift(4) and trigShift(3);
      when "11"   => trigFound <= trigShift(9) and trigShift(8) and trigShift(7) and trigShift(6);
      when others => trigFound <= trigShift(0);
    end case;
  end process makeTrigger;

  -- here we define the trigShift
  makeTrigShift : process ( CLK_I ) is
  begin
    if (rising_edge( CLK_I )) then
      if (RST_I = '1' or resetCore = '1') then
        trigShift <= (others => '0');
      elsif (currentState = ACTIVE) then
        case (comparator0) is
          when EQ      => if ( (tappedWiresReg and mask0) = reference0) then trigShift(0) <= '1';
                                                                        else trigShift(0) <= '0';
                          end if;
          when LESS    => if ( unsigned(tappedWiresReg and mask0) < unsigned(reference0)) then trigShift(0) <= '1';
                                                                                          else trigShift(0) <= '0';
                          end if;
          when GREATER => if ( unsigned(tappedWiresReg and mask0) > unsigned(reference0)) then trigShift(0) <= '1';
                                                                                          else trigShift(0) <= '0';
                          end if;
          when others  => trigShift(0) <= '1';
        end case;
        case (comparator1) is
          when EQ      => if ( (tappedWiresReg and mask1) = reference1) then trigShift(2) <= '1';
                                                                        else trigShift(2) <= '0';
                          end if;
          when LESS    => if ( unsigned(tappedWiresReg and mask1) < unsigned(reference1)) then trigShift(2) <= '1';
                                                                                          else trigShift(2) <= '0';
                          end if;
          when GREATER => if ( unsigned(tappedWiresReg and mask1) > unsigned(reference1)) then trigShift(2) <= '1';
                                                                                          else trigShift(2) <= '0';
                          end if;
          when others  => trigShift(2) <= '1';
        end case;
        case (comparator2) is
          when EQ      => if ( (tappedWiresReg and mask2) = reference2) then trigShift(5) <= '1';
                                                                        else trigShift(5) <= '0';
                          end if;
          when LESS    => if ( unsigned(tappedWiresReg and mask2) < unsigned(reference2)) then trigShift(5) <= '1';
                                                                                          else trigShift(5) <= '0';
                          end if;
          when GREATER => if ( unsigned(tappedWiresReg and mask2) > unsigned(reference2)) then trigShift(5) <= '1';
                                                                                          else trigShift(5) <= '0';
                          end if;
          when others  => trigShift(5) <= '1';
        end case;
        case (comparator3) is
          when EQ      => if ( (tappedWiresReg and mask3) = reference3) then trigShift(9) <= '1';
                                                                        else trigShift(9) <= '0';
                          end if;
          when LESS    => if ( unsigned(tappedWiresReg and mask3) < unsigned(reference3)) then trigShift(9) <= '1';
                                                                                          else trigShift(9) <= '0';
                          end if;
          when GREATER => if ( unsigned(tappedWiresReg and mask3) > unsigned(reference3)) then trigShift(9) <= '1';
                                                                                          else trigShift(9) <= '0';
                          end if;
          when others  => trigShift(9) <= '1';
        end case;
        trigShift(1) <= trigShift(0);
        trigShift(3) <= trigShift(1);
        trigShift(4) <= trigShift(2);
        trigShift(6) <= trigShift(3);
        trigShift(7) <= trigShift(4);
        trigShift(8) <= trigShift(5);
      end if;
    end if;
  end process makeTrigShift;

  -- here we define the reset counter used to clear the memory
  makeResetCounter : process ( CLK_I ) is
  begin
    if (rising_edge(CLK_I)) then
      if (RST_I = '1' or resetCore = '1') then resetCounter <= (others => '0');
      elsif (resetCounter /= to_unsigned(0, 9)) then resetCounter <= resetCounter - to_unsigned(1, 9);
      end if;
    end if;
  end process makeResetCounter;
  
  -- here we define the writeCounter
  makeWriteCounter : process ( CLK_I ) is
  begin
    if (rising_edge(CLK_I)) then
      if (RST_I = '1') then writeAddress <= (others => '0');
      elsif (validSampleReg(1) = '1') then writeAddress <= writeAddress + to_unsigned(1, 9);
      end if;
    end if;
  end process makeWriteCounter;
  
  -- here we define the startAddress
  makeStartAddress : process ( CLK_I ) is
  begin
    if (rising_edge(CLK_I)) then
      if (RST_I = '1') then startAddress <= (others => '0');
      elsif (currentState = ACTIVE and trigFound = '1') then
        startAddress <= std_logic_vector(writeAddress + endCounter + to_unsigned(2 , 9));
      end if;
    end if;
  end process makeStartAddress;
  
  -- here we define the endCounter
  makeEndCounter : process ( CLK_I ) is
  begin
    if (rising_edge(CLK_I)) then
      if (resetCore = '1') then endCounter <= unsigned(postTrigSamples);
      elsif (currentState = FINISH and endCounter /= to_unsigned(0, 9)) then
        endCounter <= endCounter - to_unsigned(1, 9);
      end if;
    end if;
  end process makeEndCounter;
  
  -- here we define the state machine
  makeStates : process ( CLK_I ) is
  begin
    if (rising_edge(CLK_I)) then
      if (RST_I = '1') then currentState <= IDLE;
                       else
        case (currentState) is
          when IDLE    => if (resetCore = '1') then currentState <= RESET;
                                              else currentState <= IDLE;
                          end if;
          when RESET   => if (resetCounter = to_unsigned(0, 9)) then currentState <= ACTIVE;
                                                                else currentState <= RESET;
                          end if;
          when ACTIVE  => if (trigFound = '0') then currentState <= ACTIVE;
                          elsif (endCounter = to_unsigned(0, 9)) then currentState <= IDLE;
                                                                 else currentState <= FINISH;
                         end if;
          when others  => if (endCounter = to_unsigned(0, 9)) then currentState <= IDLE;
                                                              else currentState <= FINISH;
                          end if;
        end case;
      end if;
    end if;
  end process makeStates;
  
  done <= '1' when (currentState = IDLE and validSampleReg = "00") else '0';
  
  -- here we map the two ram components
  sramLow : entity work.ssramPseudoDual(noPlatformSpecific)
    generic map ( BITWIDTH => 32,
                  NR_ENTRIES => 512 )
    port map ( clock        => CLK_I,
               writeEnable  => ramWriteEnable,
               writeAddress => ramWriteAddress,
               writeData    => tappedWiresDelayedReg( 31 downto 0 ),
               readAddress  => readAddress,
               readData     => dataLow);

  sramHigh : entity work.ssramPseudoDual(noPlatformSpecific)
    generic map ( BITWIDTH => 32,
                  NR_ENTRIES => 512 )
    port map ( clock        => CLK_I,
               writeEnable  => ramWriteEnable,
               writeAddress => ramWriteAddress,
               writeData    => tappedWiresDelayedReg( 63 downto 32 ),
               readAddress  => readAddress,
               readData     => dataHigh);

end architecture platformIndependant;
