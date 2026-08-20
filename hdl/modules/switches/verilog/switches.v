module switches
  #( parameter DataBits = 32, // must be 32 for this module
     parameter AddrBits = 32, // must be > 5 for this module
     parameter [AddrBits-1:0] BaseAddress )
   ( input  wire CLK_I,
     input  wire RST_I,
     input  wire [DataBits-1:0] DAT_I,
     output wire [DataBits-1:0] DAT_O,
     // TAGD_I and TAGD_O are not implemented
     output wire ACK_O,
     input  wire [AddrBits-1:0] ADDR_I,
     input  wire CYC_I,
     output wire ERR_O,
     // LOCK_I is not used in this module
     // RTY_I is not implemented
     input  wire [(DataBits/8)-1:0] SEL_I,
     input  wire STB_I,
     // TGA_O and TGC_O are not implemented
     input  wire WE_I,
     input  wire [2:0] CTI_I, // Registered feedback
     // BTE_I is not used in this module

     // here the interface signals are defined
     input  wire      oneKHzTick,
     output wire      irqDip,
     output wire      irqJoy,
     input wire [4:0] nButtons, 
     input wire [7:0] nDipSwitch,
     input wire [4:0] nJoystick);

  reg ackReg;
  reg errorReg;
  reg weReg;
  reg reReg;
  reg [31:0] dataInReg;
  reg [31:0] s_dataOut;
  reg [2:0] indexReg;

  reg [7:0]  s_dipSwitchPressedIrqMaskReg, s_dipSwitchReleasedIrqMaskReg;
  reg [9:0]  s_joystickPressedIrqMaskReg, s_joystickReleasedIrqMaskReg;
  reg [1:0]  s_irqDipReg, s_irqJoyReg;
  wire [7:0] s_dipswitchPressedIrqs, s_dipSwitchReleasedIrqs;
  wire [9:0] s_joystickPressedIrqs, s_joystickReleasedIrqs;
  reg s_countActiveReg;
  reg [31:0] s_delayCounterReg;
  wire [7:0] s_dipswitchState;
  wire [9:0]  s_joystickState;
  
  wire isMyTransaction = (ADDR_I[AddrBits-1:5] == BaseAddress[AddrBits-1:5]) ? CYC_I & STB_I : 1'b0;
  wire isCorrectTransaction = (CTI_I == 3'b000 && SEL_I == 4'b1111) ? isMyTransaction : 1'b0; // this module only supports clasic word transfers
  assign ERR_O = errorReg;
  assign ACK_O = ackReg;
  assign DAT_O = s_dataOut;
  
  always @(posedge CLK_I)
  begin
    ackReg    <= (RST_I == 1'b1) ? 1'b0 : ~ackReg & isCorrectTransaction;
    errorReg  <= (RST_I == 1'b1) ? 1'b0 : ~errorReg & isMyTransaction & ~isCorrectTransaction;
    weReg     <= ~ackReg & isCorrectTransaction & WE_I;
    reReg     <= ~ackReg & isCorrectTransaction & ~WE_I;
    indexReg  <= (RST_I == 1'b1) ? 3'd0 : (ackReg == 1'b0 && isCorrectTransaction == 1'b1) ? ADDR_I[4:2] : indexReg;
    dataInReg <= (ackReg == 1'b0 && isCorrectTransaction == 1'b1) ? DAT_I : dataInReg;
  end
  
  always @*
    case (indexReg)
      3'd0    : s_dataOut <= {24'd0, s_dipswitchState};
      3'd1    : s_dataOut <= {24'd0, s_dipswitchPressedIrqs};
      3'd2    : s_dataOut <= {24'd0, s_dipSwitchReleasedIrqs};
      3'd3    : s_dataOut <= {22'd0, s_joystickState};
      3'd4    : s_dataOut <= {22'd0, s_joystickPressedIrqs};
      3'd5    : s_dataOut <= {22'd0, s_joystickReleasedIrqs};
      3'd6    : s_dataOut <= s_delayCounterReg;
      default : s_dataOut <= 32'd0;
    endcase
  
  // Here we define the IRQ enable masks
  wire s_clearAllIrqMasks              = (indexReg == 3'd7) ? weReg : 1'b0;
  wire s_weDipSwitchPressedIrqMask     = (indexReg == 3'd1) ? weReg : 1'b0;
  wire s_weDipSwitchReleasedIrqMask    = (indexReg == 3'd2) ? weReg : 1'b0;
  wire s_clearDipSwitchPressedIrqs     = (indexReg == 3'd7 || indexReg == 3'd1) ? reReg : 1'b0;
  wire s_clearDipSwitchReleasedIrqMask = (indexReg == 3'd7 || indexReg == 3'd2) ? reReg : 1'b0;
  wire s_weJoystickPressedIrqMask      = (indexReg == 3'd4) ? weReg : 1'b0;
  wire s_weJoystickReleasedIrqMask     = (indexReg == 3'd5) ? weReg : 1'b0;
  wire s_clearJoystickPressedIrqs      = (indexReg == 3'd7 || indexReg == 3'd4) ? reReg : 1'b0;
  wire s_clearJoystickReleasedIrqMask  = (indexReg == 3'd7 || indexReg == 3'd5) ? reReg : 1'b0;
  
  assign irqDip = s_irqDipReg[0];
  assign irqJoy = s_irqJoyReg[0];
  
   always @(posedge CLK_I)
    begin
      s_dipSwitchPressedIrqMaskReg  <= (RST_I == 1'b1 || s_clearAllIrqMasks == 1'b1) ? 8'd0 : (s_weDipSwitchPressedIrqMask == 1'b1) ? dataInReg[7:0] : s_dipSwitchPressedIrqMaskReg;
      s_dipSwitchReleasedIrqMaskReg <= (RST_I == 1'b1 || s_clearAllIrqMasks == 1'b1) ? 8'd0 : (s_weDipSwitchReleasedIrqMask == 1'b1) ? dataInReg[7:0] : s_dipSwitchReleasedIrqMaskReg;
      s_joystickPressedIrqMaskReg   <= (RST_I == 1'b1 || s_clearAllIrqMasks == 1'b1) ? 10'd0 : (s_weJoystickPressedIrqMask == 1'b1) ? dataInReg[9:0] : s_joystickPressedIrqMaskReg;
      s_joystickReleasedIrqMaskReg  <= (RST_I == 1'b1 || s_clearAllIrqMasks == 1'b1) ? 10'd0 : (s_weJoystickReleasedIrqMask == 1'b1) ? dataInReg[9:0] : s_joystickReleasedIrqMaskReg;
      s_irqDipReg[0]                <= (s_dipswitchPressedIrqs != 8'd0 || s_dipSwitchReleasedIrqs != 8'd0) ? 1'b1 : 1'b0;
      s_irqDipReg[1]                <= (RST_I == 1'b1) ? 1'b0 : s_irqDipReg[0];
      s_irqJoyReg[0]                <= (s_joystickPressedIrqs != 10'd0 || s_joystickReleasedIrqs != 10'd0) ? 1'b1 : 1'b0;
      s_irqJoyReg[1]                <= (RST_I == 1'b1) ? 1'b0 : s_irqJoyReg[0];
    end

  // here we define the irq response delay counter
  wire s_startCount = (s_irqDipReg[0] & ~s_irqDipReg[1]) | (s_irqJoyReg[0] & ~s_irqJoyReg[1]);
  wire s_stopCount = (s_irqDipReg[1] & ~s_irqDipReg[0]) | (s_irqJoyReg[1] & ~s_irqJoyReg[0]);
  
  always @(posedge CLK_I)
    begin
      s_countActiveReg  <= (RST_I == 1'b1 || s_stopCount == 1'b1) ? 1'b0 : s_countActiveReg | s_startCount;
      s_delayCounterReg <= (RST_I == 1'b1 || s_startCount == 1'b1) ? 32'd0 : (s_countActiveReg == 1'b1 && s_delayCounterReg[31] == 1'b0) ? s_delayCounterReg + 32'd1 : s_delayCounterReg;
    end

  // here we insert the anti-dender modules
  genvar n;
  
  generate
     for (n = 0; n < 8 ; n = n + 1)
       begin : dipsw
         debouncerWithIrq debounce ( .clock(CLK_I),
                                     .reset(RST_I),
                                     .nButtonIn(nDipSwitch[n]),
                                     .scanTick(oneKHzTick),
                                     .enablePressIrq(s_dipSwitchPressedIrqMaskReg[n]),
                                     .enableReleaseIrq(s_dipSwitchReleasedIrqMaskReg[n]),
                                     .resetPressIrq(s_clearDipSwitchPressedIrqs),
                                     .resetReleaseIrq(s_clearDipSwitchReleasedIrqMask),
                                     .pressIrq(s_dipswitchPressedIrqs[n]),
                                     .releasIrq(s_dipSwitchReleasedIrqs[n]),
                                     .currentState(s_dipswitchState[n]) );
       end
     for (n = 0; n < 5 ; n = n + 1)
       begin : joy
         debouncerWithIrq debounce ( .clock(CLK_I),
                                     .reset(RST_I),
                                     .nButtonIn(nJoystick[n]),
                                     .scanTick(oneKHzTick),
                                     .enablePressIrq(s_joystickPressedIrqMaskReg[n]),
                                     .enableReleaseIrq(s_joystickReleasedIrqMaskReg[n]),
                                     .resetPressIrq(s_clearJoystickPressedIrqs),
                                     .resetReleaseIrq(s_clearJoystickReleasedIrqMask),
                                     .pressIrq(s_joystickPressedIrqs[n]),
                                     .releasIrq(s_joystickReleasedIrqs[n]),
                                     .currentState(s_joystickState[n]) );
       end
     for (n = 0; n < 5 ; n = n + 1)
       begin : but
         debouncerWithIrq debounce ( .clock(CLK_I),
                                     .reset(RST_I),
                                     .nButtonIn(nButtons[n]),
                                     .scanTick(oneKHzTick),
                                     .enablePressIrq(s_joystickPressedIrqMaskReg[n+5]),
                                     .enableReleaseIrq(s_joystickReleasedIrqMaskReg[n+5]),
                                     .resetPressIrq(s_clearJoystickPressedIrqs),
                                     .resetReleaseIrq(s_clearJoystickReleasedIrqMask),
                                     .pressIrq(s_joystickPressedIrqs[n+5]),
                                     .releasIrq(s_joystickReleasedIrqs[n+5]),
                                     .currentState(s_joystickState[n+5]) );
       end
  endgenerate
  
  
endmodule
