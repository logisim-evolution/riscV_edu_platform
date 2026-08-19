library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity leds is
  generic ( DataBits    : integer := 32;  -- must be 32 for this module
            AddrBits    : integer := 32;  -- must be > 11 for this module
            BaseAddress : std_logic_vector := std_logic_vector(to_unsigned(0,32)));
  port ( CLK_I     : in  std_logic;
         RST_I     : in  std_logic;
         DAT_I     : in  std_logic_vector( DataBits-1 downto 0 );
         DAT_O     : out std_logic_vector( DataBits-1 downto 0 );
         -- TAGD_I and TAGD_O are not implemented
         ACK_O     : out std_logic;
         ADDR_I    : in  std_logic_vector( AddrBits-1 downto 0 );
         CYC_I     : in  std_logic;
         ERR_O     : out std_logic;
         -- LOCK_I is not used in this module
         -- RTY_I is not implemented
         SEL_I     : in  std_logic_vector( (DataBits/8)-1 downto 0 );
         STB_I     : in  std_logic;
         -- TGA_O and TGC_O are not implemented
         WE_I      : in  std_logic;
         CTI_I     : in  std_logic_vector( 2 downto 0 ); -- Registered feedback
         -- BTE_I is not used in this module
         
         -- here the external signals are defined
         oneKhzTick : in  std_logic;
         rgbRow     : out std_logic_vector( 3 downto 0 );
         nRed       : out std_logic_vector( 9 downto 0 );
         nGreen     : out std_logic_vector( 9 downto 0 );
         nBlue      : out std_logic_vector( 9 downto 0 )); 
end entity leds;

architecture platformIndependent of leds is

  type LED_TYPE is array( 127 downto 0 ) of std_logic_vector( 2 downto 0 );
  type LINE_TYPE is array( 11 downto 0 ) of std_logic_vector( 11 downto 0 );

  signal ackReg               : std_logic;
  signal errorReg             : std_logic;
  signal weReg                : std_logic;
  signal baseAddressReg       : std_logic_vector( 31 downto 0 );
  signal indexReg             : std_logic_vector( 8 downto 0 );
  signal dataInReg            : std_logic_vector( 31 downto 0 );
  signal s_ledsReg            : LED_TYPE;
  signal s_ledsNext           : LED_TYPE;
  signal s_rowSelectReg       : unsigned( 3 downto 0 );
  signal s_weRed              : std_logic_vector( 127 downto 0 );
  signal s_weGreen            : std_logic_vector( 127 downto 0 );
  signal s_weBlue             : std_logic_vector( 127 downto 0 );
  signal s_selectedLine       : LINE_TYPE;
  signal s_pixelBased         : std_logic;
  signal s_pixelIndex         : unsigned( 7 downto 0 );
  signal isMyTransaction      : std_logic;
  signal isCorrectTransaction : std_logic;

begin
  -- here the bus signals are defined
  isMyTransaction      <= CYC_I and STB_I when ADDR_I( AddrBits - 1 downto 0 ) = baseAddressReg( AddrBits - 1 downto 0 ) else '0';
  isCorrectTransaction <= isMyTransaction when CTI_I = "000" and SEL_I = X"F" else '0';
  s_pixelBased         <= indexReg(8);
  s_pixelIndex         <= unsigned(indexReg( 7 downto 0 ));
  ACK_O                <= ackReg;
  ERR_O                <= errorReg;
  DAT_O                <= baseAddressReg when indexReg = "111111111" else
                          X"0000000"&"0"&s_ledsReg(to_integer(s_pixelIndex( 6 downto 0 ))) when s_pixelBased = '1' else
                          X"00000"&s_selectedLine(to_integer(s_pixelIndex( 5 downto 2 )));
  
  makeBusRegs : process ( CLK_I ) is
  begin
    if (rising_edge( CLK_I )) then
      if (RST_I = '1') then
        ackReg         <= '0';
        errorReg       <= '0';
        weReg          <= '0';
        indexReg       <= (others => '0');
        dataInReg      <= (others => '0');
        baseAddressReg <= BaseAddress;
                       else
        ackReg         <= not(ackReg) and isCorrectTransaction;
        errorReg       <= not(errorReg) and isMyTransaction and not(isCorrectTransaction);
        weReg          <= not(ackReg) and isCorrectTransaction and WE_I;
        if (ackReg = '0' and isCorrectTransaction = '1') then
          indexReg  <= ADDR_I( 10 downto 2 );
          dataInReg <= DAT_I;
        end if;
        if (weReg = '1' and indexReg = "111111111") then
          baseAddressReg <= dataInReg;
        end if;
      end if;
    end if;
  end process makeBusRegs;
  
  -- here the led functionality is defined
  genleds : for n in 127 downto 0 generate
    s_selectedLine(n/12)(n mod 12) <= s_ledsReg(n)(0) when s_pixelIndex(1 downto 0) = "00" else
                                      s_ledsReg(n)(1) when s_pixelIndex(1 downto 0) = "01" else
                                      s_ledsReg(n)(2) when s_pixelIndex(1 downto 0) = "10" else
                                      s_ledsReg(n)(0) and s_ledsReg(n)(1) and s_ledsReg(n)(2);
    s_ledsNext(n)(0)               <= dataInReg(0) when s_pixelBased = '1' else
                                      dataInReg(11 - (n mod 12)) when s_pixelIndex(7 downto 6) = "00" else
                                      dataInReg(11 - (n mod 12)) or s_ledsReg(n)(0) when s_pixelIndex(7 downto 6) = "01" else
                                      not(dataInReg(11 - (n mod 12))) and s_ledsReg(n)(0) when s_pixelIndex(7 downto 6) = "10" else
                                      dataInReg(11 - (n mod 12)) xor s_ledsReg(n)(0);
    s_ledsNext(n)(1)               <= dataInReg(1) when s_pixelBased = '1' else
                                      dataInReg(11 - (n mod 12)) when s_pixelIndex(7 downto 6) = "00" else
                                      dataInReg(11 - (n mod 12)) or s_ledsReg(n)(1) when s_pixelIndex(7 downto 6) = "01" else
                                      not(dataInReg(11 - (n mod 12))) and s_ledsReg(n)(1) when s_pixelIndex(7 downto 6) = "10" else
                                      dataInReg(11 - (n mod 12)) xor s_ledsReg(n)(1);
    s_ledsNext(n)(2)               <= dataInReg(2) when s_pixelBased = '1' else
                                      dataInReg(11 - (n mod 12)) when s_pixelIndex(7 downto 6) = "00" else
                                      dataInReg(11 - (n mod 12)) or s_ledsReg(n)(2) when s_pixelIndex(7 downto 6) = "01" else
                                      not(dataInReg(11 - (n mod 12))) and s_ledsReg(n)(2) when s_pixelIndex(7 downto 6) = "10" else
                                      dataInReg(11 - (n mod 12)) xor s_ledsReg(n)(2);
    s_weRed(n)                     <= weReg when (s_pixelBased = '1' and to_integer(s_pixelIndex(6 downto 0)) = n) or
                                                 (s_pixelBased = '0' and to_integer(s_pixelIndex(5 downto 2)) = n/12 and
                                                  (s_pixelIndex(1 downto 0) = "10" or s_pixelIndex(1 downto 0) = "11")) else '0';
    s_weGreen(n)                   <= weReg when (s_pixelBased = '1' and to_integer(s_pixelIndex(6 downto 0)) = n) or
                                                 (s_pixelBased = '0' and to_integer(s_pixelIndex(5 downto 2)) = n/12 and
                                                  (s_pixelIndex(1 downto 0) = "01" or s_pixelIndex(1 downto 0) = "11")) else '0';
    s_weBlue(n)                    <= weReg when (s_pixelBased = '1' and to_integer(s_pixelIndex(6 downto 0)) = n) or
                                                 (s_pixelBased = '0' and to_integer(s_pixelIndex(5 downto 2)) = n/12 and
                                                  (s_pixelIndex(1 downto 0) = "00" or s_pixelIndex(1 downto 0) = "11")) else '0';
    ledRegs : process ( CLK_I ) is
    begin
      if (rising_edge(CLK_I)) then
        if (RST_I = '1') then
          s_ledsReg(n) <= "000";
        else
          if (s_weBlue(n) = '1') then s_ledsReg(n)(0) <= s_ledsNext(n)(0);
          end if;
          if (s_weGreen(n) = '1') then s_ledsReg(n)(1) <= s_ledsNext(n)(1);
          end if;
          if (s_weRed(n) = '1') then s_ledsReg(n)(2) <= s_ledsNext(n)(2);
          end if;
        end if;
      end if;
    end process ledRegs;
  end generate genleds;

  genColors : for n in 9 downto 0 generate
    genRegs : process( CLK_I ) is
    begin
      if (rising_edge(CLK_I)) then
        nRed(n)   <= not (s_ledsReg(n*12+to_integer(s_rowSelectReg))(2));
        nGreen(n) <= not (s_ledsReg(n*12+to_integer(s_rowSelectReg))(1));
        nBlue(n)  <= not (s_ledsReg(n*12+to_integer(s_rowSelectReg))(0));
      end if;
    end process genRegs;
  end generate genColors;
  
  genRowSel : process (CLK_I) is
  begin
    if (rising_edge(CLK_I)) then
      if (RST_I = '1' or (s_rowSelectReg = to_unsigned(0, 4) and oneKhzTick = '1')) then
        s_rowSelectReg <= to_unsigned(11, 4);
      elsif (oneKhzTick = '1') then
        s_rowSelectReg <= s_rowSelectReg - to_unsigned(1, 4);
      end if;
    end if;
  end process genRowSel;
  
  rgbRow <= std_logic_vector( s_rowSelectReg );
end architecture platformIndependent;
