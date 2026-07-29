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

See the code generation section of the top level README for the `^^XX`
directive table.

## Requirements:
argparse, os, re, shutil, sys (all standard library)

## gen_axis/
The stock build, i.e. what comes out when both csv files are left at their
shipped defaults. The testbenches read this directory instead of `../hdl`, and
regenerate it only when it is missing. Not tracked.

## gen/
The results of a user code generation, i.e. any run whose portmap or
configuration differs from the defaults. Not tracked.
