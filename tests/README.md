# Tests
This directory contains the tests for the ILA. The testing is done in several steps.

The split is by what a test **needs to run**, not by what it covers:

| Directory | Needs | Run with |
|-----------|-------|----------|
| `hdl/`    | ghdl, plus the generated core in `codegen/gen_axis/` | `make sim-hdl` |
| `python/` | python3 and nothing else | `make sim-python` |
| `c/`      | a C compiler and nothing else | `make sim-c` |

`make sim` from the project root runs all three, host side tests first because they take milliseconds and a broken packet format or register map should not wait for the simulations to finish. A directory counts as a test if it carries a Makefile with a `sim` target, so the numbering is a convention and not something the build depends on.

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
| `07_sim_edge_test`       | Level versus rising versus falling trigger, `trig_cfg` bits 1 and 2 |
| `08_sim_addr_bound_check`| Address decoding at and past the end of the register map |

`08_sim_addr_bound_check` covers the three regions the other tests never
address. Registers below `C_N_REGS` are real; the ones between there and the top
of the decoded address slice are decodable but have nothing behind them, and
must read zero and swallow writes; anything above the slice has its high bits
dropped and aliases back onto the map. The unmapped region is the one worth
having a test for, because the range checks in `p_wlg`/`p_rlg` are all that
stands between it and an out of range array index — declare the decoded index
over the register count instead of over the slice and every access there becomes
a GHDL bound check failure rather than a zero, with the range check never
getting to run. The test also pins the output block being read only, which falls
out of the map order rather than out of any explicit write protection: the block
sits below the input one and `p_wlg` rebases the write index onto the input
block, so a write under `C_AXIL_N_CTRL_REGS_OUT` is out of range by
construction. Depth and probe width are picked so the register count is not a
power of two, since otherwise the map fills the slice exactly and there is no
unmapped region left to test; an elaboration assert catches that.

`07_sim_edge_test` runs its testbench three times over, once per trigger mode: `level`, `rising` and `falling`. All three share one stimulus in which the trigger condition is already true when the ILA is armed, then falls and rises again, because that is the case the three modes disagree about. The level run triggers on the first sample, the two edge runs wait for their transition, and each run checks the probe counter carried by the sample the DUT names in `trig_idx`. `make sim-rising` or `make wave-falling` picks one out. Since the condition holds across the arm, this is also what pins the seeding of `trig_lvl_prev`: cleared instead of seeded, the rising run would fire on the first sample and its check would fail.

`00_sim_ext_trig` runs its testbench three times over, once per trigger position: `0` (the first slot of the sample buffer), `C_DEPTH` (one past its last slot) and `3` (inside it). Each run gets its own work directory under `work/` holding its own copy of `tb.vhdl` with `C_TRIG_IDX` patched into it, so the three builds and waveforms survive each other. `make sim` runs all three, `make sim-trig_0` or `make wave-trig_3` picks one out, and the variant list lives at the top of that test's Makefile. Every report line carries its `C_TRIG_IDX`, so one log covering three runs still reads.

These read `codegen/gen_axis/` rather than `hdl/`, so what gets simulated is what the generator actually emits. **After editing anything in `hdl/`, delete `codegen/gen_axis/` (or run `make clean`) or the tests will keep simulating the previous build.**

## python/
Host side tests for the drivers. No ghdl, no generated core, and pyserial is stubbed so nothing opens a real port.

| Test | What it covers |
|------|----------------|
| `00_pkt_format` | The python driver's packet format, register map, control path and readout, against a model of the wrapper's parser |
| `01_vcd` | The portmap parsing and the VCD writing, against the generator's parse rules and a second reader of the format |
| `02_cli` | Every verb of `libre_ila.py` end to end, against the same model of the wrapper |

`00_pkt_format` exists because the UART packet format is the one thing the RTL and the python driver have to agree on, and nothing else checks that agreement: the wrapper is happy to answer a malformed request and the driver is happy to misparse a well-formed reply.

`01_vcd` exists for the same reason one level up: `portmap.csv` is parsed once by the generator to build the hardware and once by the driver to name the bits coming back, and nothing links the two. A layout that disagrees does not raise, it produces a waveform with the boundaries in the wrong places.

`02_cli` covers what sits between argparse and the driver and is reachable from neither: when a port gets opened, how a half-given trigger is merged into the one the core already holds, which files `--reset` is willing to delete, and what exit status a shell ends up seeing.

## c/
The baremetal driver, compiled and run on the host. No cross toolchain: it reaches the hardware only through the four `HW_*_reg()` accessors, so `stub/` backs those with a flat array and supplies the `HAL_*_reg()` macros, `addr_t` and `readmtime()` that the PolarFire SoC toolchain would otherwise provide.

| Test | What it covers |
|------|----------------|
| `00_reg_map` | The register map the driver derives at runtime, its argument checks, the readout, and two cores of different probe widths driven from one binary |

The stubbed `HAL_*_reg()` macros are reimplemented rather than copied, partly to keep vendor code out of the tree and partly because the contract they impose is itself what the map ordering answers: they paste `REG_NAME##_REG_OFFSET` at preprocess time, so an offset worked out at runtime cannot go through them. That is why offsets in `core_libre_ila_regs.h` are relative to their block and the part that moves with the probe width sits in the block's base address instead.

See [c/00_reg_map/README.md](c/00_reg_map/README.md) for the case list and for the three injected regressions the suite was checked against — a test that cannot fail is not covering anything.

The same `FakeWrapper` also serves the register map, so the tests cover the two other places the driver can silently disagree with the hardware:

* **The register map derived from the probe width.** Everything scales with the stride, the lane count rounded up to a power of two with a minimum of four, so `TestRegisterMap` pins the offsets against the map in the [datasheet](../docs/datasheet.pdf) rather than against the driver's own arithmetic. This matters because the core truncates an address it cannot decode instead of rejecting it, so a wrong stride aliases onto real registers rather than failing.
* **The control path and the readout.** `TestControl` covers the status decode and the ARM_FT guards, `TestReadout` covers unrolling the circular buffer from the oldest sample and rebasing the trigger index onto that ordering.
