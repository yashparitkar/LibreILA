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
| `00_sim_ext_trig`        | External trigger path |
| `01_sim_axil_trig`       | Trigger vector over AXI4Lite |
| `02_sim_axil_trig_data`  | Trigger plus sample buffer readout |
| `03_sim_axil_cdc`        | Clock domain crossing on arm and status |
| `04_sim_axil_force_trig` | Force trigger |
| `06_sim_libre_ila_uart`  | End to end dataflow through the UART wrapper |

These read `codegen/gen_axis/` rather than `hdl/`, so what gets simulated is what the generator actually emits. **After editing anything in `hdl/`, delete `codegen/gen_axis/` (or run `make clean`) or the tests will keep simulating the previous build.**

## python/
Host side tests for the drivers. No ghdl, no generated core, and pyserial is stubbed so nothing opens a real port.

| Test | What it covers |
|------|----------------|
| `00_pkt_format` | The python driver's packet format against a model of the wrapper's parser |

`00_pkt_format` exists because the UART packet format is the one thing the RTL and the python driver have to agree on, and nothing else checks that agreement: the wrapper is happy to answer a malformed request and the driver is happy to misparse a well-formed reply.
