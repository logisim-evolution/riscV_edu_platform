library ieee;
use ieee.std_logic_1164.all;

-- Original Verilog comments:
-- /*****************************************************************************\
-- |                      Copyright (C) 2021-2022 Luke Wren                      |
-- |                     SPDX-License-Identifier: Apache-2.0                     |
-- \*****************************************************************************/
--
-- // A 2FF synchronizer to mitigate metastabilities. This is a baseline
-- // implementation -- you should replace it with cells specific to your
-- // FPGA/process
--
-- `ifndef HAZARD3_REG_KEEP_ATTRIBUTE
-- `define HAZARD3_REG_KEEP_ATTRIBUTE (* keep = 1'b1 *) (* async_reg *)
-- `endif
--
-- `default_nettype none
--
-- module hazard3_sync_1bit #(
-- 	parameter N_STAGES = 2 // Should be >=2
-- ) (
-- 	input wire clk,
-- 	input wire rst_n,
-- 	input wire i,
-- 	output wire o
-- );

entity hazard3_sync_1bit is
	generic (
		N_STAGES : integer range 2 to integer'high := 2
	);
	port (
		clk   : in std_logic;
		rst   : in std_logic;
		i     : in std_logic;
		o     : out std_logic
	);
end entity hazard3_sync_1bit;

architecture rtl of hazard3_sync_1bit is
	attribute keep               : boolean;
	signal sync_flops            : std_logic_vector(N_STAGES - 1 downto 0);
	attribute keep of sync_flops : signal is true;

begin

	FF_SYNCRONIZER : process (clk, rst)
	begin
		if ?? rst then
			sync_flops <= (others => '0');
		elsif rising_edge(clk) then
			sync_flops <= sync_flops(N_STAGES - 2 downto 0) & i;
		end if;
	end process FF_SYNCRONIZER;

	o <= sync_flops(N_STAGES - 1);

end architecture rtl;
