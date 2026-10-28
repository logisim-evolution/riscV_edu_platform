library ieee;
use ieee.std_logic_1164.all;

-- Original Verilog comments:
-- /*****************************************************************************\
-- |                      Copyright (C) 2021-2022 Luke Wren                      |
-- |                     SPDX-License-Identifier: Apache-2.0                     |
-- \*****************************************************************************/
--
-- // The ECP5 JTAGG primitive (yes that is the correct spelling) allows you to
-- // add two custom DRs to the FPGA's chip TAP, selected using the 8-bit ER1
-- // (0x32) and ER2 (0x38) instructions.
-- //
-- // Brian Swetland pointed out on Twitter that the standard RISC-V JTAG-DTM
-- // only uses two DRs (DTMCS and DMI), besides the standard IDCODE and BYPASS
-- // which are provided already by the ECP5 TAP. This file instantiates the
-- // guts of Hazard3's standard JTAG-DTM and connects the DTMCS and DMI
-- // registers to the JTAGG primitive's ER1/ER2 DRs.
-- //
-- // The exciting part is that upstream OpenOCD already allows you to set the IR
-- // length *and* set custom DTMCS/DMI IR values for RISC-V JTAG DTMs. This
-- // means with the right config file, you can access a debug module hung from
-- // the ECP5 TAP in this fashion using only upstream OpenOCD and gdb.
--
-- `default_nettype none
--
-- module hazard3_ecp5_jtag_dtm #(
--     parameter DTMCS_IDLE_HINT = 3'd4,
--     parameter W_PADDR         = 9,
--     parameter ABITS           = W_PADDR - 2 // do not modify
-- ) (
--     // This is synchronous to TCK and asserted for one TCK cycle only
--     output wire               dmihardreset_req,
--
--     // Bus clock + reset for Debug Module Interface
--     input  wire               clk_dmi,
--     input  wire               rst_n_dmi,
--
--     // Debug Module Interface (APB)
--     output wire               dmi_psel,
--     output wire               dmi_penable,
--     output wire               dmi_pwrite,
--     output wire [W_PADDR-1:0] dmi_paddr,
--     output wire [31:0]        dmi_pwdata,
--     input  wire [31:0]        dmi_prdata,
--     input  wire               dmi_pready,
--     input  wire               dmi_pslverr
-- );

entity hazard3_ecp5_jtag_dtm is
	generic (
		DTMCS_IDLE_HINT : std_logic_vector(2 downto 0) := "100";
		W_PADDR         : natural                      := 9
	);
	port (
		-- This is synchronous to TCK and asserted for one TCK cycle only
		dmihardreset_req : out std_logic;

		-- Bus clock + reset for Debug Module Interface
		clk_dmi   : in std_logic;
		rst_dmi   : in std_logic;

		-- Debug Module Interface (APB)
		dmi_psel    : out std_logic;
		dmi_penable : out std_logic;
		dmi_pwrite  : out std_logic;
		dmi_paddr   : out std_logic_vector(W_PADDR - 1 downto 0);
		dmi_pwdata  : out std_logic_vector(31 downto 0);
		dmi_prdata  : in std_logic_vector(31 downto 0);
		dmi_pready  : in std_logic;
		dmi_pslverr : in std_logic
	);
end entity hazard3_ecp5_jtag_dtm;

architecture rtl of hazard3_ecp5_jtag_dtm is
	constant W_DR_SHIFT : natural := W_PADDR - 2 + 32 + 2;

	signal jtdo2                       : std_logic;
	signal jtdo1                       : std_logic;
	signal jtdi                        : std_logic;
	signal jtck_posedge_dont_use       : std_logic;
	signal jshift                      : std_logic;
	signal jupdate                     : std_logic;
	signal jrst_n                      : std_logic;
	signal jce2                        : std_logic;
	signal jce1                        : std_logic;
	signal jtck                        : std_logic;
	signal core_dr_wen_reg             : std_logic := '0';
	signal core_dr_ren_reg             : std_logic := '0';
	signal core_dr_sel_dmi_ndtmcs_reg  : std_logic := '0';
	signal dr_shift_en_reg             : std_logic := '0';
	signal core_dr_wdata               : std_logic_vector(W_DR_SHIFT - 1 downto 0);
	signal core_dr_rdata               : std_logic_vector(W_DR_SHIFT - 1 downto 0);
	signal dr_shift_reg                : std_logic_vector(W_DR_SHIFT - 1 downto 0);
	signal dr_shift_next_halfcycle_reg : std_logic;

	component JTAGG is
		port (
			-- Clock and Data from external JTAG pins to fabric
			JTCK : out std_logic;
			JTDI : out std_logic;

			-- User data shifted back to external TDO pin
			JTDO1 : in std_logic;
			JTDO2 : in std_logic;

			-- TAP Controller State Indicators
			JSHIFT  : out std_logic;
			JUPDATE : out std_logic;
			JRSTN   : out std_logic;

			-- Clock Enables for USER1 (ER1) and USER2 (ER2) instructions
			JCE1 : out std_logic;
			JCE2 : out std_logic;

			-- No idea what those are:
			JRTI1 : out std_logic;
			JRTI2 : out std_logic
		);
	end component;
begin

	jtag_u : JTAGG
	port map
	(
		JTCK    => jtck_posedge_dont_use,
		JTDI    => jtdi,
		JTDO1   => jtdo1,
		JTDO2   => jtdo2,
		JSHIFT  => jshift,
		JUPDATE => jupdate,
		JRSTN   => jrst_n,
		JCE1    => jce1,
		JCE2    => jce2,
		JRTI1   => open,
		JRTI2   => open
	);

	-- JTAGG primitive asserts its signals synchronously to JTCK's posedge, but
	-- you get weird and inconsistent results if you try to consume them
	-- synchronously on JTCK's posedge, possibly due to a lack of hold
	-- constraints in nextpnr.
	--
	-- A quick hack is to move the sampling onto the negedge of the clock. This
	-- then creates more problems because we would be running our shift logic on
	-- a different edge from the control + CDC logic in the DTM core.
	--
	-- So, even worse hack, move all our JTAG-domain logic onto the negedge
	-- (or near enough) by inverting the clock.
	jtck <= not jtck_posedge_dont_use;

	-- Decode our shift controls from the interesting ECP5 ones, and re-register
	-- onto JTCK negedge (our posedge). Note without re-registering we observe
	-- them a half-cycle (effectively one cycle) too early. This is another
	-- consequence of the stupid JTDI thing

	process (jtck, jrst_n)
	begin
		if jrst_n = '0' then
			core_dr_sel_dmi_ndtmcs_reg <= '0';
			core_dr_wen_reg            <= '0';
			core_dr_ren_reg            <= '0';
			dr_shift_en_reg            <= '0';
		elsif rising_edge(jtck) then
			if jce1 = '1' or jce2 = '1' then
				core_dr_sel_dmi_ndtmcs_reg <= jce2;
			end if;
			core_dr_ren_reg <= (jce1 or jce2) and not jshift;
			core_dr_wen_reg <= jupdate;
			dr_shift_en_reg <= jshift;
		end if;
	end process;

	core_dr_wdata <= dr_shift_reg;

	process (jtck, jrst_n)
	begin
		if jrst_n = '0' then
			dr_shift_reg <= (others => '0');
		elsif rising_edge(jtck) then
			if core_dr_ren_reg = '1' then
				dr_shift_reg <= core_dr_rdata;
			elsif dr_shift_en_reg = '1' then
				dr_shift_reg <= jtdi & dr_shift_reg(W_DR_SHIFT - 1 downto 1);
				if core_dr_sel_dmi_ndtmcs_reg = '0' then
					dr_shift_reg(31) <= jtdi;
				end if;
			end if;
		end if;
	end process;

	-- Not documented on ECP5: as well as the posedge flop on JTDI, the ECP5 puts
	-- a negedge flop on JTDO1, JTDO2. (Conjecture based on dicking around with a
	-- logic analyser.) To get JTDOx to appear with the same timing as our shifter
	-- LSB (which we update on every JTCK negedge) we:
	--
	-- - Register the LSB of the *next* value of dr_shift on the JTCK posedge, so
	--   half a cycle earlier than the actual dr_shift update
	--
	-- - This then gets re-registered with the pointless JTDO negedge flops, so
	--   that it appears with the same timing as our DR shifter update.

	process (jtck, jrst_n)
	begin
		if jrst_n = '0' then
			dr_shift_next_halfcycle_reg <= '0';
		elsif falling_edge(jtck) then
			if core_dr_ren_reg = '1' then
				dr_shift_next_halfcycle_reg <= core_dr_rdata(0);
			elsif dr_shift_en_reg = '1' then
				dr_shift_next_halfcycle_reg <= dr_shift_reg(1);
			else
				dr_shift_next_halfcycle_reg <= dr_shift_reg(0);
			end if;
		end if;
	end process;

	-- We have only a single shifter for the ER1 and ER2 chains, so these are tied
	-- together:
	jtdo1         <= dr_shift_next_halfcycle_reg;
	jtdo2         <= dr_shift_next_halfcycle_reg;

	-- The actual DTM is in here:
	inst_hazard3_jtag_dtm_core : entity work.hazard3_jtag_dtm_core
		generic map(
			DTMCS_IDLE_HINT => DTMCS_IDLE_HINT,
			W_ADDR          => W_PADDR - 2
		)
		port map
		(
			tck               => jtck,
			trst_n            => jrst_n,
			clk_dmi           => clk_dmi,
			rst_dmi           => rst_dmi,
			dr_wen            => core_dr_wen_reg,
			dr_ren            => core_dr_ren_reg,
			dr_sel_dmi_ndtmcs => core_dr_sel_dmi_ndtmcs_reg,
			dr_wdata          => core_dr_wdata,
			dr_rdata          => core_dr_rdata,
			dmihardreset_req  => dmihardreset_req,
			dmi_psel          => dmi_psel,
			dmi_penable       => dmi_penable,
			dmi_pwrite        => dmi_pwrite,
			dmi_paddr         => dmi_paddr(W_PADDR - 1 downto 2),
			dmi_pwdata        => dmi_pwdata,
			dmi_prdata        => dmi_prdata,
			dmi_pready        => dmi_pready,
			dmi_pslverr       => dmi_pslverr
		);

	dmi_paddr(1 downto 0) <= "00";

end architecture rtl;
