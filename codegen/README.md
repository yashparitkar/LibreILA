# Codegen
This directory contains files for generating ILA files for the given configuration.

## code_generator.py
This script generates the VHDL files from the templates in `../hdl`, filling in
the probe port configuration from `portmap.csv` and the generic defaults from
`configuration.csv`.

```sh
python3 code_generator.py                                    # stock build -> gen_axis/
python3 code_generator.py --portmap portmap.csv \
                         --config  configuration.csv         # user build  -> gen/
python3 code_generator.py --dry-run                          # report only
```

| Option | Description |
|--------|-------------|
| `--portmap <file>` | probe portmap CSV, default `templates/default_portmap.csv` |
| `--config <file>`  | core configuration CSV, default `templates/default_configuration.csv` |
| `--outdir <dir>`   | override the output directory |
| `--dry-run`        | report what would be generated without writing anything |

Defaults are resolved relative to this script, so it can be invoked from
anywhere, including the project Makefile at the repository root.

## Code generation
Since the core is generic, a build is fully described by two csv files in this directory:

* `portmap.csv`: the probed signals, one per line as `signal,width,type`, listed LSB first. This defines both probe ports, the `w_probe` concatenation and `G_PROBE_WIDTH`. The same file is read by the python driver to name the signals in the .vcd.
* `configuration.csv`: the generic values, one per line as `generic,type,value`.

`type` is the direction the signal has on `probe_slave_*`, i.e. the direction the probed link's slave would give it:

| type | Slave side | Master side | Pass through |
|------|------------|-------------|--------------|
| `in`  | input  | output | yes, slave to master |
| `out` | output | input  | yes, master to slave |
| `mon` | input  | none   | no, parallel tap only |

### Why there is no `inout`

A signal assignment cannot pass a bidirectional line through. `probe_master_x <= probe_slave_x` makes the core a *second driver* on the master side, so anything the far end drives resolves to `'X'`, and nothing ever propagates backwards. Writing both directions is a combinational loop. Even the open-drain idiom (`'0' when other = '0' else 'Z'`, both ways) latches up once both sides are low — real I2C repeaters avoid that with offset voltages, not logic.

It also isn't needed, because an ILA cannot sit between a pad and the outside world. Splice it on the fabric side of the IO buffer, where the bus is not bidirectional yet. A QPI flash, for example, is three unidirectional groups before the tristate:

```
qspi_sio_o,4,in     data the controller drives
qspi_sio_oe,1,in    turnaround control
qspi_sio_i,4,out    data read back
```

That captures strictly more than a pad probe would: drive value, enable and read value are separate, so the pad is reconstructable (`oe=1` controller driving, `oe=0` flash driving) and the turnaround itself becomes visible and triggerable — which is where the bugs usually are.

Where the bus genuinely cannot be spliced in series, for instance a controller that only exposes one bidirectional port, tap it in parallel with `mon`. The core reads the resolved value and never drives it.

`templates/` holds a starting point for both (`default_portmap.csv` is the stock AXI4S probe, `default_configuration.csv` the default generics). Both are read from `../hdl/`, never written back to it, so the templates in `../hdl/` stay the single source.

### Running it

```sh
python3 code_generator.py                        # stock build  -> gen_axis/
python3 code_generator.py \
        --portmap portmap.csv \
        --config  configuration.csv              # user build   -> codegen/gen/
python3 code_generator.py --dry-run              # report only, writes nothing
```

The output directory is picked automatically: a run with **both** csv files left at their shipped defaults is the stock build and lands in `gen_axis/`, anything else lands in `gen/`. `--outdir` overrides that. Neither directory is tracked.

`GEN_TYPE` decides which files come out: `0` emits the bare AXI4Lite core alone, `1` emits it together with the UART wrapper and the fifo/uart blocks it instantiates. The testbenches need the wrapper, so `templates/default_configuration.csv` keeps `GEN_TYPE` at 1.

The testbenches under `tests/hdl/` read `gen_axis/` rather than `../hdl/`, so what gets simulated is what the generator actually emits. Each of those test Makefiles treats that directory as an order-only prerequisite: if it exists it is reused untouched, if it is missing the generator runs first. **After editing anything in `../hdl/`, delete `gen_axis/` (or run `make clean`) or the tests will keep simulating the previous build.**

The generated files can be passed through VHDL Style Guide (VHDL Style Guide) to make them more readable.

> `configuration_generation.py` is still to be written, see the future improvements section.

### Code generation directives
The script works as find and replace. The lines with ^^XX are used as reference. Depending on the type of XX, different format are inserted. The generated block is inserted after the directive's comment header, i.e. after the run of comment lines that immediately follows the ^^XX line, so the heading and its closing rule stay above the generated code. See table for details:

| ^^XX | File | Description |
|------|------|-------------|
| ^^DI | both | Declaration of the probe ports, slave side |
| ^^DO | both | Declaration of the probe ports, master side |
| ^^MI | libre_ila_uart | Mapping of the slave ports in libre_ila_uart |
| ^^MO | libre_ila_uart | Mapping of the master ports in libre_ila_uart |
| ^^SH | libre_ila | Shorting of the probe master and slave ports |
| ^^MX | libre_ila | MUXING of the probe ports to the w_probe concatenation for writing into sampling buffer |

A directive listed for a file but never found in it aborts the run, so a silently dropped block cannot turn into an unconnected port at elaboration.

Alongside the directives the script rewrites the default of every generic named in `configuration.csv`, plus `G_PROBE_WIDTH` which it sums from the portmap. Only declarations that already carry a `:=` are touched, which confines this to the entity and leaves the wrapper's component declarations alone.

`G_UID` is the one key that may be left out of `configuration.csv` entirely, since a build with a single ILA in it has no use for an instance identity; leaving it out is the same as setting it to zero. A `natural` value may be written in hex, so `G_UID,natural,0x0BADC0DE` is read as 195936478. The ceiling is `0x7FFFFFFF`, because a VHDL `natural` is a subtype of the signed 32 bit `integer` and cannot hold anything with the top bit set.

## Requirements:
argparse, os, re, shutil, sys (all standard library)

## gen_axis/
The stock build, i.e. what comes out when both csv files are left at their
shipped defaults. The testbenches read this directory instead of `../hdl`, and
regenerate it only when it is missing. Not tracked.

## gen/
The results of a user code generation, i.e. any run whose portmap or
configuration differs from the defaults. Not tracked.
