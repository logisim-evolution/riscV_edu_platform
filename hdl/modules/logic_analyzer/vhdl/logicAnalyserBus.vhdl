library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity logicAnalyserBus is
  generic ( DataBits    : integer := 32;  -- must be 32 for this module
            AddrBits    : integer := 32;  -- must be bigger than 13 for this module
            BaseAddress : std_logic_vector := std_logic_vector(to_unsigned(0,32)));
  port ( tappedWires : in std_logic_vector( 63 downto 0 );
  
         -- here the wishbone signals are defined
         CLK_I    : in  std_logic;
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
         CTI_I    : in  std_logic_vector( 2 downto 0 ) -- Registered feedback
         -- BTE_I is not used in this module
         ); 
end entity logicAnalyserBus;

architecture platformIndependent of logicAnalyserBus is

  -- read-only addresses (ADDR_I( 12 downto 11 ))
  constant LOW_BASE      : std_logic_vector( 1 downto 0 ) := "00";
  constant HIGH_BASE     : std_logic_vector( 1 downto 0 ) := "01";
  constant DONE          : std_logic_vector( 1 downto 0 ) := "10";
  constant START_ADDRESS : std_logic_vector( 1 downto 0 ) := "11";
  
  -- write-only address (ADDR_I( 6 downto 2))
  constant MASK_0_LO         : std_logic_vector( 4 downto 0 ) := "10000";
  constant MASK_0_HI         : std_logic_vector( 4 downto 0 ) := "10001";
  constant MASK_1_LO         : std_logic_vector( 4 downto 0 ) := "10010";
  constant MASK_1_HI         : std_logic_vector( 4 downto 0 ) := "10011";
  constant MASK_2_LO         : std_logic_vector( 4 downto 0 ) := "10100";
  constant MASK_2_HI         : std_logic_vector( 4 downto 0 ) := "10101";
  constant MASK_3_LO         : std_logic_vector( 4 downto 0 ) := "10110";
  constant MASK_3_HI         : std_logic_vector( 4 downto 0 ) := "10111";
  constant REFERENCE_0_LO    : std_logic_vector( 4 downto 0 ) := "11000";
  constant REFERENCE_0_HI    : std_logic_vector( 4 downto 0 ) := "11001";
  constant REFERENCE_1_LO    : std_logic_vector( 4 downto 0 ) := "11010";
  constant REFERENCE_1_HI    : std_logic_vector( 4 downto 0 ) := "11011";
  constant REFERENCE_2_LO    : std_logic_vector( 4 downto 0 ) := "11100";
  constant REFERENCE_2_HI    : std_logic_vector( 4 downto 0 ) := "11101";
  constant REFERENCE_3_LO    : std_logic_vector( 4 downto 0 ) := "11110";
  constant REFERENCE_3_HI    : std_logic_vector( 4 downto 0 ) := "11111";
  constant COMPARATOR_0      : std_logic_vector( 4 downto 0 ) := "00110";
  constant COMPARATOR_1      : std_logic_vector( 4 downto 0 ) := "00111";
  constant COMPARATOR_2      : std_logic_vector( 4 downto 0 ) := "01000";
  constant COMPARATOR_3      : std_logic_vector( 4 downto 0 ) := "01001";
  constant RESET             : std_logic_vector( 4 downto 0 ) := "01111";
  constant SEQ_LEN           : std_logic_vector( 4 downto 0 ) := "00100";
  constant POST_TRIG_SAMPLES : std_logic_vector( 4 downto 0 ) := "00101";

  signal isMyTransaction      : std_logic;
  signal lacReadAddress       : std_logic_vector( 8 downto 0 );
  signal addrReg              : std_logic_vector(10 downto 0 );
  signal dataReg              : std_logic_vector( DataBits-1 downto 0 );
  signal isWriteTransaction   : std_logic;
  signal isError              : std_logic;
  signal genAck               : std_logic;
  signal isCorrectTransaction : std_logic;
  signal lacReset             : std_logic;
  signal lacDone              : std_logic;
  signal lacStartAddress      : std_logic_vector( 8 downto 0 );
  signal lacDataLow           : std_logic_vector(31 downto 0 );
  signal lacDataHigh          : std_logic_vector(31 downto 0 );
  signal comparator0          : std_logic_vector( 2 downto 0 );
  signal comparator1          : std_logic_vector( 2 downto 0 );
  signal comparator2          : std_logic_vector( 2 downto 0 );
  signal comparator3          : std_logic_vector( 2 downto 0 );
  signal mask0                : std_logic_vector(63 downto 0 );
  signal mask1                : std_logic_vector(63 downto 0 );
  signal mask2                : std_logic_vector(63 downto 0 );
  signal mask3                : std_logic_vector(63 downto 0 );
  signal reference0           : std_logic_vector(63 downto 0 );
  signal reference1           : std_logic_vector(63 downto 0 );
  signal reference2           : std_logic_vector(63 downto 0 );
  signal reference3           : std_logic_vector(63 downto 0 );
  signal seqLen               : std_logic_vector( 1 downto 0 ); -- actual length is seqLen + 1
  signal postTrigSamples      : std_logic_vector( 8 downto 0 );

begin
  -- here we define some control signal
  isMyTransaction      <= CYC_I and STB_I when (ADDR_I(AddrBits-1 downto 13) = BaseAddress(AddrBits-1 downto 13)) else '0';
  lacReadAddress       <= ADDR_I( 10 downto 2 );
  isCorrectTransaction <= isMyTransaction when (CTI_I = "000" and SEL_I = "1111") else '0';
  ERR_O                <= isError;
  ACK_O                <= genAck;
  
  -- here we define ths bus input regs
  inputRegs : process( CLK_I ) is
  begin
    if (rising_edge(CLK_I)) then
      if (isCorrectTransaction = '1') then
        addrReg <= ADDR_I( 12 downto 2 );
        dataReg <= DAT_I;
      end if;
      isWriteTransaction <= isCorrectTransaction and WE_I and not(genAck);
      if (RST_I = '1') then
        genAck  <= '0';
        isError <= '0';
                       else
        genAck  <= not(genAck) and isCorrectTransaction;
        isError <= not(isError) and isMyTransaction and not(isCorrectTransaction);
      end if;
    end if;
  end process inputRegs;
  
  -- here we define the read data
  readData : process( addrReg, lacDataLow, lacDataHigh, lacDone, lacStartAddress ) is
  begin
    case (addrReg( 10 downto 9)) is
      when LOW_BASE  => DAT_O <= lacDataLow;
      when HIGH_BASE => DAT_O <= lacDataHigh;
      when DONE      => DAT_O(DataBits-1 downto 1) <= (others => '0');
                        DAT_O(0) <= lacDone;
      when others    => DAT_O(DataBits-1 downto 9) <= (others => '0');
                        DAT_O(8 downto 0) <= lacReadAddress;
    end case;
  end process readData;
  
  -- here we define the write action
  writeData : process (CLK_I) is
  begin
    if (rising_edge(CLK_I)) then
      if (RST_I = '1') then
        lacReset        <= '0';
        comparator0     <= (others => '0');
        comparator1     <= (others => '0');
        comparator2     <= (others => '0');
        comparator3     <= (others => '0');
        mask0           <= (others => '0');
        mask1           <= (others => '0');
        mask2           <= (others => '0');
        mask3           <= (others => '0');
        reference0      <= (others => '0');
        reference1      <= (others => '0');
        reference2      <= (others => '0');
        reference3      <= (others => '0');
        seqLen          <= (others => '0');
        postTrigSamples <= (others => '0');
      else
        lacReset <= '0';
        if (isWriteTransaction = '1') then
          case (addrReg(4 downto 0)) is
            when RESET             => lacReset <= '1';
            when COMPARATOR_0      => comparator0 <= dataReg( 2 downto 0 );
            when COMPARATOR_1      => comparator1 <= dataReg( 2 downto 0 );
            when COMPARATOR_2      => comparator2 <= dataReg( 2 downto 0 );
            when COMPARATOR_3      => comparator3 <= dataReg( 2 downto 0 );
            when MASK_0_LO         => mask0(31 downto 0) <= dataReg;
            when MASK_0_HI         => mask0(63 downto 32) <= dataReg;
            when MASK_1_LO         => mask1(31 downto 0) <= dataReg;
            when MASK_1_HI         => mask1(63 downto 32) <= dataReg;
            when MASK_2_LO         => mask2(31 downto 0) <= dataReg;
            when MASK_2_HI         => mask2(63 downto 32) <= dataReg;
            when MASK_3_LO         => mask3(31 downto 0) <= dataReg;
            when MASK_3_HI         => mask3(63 downto 32) <= dataReg;
            when REFERENCE_0_LO    => reference0(31 downto 0) <= dataReg;
            when REFERENCE_0_HI    => reference0(63 downto 32) <= dataReg;
            when REFERENCE_1_LO    => reference1(31 downto 0) <= dataReg;
            when REFERENCE_1_HI    => reference1(63 downto 32) <= dataReg;
            when REFERENCE_2_LO    => reference2(31 downto 0) <= dataReg;
            when REFERENCE_2_HI    => reference2(63 downto 32) <= dataReg;
            when REFERENCE_3_LO    => reference3(31 downto 0) <= dataReg;
            when REFERENCE_3_HI    => reference3(63 downto 32) <= dataReg;
            when SEQ_LEN           => seqLen <= dataReg(1 downto 0);
            when POST_TRIG_SAMPLES => postTrigSamples <= dataReg(8 downto 0);
            when others            => null;
          end case;
        end if;
      end if;
    end if;
  end process writeData;
  
end architecture platformIndependent;
