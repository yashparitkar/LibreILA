# LibreILA C drivers
This folder contains C drivers to control the libre_ila (not the libre_ila_uart).

The driver is written in C and is designed to be used in embedded systems. 

> The defaults are for the 64-bit AXI4S build. They size the arrays you hand the driver and nothing else, see [Definitions needed](#definitions-needed).

The AXI4Lite is implemented using the HAL functions provided by the PolarFire SoC toolchain. The AXI4Lite functions are implemented in the HAL library and are used to read and write to the registers of the LibreILA. Additionally, those can be changed with memory write and read functions, but it is not recommended to do so. In case user wants to use Xilinx toolchain, the AXI4Lite functions need to be implemented by user due to their tool chain dependence (XilIn32, XilOut32, etc.).

The driver is written close to FPGA agnostic, meaning it needs to be adapted to the specific FPGA being used.

## The probe is opaque
The driver knows nothing about what the ILA is wired to. It sees one flat probe word of `CORE_LIBRE_ILA_PROBE_WIDTH` bits, bit 0 upwards, and both the trigger vector and the captured samples use that same layout. Naming the bits is your project's job:

```c
#define MY_PROBE_ERR_BIT  (3u)

cond[LIBRE_ILA_BIT_WORD(MY_PROBE_ERR_BIT)] |= LIBRE_ILA_BIT_MASK(MY_PROBE_ERR_BIT);
mask[LIBRE_ILA_BIT_WORD(MY_PROBE_ERR_BIT)] |= LIBRE_ILA_BIT_MASK(MY_PROBE_ERR_BIT);

LIBRE_ILA_configure_trigger(&ila, cond, mask, CORE_LIBRE_ILA_STRIDE_WIDTH,
                            LIBRE_ILA_TRIG_MODE_AND);
```

For the stock AXI4S build the probe is TDATA in the low bits, then TLAST, TVALID and TREADY — so a 64-bit bus gives `CORE_LIBRE_ILA_PROBE_WIDTH` of 67. That concatenation lives in one place, `w_probe` in [hdl/libre_ila.vhdl](../../hdl/libre_ila.vhdl); change it there and the sample buffer and trigger vector follow.

## The register map comes from the core

`LIBRE_ILA_init()` reads the probe width, buffer depth and sampling clock frequency out of the core and works the register map out from them, leaving the lot in the instance. Nothing in the driver is compiled against one synthesis, so re-synthesising with a different `G_PROBE_WIDTH` does not need a firmware rebuild, and **one binary can drive several cores of different probe widths at once** — each `libre_ila_instance_t` carries its own geometry.

This works because the output block sits at the base address in every build: the registers that report the width are findable before the width is known. See the register summary section of the [datasheet](../../docs/datasheet.pdf).

## Definitions needed

These size the arrays you declare, and nothing else. The driver does not read them.

* `CORE_LIBRE_ILA_PROBE_WIDTH` : Total probed bits, `G_PROBE_WIDTH` in the HDL
* `CORE_LIBRE_ILA_SAMP_BUFF_DEPTH` : Depth of the sample buffer in samples, `G_SAMP_BUFF_DEPTH` in the HDL
* `CORE_LIBRE_ILA_SAMP_FREQ_HZ` : Sampling clock frequency in Hz, `G_SAMP_CLK_FREQ` in the HDL. Nothing is derived from this one at all, it is only somewhere to record what you expect; the core reports the real value in `ila.samp_clk_freq_hz`.

Array sizes cannot come from the hardware — they are storage in your own scope and there is no allocator on the way. So the size stays a build time decision, but `LIBRE_ILA_configure_trigger()` and `LIBRE_ILA_read_data()` take the length alongside the pointer and return `CMD_STATUS_BAD_PARAM` unless it matches what the core actually needs. A width guessed wrong fails at the call rather than overrunning the buffer or filling it at one row length and indexing it at another.

For a second core of a different width, size its arrays with `LIBRE_ILA_TRIG_WORDS(width)` / `LIBRE_ILA_SAMPLE_WORDS(width, depth)` and index them with `LIBRE_ILA_SAMPLE_WORD_N()` / `LIBRE_ILA_SAMPLE_BIT_N()`, passing that instance's `n_lanes`.

## Directory structure: 
```text
drivers/
├── core_libre_ila.c     : C source file for the LibreILA driver implementation
├── core_libre_ila.h     : C header file for the LibreILA driver, containing function prototypes
├── core_libre_ila_regs.h : C header file defining register addresses and bit fields for the LibreILA
└── README.md       : This file
```
