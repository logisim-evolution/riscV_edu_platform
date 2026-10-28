library ieee;
use ieee.std_logic_1164.all;

-- Original Verilog comments:
-- /*****************************************************************************\
-- |                      Copyright (C) 2021-2022 Luke Wren                      |
-- |                     SPDX-License-Identifier: Apache-2.0                     |
-- \*****************************************************************************/
--
-- // The output is asserted asynchronously when the input is asserted,
-- // but deasserted synchronously when clocked with the input deasserted.
-- // Input and output are both active-low.
-- //
-- // This is a baseline implementation -- you should replace it with cells
-- // specific to your FPGA/process
--
-- `ifndef HAZARD3_REG_KEEP_ATTRIBUTE
-- `define HAZARD3_REG_KEEP_ATTRIBUTE (* keep = 1'b1 *)
-- `endif
--
-- `default_nettype none
--
-- module hazard3_reset_sync #(
-- 	parameter N_STAGES = 2 // Should be >= 2
-- ) (
-- 	input  wire clk,
-- 	input  wire rst_n_in,
-- 	output wire rst_n_out
-- );

entity hazard3_reset_sync is
	generic (
		N_STAGES : integer range 0 to integer'high := 2
	);
	port (
		clk       : in std_logic;
		rst_in  : in std_logic;
		rst_out : out std_logic
	);
end entity hazard3_reset_sync;

architecture rtl of hazard3_reset_sync is
	attribute keep          : boolean;
	signal delay            : std_logic_vector(N_STAGES - 1 downto 0);
	attribute keep of delay : signal is true;
begin

	RST_SYNC : process (clk, rst_in)
	begin
		if ?? rst_in then
			delay <= (others => '1');
		elsif rising_edge(clk) then
			delay <= delay(N_STAGES - 2 downto 0) & '0';
		end if;
	end process RST_SYNC;

	rst_out <= delay(N_STAGES - 1);

end architecture rtl;
