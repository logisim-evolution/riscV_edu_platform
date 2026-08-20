library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sevenSegments is
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

         -- here the external signals are defined
         oneKhzTick    : in  std_logic;
         displaySelect : out std_logic_vector( 2 downto 0 );
         nSegments     : out std_logic_vector( 7 downto 0 )); 
end entity sevenSegments;

architecture platformIndependant of sevenSegments is

  signal ackReg               : std_logic;
  signal errorReg             : std_logic;
  signal weReg                : std_logic;
  signal baseAddressReg       : std_logic_vector( 31 downto 0 );
  signal dataInReg            : std_logic_vector( 31 downto 0 );
  signal indexReg             : std_logic_vector( 2 downto 0 );
  signal s_displ1Reg          : std_logic_vector( 7 downto 0 );
  signal s_displ2Reg          : std_logic_vector( 7 downto 0 );
  signal s_displ3Reg          : std_logic_vector( 7 downto 0 );
  signal s_displ4Reg          : std_logic_vector( 7 downto 0 );
  signal s_displ1Next         : std_logic_vector( 7 downto 0 );
  signal s_displ2Next         : std_logic_vector( 7 downto 0 );
  signal s_displ3Next         : std_logic_vector( 7 downto 0 );
  signal s_displ4Next         : std_logic_vector( 7 downto 0 );
  signal s_scanReg            : unsigned( 2 downto 0 );
  signal s_selectedSegment    : std_logic_vector( 7 downto 0 );
  signal isMyTransaction      : std_logic;
  signal isCorrectTransaction : std_logic;

begin
  -- Here the bus signals are defined
  isMyTransaction      <= CYC_I and STB_I when ADDR_I(AddrBits-1 downto 5) = baseAddressReg(AddrBits-1 downto 5) else '0';
  isCorrectTransaction <= isMyTransaction when CTI_I = "000" and SEL_I = X"F" else '0'; -- this module only supports clasic word transfers
  ERR_O                <= errorReg;
  ACK_O                <= ackReg;
  
  busRegs : process ( CLK_I ) is
  begin
    if (rising_edge( CLK_I)) then
      if (RST_I = '1') then
        baseAddressReg <= BaseAddress;
        ackReg         <= '0';
        errorReg       <= '0';
        weReg          <= '0';
        indexReg       <= (others => '0');
        dataInReg      <= (others => '0');
      else
        ackReg   <= not( ackReg ) and isCorrectTransaction;
        errorReg <= not( errorReg ) and isMyTransaction and not( isCorrectTransaction );
        weReg    <= not( ackReg ) and isCorrectTransaction and WE_I;
        if (ackReg = '0' and isCorrectTransaction = '1') then
          indexReg  <= ADDR_I( 4 downto 2 );
          dataInReg <= DAT_I;
        end if;
        if (weReg = '1' and indexReg = "111") then
          baseAddressReg <= dataInReg;
        end if;
      end if;
    end if;
  end process busRegs;
  
  makebusOut : process ( indexReg, baseAddressReg, s_displ1Reg, s_displ2Reg, s_displ3Reg, s_displ4Reg ) is
  begin
    case (indexReg) is
      when "111"  => DAT_O <= baseAddressReg;
      when "000" |
           "100"  => DAT_O <= X"000000"&s_displ1Reg;
      when "001" |
           "101"  => DAT_O <= X"000000"&s_displ2Reg;
      when "010" |
           "110"  => DAT_O <= X"000000"&s_displ3Reg;
      when others => DAT_O <= X"000000"&s_displ4Reg;
    end case;
  end process makebusOut;
  
  -- here we define the segments
  displaySelect <= std_logic_vector( s_scanReg );
  nSegments     <= not( s_selectedSegment );
  
  seg1 : entity work.sevenSegmentUpdate(platformIndependant)
    generic map ( segmentId => 0 )
    port map ( currentValue   => s_displ1Reg,
               dataIn         => dataInReg,
               functionSelect => indexReg,
               newValue       => s_displ1Next );

  seg2 : entity work.sevenSegmentUpdate(platformIndependant)
    generic map ( segmentId => 1 )
    port map ( currentValue   => s_displ2Reg,
               dataIn         => dataInReg,
               functionSelect => indexReg,
               newValue       => s_displ2Next );

  seg3 : entity work.sevenSegmentUpdate(platformIndependant)
    generic map ( segmentId => 2 )
    port map ( currentValue   => s_displ3Reg,
               dataIn         => dataInReg,
               functionSelect => indexReg,
               newValue       => s_displ3Next );

  seg4 : entity work.sevenSegmentUpdate(platformIndependant)
    generic map ( segmentId => 3 )
    port map ( currentValue   => s_displ4Reg,
               dataIn         => dataInReg,
               functionSelect => indexReg,
               newValue       => s_displ4Next );

  makeSegRegs : process ( CLK_I ) is
  begin
    if (rising_edge( CLK_I )) then
      if (RST_I = '1') then
        s_displ1Reg <= (others => '0');
        s_displ2Reg <= (others => '0');
        s_displ3Reg <= (others => '0');
        s_displ4Reg <= (others => '0');
      elsif (weReg = '1') then
        s_displ1Reg <= s_displ1Next;
        s_displ2Reg <= s_displ2Next;
        s_displ3Reg <= s_displ3Next;
        s_displ4Reg <= s_displ4Next;
      end if;
    end if;
  end process makeSegRegs;
  
  makeScanReg : process ( CLK_I ) is
  begin
    if (rising_edge( CLK_I )) then
      if (RST_I = '1' or (s_scanReg = to_unsigned(0, 3) and oneKhzTick = '1')) then
        s_scanReg <= to_unsigned(4, 3);
      elsif (oneKhzTick = '1') then
        s_scanReg <= s_scanReg - to_unsigned(1, 3);
      end if;
    end if;
  end process makeScanReg;
  
  makeSelectedSegs : process( s_scanReg, s_displ1Reg, s_displ2Reg, s_displ3Reg, s_displ4Reg ) is
  begin
    case (s_scanReg) is
      when "000"  => s_selectedSegment <= s_displ4Reg;
      when "001"  => s_selectedSegment <= s_displ3Reg;
      when "010"  => s_selectedSegment <= s_displ2Reg;
      when "011"  => s_selectedSegment <= s_displ1Reg;
      when others => s_selectedSegment <= (others => '0');
    end case;
  end process makeSelectedSegs;
  
end architecture platformIndependant;
