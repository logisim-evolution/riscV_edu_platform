library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uartBus is
  generic ( DataBits    : integer := 32;  -- must be 32 for this module
            AddrBits    : integer := 32;  -- must be > 4 for this module
            BaseAddress : std_logic_vector := std_logic_vector(to_unsigned(0,32)));
  port ( CLK_I      : in  std_logic;
         RST_I      : in  std_logic;
         DAT_I      : in  std_logic_vector( DataBits-1 downto 0 );
         DAT_O      : out std_logic_vector( DataBits-1 downto 0 );
         -- TAGD_I and TAGD_O are not implemented
         ACK_O      : out std_logic;
         ADDR_I     : in  std_logic_vector( AddrBits-1 downto 0 );
         CYC_I      : in  std_logic;
         ERR_O      : out std_logic;
         -- LOCK_I is not used in this module
         -- RTY_I is not implemented
         SEL_I      : in  std_logic_vector( (DataBits/8)-1 downto 0 );
         STB_I      : in  std_logic;
         -- TGA_O and TGC_O are not implemented
         WE_I       : in  std_logic;
         CTI_I      : in  std_logic_vector( 2 downto 0 );
         -- BTE_I is not used in this module
         
         -- here all external signals are defined
         clock50MHz : in  std_logic;
         irq        : out std_logic;
         RxD        : in  std_logic;
         TxD        : out std_logic);
end entity uartBus;

architecture platformIndependent of uartBus is

  signal s_ackReg, s_errorReg, s_weReg, s_reReg                                            : std_logic;
  signal s_indexReg                                                                        : std_logic_vector(2 downto 0);
  signal s_dataInReg                                                                       : std_logic_vector(31 downto 0);
  signal s_byteEnablesReg                                                                  : std_logic_vector(3 downto 0);
  signal s_divisorReg                                                                      : std_logic_vector(15 downto 0);
  signal s_lineControlReg, s_interruptEnableReg, s_scratchReg, s_modemControlReg           : std_logic_vector(7 downto 0);
  signal s_fifoControlReg                                                                  : std_logic_vector(7 downto 6);
  signal s_weRegsVector, s_TxFifoData, s_lineStatusReg, s_rxFifoData, s_receiverBufferReg  : std_logic_vector(7 downto 0);
  signal s_TxD, s_baudRateX16Tick, s_baudRateX2Tick, isMyTransaction, isCorrectTransaction : std_logic;
  signal s_TxFifoRe, s_TxFifoEmpty, s_TxFifoFull, s_TxBusy, s_TxFifoWe, s_resetTxFifo      : std_logic;
  signal s_rxFifoEmpty, s_rxFifoWe, s_clearError, s_frameError, s_parityError, s_rxFifoFull: std_logic;
  signal s_overrunError, s_break, s_lineStatus1Reg, s_resetRxFifo, s_uartRx, s_reRxFifo    : std_logic;
  signal s_rxNrOfEntries                                                                   : std_logic_vector(4 downto 0);
  signal s_lineStatusIrq, s_rxAvailableIrq, s_rxAvailableNext, s_txEmptyIrq, s_txEmptyNext : std_logic;
  signal s_interruptIdentReg                                                               : std_logic_vector(7 downto 0);
  signal s_txEmptyEdgeReg                                                                  : std_logic_vector(1 downto 0);

begin
  ERR_O               <= s_errorReg;
  ACK_O               <= s_ackReg;
  DAT_O(31 downto 24) <= s_scratchReg when s_indexReg(2) = '1' else s_lineControlReg;
  DAT_O(23 downto 16) <= X"00" when s_indexReg(2) = '1' else s_interruptIdentReg;
  DAT_O(15 downto  8) <= s_lineStatusReg when s_indexReg(2) = '1' else
                         s_interruptEnableReg when s_lineControlReg(7) = '0' else s_divisorReg(15 downto 8);
  DAT_O( 7 downto  0) <= s_modemControlReg when s_indexReg(2) = '1' else
                         s_receiverBufferReg when s_lineControlReg(7) = '0' else s_divisorReg(7 downto 0);
  TxD                 <= s_TxD or s_modemControlReg(4);
  isMyTransaction     <= CYC_I and STB_I when ADDR_I(AddrBits-1 downto 3) = BaseAddress(AddrBits-1 downto 3) else '0';
  isCorrectTransaction<= isMyTransaction when CTI_I = "000" else '0'; -- this module only supports classic transactions

  makeBusRegs : process (CLK_I) is
  begin
    if (rising_edge(CLK_I)) then
      if (RST_I = '1') then
        s_ackReg         <= '0';
        s_errorReg       <= '0';
        s_weReg          <= '0';
        s_reReg          <= '0';
        s_indexReg       <= (others => '0');
        s_dataInReg      <= (others => '0');
        s_byteEnablesReg <= (others => '0');
                       else
        s_ackReg         <= not(s_ackReg) and isCorrectTransaction;
        s_errorReg       <= not(s_errorReg) and isMyTransaction and not(isCorrectTransaction);
        s_weReg          <= not(s_ackReg) and isCorrectTransaction and WE_I;
        s_reReg          <= not(s_ackReg) and isCorrectTransaction and not(WE_I);
        if (s_ackReg = '0' and isCorrectTransaction = '1') then
          s_indexReg       <= ADDR_I(2 downto 0);
          s_dataInReg      <= DAT_I;
          s_byteEnablesReg <= SEL_I;
        end if;
      end if;
    end if;
  end process makeBusRegs;

  -- here the uart registers are defined
  genWeVector : for n in 3 downto 0 generate
    s_weRegsVector(n)   <= not(s_indexReg(2)) and s_weReg and s_byteEnablesReg(n);
    s_weRegsVector(n+4) <= s_indexReg(2) and s_weReg and s_byteEnablesReg(n);
  end generate genWeVector;
  
  makeUartRegs : process (CLK_I) is
  begin
    if (rising_edge(CLK_I)) then
      if (RST_I = '1') then
        s_divisorReg         <= (others => '0');
        s_lineControlReg     <= (others => '0');
        s_interruptEnableReg <= (others => '0');
        s_scratchReg         <= (others => '0');
        s_modemControlReg    <= (others => '0');
        s_fifoControlReg     <= (others => '0');
                       else
        if (s_weRegsVector(0) = '1' and s_lineControlReg(7) = '1') then
          s_divisorReg(7 downto 0) <= s_dataInReg(7 downto 0);
        end if;
        if (s_weRegsVector(1) = '1') then
          if (s_lineControlReg(7) = '1') then
            s_divisorReg(15 downto 8) <= s_dataInReg(15 downto 8);
                                         else
            s_interruptEnableReg      <= "000000"&s_dataInReg(9 downto 8);
          end if;
        end if;
        if (s_weRegsVector(2) = '1') then
          s_fifoControlReg <= s_dataInReg(23 downto 22);
        end if;
        if (s_weRegsVector(3) = '1') then
          s_lineControlReg <= s_dataInReg(31 downto 24);
        end if;
        if (s_weRegsVector(4) = '1') then
          s_modemControlReg <= "000"&s_dataInReg(4)&X"0";
        end if;
        if (s_weRegsVector(7) = '1') then
          s_scratchReg <= s_dataInReg(31 downto 24);
        end if;
      end if;
    end if;
  end process makeUartRegs;
  
  -- here the baud rate generator is defined
  bdg : entity work.baudGenerator(behav)
     port map( clock           => CLK_I,
               clock_50MHz     => clock50MHz,
               reset           => RST_I,
               baudDivisor     => s_divisorReg,
               baudRateX16Tick => s_baudRateX16Tick,
               baudRateX2Tick  => s_baudRateX2Tick);

  -- here the tx path is defined
  s_TxFifoWe    <= not(s_TxFifoFull) and s_weRegsVector(0) and not(s_lineControlReg(7));
  s_resetTxFifo <= RST_I or (s_weRegsVector(2) and s_dataInReg(18));
  
  TXF : entity work.uartTxFifo(platformIndependent)
    port map ( reset     => s_resetTxFifo,
               clock     => CLK_I,
               fifoRe    => s_TxFifoRe,
               fifoWe    => s_TxFifoWe,
               fifoFull  => s_TxFifoFull,
               fifoEmpty => s_TxFifoEmpty,
               dataIn    => s_dataInReg( 7 downto 0 ),
               dataOut   => s_TxFifoData);

  TXC : entity work.uartTx(platformIndependent)
    port map ( clock           => CLK_I,
               reset           => RST_I,
               baudRateX2tick  => s_baudRateX2Tick,
               controlReg      => s_lineControlReg(6 downto 0),
               fifoData        => s_TxFifoData,
               fifoEmpty       => s_TxFifoEmpty,
               fifoReadAck     => s_TxFifoRe,
               uartTxLine      => s_TxD,
               busy            => s_TxBusy);

  -- Here the Rx path is defined
  s_resetRxFifo      <= RST_I or (s_weRegsVector(2) and s_dataInReg(17));
  s_uartRx           <= s_TxD when s_modemControlReg(4) = '1' else RxD;
  s_reRxFifo         <= s_reReg and not(s_indexReg(2)) and s_byteEnablesReg(0);
  s_lineStatusReg(0) <= not(s_rxFifoEmpty);
  s_lineStatusReg(1) <= s_lineStatus1Reg;
  s_lineStatusReg(5) <= s_TxFifoEmpty;
  s_lineStatusReg(6) <= s_TxFifoEmpty and not(s_TxBusy);
  
  makeLineStat1 : process (CLK_I) is
  begin
    if (rising_edge(CLK_I)) then
      if (s_clearError = '1' or s_resetRxFifo = '1') then s_lineStatus1Reg <= '0';
                                                     else s_lineStatus1Reg <= s_lineStatus1Reg or s_overrunError;
      end if;
    end if;
  end process makeLineStat1;

  RXF : entity work.uartRxFifo(platformIndependent)
    port map ( clock          => CLK_I,
               reset          => s_resetRxFifo,
               fifoRe         => s_reRxFifo,
               fifoWe         => s_rxFifoWe,
               clearError     => s_clearError,
               frameErrorIn   => s_frameError,
               parityErrorIn  => s_parityError,
               breakIn        => s_break,
               fifoEmpty      => s_rxFifoEmpty,
               fifoFull       => s_rxFifoFull,
               dataIn         => s_rxFifoData,
               frameErrorOut  => s_lineStatusReg(3),
               parityErrorOut => s_lineStatusReg(2),
               breakOut       => s_lineStatusReg(4),
               fifoError      => s_lineStatusReg(7),
               nrOfEntries    => s_rxNrOfEntries,
               dataOut        => s_receiverBufferReg);

  RXC : entity work.uartRx(platformindependent)
    port map ( clock           => CLK_I,
               reset           => RST_I,
               baudRateX16Tick => s_baudRateX16Tick,
               uartRxLine      => s_uartRx,
               fifoFull        => s_rxFifoFull,
               controlReg      => s_lineControlReg( 5 downto 0 ),
               fifoData        => s_rxFifoData,
               fifoWe          => s_rxFifoWe,
               frameError      => s_frameError,
               breakDetected   => s_break,
               parityError     => s_parityError,
               overrunError    => s_overrunError);

  -- here the irq's are defined
  s_txEmptyNext <= '0' when RST_I = '1' or s_TxFifoWe = '1' or
                            (s_reReg = '1' and s_indexReg(2) = '0' and s_byteEnablesReg(2) = '1' and
                             s_rxAvailableIrq = '0' and s_lineStatusIrq = '0') else
                   '1' when s_txEmptyEdgeReg = "01" else s_txEmptyIrq;
  s_interruptIdentReg(7 downto 3) <= "11000";
  s_interruptIdentReg(2)          <= s_lineStatusIrq or s_rxAvailableIrq;
  s_interruptIdentReg(1)          <= s_lineStatusIrq or s_txEmptyIrq;
  s_interruptIdentReg(0)          <= not(s_lineStatusIrq or s_rxAvailableIrq or s_txEmptyIrq);
  irq                             <= s_lineStatusIrq or s_rxAvailableIrq or s_txEmptyIrq;
  s_clearError                    <= s_reReg and s_indexReg(2) and s_byteEnablesReg(1);
  
  makeLineStatusIrq : process (CLK_I) is
  begin
    if (rising_edge(CLK_I)) then
      if (RST_I = '1' or s_clearError = '1') then
        s_lineStatusIrq <= '0';
                                             else
        s_lineStatusIrq <= (s_lineStatusIrq or s_lineStatusReg(4) or s_lineStatusReg(3) or s_lineStatusReg(2) or s_lineStatusReg(1)) and s_interruptEnableReg(2);
      end if;
    end if;
  end process makeLineStatusIrq;
  
  makeIrqs : process (CLK_I) is
  begin
    if (rising_edge(CLK_I)) then
      s_txEmptyIrq     <= s_txEmptyNext;
      if (RST_I = '1') then
        s_rxAvailableIrq <= '0';
        s_txEmptyEdgeReg <= "00";
                       else
        s_rxAvailableIrq <= s_rxAvailableNext and s_interruptEnableReg(0);
        s_txEmptyEdgeReg <= s_txEmptyEdgeReg(0)&s_lineStatusReg(6);
      end if;
    end if;
  end process makeIrqs;
  
  makeRxAvailable : process ( s_fifoControlReg, s_rxNrOfEntries ) is
  begin
    case (s_fifoControlReg) is
      when "00"   => s_rxAvailableNext <= s_rxNrOfEntries(4) or s_rxNrOfEntries(3) or s_rxNrOfEntries(2) or s_rxNrOfEntries(1) or s_rxNrOfEntries(0);
      when "01"   => s_rxAvailableNext <= s_rxNrOfEntries(4) or s_rxNrOfEntries(3) or s_rxNrOfEntries(2);
      when "10"   => s_rxAvailableNext <= s_rxNrOfEntries(4) or s_rxNrOfEntries(3);
      when others => if (s_rxNrOfEntries(4) = '1' or s_rxNrOfEntries(4 downto 1) = X"7") then s_rxAvailableNext <= '1';
                                                                                         else s_rxAvailableNext <= '0';
                     end if;
    end case;
  end process makeRxAvailable;

end architecture platformIndependent;
