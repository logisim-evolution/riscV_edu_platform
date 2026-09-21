library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uartTxFifo is
   port ( reset     : in  std_logic;
          clock     : in  std_logic;
          fifoRe    : in  std_logic;
          fifoWe    : in  std_logic;
          fifoFull  : out std_logic;
          fifoEmpty : out std_logic;
          dataIn    : in  std_logic_vector( 7 downto 0 );
          dataOut   : out std_logic_vector( 7 downto 0 ));
end entity uartTxFifo;

architecture platformIndependent of uartTxFifo is

   signal s_fifoFullReg      : std_logic;
   signal s_fifoFullNext     : std_logic;
   signal s_fifoEmptyReg     : std_logic;
   signal s_fifoEmptyNext    : std_logic;
   signal s_writeAddressReg  : unsigned( 3 downto 0 );
   signal s_writeAddressNext : unsigned( 3 downto 0 );
   signal s_readAddressReg   : unsigned( 3 downto 0 );
   signal s_readAddressNext  : unsigned( 3 downto 0 );
   signal s_fifoWe           : std_logic;
   signal s_fifoRe           : std_logic;
   
BEGIN
-- Assign outputs
   fifoFull   <= s_fifoFullReg;
   fifoEmpty  <= s_fifoEmptyReg;
   
-- Assign control signals
   s_fifoFullNext     <= '0' when (reset ='1' or (s_fifoRe = '1' and s_fifoWe = '0')) else
                         '1' when (s_fifoWe = '1' and s_fifoRe = '0' and s_writeAddressNext = s_readAddressReg) else s_fifoFullReg;
   s_fifoEmptyNext    <= '1' when (reset = '1' or (s_fifoRe = '1' and s_fifoWe = '0' and s_readAddressNext = s_writeAddressReg)) else
                         '0' when (s_fifoWe = '1' and s_fifoRe = '0') else s_fifoEmptyReg;
   s_writeAddressNext <= (others => '0') when reset = '1' else s_writeAddressReg + to_unsigned(1, 4);
   s_readAddressNext  <= (others => '0') when reset = '1' else s_readAddressReg + to_unsigned(1, 4);
   s_fifoWe           <= (not(fifoRe) and fifoWe and not(s_fifoFullReg)) or (fifoRe and fifoWe);
   s_fifoRe           <= (fifoRe and not(fifoWe) and not(s_fifoEmptyReg)) or (fifoRe and fifoWe);

   makeRegs : process ( clock ) is
   begin
     if (rising_edge( clock )) then
       s_fifoFullReg   <= s_fifoFullNext;
       s_fifoEmptyReg  <= s_fifoEmptyNext;
       if (s_fifoWe = '1' or reset = '1') then s_writeAddressReg <= s_writeAddressNext;
       end if;
       if (s_fifoRe = '1' or reset = '1') then s_readAddressReg <= s_readAddressNext;
       end if;
     end if;
   end process makeRegs;
                        
-- assign components
   fifo_mem : entity work.sramLutRam(platformIndependent)
      generic map ( nrOfAddressBits => 4,
                    nrOfDataBits    => 8)
      port map ( clock        => clock,
                 writeData    => dataIn,
                 writeAddress => s_writeAddressReg,
                 WriteEnable  => s_fifoWe,
                 readAddress  => s_readAddressReg,
                 readData     => dataOut);
end architecture platformIndependent;
