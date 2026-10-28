library ieee;
use ieee.std_logic_1164.all;

-- Original Verilog comments:
-- /*****************************************************************************\
-- |                      Copyright (C) 2021-2022 Luke Wren                      |
-- |                     SPDX-License-Identifier: Apache-2.0                     |
-- \*****************************************************************************/
--
-- // APB-to-APB asynchronous bridge for connecting DTM to DM, in case DTM is in
-- // a different clock domain (e.g. running directly from crystal to get a
-- // fixed baud reference)
-- //
-- // Note this module depends on the hazard3_sync_1bit module (a flop-chain
-- // synchroniser) which should be reimplemented for your FPGA/process.
--
-- `ifndef HAZARD3_REG_KEEP_ATTRIBUTE
-- `define HAZARD3_REG_KEEP_ATTRIBUTE (* keep = 1'b1 *)
-- `endif
--
-- `default_nettype none
--
-- module hazard3_apb_async_bridge #(
--     parameter W_ADDR = 8,
--     parameter W_DATA = 32,
--     parameter N_SYNC_STAGES = 2
-- ) (
--     // Resets assumed to be synchronised externally
--     input wire               clk_src,
--     input wire               rst_n_src,
--
--     input wire               clk_dst,
--     input wire               rst_n_dst,
--
--     // APB port from Transport Module
--     input  wire              src_psel,
--     input  wire              src_penable,
--     input  wire              src_pwrite,
--     input  wire [W_ADDR-1:0] src_paddr,
--     input  wire [W_DATA-1:0] src_pwdata,
--     output wire [W_DATA-1:0] src_prdata,
--     output wire              src_pready,
--     output wire              src_pslverr,
--
--     // APB port to Debug Module
--     output wire              dst_psel,
--     output wire              dst_penable,
--     output wire              dst_pwrite,
--     output wire [W_ADDR-1:0] dst_paddr,
--     output wire [W_DATA-1:0] dst_pwdata,
--     input  wire [W_DATA-1:0] dst_prdata,
--     input  wire              dst_pready,
--     input  wire              dst_pslverr
-- );

entity hazard3_apb_async_bridge is
	generic (
		W_ADDR        : positive := 8;
		W_DATA        : positive := 32;
		N_SYNC_STAGES : integer range 2 to integer'high := 2
	);
	port (
		-- Resets assumed to be synchronised externally
		clk_src   : in std_logic;
		rst_src   : in std_logic;

		clk_dst   : in std_logic;
		rst_dst   : in std_logic;

		-- APB port from Transport Module
		src_psel    : in std_logic;
		src_penable : in std_logic;
		src_pwrite  : in std_logic;
		src_paddr   : in std_logic_vector(W_ADDR - 1 downto 0);
		src_pwdata  : in std_logic_vector(W_DATA - 1 downto 0);
		src_prdata  : out std_logic_vector(W_DATA - 1 downto 0);
		src_pready  : out std_logic;

		-- APB port to Debug Module
		src_pslverr : out std_logic;
		dst_psel    : out std_logic;
		dst_penable : out std_logic;
		dst_pwrite  : out std_logic;
		dst_paddr   : out std_logic_vector(W_ADDR - 1 downto 0);
		dst_pwdata  : out std_logic_vector(W_DATA - 1 downto 0);
		dst_prdata  : in std_logic_vector(W_DATA - 1 downto 0);
		dst_pready  : in std_logic;
		dst_pslverr : in std_logic
	);
end entity hazard3_apb_async_bridge;

architecture rtl of hazard3_apb_async_bridge is
	attribute keep : boolean;

	-- Clock-crossing registers
	--
	-- We're using a modified req/ack handshake:
	--
	-- - Initially both req and ack are low
	-- - src asserts req high
	-- - dst responds with ack high and begins transfer
	-- - src deasserts req once it sees ack high
	-- - dst deasserts ack once:
	--     - transfer is complete *and*
	--     - dst sees req deasserted
	-- - Once src sees ack low, a new transfer can begin.
	--
	-- A NRZI toggle handshake might be more appropriate, but can cause spurious
	-- bus accesses when only one side of the link is reset.
	signal src_req_reg : std_logic;
	signal dst_req     : std_logic;
	signal dst_ack_reg : std_logic;
	signal src_ack     : std_logic;

	-- Note the launch registers are not resettable. We maintain setup/hold on
	-- launch-to-capture paths thanks to the req/ack handshake. A stray reset
	-- could violate this.
	--
	-- The req/ack logic itself can be reset safely because the receiving domain
	-- is protected from metastability by a 2FF synchroniser.
	signal src_paddr_pwdata_pwrite_reg : std_logic_vector(W_ADDR + W_DATA downto 0); -- launch
	signal dst_paddr_pwdata_pwrite_reg : std_logic_vector(W_ADDR + W_DATA downto 0); -- capture
	signal dst_prdata_pslverr_reg      : std_logic_vector(W_DATA downto 0); -- launch
	signal src_prdata_pslverr_reg      : std_logic_vector(W_DATA downto 0); -- capture

	signal src_waiting_for_downstream_eg : std_logic;
	signal src_pready_reg                : std_logic;

	signal dst_psel_reg    : std_logic;
	signal dst_penable_reg : std_logic;
	signal dst_bus_finish  : std_logic;


	attribute keep of src_req_reg                 : signal is true;
	attribute keep of dst_ack_reg                 : signal is true;
	attribute keep of src_paddr_pwdata_pwrite_reg : signal is true;
	attribute keep of dst_paddr_pwdata_pwrite_reg : signal is true;
	attribute keep of dst_prdata_pslverr_reg      : signal is true;
	attribute keep of src_prdata_pslverr_reg      : signal is true;
begin

	sync_req : entity work.hazard3_sync_1bit
		generic map(
			N_STAGES => N_SYNC_STAGES
		)
		port map
		(
			clk   => clk_dst,
			rst   => rst_dst,
			i     => src_req_reg,
			o     => dst_req
		);

	sync_ack : entity work.hazard3_sync_1bit
		generic map(
			N_STAGES => N_SYNC_STAGES
		)
		port map
		(
			clk   => clk_src,
			rst   => rst_src,
			i     => dst_ack_reg,
			o     => src_ack
		);

	-- 	------------------------------------------------------------------------
	-- src state machine
	process (clk_src)
	begin
		if rising_edge(clk_src) then
			if ?? rst_src then
				src_req_reg                   <= '0';
				src_waiting_for_downstream_eg <= '0';
				src_prdata_pslverr_reg        <= (others => '0');
				src_pready_reg                <= '1';
			elsif ?? src_waiting_for_downstream_eg then
				if src_req_reg = '1' and src_ack = '1' then
					-- Request was acknowledged, so deassert.
					src_req_reg <= '0';
				elsif src_req_reg = '0' and src_ack = '0' then
					-- Downstream transfer has finished, data is valid.
					src_pready_reg                <= '1';
					src_waiting_for_downstream_eg <= '0';
					-- Note this assignment is cross-domain (but data has been stable
					-- for duration of ack synchronisation delay):
					src_prdata_pslverr_reg <= dst_prdata_pslverr_reg;
				end if;
			else
				-- paddr, pwdata and pwrite are all valid during the setup phase, and
				-- APB defines the setup phase to always last one cycle and proceed
				-- to access phase. So, we can ignore penable, and pready is ignored.
				if src_psel = '1' and src_penable = '0' then
					src_pready_reg                <= '0';
					src_req_reg                   <= '1';
					src_waiting_for_downstream_eg <= '1';
				end if;
			end if;
		end if;
	end process;

	-- Bus request launch register is not resettable
	process (clk_src)
	begin
		if rising_edge(clk_src) then
			if src_psel = '1' and src_waiting_for_downstream_eg = '0' then
				src_paddr_pwdata_pwrite_reg <= src_paddr & src_pwdata & src_pwrite;
			end if;
		end if;
	end process;

	src_prdata  <= src_prdata_pslverr_reg(W_DATA downto 1);
	src_pslverr <= src_prdata_pslverr_reg(0);
	src_pready  <= src_pready_reg;

	-- -------------------------------------------------------------------------
	-- dst state machine

	dst_bus_finish <= dst_penable_reg and dst_pready;

	process (clk_dst)
	begin
		if rising_edge(clk_dst) then
			if ?? rst_dst then
				dst_ack_reg <= '0';
			elsif ?? dst_req then
				dst_ack_reg <= '1';
			elsif dst_req = '0' and dst_ack_reg = '1' and dst_psel_reg = '0' then
				dst_ack_reg <= '0';
			end if;
		end if;
	end process;

	process (clk_dst)
	begin
		if rising_edge(clk_dst) then
			if ?? rst_dst then
				dst_psel_reg                <= '0';
				dst_penable_reg             <= '0';
				dst_paddr_pwdata_pwrite_reg <= (others => '0');
			elsif dst_req = '1' and dst_ack_reg = '0' then
				dst_psel_reg <= '1';
				-- Note this assignment is cross-domain. The src register has been
				-- stable for the duration of the req sync delay.
				dst_paddr_pwdata_pwrite_reg <= src_paddr_pwdata_pwrite_reg;
			elsif dst_psel_reg = '1' and dst_penable_reg = '0' then
				dst_penable_reg <= '1';
			elsif ?? dst_bus_finish then
				dst_psel_reg    <= '0';
				dst_penable_reg <= '0';
			end if;
		end if;
	end process;

	-- Bus response launch register is not resettable
	process (clk_dst)
	begin
		if rising_edge(clk_dst) then
			if ?? dst_bus_finish then
				dst_prdata_pslverr_reg <= dst_prdata & dst_pslverr;
			end if;
		end if;
	end process;

	dst_psel    <= dst_psel_reg;
	dst_penable <= dst_penable_reg;
	dst_paddr   <= dst_paddr_pwdata_pwrite_reg(W_ADDR + W_DATA downto W_DATA + 1);
	dst_pwdata  <= dst_paddr_pwdata_pwrite_reg(W_DATA downto 1);
	dst_pwrite  <= dst_paddr_pwdata_pwrite_reg(0);

end architecture rtl;
