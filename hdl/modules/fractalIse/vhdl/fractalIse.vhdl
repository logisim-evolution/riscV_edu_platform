LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY fractal IS
   GENERIC( FRACTAL_CI : std_logic_vector( 6 DOWNTO 0 ) := "0000000";
            NMAX_CI    : std_logic_vector( 6 DOWNTO 0 ) := "0000001";
            W_DATA     : integer := 32); -- Important: W_DATA must be bigger or equal to 32!
   PORT ( clock       : IN  std_logic;
          reset       : IN  std_logic;
          ci_id     : in  std_logic_vector(6 downto 0);
          ci_start  : in  std_logic;
          ci_dataa  : in  std_logic_vector(W_DATA-1 downto 0);
          ci_datab  : in  std_logic_vector(W_DATA-1 downto 0);
          ci_done   : out std_logic;
          ci_result : out std_logic_vector(W_DATA-1 downto 0));
END fractal;

ARCHITECTURE platformindependent OF fractal IS

   TYPE STATETYPE IS (IDLE,CALCMULT,DOADD,DONE);
   -- ColorModel = 0 => Black and white
   -- ColorModel = 1 => Grayscale
   -- ColorModel = 2 => Color1
   -- ColorModel = 3 => Color2

   SIGNAL nmax            : unsigned( 15 DOWNTO 0 );
   SIGNAL colorModel      : std_logic_vector( 1 DOWNTO 0 );
   SIGNAL s_isMyNmax      : std_logic;
   SIGNAL s_startFract    : std_logic;
   SIGNAL s_Delta         : signed(31 DOWNTO 0);
   SIGNAL s_xReg          : signed(31 DOWNTO 0);
   SIGNAL s_xNext         : signed(31 DOWNTO 0);
   SIGNAL s_yReg          : signed(31 DOWNTO 0);
   SIGNAL s_yNext         : signed(31 DOWNTO 0);
   SIGNAL s_cxReg         : signed(31 DOWNTO 0);
   SIGNAL s_cyReg         : signed(31 DOWNTO 0);
   SIGNAL s_multXX        : signed(63 DOWNTO 0);
   SIGNAL s_multYY        : signed(63 DOWNTO 0);
   SIGNAL s_multXY        : signed(63 DOWNTO 0);
   SIGNAL s_xxReg         : signed(31 DOWNTO 0);
   SIGNAL s_xxNext        : signed(31 DOWNTO 0);
   SIGNAL s_yyReg         : signed(31 DOWNTO 0);
   SIGNAL s_yyNext        : signed(31 DOWNTO 0);
   SIGNAL s_2xyReg        : signed(31 DOWNTO 0);
   SIGNAL s_2xyNext       : signed(31 DOWNTO 0);
   SIGNAL s_newX          : signed(31 DOWNTO 0);
   SIGNAL s_newY          : signed(31 DOWNTO 0);
   SIGNAL s_xxPlusyy      : signed(31 DOWNTO 0);
   SIGNAL s_abort1        : std_logic;
   SIGNAL s_abort2        : std_logic;
   SIGNAL s_nReg          : unsigned( 15 DOWNTO 0 );
   SIGNAL s_nNext         : unsigned( 15 DOWNTO 0 );
   SIGNAL s_stateReg      : STATETYPE;
   SIGNAL s_stateNext     : STATETYPE;
   SIGNAL s_fractDone     : std_logic;
   SIGNAL s_BlackAndWhite : std_logic_vector( 15 DOWNTO 0 );
   SIGNAL s_GrayScale     : std_logic_vector( 15 DOWNTO 0 );
   SIGNAL s_Color1        : std_logic_vector( 15 DOWNTO 0 );
   SIGNAL s_Red1          : std_logic_vector(  4 DOWNTO 0 );
   SIGNAL s_Green1        : std_logic_vector(  5 DOWNTO 0 );
   SIGNAL s_Blue1         : std_logic_vector(  4 DOWNTO 0 );
   SIGNAL s_selected1     : std_logic_vector(  4 DOWNTO 0 );
   SIGNAL s_Color2        : std_logic_vector( 15 DOWNTO 0 );
   SIGNAL s_Red2          : std_logic_vector(  4 DOWNTO 0 );
   SIGNAL s_Green2        : std_logic_vector(  5 DOWNTO 0 );
   SIGNAL s_Blue2         : std_logic_vector(  4 DOWNTO 0 );
   SIGNAL s_Selected      : std_logic_vector( 15 DOWNTO 0 );
   SIGNAL s_x1Reg         : signed(31 DOWNTO 0);
   SIGNAL s_x1Next        : signed(31 DOWNTO 0);
   SIGNAL s_y1Reg         : signed(31 DOWNTO 0);
   SIGNAL s_y1Next        : signed(31 DOWNTO 0);
   SIGNAL s_cx1Reg        : signed(31 DOWNTO 0);
   SIGNAL s_cy1Reg        : signed(31 DOWNTO 0);
   SIGNAL s_multXX1       : signed(63 DOWNTO 0);
   SIGNAL s_multYY1       : signed(63 DOWNTO 0);
   SIGNAL s_multXY1       : signed(63 DOWNTO 0);
   SIGNAL s_xx1Reg        : signed(31 DOWNTO 0);
   SIGNAL s_xx1Next       : signed(31 DOWNTO 0);
   SIGNAL s_yy1Reg        : signed(31 DOWNTO 0);
   SIGNAL s_yy1Next       : signed(31 DOWNTO 0);
   SIGNAL s_2xyReg1       : signed(31 DOWNTO 0);
   SIGNAL s_2xyNext1      : signed(31 DOWNTO 0);
   SIGNAL s_newX1         : signed(31 DOWNTO 0);
   SIGNAL s_newY1         : signed(31 DOWNTO 0);
   SIGNAL s_xxPlusyy1     : signed(31 DOWNTO 0);
   SIGNAL s_n1Reg         : unsigned( 15 DOWNTO 0 );
   SIGNAL s_n1Next        : unsigned( 15 DOWNTO 0 );
   SIGNAL s_state1Reg     : STATETYPE;
   SIGNAL s_state1Next    : STATETYPE;
   SIGNAL s_abort3        : std_logic;
   SIGNAL s_abort4        : std_logic;
   SIGNAL s_BlackAndWhite1: std_logic_vector( 15 DOWNTO 0 );
   SIGNAL s_GrayScale1    : std_logic_vector( 15 DOWNTO 0 );
   SIGNAL s_Color3        : std_logic_vector( 15 DOWNTO 0 );
   SIGNAL s_Red3          : std_logic_vector(  4 DOWNTO 0 );
   SIGNAL s_Green3        : std_logic_vector(  5 DOWNTO 0 );
   SIGNAL s_Blue3         : std_logic_vector(  4 DOWNTO 0 );
   SIGNAL s_selected3     : std_logic_vector(  4 DOWNTO 0 );
   SIGNAL s_Color4        : std_logic_vector( 15 DOWNTO 0 );
   SIGNAL s_Red4          : std_logic_vector(  4 DOWNTO 0 );
   SIGNAL s_Green4        : std_logic_vector(  5 DOWNTO 0 );
   SIGNAL s_Blue4         : std_logic_vector(  4 DOWNTO 0 );
   SIGNAL s_Selected4     : std_logic_vector( 15 DOWNTO 0 );

BEGIN
   ci_done   <= s_isMyNmax OR s_fractDone;
   -- Account for big-endian
   ci_result <= s_Selected(15 downto 0)&s_Selected4(15 downto 0) WHEN s_fractDone = '1' ELSE (OTHERS => '0');
   WITH (colorModel) SELECT s_Selected <=
      s_BlackAndWhite WHEN "00",
      s_GrayScale     WHEN "01",
      s_Color1        WHEN "10",
      s_Color2        WHEN OTHERS;
   WITH (colorModel) SELECT s_Selected4 <=
      s_BlackAndWhite1 WHEN "00",
      s_GrayScale1     WHEN "01",
      s_Color3         WHEN "10",
      s_Color4         WHEN OTHERS;

   s_isMyNmax   <= ci_start WHEN ci_id = NMAX_CI ELSE '0';
   s_startFract <= ci_start WHEN ci_id = FRACTAL_CI ELSE '0';
   s_fractDone  <= '1' WHEN s_stateReg = DONE  AND s_state1Reg = DONE ELSE '0';

   MakeNmax : PROCESS( clock ) IS
   BEGIN
      IF (rising_edge(clock)) THEN
         IF (s_isMyNmax = '1') THEN nmax       <= unsigned(ci_dataa( 15 DOWNTO 0 ));
                                    colorModel <= ci_dataa(17 DOWNTO 16);
                                    s_Delta    <= signed(ci_datab(31 downto 0));
         END IF;
      END IF;
   END PROCESS MakeNmax;

   -- Here the fractal calculation is done
   s_xNext     <= signed(ci_dataa(31 downto 0)) WHEN s_startFract = '1' ELSE 
                  s_newX       WHEN s_stateReg = DOADD ELSE s_xReg;
   s_yNext     <= signed(ci_datab(31 downto 0)) WHEN s_startFract = '1' ELSE 
                  s_newY       WHEN s_stateReg = DOADD ELSE s_yReg;
   s_xxNext    <= s_multXX(59 DOWNTO 28) WHEN s_stateReg = CALCMULT ELSE s_xxReg;
   s_yyNext    <= s_multYY(59 DOWNTO 28) WHEN s_stateReg = CALCMULT ELSE s_yyReg;
   s_2xyNext   <= s_multXY(58 DOWNTO 27) WHEN s_stateReg = CALCMULT ELSE s_2xyReg;
   s_nNext     <= (OTHERS => '0') WHEN s_startFract = '1' ELSE
                  s_nReg + 1 WHEN s_stateReg = CALCMULT ELSE
                  s_nReg;
   s_multXX    <= s_xReg * s_xReg;
   s_multYY    <= s_yReg * s_yReg;
   s_multXY    <= s_xReg * s_yReg;
   s_newX      <= s_xxReg - s_yyReg + s_cxReg;
   s_newY      <= s_2xyReg + s_cyReg;
   s_xxPlusyy  <= s_xxReg+s_yyReg;
   s_abort1    <= '1' WHEN s_xxPlusyy(31) = '0' AND s_xxPlusyy(30) = '1' ELSE '0';
   s_abort2    <= '1' WHEN nmax = s_nReg ELSE '0';
   s_x1Next    <= signed(ci_dataa(31 downto 0))+s_Delta WHEN s_startFract = '1' ELSE 
                  s_newX1      WHEN s_state1Reg = DOADD ELSE s_x1Reg;
   s_y1Next    <= signed(ci_datab(31 downto 0)) WHEN s_startFract = '1' ELSE 
                  s_newY1      WHEN s_state1Reg = DOADD ELSE s_y1Reg;
   s_xx1Next   <= s_multXX1(59 DOWNTO 28) WHEN s_state1Reg = CALCMULT ELSE s_xx1Reg;
   s_yy1Next   <= s_multYY1(59 DOWNTO 28) WHEN s_state1Reg = CALCMULT ELSE s_yy1Reg;
   s_2xyNext1  <= s_multXY1(58 DOWNTO 27) WHEN s_state1Reg = CALCMULT ELSE s_2xyReg1;
   s_n1Next    <= (OTHERS => '0') WHEN s_startFract = '1' ELSE
                  s_n1Reg + 1 WHEN s_state1Reg = CALCMULT ELSE
                  s_n1Reg;
   s_multXX1   <= s_x1Reg * s_x1Reg;
   s_multYY1   <= s_y1Reg * s_y1Reg;
   s_multXY1   <= s_x1Reg * s_y1Reg;
   s_newX1     <= s_xx1Reg - s_yy1Reg + s_cx1Reg;
   s_newY1     <= s_2xyReg1 + s_cy1Reg;
   s_xxPlusyy1 <= s_xx1Reg+s_yy1Reg;
   s_abort3    <= '1' WHEN s_xxPlusyy1(31) = '0' AND s_xxPlusyy1(30) = '1' ELSE '0';
   s_abort4    <= '1' WHEN nmax = s_n1Reg ELSE '0';

   makeRegs : PROCESS( clock ) IS
   BEGIN
      IF (rising_edge(clock)) THEN
         s_xReg    <= s_xNext;
         s_yReg    <= s_yNext;
         s_xxReg   <= s_xxNext;
         s_yyReg   <= s_yyNext;
         s_2xyReg  <= s_2xyNext;
         s_nReg    <= s_nNext;
         s_x1Reg   <= s_x1Next;
         s_y1Reg   <= s_y1Next;
         s_xx1Reg  <= s_xx1Next;
         s_yy1Reg  <= s_yy1Next;
         s_2xyReg1 <= s_2xyNext1;
         s_n1Reg   <= s_n1Next;
         IF (s_startFract = '1') THEN s_cxReg  <= signed(ci_dataa(31 downto 0));
                                      s_cyReg  <= signed(ci_datab(31 downto 0));
                                      s_cx1Reg <= s_x1Next;
                                      s_cy1Reg <= s_y1Next;
         END IF;
      END IF;
   END PROCESS makeRegs;

   makeStateNext : PROCESS ( s_stateReg , s_startFract , s_abort1 , s_abort2 , s_fractDone ) IS
   BEGIN
      CASE (s_stateReg) IS
         WHEN IDLE    => IF (s_startFract = '1') THEN s_stateNext <= CALCMULT;
                                                 ELSE s_stateNext <= IDLE;
                         END IF;
         WHEN CALCMULT=> s_stateNext <= DOADD;
         WHEN DOADD   => IF (s_abort1 = '1' OR s_abort2 = '1') THEN s_stateNext <= DONE;
                                                               ELSE s_stateNext <= CALCMULT;
                         END IF;
         WHEN DONE    => IF (s_fractDone = '1') THEN s_stateNext <= IDLE;
                                                ELSE s_stateNext <= DONE;
                         END IF;
         WHEN OTHERS  => s_stateNext <= IDLE;
      END CASE;
   END PROCESS makeStateNext;

   makeStateReg : PROCESS( clock ) IS
   BEGIN
      IF (rising_edge(clock)) THEN
         IF (reset = '1') THEN s_stateReg <= IDLE;
                          ELSE s_stateReg <= s_stateNext;
         END IF;
      END IF;
   END PROCESS makeStateReg;

   makeState1Next : PROCESS ( s_state1Reg , s_startFract , s_abort3 , s_abort4 , s_fractDone ) IS
   BEGIN
      CASE (s_state1Reg) IS
         WHEN IDLE    => IF (s_startFract = '1') THEN s_state1Next <= CALCMULT;
                                                 ELSE s_state1Next <= IDLE;
                         END IF;
         WHEN CALCMULT=> s_state1Next <= DOADD;
         WHEN DOADD   => IF (s_abort3 = '1' OR s_abort4 = '1') THEN s_state1Next <= DONE;
                                                               ELSE s_state1Next <= CALCMULT;
                         END IF;
         WHEN DONE    => IF (s_fractDone = '1') THEN s_state1Next <= IDLE;
                                                ELSE s_state1Next <= DONE;
                         END IF;
         WHEN OTHERS  => s_state1Next <= IDLE;
      END CASE;
   END PROCESS makeState1Next;

   makeState1Reg : PROCESS( clock ) IS
   BEGIN
      IF (rising_edge(clock)) THEN
         IF (reset = '1') THEN s_state1Reg <= IDLE;
                          ELSE s_state1Reg <= s_state1Next;
         END IF;
      END IF;
   END PROCESS makeState1Reg;

   -- Here the calculation of the color models is done
   s_BlackAndWhite <= (OTHERS => '0') WHEN s_nReg = nMax ELSE (OTHERS => '1');
   s_GrayScale     <= (OTHERS => '0') WHEN s_nReg = nMax ELSE std_logic_vector(s_nReg(3 DOWNTO 0))&"0"&std_logic_vector(s_nReg(3 DOWNTO 0))&"00"&std_logic_vector(s_nReg(3 DOWNTO 0))&"0";
   s_Color1        <= (OTHERS => '0') WHEN s_nReg = nMax ELSE s_Red1&s_Green1&s_Blue1;
   s_Color2        <= (OTHERS => '0') WHEN s_nReg = nMax ELSE s_Red2&s_Green2&s_Blue2;
   s_selected1     <= s_nReg(0)&X"F";
   s_Red1          <= s_selected1 WHEN s_nReg(3) = '1' ELSE (OTHERS => '0');
   s_Green1        <= s_selected1&"0" WHEN s_nReg(2) = '1' ELSE (OTHERS => '0');
   s_Blue1         <= s_selected1 WHEN s_nReg(1) = '1' ELSE (OTHERS => '0');
   s_Red2          <= std_logic_vector(NOT(s_nReg(6 DOWNTO 3)))&"0" WHEN s_nReg(2) = '1' ELSE (OTHERS => '0');
   s_Green2        <= std_logic_vector(NOT(s_nReg(6 DOWNTO 3)))&"00" WHEN s_nReg(1) = '1' ELSE (OTHERS => '0');
   s_Blue2         <= std_logic_vector(NOT(s_nReg(6 DOWNTO 3)))&"0" WHEN s_nReg(0) = '1' ELSE (OTHERS => '0');


   s_BlackAndWhite1<= (OTHERS => '0') WHEN s_n1Reg = nMax ELSE (OTHERS => '1');
   s_GrayScale1    <= (OTHERS => '0') WHEN s_n1Reg = nMax ELSE std_logic_vector(s_n1Reg(3 DOWNTO 0))&"0"&std_logic_vector(s_n1Reg(3 DOWNTO 0))&"00"&std_logic_vector(s_n1Reg(3 DOWNTO 0))&"0";
   s_Color3        <= (OTHERS => '0') WHEN s_n1Reg = nMax ELSE s_Red3&s_Green3&s_Blue3;
   s_Color4        <= (OTHERS => '0') WHEN s_n1Reg = nMax ELSE s_Red4&s_Green4&s_Blue4;
   s_selected3     <= s_n1Reg(0)&X"F";
   s_Red3          <= s_selected3 WHEN s_n1Reg(3) = '1' ELSE (OTHERS => '0');
   s_Green3        <= s_selected3&"0" WHEN s_n1Reg(2) = '1' ELSE (OTHERS => '0');
   s_Blue3         <= s_selected3 WHEN s_n1Reg(1) = '1' ELSE (OTHERS => '0');
   s_Red4          <= std_logic_vector(NOT(s_n1Reg(6 DOWNTO 3)))&"0" WHEN s_n1Reg(2) = '1' ELSE (OTHERS => '0');
   s_Green4        <= std_logic_vector(NOT(s_n1Reg(6 DOWNTO 3)))&"00" WHEN s_n1Reg(1) = '1' ELSE (OTHERS => '0');
   s_Blue4         <= std_logic_vector(NOT(s_n1Reg(6 DOWNTO 3)))&"0" WHEN s_n1Reg(0) = '1' ELSE (OTHERS => '0');
END platformindependent;
