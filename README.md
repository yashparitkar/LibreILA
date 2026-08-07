# LibreILA


<p align="center" width="100%">
    <img width="20%" src="docs/tex/images/libre_ila_logo.svg"> 
</p>

## What is LibreILA?

### ILA (Integrated Logic Analyzer)
It is a tool used to debug the signals in the FPGA fabric. It is a very useful tool to debug the signals in the FPGA fabric. The ILA core can be used to capture and analyze the signals in the FPGA fabric. The ILA core can be used to capture and analyze the signals in the FPGA fabric. The ILA core can be used to capture and analyze the signals in the FPGA fabric.

The motivation to make this is follows:
* There is no ILA like in Xilinx toolchain in the Microchip toolchain, the SmartDebug can not replace the ILA
* ILA serves as a really good tool to debug the signals

The core itself is generic: it samples a single flat probe word of `G_PROBE_WIDTH` bits and knows nothing about what those bits mean. The build shipped in [hdl/libre_ila.vhdl](hdl/libre_ila.vhdl) wires that probe to a pass through 64-bit AXI4S pair (67 probe bits), which is the reference configuration used by the tests and the drivers. Any other probe port map is meant to be produced by the generator in [codegen/](codegen/) from a `portmap.csv`.

> The generator scripts in [codegen/](codegen/) are still work in progress, for now the probe concatenation is edited by hand in `w_probe`.

## Features
* Generic probe: one flat probe word, the same layout is shared by the trigger vector and the sample buffer
* Optional external trigger port to synchronise with other ILAs
* Uses fabric ram for data storage and can be read back with AXI4Lite interface
* Data acquisition happens in a circular buffer, one sample per sampling clock edge while armed
* Probe taps are pass through, no delay is introduced due to the IP
* Customizable trigger:
    * Trigger can be set with AXI4Lite interface
    * Once setting the triggers condition, the ILA can be armed
    * Number of samples before and after trigger can be adjusted
    * The trigger condition can be taken on its level, its rising edge or its falling edge
    * Can also use an external trigger
    * A capture can be disarmed from either side of the trigger, so a condition that never fires costs a register write rather than a reset
* CDC on the ARM, DISARM and status bits
* Each core carries an instance ID, `G_UID`, read back at `0x14`, so a system holding several ILAs can tell which one it has reached
* A serial wrapper is also provided to easily use the ILA with the PC
* A C driver for the bare AXI4Lite core, and a python driver (work in progress) for the serial wrapper

# Documentation

> Note: Many of the docs are LLM generated, so they may contain errors. Please report any issues you find.

The datasheet is the specification. Everything else below is either a shorter
route to one part of it, or the thing it describes.

| Looking for | Go to |
|-------------|-------|
| How the core behaves and how to talk to it: probe and port structure, capture and trigger behaviour, clock domains, core parameters, the AXI4Lite register map register by register, and the UART packet format | [docs/datasheet.pdf](docs/datasheet.pdf) |
| The same register map, csv for ease of use, one row per field | [REGISTER_MAP.csv](REGISTER_MAP.csv) |
| Step-by-step usage | [docs/manual.pdf](docs/manual.pdf), work in progress |
| Generating a core for your own probe: the `portmap.csv` and `configuration.csv` formats, the `^^XX` directives, and why there is no `inout` | [codegen/README.md](codegen/README.md) |
| Driving the bare core from firmware over AXI4Lite | [drivers/baremetal/README.md](drivers/baremetal/README.md) |
| Driving the UART wrapper from a PC and dumping a `.vcd` | [drivers/python/README.md](drivers/python/README.md) |
| What each test covers and what it needs to run | [tests/README.md](tests/README.md) |
| The RTL itself | [hdl/libre_ila.vhdl](hdl/libre_ila.vhdl), wrapper in [hdl/libre_ila_uart.vhdl](hdl/libre_ila_uart.vhdl) |

The `.tex` sources for both documents are under [docs/tex/](docs/tex/); `make`
in that directory rebuilds the PDFs.

# Code generation
Since the core is generic, a build is fully described by two csv files in [codegen/](codegen/): `portmap.csv` and `configuration.csv`. See [codegen/README.md](codegen/README.md) for both formats, the `^^XX` directive table and how to run the generator.

# Tests
[tests/](tests/) is split by what a test needs to run rather than by what it covers:

* [tests/hdl/](tests/hdl/): GHDL simulations of the core and the wrapper, numbered in the order they build up in. These need ghdl and the generated core. `make sim-hdl`
* [tests/python/](tests/python/): host side tests for the python driver, no ghdl and no generated core, pyserial stubbed so nothing opens a port. `make sim-python`
* [tests/c/](tests/c/): the baremetal driver compiled and run on the host against a stubbed HAL, so it needs a C compiler and nothing from the PolarFire toolchain. `make sim-c`

`make sim` runs all three, host side first because those take milliseconds. A directory counts as a test if it carries a Makefile with a `sim` target, so the numbering is a convention and not something the build depends on. See [tests/README.md](tests/README.md) for what each one covers.

# Drivers

<p align="center" width="100%">
    <img width="60%" src="docs/tex/images/05-armed.png"> 
</p>
* [drivers/baremetal/](drivers/baremetal/): C driver for the bare core over AXI4Lite. The probe is opaque to it, the whole register map is derived from the probe width, buffer depth and sampling clock frequency read back from the core.
* [drivers/python/](drivers/python/): python driver for the UART wrapper. `libre_ila.py` is the command line front end, `driver.py` speaks the register map and `vcd.py` turns the samples back into named signals, reading `portmap.csv` for the names and writing a `.vcd` any waveform viewer will open. `read_regs`/`write_regs` speak the UART packet format, splitting anything longer than 127 words across packets, and raise on a timeout or a mismatched response header. The GUI is still to come.

# Future improvements

### Data compression
This can be further optimised for the data storage compression although I don't prefer that as it will make the readout complex.

### Finishing the generator script
The generator writes the probe port declarations, the shorting block, the `w_probe` concatenation and the default generics. One thing is still open:

* `i_ext_trig`/`o_trig_out` are always declared. `G_EXTERNAL_TRIG` only selects which trigger logic is generated inside, it does not remove the pins when they are unused.

### Generating the driver headers
`drivers/baremetal/core_libre_ila_regs.h` still wants `CORE_LIBRE_ILA_PROBE_WIDTH` and friends defined by hand per synthesis. The generator already computes all of it and could emit the header, and the per signal bit offsets it prints could feed the python driver's .vcd naming directly instead of it re-parsing `portmap.csv`.

### Masked data values
If needed, user can also modify the core to use masked data values for triggering.

# Serving suggestions

VHDL Style Guide can be used to make the generated code more readable.

GHDL can be used to verify the generated code in the make itself.

## License

Copyright 2026 Yash Paritkar

Licensed under the CERN Open Hardware Licence Version 2 - Permissive
(`CERN-OHL-P-2.0`). See [LICENSE](LICENSE). Every source file carries its own
copyright and `SPDX-License-Identifier` header, so the licence travels with the
file when you copy the HDL into your own project.

Exception: [hdl/uart.vhdl](hdl/uart.vhdl) is derived from
[pabennett/uart](https://github.com/pabennett/uart), Copyright 2015 Peter
Bennett, licensed under Apache-2.0, and is modified here.
