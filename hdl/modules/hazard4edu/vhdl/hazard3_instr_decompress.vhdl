library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.hazard3_constants.all;

entity hazard3_instr_decompress is
    generic(
        EXTENSION_C : boolean := TRUE;
        EXTENSION_M : boolean := TRUE
    );
    port(
        clk                        : in  std_logic;
        rst_n                      : in  std_logic;
        instr_in                   : in  std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        instr_is_32bit             : out std_logic;
        instr_out                  : out std_logic_vector(DATA_WIDTH_C - 1 downto 0);
        instr_out_is_uop           : out std_logic;
        instr_out_is_final_uop     : out std_logic;
        instr_out_uop_no_pc_update : out std_logic;
        instr_out_uop_atomic       : out std_logic;
        instr_out_uop_stall        : in  std_logic;
        instr_out_uop_clear        : in  std_logic;
        df_uop_step                : out std_logic_vector(3 downto 0);
        invalid                    : out std_logic
    );
end entity hazard3_instr_decompress;

architecture rtl of hazard3_instr_decompress is
    constant REGISTER_X0 : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0) := 5d"0"; -- Zero Register
    constant REGISTER_X1 : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0) := 5d"1"; -- Return Address
    constant REGISTER_X2 : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0) := 5d"2"; -- Stack Pointer

    -- Helper function to expand the read register (rd) for convenient ORing
    function format_rd(register_number : std_logic_vector) return std_logic_vector is
    begin
        return x"00000" & register_number & "0000000";
    end function format_rd;

    -- Helper function to expand the source register 1 (rs1) for convenient ORing
    function format_rs1(register_number : std_logic_vector) return std_logic_vector is
    begin
        return x"000" & register_number & "000000000000000";
    end function format_rs1;

    -- Helper function to expand the source register 2 (rs2) for convenient ORing
    function format_rs2(register_number : std_logic_vector) return std_logic_vector is
    begin
        return "0000000" & register_number & x"00000";
    end function format_rs2;

    -- Helper function to convert 'don't care' bits ('-') from opcode constants into '0's 
    -- for bitwise OR operations. Without this, ORing with '-' yields '-' ('X' in Verilog).
    function noz(op : std_logic_vector) return std_logic_vector is
        variable res : std_logic_vector(op'range);
    begin
        for i in op'range loop
            if op(i) = '1' then
                res(i) := '1';
            else
                res(i) := '0';
            end if;
        end loop;
        return res;
    end function noz;

    signal rd_long      : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
    signal rs1_long     : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
    signal rs2_long     : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
    signal rd_short     : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
    signal rs1_short    : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
    signal rs2_short    : std_logic_vector(REGISTER_ADDRESS_WIDTH_C - 1 downto 0);
    signal immediate_ci : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal immediate_cj : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal immediate_cb : std_logic_vector(DATA_WIDTH_C - 1 downto 0);

begin
    -- Long register formats: cr, ci, css
    -- Short register formats: ciw, cl, cs, cb, cj
    rd_long   <= instr_in(11 downto 7);
    rs1_long  <= instr_in(11 downto 7);
    rs2_long  <= instr_in(6 downto 2);
    rd_short  <= "01" & instr_in(4 downto 2);
    rs1_short <= "01" & instr_in(9 downto 7);
    rs2_short <= "01" & instr_in(4 downto 2);

    -- Mapping of cx -> x immediate formats (we are *expanding* instructions, not decoding them):
    immediate_ci <= (11 downto 5 => instr_in(12)) & instr_in(6 downto 2) & x"00000";
    immediate_cj <= instr_in(12) & instr_in(8) & instr_in(10 downto 9) & instr_in(6) & instr_in(7) & instr_in(2) & instr_in(11) & instr_in(5 downto 3) & (20 downto 12 => instr_in(12)) & 12x"000";
    immediate_cb <= (31 downto 28 => instr_in(12)) & instr_in(6 downto 5) & instr_in(2) & 13d"0" & instr_in(11 downto 10) & instr_in(4 downto 3) & instr_in(12) & 7d"0";

    -- Micro-Instructions not supported in this fork. Set to zero for formal equivalence with the Verilog code,
    -- but might be removed at a later date.
    instr_out_is_uop           <= '0';
    instr_out_is_final_uop     <= '0';
    instr_out_uop_atomic       <= '0';
    instr_out_uop_no_pc_update <= '0';
    df_uop_step                <= (others => '0');

    -- Compressed instructions unsupported / not decompressed, pass them right along
    NO_COMPRESSED_INSTRUCTIONS : if not EXTENSION_C generate
        passthrough_logic : process(all) is
        begin
            instr_is_32bit <= '1';
            instr_out      <= instr_in;
            invalid        <= '0';
        end process passthrough_logic;
    end generate NO_COMPRESSED_INSTRUCTIONS;

 -- Compressed instructions supported, decompress them to 32-bit instructions
    COMPRESSED_INSTRUCTIONS : if EXTENSION_C generate
        decompress_logic : process(all) is
        begin
            if instr_in(1 downto 0) = "11" then
                instr_is_32bit <= '1';
                instr_out      <= instr_in;
                invalid        <= '0';
            else
                instr_is_32bit <= '0';
                instr_out      <= (others => '0');
                invalid        <= '0';

                case? instr_in(15 downto 0) is
                    when OPCODE_C.C_ADDI4SPN =>
                        instr_out <= noz(OPCODE_C.ADDI) or format_rd(rd_short) or format_rs1(REGISTER_X2) or 
                                    ("00" & instr_in(10 downto 7) & instr_in(12 downto 11) & instr_in(5) & instr_in(6) & 22d"0");
                        invalid   <= not (or instr_in(12 downto 2));
                    when OPCODE_C.C_LW => 
                        instr_out <= noz(OPCODE_C.LW) or format_rd(rd_short) or format_rs1(rs1_short) or 
                                    (5d"0" & instr_in(5) & instr_in(12 downto 10) & instr_in(6) & "00" & 20d"0");
                    when OPCODE_C.C_SW => 
                        instr_out <= noz(OPCODE_C.SW) or format_rs2(rs2_short) or format_rs1(rs1_short) or 
                                    (5d"0" & instr_in(5) & instr_in(12) & 13d"0" & instr_in(11 downto 10) & instr_in(6) & 9d"0");
                    when OPCODE_C.C_ADDI => 
                        instr_out <= noz(OPCODE_C.ADDI) or format_rd(rd_long) or format_rs1(rs1_long) or immediate_ci;
                    when OPCODE_C.C_JAL => 
                        instr_out <= noz(OPCODE_C.JAL) or format_rd(REGISTER_X1) or immediate_cj;
                    when OPCODE_C.C_J => 
                        instr_out <= noz(OPCODE_C.JAL) or format_rd(REGISTER_X0) or immediate_cj;
                    when OPCODE_C.C_LI => 
                        instr_out <= noz(OPCODE_C.ADDI) or format_rd(rd_long) or immediate_ci;
                    when OPCODE_C.C_LUI => 
                        if rd_long = REGISTER_X2 then
                            instr_out <= noz(OPCODE_C.ADDI) or format_rd(REGISTER_X2) or format_rs1(REGISTER_X2) or 
                                        ((29 downto 27 => instr_in(12)) & instr_in(4 downto 3) & instr_in(5) & instr_in(2) & instr_in(6) & 24d"0");
                        else
                            instr_out <= noz(OPCODE_C.LUI) or format_rd(rd_long) or ((26 downto 12 => instr_in(12)) & instr_in(6 downto 2) & 12d"0");
                        end if;
                        invalid <= not (or (instr_in(12) & instr_in(6 downto 2)));
                    when OPCODE_C.C_SLLI => 
                        instr_out <= noz(OPCODE_C.SLLI) or format_rd(rs1_long) or format_rs1(rs1_long) or immediate_ci;
                    when OPCODE_C.C_SRAI => 
                        instr_out <= noz(OPCODE_C.SRAI) or format_rd(rs1_short) or format_rs1(rs1_short) or immediate_ci;
                    when OPCODE_C.C_SRLI => 
                        instr_out <= noz(OPCODE_C.SRLI) or format_rd(rs1_short) or format_rs1(rs1_short) or immediate_ci;
                    when OPCODE_C.C_ANDI => 
                        instr_out <= noz(OPCODE_C.ANDI) or format_rd(rs1_short) or format_rs1(rs1_short) or immediate_ci;
                    when OPCODE_C.C_AND => 
                        instr_out <= noz(OPCODE_C.AND_OP) or format_rd(rs1_short) or format_rs1(rs1_short) or format_rs2(rs2_short);
                    when OPCODE_C.C_OR => 
                        instr_out <= noz(OPCODE_C.OR_OP) or format_rd(rs1_short) or format_rs1(rs1_short) or format_rs2(rs2_short);
                    when OPCODE_C.C_XOR => 
                        instr_out <= noz(OPCODE_C.XOR_OP) or format_rd(rs1_short) or format_rs1(rs1_short) or format_rs2(rs2_short);
                    when OPCODE_C.C_SUB => 
                        instr_out <= noz(OPCODE_C.SUB) or format_rd(rs1_short) or format_rs1(rs1_short) or format_rs2(rs2_short);
                    when OPCODE_C.C_ADD => 
                        if rs2_long /= REGISTER_X0 then
                            instr_out <= noz(OPCODE_C.ADD) or format_rd(rd_long) or format_rs1(rs1_long) or format_rs2(rs2_long);
                        elsif rs1_long /= REGISTER_X0 then
                            instr_out <= noz(OPCODE_C.JALR) or format_rd(REGISTER_X1) or format_rs1(rs1_long);
                        else
                            instr_out <= noz(OPCODE_C.EBREAK);
                        end if;
                    when OPCODE_C.C_MV => 
                        if rs2_long /= REGISTER_X0 then
                            instr_out <= noz(OPCODE_C.ADD) or format_rd(rd_long) or format_rs2(rs2_long);
                        else
                            instr_out <= noz(OPCODE_C.JALR) or format_rs1(rs1_long);
                            invalid   <= not (or rs1_long);
                        end if;
                    when OPCODE_C.C_LWSP => 
                        instr_out <= noz(OPCODE_C.LW) or format_rd(rd_long) or format_rs1(REGISTER_X2) or 
                                    (x"0" & instr_in(3 downto 2) & instr_in(12) & instr_in(6 downto 4) & 22d"0");
                        invalid   <= not (or rd_long);
                    when OPCODE_C.C_SWSP => 
                        instr_out <= noz(OPCODE_C.SW) or format_rs2(rs2_long) or format_rs1(REGISTER_X2) or 
                                    (x"0" & instr_in(8 downto 7) & instr_in(12) & 13d"0" & instr_in(11 downto 9) & 9d"0");
                    when OPCODE_C.C_BEQZ => 
                        instr_out <= noz(OPCODE_C.BEQ) or format_rs1(rs1_short) or immediate_cb;
                    when OPCODE_C.C_BNEZ => 
                        instr_out <= noz(OPCODE_C.BNE) or format_rs1(rs1_short) or immediate_cb;
                    when OPCODE_C.C_MUL => 
                        instr_out <= noz(OPCODE_C.MUL) or format_rd(rs1_short) or format_rs1(rs1_short) or format_rs2(rs2_short);
                        if not EXTENSION_M then
                            invalid <= '1';
                        end if;
                    when others => 
                        invalid <= '1';
                end case?;
            end if;
        end process decompress_logic;
    end generate COMPRESSED_INSTRUCTIONS;
end architecture rtl;
