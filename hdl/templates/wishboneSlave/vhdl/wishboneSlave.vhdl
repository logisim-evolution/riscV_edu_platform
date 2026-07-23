library ieee;
use ieee.std_logic_1164.all;

entity wishboneSlave is
  generic ( DataBits    : integer := 32;  -- must be a multiple of 8, eg. 8, 16, 24, 32, ...
            AddrBits    : integer := 32;
            BaseAddress : integer := 0x00000000);
  port ( CLK_I    : in  std_logic;
         RST_I    : in  std_logic;
         DAT_I    : in  std_logic_vector( DataBits-1 downto 0 );
         DAT_O    : out std_logic_vector( DataBits-1 downto 0 );
         -- TAGD_I and TAGD_O are not implemented
         ACK_O    : out std_logic;
         ADDR_I   : in  std_logic_vector( AddrBits-1 downto 0 );
         CYC_I    : in  std_logic;
         ERR_O    : out std_logic;
         LOCK_I   : in  std_logic;
         -- RTY_I is not implemented
         SEL_I    : in  std_logic_vector( (DataBits/8)-1 downto 0 );
         STB_I    : in  std_logic;
         -- TGA_O and TGC_O are not implemented
         WE_I     : in  std_logic;
         CTI_I    : in  std_logic_vector( 2 downto 0 ) ); -- Registered feedback
end wishboneSlave;
