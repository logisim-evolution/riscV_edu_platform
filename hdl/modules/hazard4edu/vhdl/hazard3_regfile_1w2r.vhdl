library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.hazard3_constants.all;

entity hazard3_regfile_1w2r is
    generic (
        EXTENSION_E : boolean := true;
        RESET_REGFILE : boolean := false;
        N_REGS : positive := 16;
        REGNUM_MASK : std_logic_vector(4 downto 0) := "01111"
    );
    port (
        clk    : in std_logic;
        rst_n  : in std_logic;
        raddr1 : in std_logic_vector(4 downto 0);
        rdata1 : out std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        raddr2 : in std_logic_vector(4 downto 0);
        rdata2 : out std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        waddr  : in std_logic_vector(4 downto 0);
        wdata  : in std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        wen    : in std_logic
    );
end entity hazard3_regfile_1w2r;

architecture rtl of hazard3_regfile_1w2r is
    type mem_t is array (0 to N_REGS - 1) of
        std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal raddr1_masked : std_logic_vector(4 downto 0);
    signal raddr2_masked : std_logic_vector(4 downto 0);
    signal waddr_masked  : std_logic_vector(4 downto 0);
begin
    raddr1_masked <= raddr1 and REGNUM_MASK;
    raddr2_masked <= raddr2 and REGNUM_MASK;
    waddr_masked  <= waddr and REGNUM_MASK;

    with_reset : if RESET_REGFILE generate
        signal mem : mem_t;
    begin
        process(clk, rst_n)
        begin
            if rst_n = '0' then
                for i in mem'range loop
                    mem(i) <= (others => '0');
                end loop;
                rdata1 <= (others => '0');
                rdata2 <= (others => '0');
            elsif rising_edge(clk) then
                if wen = '1' then
                    mem(to_integer(unsigned(waddr_masked))) <= wdata;
                end if;
                rdata1 <= mem(to_integer(unsigned(raddr1_masked)));
                rdata2 <= mem(to_integer(unsigned(raddr2_masked)));
            end if;
        end process;
    end generate with_reset;

    without_reset : if not RESET_REGFILE generate
        signal mem : mem_t;
    begin
        process(clk)
        begin
            if rising_edge(clk) then
                if wen = '1' then
                    mem(to_integer(unsigned(waddr_masked))) <= wdata;
                end if;
                rdata1 <= mem(to_integer(unsigned(raddr1_masked)));
                rdata2 <= mem(to_integer(unsigned(raddr2_masked)));
            end if;
        end process;
    end generate without_reset;
end architecture rtl;
