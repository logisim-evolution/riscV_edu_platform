library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.hazard3_constants.all;

entity hazard3_regfile_1w2r is
    port (
        clk    : in std_logic;

        raddr1 : in  std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
        rdata1 : out std_logic_vector(DATA_WIDTH_C - 1 downto 0);

        raddr2 : in  std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
        rdata2 : out std_logic_vector(DATA_WIDTH_C - 1 downto 0);

        waddr  : in std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
        wdata  : in std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        wen    : in std_logic
    );
end entity hazard3_regfile_1w2r;

architecture rtl of hazard3_regfile_1w2r is

    signal reg_a_data : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal reg_b_data : std_logic_vector(DATA_WIDTH_C - 1 downto 0);

begin
    -- One LUT RAM per read port, both written identically
    DATA_A_RAM : entity work.sramLutRam
        generic map (
            nrOfAddressBits => REGISTER_ADDRESS_WIDTH_C,
            nrOfDataBits    => DATA_WIDTH_C
        )
        port map (
            clock        => clk,
            writeEnable  => wen,
            writeAddress => unsigned(waddr),
            readAddress  => unsigned(raddr1),
            writeData    => wdata,
            readData     => reg_a_data
        );

    DATA_B_RAM : entity work.sramLutRam
        generic map (
            nrOfAddressBits => REGISTER_ADDRESS_WIDTH_C,
            nrOfDataBits    => DATA_WIDTH_C
        )
        port map (
            clock        => clk,
            writeEnable  => wen,
            writeAddress => unsigned(waddr),
            readAddress  => unsigned(raddr2),
            writeData    => wdata,
            readData     => reg_b_data
        );

    -- Register x0 always reads as zero
    READ_REGS : process(clk)
    begin
        if rising_edge(clk) then
            rdata1 <= (others => '0') when unsigned(raddr1) = 0 else reg_a_data;
            rdata2 <= (others => '0') when unsigned(raddr2) = 0 else reg_b_data;
        end if;
    end process READ_REGS;
end architecture rtl;
