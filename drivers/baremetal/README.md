# LibreILA C drivers
This folder contains C drivers to control the libre_ila (not the libre_ila_uart).

The driver is written in C and is designed to be used in embedded systems. 

> The defaults are for the 64-bit AXI4S build, make sure to define the values below to match the specific LibreILA being used.

The AXI4Lite is implemented using the HAL functions provided by the PolarFire SoC toolchain. The AXI4Lite functions are implemented in the HAL library and are used to read and write to the registers of the LibreILA. Additionally, those can be changed with memory write and read functions, but it is not recommended to do so. In case user wants to use Xilinx toolchain, the AXI4Lite functions need to be implemented by user due to their tool chain dependence (XilIn32, XilOut32, etc.).

The driver is written close to FPGA agnostic, meaning it needs to be adapted to the specific FPGA being used.

## The probe is opaque
The driver knows nothing about what the ILA is wired to. It sees one flat probe word of `CORE_LIBRE_ILA_PROBE_WIDTH` bits, bit 0 upwards, and both the trigger vector and the captured samples use that same layout. Naming the bits is your project's job:

```c
#define MY_PROBE_ERR_BIT  (3u)

cond[LIBRE_ILA_BIT_WORD(MY_PROBE_ERR_BIT)] |= LIBRE_ILA_BIT_MASK(MY_PROBE_ERR_BIT);
mask[LIBRE_ILA_BIT_WORD(MY_PROBE_ERR_BIT)] |= LIBRE_ILA_BIT_MASK(MY_PROBE_ERR_BIT);

LIBRE_ILA_configure_trigger(&ila, cond, mask, LIBRE_ILA_TRIG_MODE_AND);
```

For the stock AXI4S build the probe is TDATA in bits `[G_DATA_WIDTH-1:0]`, then TLAST, TVALID and TREADY — so a 64-bit bus gives `CORE_LIBRE_ILA_PROBE_WIDTH` of 67. That concatenation lives in one place, `w_probe` in [hdl/libre_ila.vhdl](../../hdl/libre_ila.vhdl); change it there and the sample buffer and trigger vector follow.

## Definitions needed
Make sure to #define following variables, the whole register map is derived from them
* CORE_LIBRE_ILA_PROBE_WIDTH : Total probed bits, `C_PROBE_WIDTH` in the HDL
* CORE_LIBRE_ILA_SAMP_BUFF_DEPTH : Depth of the sample buffer in number of samples
* CORE_LIBRE_ILA_SAMP_FREQ_HZ : Sampling clock frequency in Hz

`LIBRE_ILA_init()` cross-checks every one of them against the values the hardware reports, so a mismatch is caught before any register offset is used.

## Directory structure: 
```text
drivers/
├── core_libre_ila.c     : C source file for the LibreILA driver implementation
├── core_libre_ila.h     : C header file for the LibreILA driver, containing function prototypes
├── core_libre_ila_regs.h : C header file defining register addresses and bit fields for the LibreILA
└── README.md       : This file
```
