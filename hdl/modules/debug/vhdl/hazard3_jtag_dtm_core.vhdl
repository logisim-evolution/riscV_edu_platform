library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Original Verilog comments:
-- /*****************************************************************************\
-- |                      Copyright (C) 2021-2022 Luke Wren                      |
-- |                     SPDX-License-Identifier: Apache-2.0                     |
-- \*****************************************************************************/
--
-- // DTMCS + DMI control logic, bus interface and bus clock domain crossing for
-- // a standard RISC-V APB JTAG-DTM. Essentially everything apart from the
-- // actual TAP controller, IR and shift registers. Instantiated by
-- // hazard3_jtag_dtm.v.
-- //
-- // This core logic can be reused and connected to some other serial transport
-- // or, for example, the ECP5 JTAGG primitive (see hazard5_ecp5_jtag_dtm.v)
--
-- `default_nettype none
--
-- module hazard3_jtag_dtm_core #(
-- 	parameter DTMCS_IDLE_HINT = 3'd4,
-- 	parameter W_ADDR = 8,
-- 	parameter W_DR_SHIFT = W_ADDR + 32 + 2 // do not modify
-- ) (
-- 	input  wire                  tck,
-- 	input  wire                  trst_n,
--
-- 	input  wire                  clk_dmi,
-- 	input  wire                  rst_n_dmi,
--
-- 	// DR capture/update (read/write) signals
-- 	input  wire                  dr_wen,
-- 	input  wire                  dr_ren,
-- 	input  wire                  dr_sel_dmi_ndtmcs,
-- 	input  wire [W_DR_SHIFT-1:0] dr_wdata,
-- 	output wire [W_DR_SHIFT-1:0] dr_rdata,
--
-- 	// This is synchronous to TCK and asserted for one TCK cycle only
-- 	output reg                   dmihardreset_req,
--
-- 	// Debug Module Interface (APB)
-- 	output wire                  dmi_psel,
-- 	output wire                  dmi_penable,
-- 	output wire                  dmi_pwrite,
-- 	output wire [W_ADDR-1:0]     dmi_paddr,
-- 	output wire [31:0]           dmi_pwdata,
-- 	input  wire [31:0]           dmi_prdata,
-- 	input  wire                  dmi_pready,
-- 	input  wire                  dmi_pslverr
-- );

entity hazard3_jtag_dtm_core is
	generic (
		DTMCS_IDLE_HINT : std_logic_vector(2 downto 0) := 3d"4";
		W_ADDR          : natural                      := 8
	);
	port (
		tck    : in std_logic;
		trst_n : in std_logic;

		clk_dmi : in std_logic;
		rst_dmi : in std_logic;

		-- DR capture/update (read/write) signals
		dr_wen            : in std_logic;
		dr_ren            : in std_logic;
		dr_sel_dmi_ndtmcs : in std_logic;
		dr_wdata          : in std_logic_vector(W_ADDR + 32 + 1 downto 0);
		dr_rdata          : out std_logic_vector(W_ADDR + 32 + 1 downto 0);

		-- This is synchronous to TCK and asserted for one TCK cycle only
		dmihardreset_req : out std_logic;

		-- Debug Module Interface (APB)
		dmi_psel    : out std_logic;
		dmi_penable : out std_logic;
		dmi_pwrite  : out std_logic;
		dmi_paddr   : out std_logic_vector(W_ADDR - 1 downto 0);
		dmi_pwdata  : out std_logic_vector(31 downto 0);
		dmi_prdata  : in std_logic_vector(31 downto 0);
		dmi_pready  : in std_logic;
		dmi_pslverr : in std_logic
	);
end entity hazard3_jtag_dtm_core;

architecture rtl of hazard3_jtag_dtm_core is
	signal write_dmi   : std_logic;
	signal write_dtmcs : std_logic;
	signal read_dmi    : std_logic;

	-- DMI bus adapter
	signal dmi_cmderr_reg : std_logic_vector(1 downto 0);
	signal dmi_busy_reg   : std_logic;

	-- DTM-domain bus, connected to a matching DM-domain bus via an APB crossing:
	signal dtm_psel    : std_logic;
	signal dtm_penable : std_logic;
	signal dtm_pwrite  : std_logic;
	signal dtm_paddr   : std_logic_vector(dmi_paddr'range);
	signal dtm_pwdata  : std_logic_vector(dmi_pwdata'range);
	signal dtm_prdata  : std_logic_vector(dmi_prdata'range);
	signal dtm_pready  : std_logic;
	signal dtm_pslverr : std_logic;
	signal dtmcs_rdata : std_logic_vector(dr_rdata'range);
	signal dmi_rdata   : std_logic_vector(dr_rdata'range);
	signal dmi_status  : std_logic_vector(1 downto 0);

	signal dmihardreset_req_reg : std_logic;
begin

	write_dmi   <= dr_wen and dr_sel_dmi_ndtmcs;
	write_dtmcs <= dr_wen and not dr_sel_dmi_ndtmcs;
	read_dmi    <= dr_ren and dr_sel_dmi_ndtmcs;

	-- We are relying on some particular features of our APB clock crossing here
	-- to save some registers:
	--
	-- - The transfer is launched immediately when psel is seen, no need to
	--   actually assert an access phase (as the standard allows the CDC to
	--   assume that access immediately follows setup) and no need to maintain
	--   pwrite/paddr/pwdata valid after the setup phase
	--
	-- - prdata/pslverr remain valid after the transfer completes, until the next
	--   transfer completes
	--
	-- These allow us to connect the upstream side of the CDC directly to our DR
	-- shifter without any sample/hold registers in between.

	-- psel is only pulsed for one cycle, penable is not asserted.
	dtm_psel <= '1' when write_dmi = '1' and (
						dr_wdata(1 downto 0) = "01" or dr_wdata(1 downto 0) = "10"
					) and dmi_busy_reg = '0' and dmi_cmderr_reg = "00" and
					dtm_pready = '1'
				else '0';

	dtm_penable <= '0';
	dtm_paddr   <= dr_wdata(34 + W_ADDR - 1 downto 34);
	dtm_pwrite  <= dr_wdata(1);
	dtm_pwdata  <= dr_wdata(33 downto 2);

	process (tck) begin
		if rising_edge(tck) then
			if ?? (not trst_n) then
				dmi_busy_reg   <= '0';
				dmi_cmderr_reg <= "00";
			elsif ?? read_dmi then
				-- Reading while busy sets the busy sticky error. Note the capture
				-- into shift register should also reflect this update on-the-fly
				if dmi_busy_reg = '1' and dmi_cmderr_reg = "00" then
					dmi_cmderr_reg <= "11";
				end if;
			elsif ?? write_dtmcs then
				-- Writing dtmcs.dmireset = 1 clears a sticky error
				if ?? dr_wdata(16) then
					dmi_cmderr_reg <= "00";
				end if;
			elsif ?? write_dmi then
				if ?? dtm_psel then
					dmi_busy_reg <= '1';
				elsif dr_wdata(1 downto 0) /= "00" then
					-- DMI ignored operation, so set sticky busy
					if dmi_cmderr_reg = "00" then
						dmi_cmderr_reg <= "11";
					end if;
				end if;
			elsif ?? (dmi_busy_reg and dtm_pready) then
				dmi_busy_reg <= '0';
				if dmi_cmderr_reg = "00" and dtm_pslverr = '1' then
					dmi_cmderr_reg <= "10";
				end if;
			end if;
		end if;
	end process;

	-- DTM logic is in TCK domain, actual DMI + DM is in processor domain

	inst_hazard3_apb_async_bridge : entity work.hazard3_apb_async_bridge
		generic map(
			W_ADDR        => W_ADDR,
			W_DATA        => 32,
			N_SYNC_STAGES => 2
		)
		port map
		(
			clk_src     => tck,
			rst_src     => not trst_n,
			clk_dst     => clk_dmi,
			rst_dst     => rst_dmi,
			src_psel    => dtm_psel,
			src_penable => dtm_penable,
			src_pwrite  => dtm_pwrite,
			src_paddr   => dtm_paddr,
			src_pwdata  => dtm_pwdata,
			src_prdata  => dtm_prdata,
			src_pready  => dtm_pready,
			src_pslverr => dtm_pslverr,
			dst_psel    => dmi_psel,
			dst_penable => dmi_penable,
			dst_pwrite  => dmi_pwrite,
			dst_paddr   => dmi_paddr,
			dst_pwdata  => dmi_pwdata,
			dst_prdata  => dmi_prdata,
			dst_pready  => dmi_pready,
			dst_pslverr => dmi_pslverr
		);

	-- -------------------------------------------------------------------------
	-- DR read/write
	
	dtmcs_rdata <= (W_ADDR-1 downto 0 => '0') &
                   19d"0" &                             -- 19'h0
                   DTMCS_IDLE_HINT &
                   dmi_cmderr_reg &
                   std_logic_vector(to_unsigned(W_ADDR, 6)) &          -- W_ADDR[5:0]
                   4d"1";                                             -- 4'd1

    dmi_status <= "11" when (dmi_busy_reg = '1' and dmi_cmderr_reg = "00") else dmi_cmderr_reg;

    dmi_rdata <= (W_ADDR-1 downto 0 => '0') & dtm_prdata & dmi_status;

    dr_rdata <= dmi_rdata when ?? dr_sel_dmi_ndtmcs else dtmcs_rdata;

    update_dmihardreset_proc : process (tck) begin
		if rising_edge(tck) then
			if ?? (not trst_n) then
            	dmihardreset_req_reg <= '0';
			else
                dmihardreset_req_reg <= write_dtmcs and dr_wdata(17);
            end if;
        end if;
    end process update_dmihardreset_proc;

	dmihardreset_req <= dmihardreset_req_reg;

end architecture rtl;
