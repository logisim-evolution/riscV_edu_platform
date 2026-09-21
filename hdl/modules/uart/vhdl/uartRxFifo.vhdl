library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uartRxFifo is
  port( clock          : in  std_logic;
        reset          : in  std_logic;
        fifoRe         : in  std_logic;
        fifoWe         : in  std_logic;
        clearError     : in  std_logic;
        frameErrorIn   : in  std_logic;
        parityErrorIn  : in  std_logic;
        breakIn        : in  std_logic;
        fifoEmpty      : out std_logic;
        fifoFull       : out std_logic;
        dataIn         : in  std_logic_vector( 7 downto 0 );
        frameErrorOut  : out std_logic;
        parityErrorOut : out std_logic;
        breakOut       : out std_logic;
        fifoError      : out std_logic;
        nrOfEntries    : out std_logic_vector( 4 downto 0 );
        dataOut        : out std_logic_vector( 7 downto 0 ));
end entity uartRxFifo;

architecture platformIndependent of uartRxFifo is

  signal s_writeAddressReg, s_readAddressReg                                          : unsigned( 3 downto 0 );
  signal s_fifoFullReg, s_fifoEmptyReg                                                : std_logic;
  signal s_frameErrorReg, s_parityErrorReg, s_breakReg                                : std_logic_vector( 15 downto 0 );
  signal s_frameErrorNext, s_parityErrorNext, s_breakNext, s_clearError, s_writeError : std_logic_vector( 15 downto 0 );
  signal s_nrOfEntriesReg, s_nrOfEntriesNext                                          : unsigned( 4 downto 0 );
  signal s_fifoWe, s_fifoRe                                                           : std_logic;
  signal s_writeAddressNext, s_readAddressNext                                        : unsigned( 3 downto 0 );
  signal s_fifoEmptyNext, s_fifoFullNext                                              : std_logic;

begin

  s_fifoWe           <= (not(fifoRe) and fifoWe and not(s_fifoFullReg)) or (fifoRe and fifoWe);
  s_fifoRe           <= (fifoRe and not(fifoWe) and not(s_fifoEmptyReg)) or (fifoRe and fifoWe);
  s_writeAddressNext <= s_writeAddressReg + to_unsigned(1, 4);
  s_readAddressNext  <= s_readAddressReg + to_unsigned(1, 4);
  s_fifoFullNext     <= '0' when reset = '1' or (s_fifoRe = '1' and s_fifoWe = '0') else
                        '1' when s_fifoWe = '1' and s_fifoRe = '0' and s_writeAddressNext = s_readAddressReg else s_fifoFullReg;
  s_fifoEmptyNext    <= '1' when reset = '1' or (s_fifoRe = '1' and s_fifoWe = '0' and s_readAddressNext = s_writeAddressReg) else
                        '0' when s_fifoWe = '1' and s_fifoRe = '0' else s_fifoEmptyReg;
  s_nrOfEntriesNext  <= (others => '0') when reset = '1' else
                        s_nrOfEntriesReg + to_unsigned(1, 5) when s_fifoWe = '1' and s_fifoRe = '0' else
                        s_nrOfEntriesReg - to_unsigned(1, 5) when s_fifoWe = '0' and s_fifoRe = '1' else s_nrOfEntriesReg;
  fifoFull           <= s_fifoFullReg;
  fifoEmpty          <= s_fifoEmptyReg;
  frameErrorOut      <= s_frameErrorReg(to_integer(s_readAddressReg));
  parityErrorOut     <= s_parityErrorReg(to_integer(s_readAddressReg));
  breakOut           <= s_breakReg(to_integer(s_readAddressReg));
  nrOfEntries        <= std_logic_vector(s_nrOfEntriesReg);

  genbits : for n in 15 downto 0 generate
    s_clearError(n)      <= '1' when to_integer(s_readAddressReg) = n and
                                     ((s_fifoRe = '1' and s_fifoWe = '0') or
                                      (s_fifoRe = '1' and s_fifoWe = '1' and to_integer(s_writeAddressReg) /= n) or
                                      clearError = '1') else '0';
    s_writeError(n)      <= '1' when to_integer(s_writeAddressReg) = n and s_fifoWe = '1' else '0';
    s_frameErrorNext(n)  <= '0' when reset = '1' or s_clearError(n) = '1' else
                            frameErrorIn when s_writeError(n) = '1' else s_frameErrorReg(n);
    s_parityErrorNext(n) <= '0' when reset = '1' or s_clearError(n) = '1' else
                            parityErrorIn when s_writeError(n) = '1' else s_parityErrorReg(n);
    s_breakNext(n)       <= '0' when reset = '1' or s_clearError(n) = '1' else
                            breakIn when s_writeError(n) = '1' else s_breakReg(n);
  end generate genbits;
  
  makeflops : process( clock ) is
  begin
    if (rising_edge( clock )) then
      s_fifoFullReg     <= s_fifoFullNext;
      s_fifoEmptyReg    <= s_fifoEmptyNext;
      s_frameErrorReg   <= s_frameErrorNext;
      s_parityErrorReg  <= s_parityErrorNext;
      s_breakReg        <= s_breakNext;
      s_nrOfEntriesReg  <= s_nrOfEntriesNext;
      if (reset = '1') then s_writeAddressReg <= (others => '0');
      elsif (s_fifoWe = '1') then s_writeAddressReg <= s_writeAddressNext;
      end if;
      if (reset = '1') then s_readAddressReg <= (others => '0');
      elsif (s_fifoRe = '1') then s_readAddressReg <= s_readAddressNext;
      end if;
      if (s_frameErrorReg = X"0000" and s_parityErrorReg = X"0000" and s_breakReg = X"0000") then fifoError <= '0';
                                                                                             else fifoError <= '1';
      end if;
    end if;
  end process makeflops;
  
  mem : entity work.sramLutRam(platformIndependent)
      generic map ( nrOfAddressBits => 4,
                    nrOfDataBits    => 8)
      port map ( clock        => clock,
                 writeData    => dataIn,
                 writeAddress => s_writeAddressReg,
                 WriteEnable  => s_fifoWe,
                 readAddress  => s_readAddressReg,
                 readData     => dataOut);
end architecture platformIndependent;
