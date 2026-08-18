#align(center + horizon)[
  #text(size: 28pt, weight: "bold")[
    Logic Analyser Manual
  ]

  #v(3em)


  #text(size: 12pt)[
    #datetime.today().display("August 2026")
  ]
]

#pagebreak()

#outline()

#pagebreak()

= Overview

The logic Analyser consists of two parts.
The first one is a hardware component written in Verilog that can be integrated
into the system running on the Gecko5Education.
The second component is a desktop application that can communicate with the
hardware component via the debug interface of the Hazard3 CPU on the Gecko5.

Up to 64 wires can be connected to the hardware part of the Logic Analyer. A trigger can
then be configured in the desktop app which defines under what conditions the connected wires should be recorded. 
After a trigger has occurred and the wires are recorded for 512 clock cycles, they can be read out by the desktop application and are displayed as a timing diagram.


= Setup

== Prerequisites
=== Part 1: Install and build the Logic Analyser
```
a:  linux:   - $ sudo apt install cmake
               $ sudo apt install build-essential
               $ sudo apt install libgl1-mesa-dev
               $ sudo apt install libxi-dev
               $ sudo apt install libxcursor-dev
    mac:     - $ xcode-select --install
               $ brew install cmake
    windows: - Install VS Build-Tools.
               instructions: https://github.com/bycloudai/InstallVSBuildToolsWindows
             - Install git bash that comes with the git installation on windows
               (or any other tool that can to run bash scripts from the powershell)
             - Install cmake from the official website: https://cmake.org/

b:  Clone the RISC-V Education Platform repository:
    https://github.com/logisim-evolution/riscV_edu_platform.git

c:  Build the desktop app (use powershell on windows):
    $ cd riscv-edu-platform/modules/logic_analyser/app
    $ ./build.sh

d:  Now you can run the newly built binary with the script:
    $ ./build/logic_analyzer
```
=== Part 2: Install OSS-CAD-Suite & Drivers

Use the official installation instructions for the Gecko5Education:
```
linux:   https://gecko5education.ti.bfh.ch/tools/cadtools/linux.html 
mac:     https://gecko5education.ti.bfh.ch/tools/cadtools/macos.html 
windows: https://gecko5education.ti.bfh.ch/tools/cadtools/windowsnative.html
         after having completed the official installations on windows, you need
         to install openocd in your msys terminal by running:
         $ pacman -S mingw-w64-x86_64-openocd 
```

#pagebreak()

== Integration
```
a:  Connect the Logic Analyser to the system bus of and set the base-address to the same base-address defined in logic_analyzer/source/utils.h as 'BASE_ADDRESS'.
b:  Connect up to 64 wires that you want to analyse to the 'i_tapped_wires' port of the Logic Analyser. (See below for an example in verilog)

logicAnalyserBus
  #( .DataBits(32), // must be 32 for this module
     .AddrBits(32), // must be bigger than 13 for this module
     .BaseAddress(32'h70000000)
   ( .tappedWires({fd_cir[6:0], ci_id, ci_done, ci_result[7:0], busy, ci_start,
                      ci_dataa[15:0], ci_datab[15:0], ci_op_vld}),
     .CLK_I(CLK_I),
     .RST_I(RST_I),
     .DAT_I(logicAnalyserBus_DAT_I),
     .DAT_O(logicAnalyserBus_DAT_O),
     .ACK_O(logicAnalyserBus_ACK_O),
     .ADDR_I(logicAnalyserBus_ADDR_I),
     .CYC_I(logicAnalyserBus_CYC_I),
     .ERR_O(logicAnalyserBus_ERR_O),
     .SEL_I(logicAnalyserBus_SEL_I),
     .STB_I(logicAnalyserBus_STB_I),
     .WE_I(logicAnalyserBus_WE_I),
     .CTI_I(logicAnalyserBus_CTI_I);
```

== Running the Logic Analyser
a:  Connect the board to your computer.

b:  Run OpenOCD using the script './run_openocd.sh'.

c:  In a separate terminal upload the project to the board: './openocd_build_and_upload.sh'. If the project is already built, you can directly use 'openocd_upload.sh'.

    Should you have trouble with steps b or c, try to instead
    upload the project with './openfpga_upload.sh' or './openfpga_build_and_upload.sh'. (Make sure that the OpenOCD server is not running for this)

d:  Run the Logic Analyser with './run_logic_analyzer.sh'.

#pagebreak()

= User Interface

== Overview
When you open the Logic Analyser app, you see the following interface:

#image("empty.png")

Section A (Configuration): The trigger mechanism can be configured here.

Section B (Buffers): A total of ten buffers exist that can each store exactly one capture. When values are captured and loaded into the program, a timing diagram of the captured signals will be displayed in this section. 

Section C (Minimap): Shows the current position of the Buffer window in relation to the complete width of the buffer. Moving the light grey rectangle along the horizontal axis, the minimap can be used as a scroll bar.

The first step is to add a new signal entry for each signal connected to the logic analyser.
Click on the green "+" to add a new signal, give it a name and the width that matches the width of the tapped signal.
Using the signal width and the correct ordering of the signals, the app will automatically calculate the correct range bounds for each signal. (see next figure)

#image("config.png")

Currently, no data is captured and therefore the buffer window displays only zeroes.

== Trigger Configuration
Before we can record anything on the board, we need to configure the trigger. This trigger configuration will then define under which condition the logic analyser has to record the signals. 
We can select between different comparators.

Let us create a very simple trigger first. We select '==' as the comparator (next to "Trig 1") and include the "ci_start" signal in the trigger configuration with the value '1'.

#image("trigger_1.png")

This configuration tells the logic analyser to start the capture as soon as the signal "ci_start" - which is at position [33:33] in the tapped wires signal - contains the value '1'. If it stays at '0', the logic analyser will simply wait.

When we now click on "Capture", the trigger configuration will be uploaded to the board first. The desktop app will then wait until either the capture has completed, the user canceled the operation or an error occurred.

After the capture completed successfully, the captured data will be displayed in the buffer window:

#image("capture_1.png")

We can see, that the trigger (indicated by the violet highlight) occurred exactly when "ci_start" was high.

We can adjust the trigger to be more precise by including more signals in "Trig_1". For example, we might only want to trigger when "ci_start" is high and "ci_id" is '4'. This can be done by simply checking the box in the "ci_id" row. The logic analyser will now only trigger when both comparisons match the given reference value. Demonstrated in pseudo code, the logic analyzer will check the following:

```
if (ci_start == 1 AND ci_id == 4) {
    start_capture()
}
```

#image("trigger_2.png")

If we use a different comparator (">", "<") we can only include one signal into the trigger configuration.
The "\*" trigger indicates a wildcard and therfore ignores it. 

#image("trigger_3.png")

#pagebreak()


You might have noticed, that the trigger did not occur at position 0 of the buffer. There is a mechanism that allows for setting a pre-trigger value that indicates how many samples are recorded before the actual trigger happens. (Internally this is done by writing the tapped values into a circular buffer and overwriting the old values when the position wraps around. The logic analyser then simply has to stop recording at the right moment to not overwrite the samples we want to keep before the mechanism triggered.)

#image("pre_trigger.png")

We can include up to 4 consecutive triggers into the configuration. When we use more than 1 triggers in sequence, the comparison of all included triggers has to be evaluated to true in sequence for the logic analyzer to trigger.



