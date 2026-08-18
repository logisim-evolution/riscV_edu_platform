To build the application execute build.sh

Important: 
1) As the logic analyser is a whisbone client, the application needs to know the correct base address of the logic analyser core on the bus. This base address is defined in the file source/utils.h as BASE_ADDRESS, please modify this when you change it in the VHDL/Verilog instantiation.
2) the triggers used in the logic analyser (greater/less) are defined on binary interpresentation (read unsigned)!

