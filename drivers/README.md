# AXI4S ILA C drivers
This folder contains C drivers to control the folding pipeline array driver (axi4s_ila).

The driver is written in C and is designed to be used in embedded systems. 

The AXI4Lite is implemented using the HAL functions provided by the PolarFire SoC toolchain. The AXI4Lite functions are implemented in the HAL library and are used to read and write to the registers of the AXI4SILA. Additionally, those can be changed with memory write and read functions, but it is not recommended to do so. In case user wants to use Xilinx toolchain, the AXI4Lite functions need to be implemented by user due to their tool chain dependence (XilIn32, XilOut32, etc.).

The AXI4Stream interfaces driver function needs to be provided with a pointer. core_axi4s_ila.h lists the assumption about those functions. The AXI4S functions are need to be implemented by user due to their tool chain dependence.

The driver is FPGA agnostic, meaning it needs to be adapted to the specific FPGA being used.

## Directory structure: 
```text
drivers/
├── core_axi4s_ila.c     : C source file for the AXI4SILA driver implementation
├── core_axi4s_ila.h     : C header file for the AXI4SILA driver, containing function prototypes
├── core_axi4s_ila_regs.h : C header file defining register addresses and bit fields for the AXI4SILA
└── README.md       : This file
```
