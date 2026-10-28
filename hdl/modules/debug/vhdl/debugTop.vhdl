library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.ceil;
use ieee.math_real.log2;

entity debugTop is
    generic(
        -- Where there are multiple harts per DM, the least-indexed hart is the
        -- least-significant on each concatenated hart access bus.
        N_HARTS         : positive                       := 1;
        -- Where there are multiple DMs, the address of each DM should be a
        -- multiple of 'h200, so that bits[8:2] decode correctly.
        NEXT_DM_ADDR    : std_logic_vector(31 downto 0)  := x"0000_0000";
        -- Implement support for system bus access:
        DTMCS_IDLE_HINT : std_logic_vector(2 downto 0)   := "100";
        W_PADDR         : positive                       := 9
    );
    port(
        -- Reset request/acknowledge. "req" is a pulse >= 1 cycle wide. "done" is
        -- level-sensitive, goes high once component is out of reset.
        -- The "sys" reset (ndmreset) is conventionally everything apart from DM +
        -- DTM, but, as per section 3.2 in 0.13.2 debug spec: "Exactly what is
        -- affected by this reset is implementation dependent, as long as it is
        -- possible to debug programs from the first instruction executed." So
        -- this could simply be an all-hart reset.
        sys_reset_req               : out std_logic;
        sys_reset_done              : in  std_logic;
        hart_reset_req              : out std_logic_vector(N_HARTS - 1 downto 0);
        hart_reset_done             : in  std_logic_vector(N_HARTS - 1 downto 0);
        -- Hart run/halt control
        hart_req_halt               : out std_logic_vector(N_HARTS - 1 downto 0);
        hart_req_halt_on_reset      : out std_logic_vector(N_HARTS - 1 downto 0);
        hart_req_resume             : out std_logic_vector(N_HARTS - 1 downto 0);
        hart_halted                 : in  std_logic_vector(N_HARTS - 1 downto 0);
        hart_running                : in  std_logic_vector(N_HARTS - 1 downto 0);
        -- Hart access to data0 CSR (assumed to be core-internal but per-hart)
        hart_data0_rdata            : out std_logic_vector(N_HARTS * 32 - 1 downto 0);
        hart_data0_wdata            : in  std_logic_vector(N_HARTS * 32 - 1 downto 0);
        hart_data0_wen              : in  std_logic_vector(N_HARTS - 1 downto 0);
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
        
        -- Wishbone Master Interface, replaces System bus
        CLK_I  : in  std_logic;
        RST_I  : in  std_logic;
        DAT_I  : in  std_logic_vector(31 downto 0);
        DAT_O  : out std_logic_vector(31 downto 0);
        -- TAGD_I/O are not implemented
        ACK_I  : in  std_logic;
        ADDR_O : out std_logic_vector(31 downto 0);
        CYC_O  : out std_logic;
        ERR_I  : in  std_logic;
        -- LOCK_O & RTY_I are not implemented
        SEL_O  : out std_logic_vector(3 downto 0);
        STB_O  : out std_logic;
        -- TGA_O & TGC_O are not implemented
        WE_O   : out std_logic;
        CTI_O  : out std_logic_vector(2 downto 0)
    );
end entity debugTop;

architecture rtl of debugTop is

    signal dmi_rst   : std_logic;
    signal dmihardreset_req : std_logic;
    signal assert_dmi_reset : std_logic;
    signal dmi_psel    : std_logic;
    signal dmi_penable : std_logic;
    signal dmi_pwrite  : std_logic;
    signal dmi_paddr : std_logic_vector(W_PADDR-1 downto 0);
    signal dmi_pwdata  : std_logic_vector(31 downto 0);
    signal dmi_prdata  : std_logic_vector(31 downto 0);
    signal dmi_pready  : std_logic;
    signal dmi_pslverr : std_logic;

begin

    assert_dmi_reset <= dmihardreset_req or RST_I;

    reset_sync : entity work.hazard3_reset_sync
        port map(
            clk     => CLK_I,
            rst_in  => assert_dmi_reset,
            rst_out => dmi_rst
        );
    

    hazard3_ecp5_jtag_dtm_instance : entity work.hazard3_ecp5_jtag_dtm
        generic map(
            DTMCS_IDLE_HINT => DTMCS_IDLE_HINT,
            W_PADDR         => W_PADDR
        )
        port map(
            dmihardreset_req => dmihardreset_req,
            clk_dmi          => CLK_I,
            rst_dmi          => dmi_rst,
            dmi_psel         => dmi_psel,
            dmi_penable      => dmi_penable,
            dmi_pwrite       => dmi_pwrite,
            dmi_paddr        => dmi_paddr,
            dmi_pwdata       => dmi_pwdata,
            dmi_prdata       => dmi_prdata,
            dmi_pready       => dmi_pready,
            dmi_pslverr      => dmi_pslverr
        );
    
    hazard3_dm_instance : entity work.hazard3_dm
        generic map(
            N_HARTS      => N_HARTS,
            NEXT_DM_ADDR => NEXT_DM_ADDR
        )
        port map(
            CLK_I                       => CLK_I,
            RST_I                       => RST_I,
            dmi_psel                    => dmi_psel,
            dmi_penable                 => dmi_penable,
            dmi_pwrite                  => dmi_pwrite,
            dmi_paddr                   => dmi_paddr,
            dmi_pwdata                  => dmi_pwdata,
            dmi_prdata                  => dmi_prdata,
            dmi_pready                  => dmi_pready,
            dmi_pslverr                 => dmi_pslverr,
            sys_reset_req               => sys_reset_req,
            sys_reset_done              => sys_reset_done,
            hart_reset_req              => hart_reset_req,
            hart_reset_done             => hart_reset_done,
            hart_req_halt               => hart_req_halt,
            hart_req_halt_on_reset      => hart_req_halt_on_reset,
            hart_req_resume             => hart_req_resume,
            hart_halted                 => hart_halted,
            hart_running                => hart_running,
            hart_data0_rdata            => hart_data0_rdata,
            hart_data0_wdata            => hart_data0_wdata,
            hart_data0_wen              => hart_data0_wen,
            hart_instr_data             => hart_instr_data,
            hart_instr_data_vld         => hart_instr_data_vld,
            hart_instr_data_rdy         => hart_instr_data_rdy,
            hart_instr_caught_exception => hart_instr_caught_exception,
            hart_instr_caught_ebreak    => hart_instr_caught_ebreak,
            DAT_I                       => DAT_I,
            DAT_O                       => DAT_O,
            ACK_I                       => ACK_I,
            ADDR_O                      => ADDR_O,
            CYC_O                       => CYC_O,
            ERR_I                       => ERR_I,
            SEL_O                       => SEL_O,
            STB_O                       => STB_O,
            WE_O                        => WE_O,
            CTI_O                       => CTI_O
        );
    

end architecture rtl;
