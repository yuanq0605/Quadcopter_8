BLE_Demo_F401_Asm
==================

Target: STM32F401RETx / NUCLEO-F401RE
Toolchain: Keil MDK-ARM ARMCC + ARMASM

USART1:
  PA9  TX
  PA10 RX
  9600 baud, 8 data bits, no parity, 1 stop bit

All application and startup code is ARMASM assembly. The implementation uses
the default 16 MHz HSI clock, direct register access, USART1 RXNE interrupts,
and the original BLE_Demo packet format:

  0xAA, IEEE-754 float (little endian), XOR checksum of the four float bytes

The project expects the STM32F4 device pack to provide the STM32F401RE flash
programming algorithm. No source files from the STM32F1 project are required.
