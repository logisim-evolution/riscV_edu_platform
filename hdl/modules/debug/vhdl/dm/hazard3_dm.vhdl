library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.ceil;
use ieee.math_real.log2;

-- Original Verilog comments:
-- /*****************************************************************************\
-- |                      Copyright (C) 2021-2022 Luke Wren                      |
-- |                     SPDX-License-Identifier: Apache-2.0                     |
-- \*****************************************************************************/
--
-- // RISC-V Debug Module for Hazard3. Supports up to 32 cores (1 hart per core).
--
-- `default_nettype none
--
-- module hazard3_dm #(
--     // Where there are multiple harts per DM, the least-indexed hart is the
--     // least-significant on each concatenated hart access bus.
--     parameter N_HARTS      = 1,
--     // Where there are multiple DMs, the address of each DM should be a
--     // multiple of 'h200, so that bits[8:2] decode correctly.
--     parameter NEXT_DM_ADDR = 32'h0000_0000,
--     // Implement support for system bus access:
--     parameter HAVE_SBA     = 1,
--
--     // Do not modify:
--     parameter XLEN         = 32,                               // Do not modify
--     parameter W_HARTSEL    = N_HARTS > 1 ? $clog2(N_HARTS) : 1 // Do not modify
-- ) (
--     // DM is assumed to be in same clock domain as core; clock crossing
--     // (if any) is inside DTM, or between DTM and DM.
--     input  wire                      clk,
--     input  wire                      rst_n,
--
--     // APB access from Debug Transport Module
--     input  wire                      dmi_psel,
--     input  wire                      dmi_penable,
--     input  wire                      dmi_pwrite,
--     input  wire [8:0]                dmi_paddr,
--     input  wire [31:0]               dmi_pwdata,
--     output reg  [31:0]               dmi_prdata,
--     output wire                      dmi_pready,
--     output wire                      dmi_pslverr,
--
--     // Reset request/acknowledge. "req" is a pulse >= 1 cycle wide. "done" is
--     // level-sensitive, goes high once component is out of reset.
--     //
--     // The "sys" reset (ndmreset) is conventionally everything apart from DM +
--     // DTM, but, as per section 3.2 in 0.13.2 debug spec: "Exactly what is
--     // affected by this reset is implementation dependent, as long as it is
--     // possible to debug programs from the first instruction executed." So
--     // this could simply be an all-hart reset.
--     output wire                      sys_reset_req,
--     input  wire                      sys_reset_done,
--     output wire [N_HARTS-1:0]        hart_reset_req,
--     input  wire [N_HARTS-1:0]        hart_reset_done,
--
--     // Hart run/halt control
--     output wire [N_HARTS-1:0]        hart_req_halt,
--     output wire [N_HARTS-1:0]        hart_req_halt_on_reset,
--     output wire [N_HARTS-1:0]        hart_req_resume,
--     input  wire [N_HARTS-1:0]        hart_halted,
--     input  wire [N_HARTS-1:0]        hart_running,
--
--     // Hart access to data0 CSR (assumed to be core-internal but per-hart)
--     output wire [N_HARTS*XLEN-1:0]   hart_data0_rdata,
--     input  wire [N_HARTS*XLEN-1:0]   hart_data0_wdata,
--     input  wire [N_HARTS-1:0]        hart_data0_wen,
--
--     // Hart instruction injection
--     output wire [N_HARTS*32-1:0]     hart_instr_data,
--     output reg  [N_HARTS-1:0]        hart_instr_data_vld,
--     input  wire [N_HARTS-1:0]        hart_instr_data_rdy,
--     input  wire [N_HARTS-1:0]        hart_instr_caught_exception,
--     input  wire [N_HARTS-1:0]        hart_instr_caught_ebreak,
--
--     // System bus access (optional) -- can be hooked up to the standalone AHB
--     // shim (hazard3_sbus_to_ahb.v) or the SBA input port on the processor
--     // wrapper, which muxes SBA into the processor's load/store bus access
--     // port. SBA does not increase debugger bus throughput, but supports
--     // minimally intrusive debug bus access for e.g. Segger RTT.
--     output wire [31:0]               sbus_addr,
--     output wire                      sbus_write,
--     output wire [1:0]                sbus_size,
--     output wire                      sbus_vld,
--     input  wire                      sbus_rdy,
--     input  wire                      sbus_err,
--     output wire [31:0]               sbus_wdata,
--     input  wire [31:0]               sbus_rdata
-- );

entity hazard3_dm is
	generic (
		-- Where there are multiple harts per DM, the least-indexed hart is the
		-- least-significant on each concatenated hart access bus.
		N_HARTS : positive := 1;
		-- Where there are multiple DMs, the address of each DM should be a
		-- multiple of 'h200, so that bits[8:2] decode correctly.
		NEXT_DM_ADDR : std_logic_vector(31 downto 0) := x"00000000";
		-- Implement support for system bus access:
		HAVE_SBA : natural := 1;

		-- Do not modify:
		XLEN      : positive := 32; -- Do not modify
		W_HARTSEL : positive := integer(ceil(log2(real(maximum(2, N_HARTS))))) -- N_HARTS > 1 ? $clog2(N_HARTS) : 1
	);
	port (
		-- DM is assumed to be in same clock domain as core; clock crossing
		-- (if any) is inside DTM, or between DTM and DM.
		clk   : in  std_logic;
		rst_n : in  std_logic;

		-- APB access from Debug Transport Module
		dmi_psel    : in  std_logic;
		dmi_penable : in  std_logic;
		dmi_pwrite  : in  std_logic;
		dmi_paddr   : in  std_logic_vector(8 downto 0);
		dmi_pwdata  : in  std_logic_vector(31 downto 0);
		dmi_prdata  : out std_logic_vector(31 downto 0);
		dmi_pready  : out std_logic;
		dmi_pslverr : out std_logic;

		-- Reset request/acknowledge. "req" is a pulse >= 1 cycle wide. "done" is
		-- level-sensitive, goes high once component is out of reset.
		--
		-- The "sys" reset (ndmreset) is conventionally everything apart from DM +
		-- DTM, but, as per section 3.2 in 0.13.2 debug spec: "Exactly what is
		-- affected by this reset is implementation dependent, as long as it is
		-- possible to debug programs from the first instruction executed." So
		-- this could simply be an all-hart reset.
		sys_reset_req   : out std_logic;
		sys_reset_done  : in  std_logic;
		hart_reset_req  : out std_logic_vector(N_HARTS - 1 downto 0);
		hart_reset_done : in  std_logic_vector(N_HARTS - 1 downto 0);

		-- Hart run/halt control
		hart_req_halt          : out std_logic_vector(N_HARTS - 1 downto 0);
		hart_req_halt_on_reset : out std_logic_vector(N_HARTS - 1 downto 0);
		hart_req_resume        : out std_logic_vector(N_HARTS - 1 downto 0);
		hart_halted            : in  std_logic_vector(N_HARTS - 1 downto 0);
		hart_running           : in  std_logic_vector(N_HARTS - 1 downto 0);

		-- Hart access to data0 CSR (assumed to be core-internal but per-hart)
		hart_data0_rdata : out std_logic_vector(N_HARTS * XLEN - 1 downto 0);
		hart_data0_wdata : in  std_logic_vector(N_HARTS * XLEN - 1 downto 0);
		hart_data0_wen   : in  std_logic_vector(N_HARTS - 1 downto 0);

		-- Hart instruction injection
		hart_instr_data             : out std_logic_vector(N_HARTS * 32 - 1 downto 0);
		hart_instr_data_vld         : out std_logic_vector(N_HARTS - 1 downto 0);
		hart_instr_data_rdy         : in  std_logic_vector(N_HARTS - 1 downto 0);
		hart_instr_caught_exception : in  std_logic_vector(N_HARTS - 1 downto 0);
		hart_instr_caught_ebreak    : in  std_logic_vector(N_HARTS - 1 downto 0);

		-- System bus access (optional) -- can be hooked up to the standalone AHB
		-- shim (hazard3_sbus_to_ahb.v) or the SBA input port on the processor
		-- wrapper, which muxes SBA into the processor's load/store bus access
		-- port. SBA does not increase debugger bus throughput, but supports
		-- minimally intrusive debug bus access for e.g. Segger RTT.
		sbus_addr  : out std_logic_vector(31 downto 0);
		sbus_write : out std_logic;
		sbus_size  : out std_logic_vector(1 downto 0);
		sbus_vld   : out std_logic;
		sbus_rdy   : in  std_logic;
		sbus_err   : in  std_logic;
		sbus_wdata : out std_logic_vector(31 downto 0);
		sbus_rdata : in  std_logic_vector(31 downto 0)
	);
end entity hazard3_dm;

architecture rtl of hazard3_dm is
	function all_harts(value : std_logic) return std_logic_vector is
		variable result : std_logic_vector(N_HARTS - 1 downto 0);
	begin
		result := (others => value);
		return result;
	end function all_harts;

	function replicate_word(value : std_logic_vector) return std_logic_vector is
		variable result : std_logic_vector(N_HARTS * value'length - 1 downto 0);
	begin
		for index in 0 to N_HARTS - 1 loop
			result((index + 1) * value'length - 1 downto index * value'length) := value;
		end loop;
		return result;
	end function replicate_word;

	-- Program buffer is fixed at 2 words plus impebreak. The main thing we care
	-- about is support for efficient memory block transfers using abstractauto;
	-- in this case 2 words + impebreak is sufficient for RV32I, and 1 word +
	-- impebreak is sufficient for RV32IC.
	constant PROGBUF_SIZE : natural := 2;

	-- -------------------------------------------------------------------------
	-- Address constants
	constant ADDR_DATA0 : std_logic_vector(6 downto 0) := "0000100";
	-- Other data registers not present.
	constant ADDR_DMCONTROL : std_logic_vector(6 downto 0) := "0010000";
	constant ADDR_DMSTATUS  : std_logic_vector(6 downto 0) := "0010001";
	constant ADDR_HARTINFO  : std_logic_vector(6 downto 0) := "0010010";
	constant ADDR_HALTSUM1  : std_logic_vector(6 downto 0) := "0010011";
	constant ADDR_HALTSUM0  : std_logic_vector(6 downto 0) := "1000000";
	-- No HALTSUM2+ registers (we don't support >32 harts anyway)
	constant ADDR_HAWINDOWSEL  : std_logic_vector(6 downto 0) := "0010100";
	constant ADDR_HAWINDOW     : std_logic_vector(6 downto 0) := "0010101";
	constant ADDR_ABSTRACTCS   : std_logic_vector(6 downto 0) := "0010110";
	constant ADDR_COMMAND      : std_logic_vector(6 downto 0) := "0010111";
	constant ADDR_ABSTRACTAUTO : std_logic_vector(6 downto 0) := "0011000";
	constant ADDR_CONFSTRPTR0  : std_logic_vector(6 downto 0) := "0011001";
	constant ADDR_CONFSTRPTR1  : std_logic_vector(6 downto 0) := "0011010";
	constant ADDR_CONFSTRPTR2  : std_logic_vector(6 downto 0) := "0011011";
	constant ADDR_CONFSTRPTR3  : std_logic_vector(6 downto 0) := "0011100";
	constant ADDR_NEXTDM       : std_logic_vector(6 downto 0) := "0011101";
	constant ADDR_PROGBUF0     : std_logic_vector(6 downto 0) := "0100000";
	constant ADDR_PROGBUF1     : std_logic_vector(6 downto 0) := "0100001";
	-- No authentication
	constant ADDR_SBCS       : std_logic_vector(6 downto 0) := "0111000";
	constant ADDR_SBADDRESS0 : std_logic_vector(6 downto 0) := "0111001";
	constant ADDR_SBDATA0    : std_logic_vector(6 downto 0) := "0111100";

	constant SBERROR_OK       : std_logic_vector(2 downto 0) := std_logic_vector(to_unsigned(0, 3));
	constant SBERROR_BADADDR  : std_logic_vector(2 downto 0) := std_logic_vector(to_unsigned(2, 3));
	constant SBERROR_BADALIGN : std_logic_vector(2 downto 0) := std_logic_vector(to_unsigned(3, 3));
	constant SBERROR_BADSIZE  : std_logic_vector(2 downto 0) := std_logic_vector(to_unsigned(4, 3));

	constant W_STATE           : positive                               := 4;
	constant S_IDLE            : std_logic_vector(W_STATE - 1 downto 0) := x"0";
	constant S_ISSUE_REGREAD   : std_logic_vector(W_STATE - 1 downto 0) := x"1";
	constant S_ISSUE_REGWRITE  : std_logic_vector(W_STATE - 1 downto 0) := x"2";
	constant S_ISSUE_REGEBREAK : std_logic_vector(W_STATE - 1 downto 0) := x"3";
	constant S_WAIT_REGEBREAK  : std_logic_vector(W_STATE - 1 downto 0) := x"4";
	constant S_ISSUE_PROGBUF0  : std_logic_vector(W_STATE - 1 downto 0) := x"5";
	constant S_ISSUE_PROGBUF1  : std_logic_vector(W_STATE - 1 downto 0) := x"6";
	constant S_ISSUE_IMPEBREAK : std_logic_vector(W_STATE - 1 downto 0) := x"7";
	constant S_WAIT_IMPEBREAK  : std_logic_vector(W_STATE - 1 downto 0) := x"8";

	constant CMDERR_OK          : std_logic_vector(2 downto 0) := std_logic_vector(to_unsigned(0, 3));
	constant CMDERR_BUSY        : std_logic_vector(2 downto 0) := std_logic_vector(to_unsigned(1, 3));
	constant CMDERR_UNSUPPORTED : std_logic_vector(2 downto 0) := std_logic_vector(to_unsigned(2, 3));
	constant CMDERR_EXCEPTION   : std_logic_vector(2 downto 0) := std_logic_vector(to_unsigned(3, 3));
	constant CMDERR_HALTRESUME  : std_logic_vector(2 downto 0) := std_logic_vector(to_unsigned(4, 3));

	-- Output registers:
	signal dmi_prdata_reg          : std_logic_vector(31 downto 0);
	signal hart_instr_data_vld_reg : std_logic_vector(N_HARTS-1 downto 0);

	-- APB is byte-addressed, DM registers are word-addressed.
	signal dmi_regaddr : std_logic_vector(6 downto 0);
	signal dmi_write   : std_logic;
	signal dmi_read    : std_logic;

	-- -------------------------------------------------------------------------
	-- Hart selection
	signal dmactive_reg : std_logic;

	-- Some fiddliness to make sure we get a single-wide zero-valued signal when 
	-- N_HARTS == 1 (so we can use this for indexing of per-hart signals)
	signal hartsel_reg  : std_logic_vector(W_HARTSEL - 1 downto 0);
	signal hartsel_next : std_logic_vector(W_HARTSEL - 1 downto 0);
	-- Also implement the hart array mask if there is more than one hart.
	signal hart_array_mask_reg  : std_logic_vector(N_HARTS - 1 downto 0);
	signal hasel_reg            : std_logic;
	signal hart_array_mask_next : std_logic_vector(N_HARTS - 1 downto 0);
	signal hasel_next           : std_logic;

	-- -------------------------------------------------------------------------
	-- Run/halt/reset control
	-- Normal read/write fields for dmcontrol (note some of these are per-hart
	-- fields that get rotated into dmcontrol based on the current/next hartsel).
	signal dmcontrol_haltreq_reg      : std_logic_vector(N_HARTS - 1 downto 0);
	signal dmcontrol_hartreset_reg    : std_logic_vector(N_HARTS - 1 downto 0);
	signal dmcontrol_resethaltreq_reg : std_logic_vector(N_HARTS - 1 downto 0);
	signal dmcontrol_ndmreset_reg     : std_logic;
	signal dmcontrol_op_mask          : std_logic_vector(N_HARTS - 1 downto 0);

	signal hart_reset_done_prev_reg : std_logic_vector(N_HARTS - 1 downto 0);
	signal dmstatus_havereset_reg   : std_logic_vector(N_HARTS - 1 downto 0);
	signal hart_available           : std_logic_vector(N_HARTS - 1 downto 0);

	signal dmcontrol_ackhavereset : std_logic;

	signal dmstatus_resumeack_reg         : std_logic_vector(N_HARTS - 1 downto 0);
	signal dmcontrol_resumereq_sticky_reg : std_logic_vector(N_HARTS - 1 downto 0);
	signal dmacontrol_resumereq       : std_logic;

	-- System bus access
	signal sbaddress_reg : std_logic_vector(31 downto 0);
	signal sbdata_reg    : std_logic_vector(31 downto 0);

	-- Update logic for address/data registers:
	signal sbbusy_reg           : std_logic;
	signal sbautoincrement_reg  : std_logic;
	signal sbaccess_reg         : std_logic_vector(2 downto 0);
	signal sbdata_write_blocked : std_logic;

	-- Control logic
	signal sbbusyerror_reg             : std_logic;
	signal sbreadonaddr_reg            : std_logic;
	signal sbreadondata_reg            : std_logic;
	signal sberror_reg                 : std_logic_vector(2 downto 0);
	signal sb_current_is_write_reg     : std_logic;
	signal sb_access_illegal_when_busy : std_logic;
	signal sb_want_start_write         : std_logic;
	signal sb_want_start_read          : std_logic;
	signal sb_next_align               : std_logic_vector(1 downto 0);
	signal sb_badalign                 : std_logic;
	signal sb_badsize                  : std_logic;

	-- Abstract command data registers
	signal abstractcs_busy                  : std_logic;
	signal abstract_data0_reg               : std_logic_vector(XLEN - 1 downto 0);
	signal progbuf0_reg                     : std_logic_vector(XLEN - 1 downto 0);
	signal progbuf1_reg                     : std_logic_vector(XLEN - 1 downto 0);
	signal abstractauto_autoexecdata_reg    : std_logic;
	signal abstractauto_autoexecprogbuf_reg : std_logic_vector(1 downto 0);

	-- Abstract command state machine
	signal abstractcs_cmderr_reg        : std_logic_vector(2 downto 0);
	signal abstractcs_cmderr_next       : std_logic_vector(2 downto 0);
	signal acmd_state_reg               : std_logic_vector(W_STATE - 1 downto 0);
	signal acmd_state_next              : std_logic_vector(W_STATE - 1 downto 0);
	signal start_abstract_cmd           : std_logic;
	signal dmi_access_illegal_when_busy : std_logic;
	signal acmd_new                     : std_logic;
	signal acmd_new_postexec            : std_logic;
	signal acmd_new_transfer            : std_logic;
	signal acmd_new_write               : std_logic;
	signal acmd_new_regno               : std_logic_vector(4 downto 0);
	signal acmd_new_unsupported         : std_logic;
	signal acmd_prev_postexec_reg       : std_logic;
	signal acmd_prev_transfer_reg       : std_logic;
	signal acmd_prev_write_reg          : std_logic;
	signal acmd_prev_regno_reg          : std_logic_vector(4 downto 0);
	signal acmd_prev_unsupported_reg    : std_logic;
	signal acmd_postexec                : std_logic;
	signal acmd_transfer                : std_logic;
	signal acmd_write                   : std_logic;
	signal acmd_regno                   : std_logic_vector(4 downto 0);
	signal acmd_unsupported             : std_logic;
	signal hart_instr_data_vld_next     : std_logic_vector(N_HARTS - 1 downto 0);
	signal hart_instr_data_next         : std_logic_vector(31 downto 0);
	signal hart_instr_data_reg          : std_logic_vector(31 downto 0);

	--  Status helper functions
	impure function status_any (
		status_mask : std_logic_vector(N_HARTS - 1 downto 0)
	) return std_logic is
	begin
		-- VHDL-2008 unary 'or' replaces Verilog's '|'
		return status_mask(to_integer(unsigned(hartsel_reg))) or (hasel_reg and ( or (status_mask and hart_array_mask_reg)));
	end function status_any;

	impure function status_all (
		status_mask : std_logic_vector(N_HARTS - 1 downto 0)
	) return std_logic is
	begin
		-- VHDL-2008 unary 'nor' replaces Verilog's '~|'
		return status_mask(to_integer(unsigned(hartsel_reg))) and ((not hasel_reg) or (nor (not status_mask and hart_array_mask_reg)));
	end function status_all;

	impure function status_all_any (
		status_mask : std_logic_vector(N_HARTS - 1 downto 0)
	) return std_logic_vector is
	begin
		return status_all(status_mask) & status_any(status_mask);
	end function status_all_any;
begin

	dmi_write              <= dmi_psel and dmi_penable and dmi_pwrite;
	dmi_read               <= dmi_psel and dmi_penable and (not dmi_pwrite);
	dmi_regaddr            <= dmi_paddr(8 downto 2);
	dmi_pready             <= '1';
	dmi_pslverr            <= '0';
	sys_reset_req          <= dmcontrol_ndmreset_reg;
	hart_reset_req         <= dmcontrol_hartreset_reg;
	hart_req_halt          <= dmcontrol_haltreq_reg;
	hart_req_halt_on_reset <= dmcontrol_resethaltreq_reg;
	hart_req_resume        <= dmcontrol_resumereq_sticky_reg;
	hart_available         <= hart_reset_done and all_harts(sys_reset_done);
	dmcontrol_ackhavereset <= '1' when dmi_write = '1' and dmi_regaddr = ADDR_DMCONTROL and dmi_pwdata(28) = '1' else '0';
	-- Hart selection L138-L150
	has_hartsel : if N_HARTS > 1 generate
		hartsel_next <= dmi_pwdata(16 + W_HARTSEL - 1 downto 16) when (dmi_write = '1' and dmi_regaddr = ADDR_DMCONTROL) else
			hartsel_reg;
	else generate
		hartsel_next <= (others => '0');
	end generate has_hartsel;

	-- L152-L160
	process (clk, rst_n) begin
		if rst_n = '0' then
			hartsel_reg <= (others => '0');
		elsif rising_edge(clk) then
			hartsel_reg <= hartsel_next;
			if dmactive_reg = '0' then
				hartsel_reg <= (others => '0');
			end if;
		end if;
	end process;

	-- L168-L182
	has_array_mask : if N_HARTS > 1 generate
		hart_array_mask_next <= dmi_pwdata(N_HARTS - 1 downto 0) when (dmi_write = '1' and dmi_regaddr = ADDR_HAWINDOW) else
			hart_array_mask_reg;
		hasel_next <= dmi_pwdata(26) when (dmi_write = '1' and dmi_regaddr = ADDR_DMCONTROL) else
			hasel_reg;
	else generate
		hart_array_mask_next <= (others => '0');
		hasel_next           <= '0';
	end generate has_array_mask;

	-- L184-L195
	process (clk, rst_n) begin
		if rst_n = '0' then
			hart_array_mask_reg <= (others => '0');
			hasel_reg           <= '0';
		elsif rising_edge(clk) then
			hart_array_mask_reg <= hart_array_mask_next;
			hasel_reg           <= hasel_next;

			if dmactive_reg = '0' then
				hart_array_mask_reg <= (others => '0');
				hasel_reg           <= '0';
			end if;
		end if;
	end process;

	-- -------------------------------------------------------------------------
	-- Run/halt/reset control
	--
	-- Normal read/write fields for dmcontrol (note some of these are per-hart
	-- fields that get rotated into dmcontrol based on the current/next hartsel).

	-- L209-L224
	dmacontrol_multiple_harts : if N_HARTS > 1 generate
		dmcontrol_op_mask <= ( all_harts('0') or (all_harts(hasel_next) and hart_array_mask_reg) ) 
							   when (to_integer(unsigned(hartsel_next)) >= N_HARTS) else 
							 ( std_logic_vector(shift_left(to_unsigned(1, N_HARTS), to_integer(unsigned(hartsel_next)))) or (all_harts(hasel_next) and hart_array_mask_reg) );
	else generate
		dmcontrol_op_mask <= (others => '1');
	end generate dmacontrol_multiple_harts;

	-- L226-L255
	process (clk, rst_n) begin
		if rst_n = '0' then
			dmactive_reg 			   <= '0';
			dmcontrol_ndmreset_reg     <= '0';
			dmcontrol_hartreset_reg    <= (others => '0');
			dmcontrol_haltreq_reg      <= (others => '0');
			dmcontrol_resethaltreq_reg <= (others => '0');
		elsif rising_edge(clk) then
			if dmactive_reg = '0' then
				if dmi_write = '1' and dmi_regaddr = ADDR_DMCONTROL then
					dmactive_reg <= dmi_pwdata(0);
				end if;
				dmcontrol_ndmreset_reg     <= '0';
				dmcontrol_hartreset_reg    <= (others => '0');
				dmcontrol_haltreq_reg      <= (others => '0');
				dmcontrol_resethaltreq_reg <= (others => '0');
			elsif dmi_write = '1' and dmi_regaddr = ADDR_DMCONTROL then
				dmactive_reg               <= dmi_pwdata(0);
				dmcontrol_ndmreset_reg     <= dmi_pwdata(1);
				dmcontrol_haltreq_reg      <= ( dmcontrol_haltreq_reg and not dmcontrol_op_mask ) or 
										      ( all_harts(dmi_pwdata(31)) and dmcontrol_op_mask );
				dmcontrol_hartreset_reg    <= ( dmcontrol_hartreset_reg and not dmcontrol_op_mask ) or
										      ( all_harts(dmi_pwdata(29)) and dmcontrol_op_mask );
				dmcontrol_resethaltreq_reg <= (dmcontrol_resethaltreq_reg and
										  not (all_harts(dmi_pwdata(2)) and dmcontrol_op_mask)) 
										   or (all_harts(dmi_pwdata(3)) and dmcontrol_op_mask);
			end if;
		end if;
	end process;

	process (clk, rst_n)
	begin
		if rst_n = '0' then
			hart_reset_done_prev_reg <= (others => '0');
		elsif rising_edge(clk) then
			hart_reset_done_prev_reg <= hart_reset_done;
		end if;
	end process;

	-- L266-272
	process (clk, rst_n) begin
		if rst_n = '0' then
			dmstatus_havereset_reg <= (others => '0');
		elsif rising_edge(clk) then
			dmstatus_havereset_reg <=         (dmstatus_havereset_reg
									  or      (hart_reset_done and not hart_reset_done_prev_reg))
									  and not (all_harts(dmcontrol_ackhavereset) and dmcontrol_op_mask);
			
			if dmactive_reg = '0' then
				dmstatus_havereset_reg <= (others => '0');
			end if;
		end if;
	end process;

	-- Note: we are required to ignore resumereq when haltreq is also set, as per
	-- spec (odd since the host is forbidden from writing both at once anyway).
	-- The wording is odd, it refers only to `haltreq` which is specifically the
	-- write-only `dmcontrol` field, not the underlying halt request state bits.
	-- L294
	dmacontrol_resumereq <= '1' when (dmi_write = '1' and dmi_regaddr = ADDR_DMCONTROL and dmi_pwdata(30) = '1' and dmi_pwdata(31) = '0') else '0';

	-- L297-L313
	process (clk, rst_n) begin
		if rst_n = '0' then
			dmstatus_resumeack_reg <= (others => '0');
			dmcontrol_resumereq_sticky_reg <= (others => '0');
		elsif rising_edge(clk) then
			dmstatus_resumeack_reg <= (dmstatus_resumeack_reg
									  or      (dmcontrol_resumereq_sticky_reg and hart_running and hart_available))
									  and not (all_harts(dmacontrol_resumereq) and dmcontrol_op_mask);
			dmcontrol_resumereq_sticky_reg <= (dmcontrol_resumereq_sticky_reg
													  and not (hart_running and hart_available))
													  or      (all_harts(dmacontrol_resumereq) and dmcontrol_op_mask);

			if dmactive_reg = '0' then
				dmstatus_resumeack_reg <= (others => '0');
				dmcontrol_resumereq_sticky_reg <= (others => '0');
			end if;
		end if;
	end process;

	-- L331-L365
	process (clk, rst_n) begin
		if rst_n = '0' then
			sbaddress_reg <= (others => '0');
			sbdata_reg <= (others => '0');
		elsif rising_edge(clk) then
			if dmactive_reg = '0' then
				sbaddress_reg <= (others => '0');
				sbdata_reg <= (others => '0');
			elsif HAVE_SBA = 1 then
				if dmi_write = '1' and dmi_regaddr = ADDR_SBDATA0 and sbdata_write_blocked = '0' then
					-- Note sbbusyerror and sberror block writes to sbdata0, as the
					-- write is required to have no side effects when they are set.
					sbdata_reg <= dmi_pwdata;
				elsif sbbusy_reg = '1' and sbus_rdy = '1' and sb_current_is_write_reg = '0' and sbus_err = '0' then
					-- Make sure the lower byte lanes see appropriately shifted data as
					-- long as the transfer is naturally aligned
					case sbaddress_reg(1 downto 0) is
						when "01" => sbdata_reg <= sbus_rdata(31 downto 8)  & sbus_rdata(15 downto 8);
						when "10" => sbdata_reg <= sbus_rdata(31 downto 16) & sbus_rdata(31 downto 16);
						when "11" => sbdata_reg <= sbus_rdata(31 downto 8)  & sbus_rdata(31 downto 24);
						when others => sbdata_reg <= sbus_rdata;
					end case;
				end if;
				if dmi_write = '1' and dmi_regaddr = ADDR_SBADDRESS0 and sbbusy_reg = '0' then
					-- Note sbaddress can't be written when busy, but
					-- sberror/sbbusyerror do not prevent writes.
					sbaddress_reg <= dmi_pwdata;
				elsif sbbusy_reg = '1' and sbus_rdy = '1' and sbus_err = '0' and sbautoincrement_reg = '1' then
					-- Note: address increments only following a successful transfer.
					-- Spec 0.13.2 weirdly implies address should increment following
					-- a sbdata0 read with sbautoincrement=1 and sbreadondata=0, but
					-- this seems to be a typo, fixed in later versions.
					sbaddress_reg <= std_logic_vector(unsigned(sbaddress_reg) + 1) when (sbaccess_reg(1 downto 0) = "00") else
									 std_logic_vector(unsigned(sbaddress_reg) + 2) when (sbaccess_reg(1 downto 0) = "01") else
									 std_logic_vector(unsigned(sbaddress_reg) + 4);
				end if;
			end if;
		end if;				
	end process;

	-- Control logic:
	sbdata_write_blocked <= sbbusy_reg or sbbusyerror_reg or (or sberror_reg);

	-- Notes on behaviour of sbbusyerror: the sbbusyerror description says:
	--
	--  "Set when the debugger attempts to read data while a read is in progress,
	--   or when the debugger initiates a new access while one is already in
	--   progress (while sbbusy is set)."
	--
	-- However, sbaddress0 description says:
	--
	--  "When the system bus master is busy, writes to this register will set
	--   sbbusyerror and don’t do anything else."
	--
	-- ...not conditioned on sbreadonaddr. Likewise the sbdata0 description says:
	--
	--   "If the bus master is busy then accesses set sbbusyerror, and don’t do
	--    anything else."
	--
	-- ...not conditioned on sbreadondata. We are going to take the union of all
	-- the cases where the spec says we should raise an error:

	-- L401
	sb_access_illegal_when_busy <= '1' when (
		(dmi_regaddr = ADDR_SBDATA0 and (dmi_read = '1' or dmi_write = '1')) or 
		(dmi_regaddr = ADDR_SBADDRESS0 and dmi_write = '1')
		) else '0';

	-- L405
	sb_want_start_write <= '1' when (dmi_write = '1' and dmi_regaddr = ADDR_SBDATA0) else '0';
	
	-- L407
	sb_want_start_read <= '1' when (
		(sbreadonaddr_reg = '1' and dmi_write = '1' and dmi_regaddr = ADDR_SBADDRESS0) or
		(sbreadondata_reg = '1' and dmi_read = '1' and dmi_regaddr = ADDR_SBDATA0)
		) else '0';
	
	-- L411
	sb_next_align <= dmi_pwdata(1 downto 0) when (sbreadonaddr_reg = '1' and dmi_write = '1' and dmi_regaddr = ADDR_SBADDRESS0) else sbaddress_reg(1 downto 0);
	
	-- L414
	sb_badalign <= '1' when ( 
		(sbaccess_reg = "001" and sb_next_align(0) = '1') or
		(sbaccess_reg = "010" and (or sb_next_align(1 downto 0)) = '1')
		) else '0';
	
	-- L418
	sb_badsize <= '1' when unsigned(sbaccess_reg) > to_unsigned(2, 3) else '0';

	-- L420-L470
	process (clk, rst_n) begin
		if rst_n = '0' then
			sbbusy_reg 				<= '0';
			sbbusyerror_reg 		<= '0';
			sbreadonaddr_reg		<= '0';
			sbreadondata_reg		<= '0';
			sbaccess_reg 			<= (others => '0');
			sbautoincrement_reg 	<= '0';
			sberror_reg 			<= SBERROR_OK;
			sb_current_is_write_reg <= '0';
		elsif rising_edge(clk) then
			if dmactive_reg = '0' then
				sbbusy_reg 				<= '0';
				sbbusyerror_reg 		<= '0';
				sbreadonaddr_reg 		<= '0';
				sbreadondata_reg 		<= '0';
				sbaccess_reg 			<= (others => '0');
				sbautoincrement_reg 	<= '0';
				sberror_reg 			<= SBERROR_OK;
				sb_current_is_write_reg <= '0';
			elsif HAVE_SBA = 1 then
				if dmi_write = '1' and dmi_regaddr = ADDR_SBCS then
					sbbusyerror_reg 	<= sbbusyerror_reg and not dmi_pwdata(22);
					sbreadonaddr_reg 	<= dmi_pwdata(20);
					sbaccess_reg 		<= dmi_pwdata(19 downto 17);
					sbautoincrement_reg <= dmi_pwdata(16);
					sbreadondata_reg 	<= dmi_pwdata(15);
					sberror_reg 		<= sberror_reg and not dmi_pwdata(14 downto 12);
				end if;
				if sbbusy_reg = '1' then
					if sb_access_illegal_when_busy then
						sbbusyerror_reg <= '1';
					end if;
					if sbus_vld = '1' and sbus_rdy = '1' then
						sbbusy_reg <= '0';
						if sbus_err = '1' then
							sberror_reg <= SBERROR_BADADDR;
						end if;
					end if;
				elsif (sb_want_start_read or sb_want_start_write) = '1' and (or sberror_reg) = '0' and sbbusyerror_reg = '0' then
					if sb_badsize = '1' then 
						sberror_reg <= SBERROR_BADSIZE;
					elsif sb_badalign = '1' then
						sberror_reg <= SBERROR_BADALIGN;
					else
						sbbusy_reg <= '1';
						sb_current_is_write_reg <= sb_want_start_write;
					end if;
				end if;
			end if;
		end if;
	end process;

	-- L472-L475
	sbus_addr <= sbaddress_reg;
	sbus_write <= sb_current_is_write_reg;
	sbus_size <= sbaccess_reg(1 downto 0);
	sbus_vld <= sbbusy_reg;

	-- Replicate byte lanes to handle naturally-aligned cases
	-- L478
	with sbaccess_reg(1 downto 0) select
		sbus_wdata <= (sbdata_reg(7 downto 0) & sbdata_reg(7 downto 0) & sbdata_reg(7 downto 0) & sbdata_reg(7 downto 0))	when "00",
					  (sbdata_reg(15 downto 0) & sbdata_reg(15 downto 0))													when "01",
					  sbdata_reg																							when others;
	
	-- -------------------------------------------------------------------------
	-- Abstract command data registers
	
	-- The same data0 register is aliased as a CSR on all harts connected to this
	-- DM. Cores may read data0 as a CSR when in debug mode, and may write it when:
	--
	-- - That core is in debug mode, and...
	-- - We are currently executing an abstract command on that core
	--
	-- The DM can also read/write data0 at all times.

	-- L496
	hart_data0_rdata <= replicate_word(abstract_data0_reg);

	-- L498-512
	update_hart_data0 : process (clk, rst_n)
	begin
		if rst_n = '0' then
			abstract_data0_reg <= (others => '0');
		elsif rising_edge(clk) then
			if dmactive_reg = '0' then
				abstract_data0_reg <= (others => '0');
				
			elsif (dmi_write = '1' and dmi_regaddr = ADDR_DATA0) then
				abstract_data0_reg <= dmi_pwdata;
				
			else
				for i in 0 to N_HARTS - 1 loop -- TODO has this been translated correctly?
					-- Convert hartsel to integer for a clean comparison with 'i'
					if (to_integer(unsigned(hartsel_reg)) = i) and (hart_data0_wen(i) = '1') and 
							(hart_halted(i) = '1') and (abstractcs_busy = '1') then
						abstract_data0_reg <= hart_data0_wdata((i * XLEN) + XLEN - 1 downto i * XLEN);
					end if;
				end loop;
			end if;
		end if;
	end process update_hart_data0;

	-- L517-L530
	update_progbufs_proc : process (clk, rst_n)
	begin
		if rst_n = '0' then
			progbuf0_reg <= (others => '0');
			progbuf1_reg <= (others => '0');
		elsif rising_edge(clk) then
			if dmactive_reg = '0' then
				progbuf0_reg <= (others => '0');
				progbuf1_reg <= (others => '0');
			elsif (dmi_write = '1' and abstractcs_busy = '0') then
				-- Standard VHDL practice maps consecutive Verilog if-statements like this.
				-- (Though practically, dmi_regaddr can only be one value at a time)
				if dmi_regaddr = ADDR_PROGBUF0 then
					progbuf0_reg <= dmi_pwdata;
				end if;
				if dmi_regaddr = ADDR_PROGBUF1 then
					progbuf1_reg <= dmi_pwdata;
				end if;
			end if;
		end if;
	end process update_progbufs_proc;


	-- L535-L546
	update_abstractauto_proc : process (clk, rst_n)
	begin
		if rst_n = '0' then
			abstractauto_autoexecdata_reg    <= '0';
			abstractauto_autoexecprogbuf_reg <= "00";
		elsif rising_edge(clk) then
			if dmactive_reg = '0' then
				abstractauto_autoexecdata_reg    <= '0';
				abstractauto_autoexecprogbuf_reg <= "00";
			elsif (dmi_write = '1' and dmi_regaddr = ADDR_ABSTRACTAUTO) then
				abstractauto_autoexecdata_reg    <= dmi_pwdata(0);
				abstractauto_autoexecprogbuf_reg <= dmi_pwdata(17 downto 16);
			end if;
		end if;
	end process update_abstractauto_proc;

	-- -------------------------------------------------------------------------
	-- Abstract command state machine

	-- L575
	abstractcs_busy <= '1' when acmd_state_reg /= S_IDLE else '0';

	-- L577
	start_abstract_cmd <= '1' when (
		(abstractcs_cmderr_reg = CMDERR_OK) and 
		(abstractcs_busy = '0') and 
		(
			(dmi_write = '1' and dmi_regaddr = ADDR_COMMAND) or
			((dmi_write = '1' or dmi_read = '1') and abstractauto_autoexecdata_reg = '1' and dmi_regaddr = ADDR_DATA0) or
			((dmi_write = '1' or dmi_read = '1') and abstractauto_autoexecprogbuf_reg(0) = '1' and dmi_regaddr = ADDR_PROGBUF0) or
			((dmi_write = '1' or dmi_read = '1') and abstractauto_autoexecprogbuf_reg(1) = '1' and dmi_regaddr = ADDR_PROGBUF1)
		)
	) else '0';

	-- L584
	dmi_access_illegal_when_busy <= '1' when (
		(dmi_write = '1' and (
			dmi_regaddr = ADDR_ABSTRACTCS or 
			dmi_regaddr = ADDR_COMMAND or 
			dmi_regaddr = ADDR_ABSTRACTAUTO or
			dmi_regaddr = ADDR_DATA0 or 
			dmi_regaddr = ADDR_PROGBUF0 or 
			dmi_regaddr = ADDR_PROGBUF1
		)) or
		(dmi_read = '1' and (
			dmi_regaddr = ADDR_DATA0 or 
			dmi_regaddr = ADDR_PROGBUF0 or 
			dmi_regaddr = ADDR_PROGBUF1
		))
	) else '0';

	-- Decode what acmd may be triggered on this cycle, and whether it is
	-- supported -- command source may be a registered version of most recent
	-- command (if abstractauto is used) or a fresh command off the bus. We don't
	-- register the entire write data; repeats of unsupported commands are
	-- detected by just registering that the last written command was
	-- unsupported.

	-- L598
	acmd_new <= '1' when dmi_write = '1' and dmi_regaddr = ADDR_COMMAND else '0';
	
	-- L600-L603
	acmd_new_postexec <= dmi_pwdata(18);
	acmd_new_transfer <= dmi_pwdata(17);
	acmd_new_write <= dmi_pwdata(16);
	acmd_new_regno <= dmi_pwdata(4 downto 0);

	-- Note: regno and aarsize are permitted to have otherwise-invalid values if
	-- the transfer flag is not set.
	-- L607-L612
	acmd_new_unsupported <= '1' when (
		(dmi_pwdata(31 downto 24) /= x"00") or								-- Only Access Register command supported
		(dmi_pwdata(22 downto 20) /= "010" and acmd_new_transfer = '1') or	-- Must be 32 bits in size
		(dmi_pwdata(19) = '1') or											-- aarpostincrement not supported
		(dmi_pwdata(15 downto 12) /= x"1" and acmd_new_transfer = '1') or	-- Only core register access supported
		(dmi_pwdata(11 downto 5)  /= "0000000" and acmd_new_transfer = '1')	-- Only GPRs supported
		) else '0';
	
	-- L620-640
	process (clk, rst_n) begin
		if rst_n = '0' then
			acmd_prev_postexec_reg    <= '0';
			acmd_prev_transfer_reg 	  <= '0';
			acmd_prev_write_reg 	  <= '0';
			acmd_prev_regno_reg 	  <= (others => '0');
			acmd_prev_unsupported_reg <= '1';
		elsif rising_edge(clk) then
			if dmactive_reg = '0' then
				acmd_prev_postexec_reg 	  <= '0';
				acmd_prev_transfer_reg 	  <= '0';
				acmd_prev_write_reg 	  <= '0';
				acmd_prev_regno_reg 	  <= (others => '0');
				acmd_prev_unsupported_reg <= '1';
			elsif start_abstract_cmd = '1' and acmd_new = '1' then
				acmd_prev_postexec_reg    <= acmd_new_postexec;
				acmd_prev_transfer_reg 	  <= acmd_new_transfer;
				acmd_prev_write_reg 	  <= acmd_new_write;
				acmd_prev_regno_reg 	  <= acmd_new_regno;
				acmd_prev_unsupported_reg <= acmd_new_unsupported;
			end if;
		end if;
	end process;

	-- L642-L646
	acmd_postexec    <= acmd_new_postexec 	 when acmd_new = '1' else acmd_prev_postexec_reg;
	acmd_transfer    <= acmd_new_transfer 	 when acmd_new = '1' else acmd_prev_transfer_reg;
	acmd_write 	     <= acmd_new_write   	 when acmd_new = '1' else acmd_prev_write_reg;
	acmd_regno    	 <= acmd_new_regno 	 	 when acmd_new = '1' else acmd_prev_regno_reg;
	acmd_unsupported <= acmd_new_unsupported when acmd_new = '1' else acmd_prev_unsupported_reg;

	-- L648-L730
	acmd_next_state_logic : process(all)
		variable h_idx : integer;
	begin
		h_idx := to_integer(unsigned(hartsel_reg));

		-- Default: no state change (prevents inferred latches)
		acmd_state_next        <= acmd_state_reg;
		abstractcs_cmderr_next <= abstractcs_cmderr_reg;

		-- Independent error-checking overrides
		if (dmi_write = '1' and dmi_regaddr = ADDR_ABSTRACTCS and abstractcs_busy = '0') then
			abstractcs_cmderr_next <= abstractcs_cmderr_reg and (not dmi_pwdata(10 downto 8));
		end if;
		
		if (abstractcs_cmderr_reg = CMDERR_OK and abstractcs_busy = '1' and dmi_access_illegal_when_busy = '1') then
			abstractcs_cmderr_next <= CMDERR_BUSY;
		end if;
		
		if (acmd_state_reg /= S_IDLE and hart_instr_caught_exception(h_idx) = '1') then
			abstractcs_cmderr_next <= CMDERR_EXCEPTION;
		end if;

		-- FSM Next-State Logic
		case acmd_state_reg is
			when S_IDLE =>
				if start_abstract_cmd = '1' then
					if (hart_halted(h_idx) = '0' or hart_available(h_idx) = '0') then
						abstractcs_cmderr_next <= CMDERR_HALTRESUME;
					elsif acmd_unsupported = '1' then
						abstractcs_cmderr_next <= CMDERR_UNSUPPORTED;
					else
						if (acmd_transfer = '1' and acmd_write = '1') then
							acmd_state_next <= S_ISSUE_REGWRITE;
						elsif (acmd_transfer = '1' and acmd_write = '0') then
							acmd_state_next <= S_ISSUE_REGREAD;
						elsif acmd_postexec = '1' then
							acmd_state_next <= S_ISSUE_PROGBUF0;
						else
							acmd_state_next <= S_IDLE;
						end if;
					end if;
				end if;

			when S_ISSUE_REGREAD =>
				if hart_instr_data_rdy(h_idx) = '1' then
					acmd_state_next <= S_ISSUE_REGEBREAK;
				end if;
				
			when S_ISSUE_REGWRITE =>
				if hart_instr_data_rdy(h_idx) = '1' then
					acmd_state_next <= S_ISSUE_REGEBREAK;
				end if;
				
			when S_ISSUE_REGEBREAK =>
				if hart_instr_data_rdy(h_idx) = '1' then
					acmd_state_next <= S_WAIT_REGEBREAK;
				end if;
				
			when S_WAIT_REGEBREAK =>
				if hart_instr_caught_ebreak(h_idx) = '1' then
					if acmd_prev_postexec_reg = '1' then
						acmd_state_next <= S_ISSUE_PROGBUF0;
					else
						acmd_state_next <= S_IDLE;
					end if;
				end if;

			when S_ISSUE_PROGBUF0 =>
				if hart_instr_data_rdy(h_idx) = '1' then
					acmd_state_next <= S_ISSUE_PROGBUF1;
				end if;
				
			when S_ISSUE_PROGBUF1 =>
				if (hart_instr_caught_exception(h_idx) = '1' or hart_instr_caught_ebreak(h_idx) = '1') then
					acmd_state_next <= S_IDLE;
				elsif hart_instr_data_rdy(h_idx) = '1' then
					acmd_state_next <= S_ISSUE_IMPEBREAK;
				end if;
				
			when S_ISSUE_IMPEBREAK =>
				if (hart_instr_caught_exception(h_idx) = '1' or hart_instr_caught_ebreak(h_idx) = '1') then
					acmd_state_next <= S_IDLE;
				elsif hart_instr_data_rdy(h_idx) = '1' then
					acmd_state_next <= S_WAIT_IMPEBREAK;
				end if;
				
			when S_WAIT_IMPEBREAK =>
				if (hart_instr_caught_exception(h_idx) = '1' or hart_instr_caught_ebreak(h_idx) = '1') then
					acmd_state_next <= S_IDLE;
				end if;

			when others =>
				-- Unreachable
				null;
				
		end case;
	end process acmd_next_state_logic;

	-- L732-L743
	process (clk, rst_n) begin
		if rst_n = '0' then
			abstractcs_cmderr_reg <= CMDERR_OK;
			acmd_state_reg <= S_IDLE;
		elsif rising_edge(clk) then
			abstractcs_cmderr_reg <= abstractcs_cmderr_next;
			acmd_state_reg <= acmd_state_next;

			if dmactive_reg = '0' then
				abstractcs_cmderr_reg <= CMDERR_OK;
				acmd_state_reg <= S_IDLE;
			end if;
		end if;
	end process;

	-- L745
	hart_instr_data_vld_next <= std_logic_vector(shift_left(to_unsigned(1, N_HARTS), to_integer(unsigned(hartsel_reg)))) 
	when (acmd_state_next = S_ISSUE_REGREAD or 
		  acmd_state_next = S_ISSUE_REGWRITE or 
		  acmd_state_next = S_ISSUE_REGEBREAK or
		  acmd_state_next = S_ISSUE_PROGBUF0 or 
		  acmd_state_next = S_ISSUE_PROGBUF1 or 
		  acmd_state_next = S_ISSUE_IMPEBREAK) else
	(others => '0');

	-- L750
	with acmd_state_next select
		hart_instr_data_next <= 
			x"bff02073" or (x"00000" & acmd_regno & "0000000")            when S_ISSUE_REGWRITE,
			x"bff01073" or (x"000"   & acmd_regno & (14 downto 0 => '0')) when S_ISSUE_REGREAD,
			progbuf0_reg                                                  when S_ISSUE_PROGBUF0,
			progbuf1_reg                                                  when S_ISSUE_PROGBUF1,
			x"00100073"                                                   when others;
	
	-- L758
	hart_instr_data <= replicate_word(hart_instr_data_reg);

	-- L760-L770
	process (clk, rst_n) begin
		if rst_n = '0' then
			hart_instr_data_vld_reg <= (others => '0');
			hart_instr_data_reg <= (others => '0');
		elsif rising_edge(clk) then
			hart_instr_data_vld_reg <= hart_instr_data_vld_next;
			if unsigned(hart_instr_data_vld_next) /= 0 then
				hart_instr_data_reg <= hart_instr_data_next;
			end if;
		end if;
	end process;

	-- Output registers
	hart_instr_data_vld <= hart_instr_data_vld_reg;

	-- DMI read data mux
	-- L802-L898
	-- TODO dmi_prdata_reg is instantiated as a latch here??
	dmi_read_mux_proc : process(all)
		variable v_allnonexistent : std_logic;
		variable v_anynonexistent : std_logic;
		variable v_sba_mask       : std_logic_vector(31 downto 0);
	begin
		-- 1. Pre-compute boolean evaluations for DMSTATUS
		if to_integer(unsigned(hartsel_reg)) >= N_HARTS then
			v_anynonexistent := '1';
		else
			v_anynonexistent := '0';
		end if;

		if (v_anynonexistent = '1') and not (hasel_reg = '1' and (or hart_array_mask_reg) = '1') then
			v_allnonexistent := '1';
		else
			v_allnonexistent := '0';
		end if;

		-- 2. Pre-compute SBA mask
		-- Assumes HAVE_SBA is an integer generic (e.g., 1 or 0)
		-- If HAVE_SBA is a std_logic, change condition to: if HAVE_SBA = '1' then
		if HAVE_SBA = 1 then
			v_sba_mask := (others => '1');
		else
			v_sba_mask := (others => '0');
		end if;

		-- 3. Multiplex register data
		dmi_prdata_reg <= (others => '0');
		case dmi_regaddr is
			when ADDR_DATA0 =>        
				dmi_prdata_reg <= abstract_data0_reg;

			when ADDR_DMCONTROL =>    
				dmi_prdata_reg <= '0' &                                -- haltreq is a W-only field
							  '0' &                                    -- resumereq is a W1 field
							  status_any(dmcontrol_hartreset_reg) &
							  '0' &                                    -- ackhavereset is a W1 field
							  '0' &                                    -- reserved
							  hasel_reg &
							  (9 - W_HARTSEL downto 0 => '0') &        -- hartsello padding
							  hartsel_reg & 
							  "0000000000" &                           -- hartselhi
							  "00" &                                   -- reserved
							  "00" &                                   -- set/clrresethaltreq are W1 fields
							  dmcontrol_ndmreset_reg &
							  dmactive_reg;

			when ADDR_DMSTATUS =>     
				dmi_prdata_reg <= "000000000" &                        -- reserved
							  '1' &                                    -- impebreak = 1
							  "00" &                                   -- reserved
							  status_all_any(dmstatus_havereset_reg) & -- allhavereset, anyhavereset (2 bits)
							  status_all_any(dmstatus_resumeack_reg) & -- allresumeack, anyresumeack (2 bits)
							  v_allnonexistent &                       -- allnonexistent (1 bit)
							  v_anynonexistent &                       -- anynonexistent (1 bit)
							  status_all_any(not hart_available) &     -- allunavail, anyunavail (2 bits)
							  status_all_any(hart_running and hart_available) & -- allrunning, anyrunning (2 bits)
							  status_all_any(hart_halted and hart_available) &  -- allhalted, anyhalted (2 bits)
							  '1' &                                    -- authenticated
							  '0' &                                    -- authbusy
							  '1' &                                    -- hasresethaltreq = 1
							  '0' &                                    -- confstrptrvalid
							  x"2";                                    -- version = 2 (4 bits)

			when ADDR_HARTINFO =>     
				dmi_prdata_reg <= x"00" &                              -- reserved
							  x"0" &                                   -- nscratch = 0
							  "000" &                                  -- reserved
							  '0' &                                    -- dataccess = 0
							  x"1" &                                   -- datasize = 1
							  x"bff";                                  -- dataaddr

			when ADDR_HALTSUM0 =>     
				dmi_prdata_reg <= (XLEN - N_HARTS - 1 downto 0 => '0') &
							  (hart_halted and hart_available);

			when ADDR_HALTSUM1 =>     
				dmi_prdata_reg <= (XLEN - 2 downto 0 => '0') &
							  (or (hart_halted and hart_available));   -- VHDL-2008 unary OR

			when ADDR_HAWINDOWSEL =>  
				dmi_prdata_reg <= x"00000000";

			when ADDR_HAWINDOW =>     
				dmi_prdata_reg <= (31 - N_HARTS downto 0 => '0') &
							  hart_array_mask_reg;

			when ADDR_ABSTRACTCS =>   
				dmi_prdata_reg <= "000" &                              -- reserved
							  "00010" &                                -- progbufsize = 2
							  "00000000000" &                          -- reserved
							  abstractcs_busy &
							  '0' &
							  abstractcs_cmderr_reg & 
							  x"0" &
							  x"1";                                    -- datacount = 1

			when ADDR_ABSTRACTAUTO => 
				dmi_prdata_reg <= "00000000000000" &
							  abstractauto_autoexecprogbuf_reg &
							  (14 downto 0 => '0') &
							  abstractauto_autoexecdata_reg;

			when ADDR_SBCS =>          
				dmi_prdata_reg <= ( "001" &                            -- version = 1
								"000000" &
								sbbusyerror_reg &
								sbbusy_reg &
								sbreadonaddr_reg &
								sbaccess_reg &                         -- RISC-V Spec defines as 3 bits
								sbautoincrement_reg &
								sbreadondata_reg &
								sberror_reg &                          -- 3 bits
								"0100000" &                            -- sbasize = 32 (7 bits)
								"00111"                                -- supported transfers (5 bits)
							  ) and v_sba_mask;

			when ADDR_SBDATA0 =>      
				dmi_prdata_reg <= sbdata_reg and v_sba_mask;
				
			when ADDR_SBADDRESS0 =>   
				dmi_prdata_reg <= sbaddress_reg and v_sba_mask;
				
			when ADDR_CONFSTRPTR0 =>  
				dmi_prdata_reg <= x"4C29_6328";
				
			when ADDR_CONFSTRPTR1 =>  
				dmi_prdata_reg <= x"2065_6B75";
				
			when ADDR_CONFSTRPTR2 =>  
				dmi_prdata_reg <= x"6E65_7257";
				
			when ADDR_CONFSTRPTR3 =>  
				dmi_prdata_reg <= x"3132_2720";
				
			when ADDR_NEXTDM =>       
				dmi_prdata_reg <= NEXT_DM_ADDR;
				
			when ADDR_PROGBUF0 =>     
				dmi_prdata_reg <= progbuf0_reg;
				
			when ADDR_PROGBUF1 =>     
				dmi_prdata_reg <= progbuf1_reg;
				
			when others =>           
				dmi_prdata_reg <= (others => '0');
				
		end case;
	end process dmi_read_mux_proc;

	dmi_prdata <= dmi_prdata_reg;

end architecture rtl;
