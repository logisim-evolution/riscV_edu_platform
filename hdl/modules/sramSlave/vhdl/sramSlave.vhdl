library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity sramSlave is
  generic ( DataBits           : integer := 32;  -- must be 32 for this module
            AddrBits           : integer := 32;
            BaseAddress        : std_logic_vector := std_logic_vector(to_unsigned(0,32));
            nrOfEntriesInBytes : integer := 64*1024 ); -- must be a 2^m value
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
         CTI_I    : in  std_logic_vector( 2 downto 0 );
         BTE_I    : in  std_logic_vector( 1 downto 0 ) ); -- Registered feedback
end entity sramSlave;

architecture platformindependent of sramSlave is

  type STATE_TYPE is (IDLE, BUSERROR, SINGLE, BURST);
  constant c_nrOfBusAddressBits : integer := integer(ceil(log2(real(nrOfEntriesInBytes))));
  
  signal s_stateReg, s_stateNext                             : STATE_TYPE;
  signal s_nClock, s_isMyTransaction, s_isCorrectTransaction : std_logic;
  signal s_byteWe                                            : std_logic_vector( 3 downto 0 );
  signal s_ramAddress                                        : std_logic_vector( c_nrOfBusAddressBits-3 downto 0 );

begin
  s_isMyTransaction      <= CYC_I and STB_I when ADDR_I(AddrBits-1 downto c_nrOfBusAddressBits) = BaseAddress(AddrBits-1 downto c_nrOfBusAddressBits) else '0';
  s_isCorrectTransaction <= s_isMyTransaction when CTI_I = "000" or CTI_I = "111" or ((CTI_I = "001" or CTI_I = "010") and BTE_I = "00") else '0';
  ERR_O                  <= CYC_I and STB_I when s_stateReg = BUSERROR else '0';
  ACK_O                  <= CYC_I and STB_I when (s_stateReg = BURST and s_isCorrectTransaction = '1') or s_stateReg = SINGLE else '0';
  
  -- here the state machine is defined
  nextState : process ( s_isMyTransaction, s_isCorrectTransaction, CTI_I, CYC_I, STB_I , s_stateReg ) is
  begin
    case (s_stateReg) is
      when IDLE   => if (s_isMyTransaction = '1' and s_isCorrectTransaction = '0') then s_stateNext <= BUSERROR;
                     elsif (s_isCorrectTransaction = '1' and CTI_I = "000") then s_stateNext <= SINGLE;
                     elsif (s_isCorrectTransaction = '1') then s_stateNext <= BURST;
                     else s_stateNext <= IDLE;
                     end if;
      when BURST  => if (s_isMyTransaction = '0' and CYC_I = '1' and STB_I = '1') then s_stateNext <= BUSERROR;
                     elsif (CTI_I = "111" or CYC_I = '0') then s_stateNext <= IDLE;
                     else s_stateNext <= BURST;
                     end if;
      when others => s_stateNext <= IDLE;
    end case;
  end process nextState;
  
  makeStateFlops : process (CLK_I) is
  begin
    if (rising_edge(CLK_I)) then
      if (RST_I = '1') then s_stateReg <= IDLE;
                       else s_stateReg <= s_stateNext;
      end if;
    end if;
  end process makeStateFlops;
  
  -- here the memories are defined
  s_ramAddress <= ADDR_I(c_nrOfBusAddressBits-1 downto 2);
  s_byteWe     <= SEL_I when WE_I = '1' and STB_I = '1' and s_isCorrectTransaction = '1' else "0000";
  s_nClock     <= not(CLK_I);
  
  byte0 : entity work.singlePortBlockRam(platformindependent)
    generic map ( nrOfAddressBits => c_nrOfBusAddressBits - 2,
                  nrOfDataBits    => 8)
    port map ( clock       => s_nClock,
               writeEnable => s_byteWe(0),
               address     => s_ramAddress,
               dataIn      => DAT_I( 7 downto 0 ),
               dataOut     => DAT_O( 7 downto 0 ));

  byte1 : entity work.singlePortBlockRam(platformindependent)
    generic map ( nrOfAddressBits => c_nrOfBusAddressBits - 2,
                  nrOfDataBits    => 8)
    port map ( clock       => s_nClock,
               writeEnable => s_byteWe(1),
               address     => s_ramAddress,
               dataIn      => DAT_I( 15 downto 8 ),
               dataOut     => DAT_O( 15 downto 8 ));

  byte2 : entity work.singlePortBlockRam(platformindependent)
    generic map ( nrOfAddressBits => c_nrOfBusAddressBits - 2,
                  nrOfDataBits    => 8)
    port map ( clock       => s_nClock,
               writeEnable => s_byteWe(2),
               address     => s_ramAddress,
               dataIn      => DAT_I( 23 downto 16 ),
               dataOut     => DAT_O( 23 downto 16 ));

  byte3 : entity work.singlePortBlockRam(platformindependent)
    generic map ( nrOfAddressBits => c_nrOfBusAddressBits - 2,
                  nrOfDataBits    => 8)
    port map ( clock       => s_nClock,
               writeEnable => s_byteWe(3),
               address     => s_ramAddress,
               dataIn      => DAT_I( 31 downto 24 ),
               dataOut     => DAT_O( 31 downto 24 ));

end architecture platformindependent;
