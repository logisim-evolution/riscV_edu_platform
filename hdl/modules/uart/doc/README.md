The UART module presented here implements a UART compatible with
a standard 16550 UART (see datasheet). The difference with the
16550 is that the modem-control and hardware handshaking are
hardwired, and thus not implemented.
Furthermore this module provides a 16 byte read and 16 byte write FIFO.
The UART module works on the bus clock and can be used as a memory-mapped 
device:
   In this case basicly the uart provides the same functionality as described in the
   datasheets of the PC16550D, with folowing differences:
   a) The modem status register is not implemented
   b) There is no irq on the modem status (bit3 of the interrupt enable 
      register is always 0)
   c) The FIFOs are always enabled (bit 0 in the fifo control register and 
      bit 7 and 6 of the interrupt identification register are always 1)
   d) The bits 3..0 of the Modem control registers are not implemented and 
      hence always 0
   e) The character timeout indicator is not implemented (see Table IV in the 
      PC16550D datasheet)
   Futhermore the uart can only be used in byte mode, and the source clock
   is the bus-clock. The divisor values as presented in Table III of the
   PC16550D datasheet can be calculated by using the attached openoffice
   calculation sheet (uart_divisor_value_calculator.ods).
