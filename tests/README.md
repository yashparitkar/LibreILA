# Tests
This directory contains the tests for the ILA. The testing is done in several steps.

The split is by what a test **needs to run**, not by what it covers:

| Directory | Needs | Run with |
|-----------|-------|----------|
| `hdl/`    | ghdl, plus the generated core in `codegen/gen_axis/` | `make sim-hdl` |
| `python/` | python3 and nothing else | `make sim-python` |

`make sim` from the project root runs both, host side tests first because they take milliseconds and a broken packet format should not wait for the simulations to finish. A directory counts as a test if it carries a Makefile with a `sim` target, so the numbering is a convention and not something the build depends on.

## hdl/
GHDL simulations of the core and the UART wrapper. The numbering is the order they build up in, each one leaning on what the last established.

| Test | What it covers |
|------|----------------|
| `00_sim_ext_trig`        | External trigger path, at three trigger positions |
| `01_sim_axil_trig`       | Trigger vector over AXI4Lite |
| `02_sim_axil_trig_data`  | Trigger plus sample buffer readout |
| `03_sim_axil_cdc`        | Clock domain crossing on arm and status |
| `04_sim_axil_force_trig` | Force trigger |
| `06_sim_libre_ila_uart`  | End to end dataflow through the UART wrapper |

`00_sim_ext_trig` runs its testbench three times over, once per trigger position: `0` (the first slot of the sample buffer), `C_DEPTH` (one past its last slot) and `3` (inside it). Each run gets its own work directory under `work/` holding its own copy of `tb.vhdl` with `C_TRIG_IDX` patched into it, so the three builds and waveforms survive each other. `make sim` runs all three, `make sim-trig_0` or `make wave-trig_3` picks one out, and the variant list lives at the top of that test's Makefile. Every report line carries its `C_TRIG_IDX`, so one log covering three runs still reads.

These read `codegen/gen_axis/` rather than `hdl/`, so what gets simulated is what the generator actually emits. **After editing anything in `hdl/`, delete `codegen/gen_axis/` (or run `make clean`) or the tests will keep simulating the previous build.**

## python/
Host side tests for the drivers. No ghdl, no generated core, and pyserial is stubbed so nothing opens a real port.

| Test | What it covers |
|------|----------------|
| `00_pkt_format` | The python driver's packet format, register map, control path and readout, against a model of the wrapper's parser |

`00_pkt_format` exists because the UART packet format is the one thing the RTL and the python driver have to agree on, and nothing else checks that agreement: the wrapper is happy to answer a malformed request and the driver is happy to misparse a well-formed reply.

The same `FakeWrapper` also serves the register map, so the tests cover the two other places the driver can silently disagree with the hardware:

* **The register map derived from the probe width.** Everything scales with the stride, the lane count rounded up to a power of two with a minimum of four, so `TestRegisterMap` pins the offsets against the map in the top level README rather than against the driver's own arithmetic. This matters because the core truncates an address it cannot decode instead of rejecting it, so a wrong stride aliases onto real registers rather than failing.
* **The control path and the readout.** `TestControl` covers the status decode and the ARM_FT guards, `TestReadout` covers unrolling the circular buffer from the oldest sample and rebasing the trigger index onto that ordering.
