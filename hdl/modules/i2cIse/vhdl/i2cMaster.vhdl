library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.log2;
use ieee.math_real.ceil;

entity i2cMaster is
  generic( CLOCK_FREQUENCY : integer := 12000000;
           I2C_FREQUENCY   : integer := 1000000);
  port( clock      : in    std_logic;
        reset      : in    std_logic;
        startWrite : in    std_logic;
        startRead  : in    std_logic;
        address    : in    std_logic_vector( 6 downto 0 );
        regIn      : in    std_logic_vector( 7 downto 0 );
        dataIn     : in    std_logic_vector( 7 downto 0 );
        dataOut    : out   std_logic_vector( 7 downto 0 );
        ackError   : out   std_logic;
        busy       : out   std_logic;
        SCL        : out   std_logic;
        SDA        : inout std_logic);
end i2cMaster;

architecture plaformIndependant of i2cMaster is

  constant CLOCK_DIVIDER_VALUE : integer := (CLOCK_FREQUENCY)/(I2C_FREQUENCY*4);
  constant NR_OF_BITS : integer := integer(ceil(log2(real(CLOCK_DIVIDER_VALUE))));
  
  type stateType is (IDLE, SENDSTART, A6, A5, A4, A3, A2, A1, A0, ACK1, SENDSTOP,
                     R7, R6, R5, R4, R3, R2, R1, R0, ACK2, D7, D6, D5, D4, D3,
                     D2, D1, D0, ACK3, DIR);
  
  signal s_stateMachineReg, s_stateMachineNext   : stateType;
  signal s_isReadActionReg, s_isReadActionNext   : std_logic;
  signal s_actionPendingReg, s_actionPendingNext : std_logic;
  signal s_firstReadPassReg, s_firstReadPassNext : std_logic;
  signal s_divideCounterReg, s_divideCounterNext : unsigned(NR_OF_BITS-1 downto 0);
  signal s_divideCounterIsZero                   : std_logic;
  signal s_clockCountReg                         : unsigned( 1 downto 0 );
  signal s_ackErrorReg, s_ackErrorNext           : std_logic;
  signal s_sclReg, s_sclNext                     : std_logic;
  signal s_sdaReg, s_sdaNext                     : std_logic;
  signal s_dataOutReg, s_dataOutNext             : std_logic_vector( 7 downto 0 );
  signal s_clockData                             : std_logic;

begin
  -- here we define the action indication signals
  s_isReadActionNext  <= '0' when reset = '1' else
                         startRead when startWrite = '1' or startRead = '1' else
                         s_isReadActionReg;
  s_actionPendingNext <= '0' when reset = '1' or (s_stateMachineReg /= IDLE and 
                                  s_firstReadPassReg = '0') else
                         '1' when startWrite = '1' or startRead = '1' else
                         s_actionPendingReg;
  busy <= '0' when s_stateMachineReg = IDLE and s_actionPendingReg = '0' else '1';
  
  makeActionRegs : process ( clock ) is
  begin
    if (rising_edge( clock )) then
      s_isReadActionReg  <= s_isReadActionNext;
      s_actionPendingReg <= s_actionPendingNext;
    end if;
  end process makeActionRegs;
  
  -- here the tick-counter is defined
  s_divideCounterNext   <= to_unsigned(CLOCK_DIVIDER_VALUE - 1, NR_OF_BITS)
                             when s_divideCounterIsZero = '1' or reset = '1' else
                           s_divideCounterReg - to_unsigned(1, NR_OF_BITS);
  s_divideCounterIsZero <= '1' when s_divideCounterReg = to_unsigned(0,NR_OF_BITS) else '0';
  
  makeTickCounter : process ( clock ) is
  begin
    if (rising_edge( clock)) then
      s_divideCounterReg <= s_divideCounterNext;
    end if;
  end process makeTickCounter;
  
  -- here we define the state machine
  s_ackErrorNext <= '0' when reset = '1' else
                    SDA when (s_stateMachineReg = ACK1 or s_stateMachineReg = ACK2 or
                              (s_stateMachineReg = ACK3 and s_isReadActionReg = '0')) and
                             s_divideCounterIsZero = '1' and s_clockCountReg = "10" else
                    s_ackErrorReg;
  s_firstReadPassNext <= '0' when reset = '1' or
                                  (s_stateMachineReg = SENDSTOP and 
                                   s_clockCountReg = "00" and 
                                   s_divideCounterIsZero = '1') or
                                  ((s_stateMachineReg = ACK1 or
                                    s_stateMachineReg = ACK2) and
                                   s_ackErrorReg = '1' and 
                                   s_clockCountReg = "00" and 
                                   s_divideCounterIsZero = '1') else
                         '1' when startRead = '1' else s_firstReadPassReg;
  ackError <= s_ackErrorReg;
  
  makeNextState : process ( s_actionPendingReg, s_clockCountReg, s_ackErrorReg,
                            s_isReadActionReg, s_firstReadPassReg, s_stateMachineReg ) is
  begin
    case (s_stateMachineReg) is
      when IDLE      => if (s_actionPendingReg = '1' and s_clockCountReg = "00") then
                          s_stateMachineNext <= SENDSTART; 
                                                                                 else
                          s_stateMachineNext <= IDLE;
                        end if;
      when SENDSTART => s_stateMachineNext <= A6;
      when A6        => s_stateMachineNext <= A5;
      when A5        => s_stateMachineNext <= A4;
      when A4        => s_stateMachineNext <= A3;
      when A3        => s_stateMachineNext <= A2;
      when A2        => s_stateMachineNext <= A1;
      when A1        => s_stateMachineNext <= A0;
      when A0        => s_stateMachineNext <= DIR;
      when DIR       => s_stateMachineNext <= ACK1;
      when ACK1      => if (s_ackErrorReg = '1') then s_stateMachineNext <= SENDSTOP;
                        elsif (s_isReadActionReg = '0' and s_firstReadPassReg = '1') then
                          s_stateMachineNext <= R7;
                                                                                     else
                          s_stateMachineNext <= D7;
                        end if;
      when R7        => s_stateMachineNext <= R6;
      when R6        => s_stateMachineNext <= R5;
      when R5        => s_stateMachineNext <= R4;
      when R4        => s_stateMachineNext <= R3;
      when R3        => s_stateMachineNext <= R2;
      when R2        => s_stateMachineNext <= R1;
      when R1        => s_stateMachineNext <= R0;
      when R0        => s_stateMachineNext <= ACK2;
      when ACK2      => if (s_ackErrorReg = '1' or s_firstReadPassReg = '1') then
                          s_stateMachineNext <= SENDSTOP;
                                                                             else
                          s_stateMachineNext <= D7;
                        end if;
      when D7        => s_stateMachineNext <= D6;
      when D6        => s_stateMachineNext <= D5;
      when D5        => s_stateMachineNext <= D4;
      when D4        => s_stateMachineNext <= D3;
      when D3        => s_stateMachineNext <= D2;
      when D2        => s_stateMachineNext <= D1;
      when D1        => s_stateMachineNext <= D0;
      when D0        => s_stateMachineNext <= ACK3;
      when ACK3      => s_stateMachineNext <= SENDSTOP;
      when others    => s_stateMachineNext <= IDLE;
    end case;
  end process makeNextState;
  
  makeStateRegs : process ( clock ) is
  begin
    if (rising_edge( clock )) then
      s_ackErrorReg      <= s_ackErrorNext;
      s_firstReadPassReg <= s_firstReadPassNext;
      if (reset = '1') then 
        s_clockCountReg   <= "00";
        s_stateMachineReg <= IDLE;
                       else
        if (s_divideCounterIsZero = '1') then
          s_clockCountReg <= s_clockCountReg + to_unsigned(1, 2);
          if (s_clockCountReg = "00") then
            s_stateMachineReg <= s_stateMachineNext;
          end if;
        end if;
      end if;
    end if;
  end process makeStateRegs;
  
  -- here the SDA and SCL lines are defined
  s_sclNext <= '0' when (s_stateMachineReg = SENDSTART and s_clockCountReg = "00") or
                        (s_stateMachineReg = SENDSTOP and 
                         (s_clockCountReg = "01" or s_clockCountReg = "10")) or
                        (s_stateMachineReg /= IDLE and s_stateMachineReg /= SENDSTART and 
                         s_stateMachineReg /= SENDSTOP and 
                         (s_clockCountReg = "01" or s_clockCountReg = "00")) else '1';
  SDA <= '0' when s_sdaReg = '0' else 'Z';
  SCL <= s_sclReg;
  
  makeSda : process ( s_stateMachineReg, s_clockCountReg, address, s_isReadActionReg,
                      s_firstReadPassReg, regIn, dataIn ) is
  begin
    case (s_stateMachineReg) is
      when SENDSTART => if (s_clockCountReg = "01") then s_sdaNext <= '1';
                                                    else s_sdaNext <= '0';
                        end if;
      when A6        => s_sdaNext <= address(6);
      when A5        => s_sdaNext <= address(5);
      when A4        => s_sdaNext <= address(4);
      when A3        => s_sdaNext <= address(3);
      when A2        => s_sdaNext <= address(2);
      when A1        => s_sdaNext <= address(1);
      when A0        => s_sdaNext <= address(0);
      when DIR       => s_sdaNext <= s_isReadActionReg and not(s_firstReadPassReg);
      when R7        => s_sdaNext <= regIn(7);
      when R6        => s_sdaNext <= regIn(6);
      when R5        => s_sdaNext <= regIn(5);
      when R4        => s_sdaNext <= regIn(4);
      when R3        => s_sdaNext <= regIn(3);
      when R2        => s_sdaNext <= regIn(2);
      when R1        => s_sdaNext <= regIn(1);
      when R0        => s_sdaNext <= regIn(0);
      when D7        => s_sdaNext <= dataIn(7) or s_isReadActionReg;
      when D6        => s_sdaNext <= dataIn(6) or s_isReadActionReg;
      when D5        => s_sdaNext <= dataIn(5) or s_isReadActionReg;
      when D4        => s_sdaNext <= dataIn(4) or s_isReadActionReg;
      when D3        => s_sdaNext <= dataIn(3) or s_isReadActionReg;
      when D2        => s_sdaNext <= dataIn(2) or s_isReadActionReg;
      when D1        => s_sdaNext <= dataIn(1) or s_isReadActionReg;
      when D0        => s_sdaNext <= dataIn(0) or s_isReadActionReg;
      when SENDSTOP  => s_sdaNext <= '0';
      when others    => s_sdaNext <= '1';
    end case;
  end process makeSda;
  
  makeSdalRegs : process ( clock ) is
  begin
    if (rising_edge( clock )) then
      if (reset = '1') then s_sclReg <= '1';
                            s_sdaReg <= '1';
      elsif (s_divideCounterIsZero = '1') then s_sclReg <= s_sclNext;
                                               s_sdaReg <= s_sdaNext;
      end if;
    end if;
  end process makeSdalRegs;
  
  -- here the data out register is defined
  s_clockData <= '1' when s_divideCounterIsZero = '1' and s_clockCountReg = "10" else '0';
  s_dataOutNext(7) <= '0' when reset = '1' else
                      SDA when s_stateMachineReg = D7 and s_clockData = '1' else 
                      s_dataOutReg(7);
  s_dataOutNext(6) <= '0' when reset = '1' else
                      SDA when s_stateMachineReg = D6 and s_clockData = '1' else 
                      s_dataOutReg(6);
  s_dataOutNext(5) <= '0' when reset = '1' else
                      SDA when s_stateMachineReg = D5 and s_clockData = '1' else 
                      s_dataOutReg(5);
  s_dataOutNext(4) <= '0' when reset = '1' else
                      SDA when s_stateMachineReg = D4 and s_clockData = '1' else 
                      s_dataOutReg(4);
  s_dataOutNext(3) <= '0' when reset = '1' else
                      SDA when s_stateMachineReg = D3 and s_clockData = '1' else 
                      s_dataOutReg(3);
  s_dataOutNext(2) <= '0' when reset = '1' else
                      SDA when s_stateMachineReg = D2 and s_clockData = '1' else 
                      s_dataOutReg(2);
  s_dataOutNext(1) <= '0' when reset = '1' else
                      SDA when s_stateMachineReg = D1 and s_clockData = '1' else 
                      s_dataOutReg(1);
  s_dataOutNext(0) <= '0' when reset = '1' else
                      SDA when s_stateMachineReg = D0 and s_clockData = '1' else 
                      s_dataOutReg(0);
  dataOut          <= s_dataOutReg;
  
  makeDataOutReg : process ( clock ) is
  begin
    if (rising_edge( clock )) then
      s_dataOutReg <= s_dataOutNext;
    end if;
  end process makeDataOutReg;
end plaformIndependant;
