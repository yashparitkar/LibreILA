#####################################################################
# File: code_generator.py
# Author: Y.U.P. (yashparitkar)
# Created: 2026-07-24 Fri 19:48
# Last Modified: 2026-07-29 Wed 13:00
#
# Description: This script generates code with the user portmap and
#   configuration.
#
# Copyright 2026 Yash Paritkar
# SPDX-License-Identifier: CERN-OHL-P-2.0
#####################################################################

import argparse
import os
import re
import shutil
import sys

# Probe types ######################################################
# in    driven by the master of the probed link, entering on the slave side
# out   driven by the slave of the probed link, entering on the master side
# mon   parallel tap, slave side only. No master port, no pass through, the
#       core never drives it. For buses that cannot be spliced in series.
#
# inout is deliberately absent, see the message below.
PROBE_TYPES = ["in", "out", "mon"]

# Types that get a mirrored port on the master side and a pass through
PASS_THROUGH_TYPES = ["in", "out"]

INOUT_HELP = """\
error: probe '{name}' is declared inout, which cannot be passed through with
  a signal assignment. The core would become a second driver on the master
  side, and nothing driven there would ever propagate back to the slave
  side. Writing both directions is a combinational loop instead.

  An ILA cannot sit between a pad and the outside world anyway, so splice it
  on the fabric side of the IO buffer and list the unidirectional signals
  the tristate is built from. For a QPI flash that is:

    qspi_sio_o,4,in     data the controller drives
    qspi_sio_oe,1,in    turnaround control
    qspi_sio_i,4,out    data read back

  That also captures more than the pad would: the turnaround becomes visible
  and triggerable instead of being guessed from a single resolved value.

  If the bus cannot be spliced in series at all, tap it in parallel with the
  'mon' type, which generates a slave side input and no master side."""


# Supporting functions ##############################################
def probe_type_mirror(probe_type):
    """Return the mirrored type for a given probe type."""
    if probe_type == "in":
        return "out"
    elif probe_type == "out":
        return "in"
    else:
        raise ValueError(f"Probe type has no mirror: {probe_type}")


def vhdl_type(width):
    """Return the VHDL type for a probe of the given width."""
    if width == 1:
        return "std_logic"

    return f"std_logic_vector({width - 1} downto 0)"


def driving_side(probe):
    """Return the port that actually carries the value of a probe.

    An 'in' probe is driven by the master of the probed link, so it enters
    on the slave side. An 'out' probe is driven by that link's slave, so it
    enters on the master side. Sampling the driver rather than the shorted
    copy keeps the probe word one delta away from the wire either way. A
    'mon' probe only ever exists on the slave side.
    """
    if probe["type"] == "out":
        return f"probe_master_{probe['name']}"

    return f"probe_slave_{probe['name']}"
#####################################################################

# Command line arguments ############################################
# --portmap <file>
# --config <file>
# --outdir <dir>
# --dry-run
#
# if nothing is provided, the default portmap and configuration files will be
# used and the run is taken as production run
#
# The defaults are resolved relative to this script, not to the current
# working directory, so the script can be invoked from anywhere (e.g. from
# the project Makefile at the repository root). Paths given on the command
# line are resolved relative to the current working directory, as usual.
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_PORTMAP_FILE = os.path.join(SCRIPT_DIR, "templates", "default_portmap.csv")
DEFAULT_CONFIG_FILE = os.path.join(SCRIPT_DIR, "templates", "default_configuration.csv")

# The stock build, both csv files left at their defaults, goes to its own
# directory. The testbenches look for it there and only re-run this script
# when it is missing, so a user build never overwrites what the tests use.
DEFAULT_OUTPUT_DIR = os.path.join(SCRIPT_DIR, "gen_axis")
USER_OUTPUT_DIR = os.path.join(SCRIPT_DIR, "gen")

HDL_DIRECTORY = os.path.join(SCRIPT_DIR, os.pardir, "hdl")

parser = argparse.ArgumentParser(
    description="Generate the LibreILA core from a portmap and a configuration."
)
parser.add_argument(
    "--portmap",
    metavar="<file>",
    default=DEFAULT_PORTMAP_FILE,
    help="probe portmap CSV (default: templates/default_portmap.csv)"
)
parser.add_argument(
    "--config",
    metavar="<file>",
    default=DEFAULT_CONFIG_FILE,
    help="core configuration CSV (default: templates/default_configuration.csv)"
)
parser.add_argument(
    "--outdir",
    metavar="<dir>",
    default=None,
    help="output directory (default: gen_axis/ for the stock build, gen/ otherwise)"
)
parser.add_argument(
    "--dry-run",
    action="store_true",
    help="report what would be generated without writing any file"
)
args = parser.parse_args()

PORTMAP_FILE = args.portmap
CONFIG_FILE = args.config
DRY_RUN = args.dry_run

for path in (CONFIG_FILE, PORTMAP_FILE):
    if not os.path.isfile(path):
        sys.exit(f"error: no such file: {path}")

# A run is the stock build only when BOTH csv files are the shipped
# defaults. Comparing the resolved paths, so --portmap ./templates/... from
# any working directory still counts as the default.
IS_DEFAULT_BUILD = (
    os.path.realpath(PORTMAP_FILE) == os.path.realpath(DEFAULT_PORTMAP_FILE)
    and os.path.realpath(CONFIG_FILE) == os.path.realpath(DEFAULT_CONFIG_FILE)
)

if args.outdir is not None:
    OUTPUT_DIR = os.path.abspath(args.outdir)
elif IS_DEFAULT_BUILD:
    OUTPUT_DIR = DEFAULT_OUTPUT_DIR
else:
    OUTPUT_DIR = USER_OUTPUT_DIR

print(f"Configuration file: {CONFIG_FILE}")
print(f"Portmap file: {PORTMAP_FILE}")
print(f"Output directory: {OUTPUT_DIR}")

#####################################################################

# Required keywords for the configuration file
required_keywords = [
    "G_SAMP_CLK_FREQ",
    "G_AXIL_CLK_FREQ",
    "G_EXTERNAL_TRIG",
    "G_SAMP_BUFF_DEPTH",
    "GEN_TYPE",
    "G_UART_RX_FIFO_DEPTH",
    "G_UART_TX_FIFO_DEPTH",
    "G_BAUD_RATE"
]

# Read the configuration file
with open(CONFIG_FILE, "r") as config_file:
    config_lines = config_file.readlines()

# Parse the configuration values and make a dictionary of them
for line in config_lines:
    if line.strip() and not line.startswith("#"):
        key, type_str, value_str = line.strip().split(",")
        if type_str == "integer":
            value = int(value_str)
        elif type_str == "natural":
            # Base 0 first so a value can be written in hex, which an identity
            # usually is, with a decimal fallback so that a leading zero stays
            # a number rather than becoming a parse error
            try:
                value = int(value_str, 0)
            except ValueError:
                value = int(value_str, 10)
            if value < 0:
                raise ValueError(f"Value for {key} must be a natural number.")
        elif type_str == "string":
            value = value_str
        else:
            raise ValueError(f"Unknown type '{type_str}' for key '{key}'.")

        globals()[key] = value

# Ensuring all required keywords are present
for keyword in required_keywords:
    if keyword not in globals():
        raise ValueError(f"Missing required configuration keyword: {keyword}")

# G_UID is the one generic that is optional. A build with a single ILA in it has
# no use for an instance identity, and requiring it would break every existing
# configuration.csv for a feature those builds never read back. Unset is zero,
# which is what the register already returned before it had a name.
if "G_UID" not in globals():
    G_UID = 0


# Checking the values ###############################################
if G_SAMP_CLK_FREQ <= 0:
    raise ValueError("Sampling clock frequency must be a positive integer.")

if G_AXIL_CLK_FREQ <= 0:
    raise ValueError("AXI-Lite clock frequency must be a positive integer.")

if G_EXTERNAL_TRIG not in (0, 1):
    raise ValueError("G_EXTERNAL_TRIG must be 0 or 1.")

if GEN_TYPE not in (0, 1):
    raise ValueError("GEN_TYPE must be 0 (bare AXI4Lite core) or 1 (UART wrapper).")

# FIFO depth should be a power of 2 and greater than 1
if G_UART_RX_FIFO_DEPTH <= 1 or (G_UART_RX_FIFO_DEPTH & (G_UART_RX_FIFO_DEPTH - 1)):
    raise ValueError("UART RX FIFO depth must be a power of 2 and greater than 1.")

if G_UART_TX_FIFO_DEPTH <= 1 or (G_UART_TX_FIFO_DEPTH & (G_UART_TX_FIFO_DEPTH - 1)):
    raise ValueError("UART TX FIFO depth must be a power of 2 and greater than 1.")

if G_SAMP_BUFF_DEPTH <= 1 or (G_SAMP_BUFF_DEPTH & (G_SAMP_BUFF_DEPTH - 1)):
    raise ValueError("Sample buffer depth must be a power of 2 and greater than 1.")

# A VHDL natural tops out at 2**31 - 1. Caught here because otherwise the only
# complaint comes out of elaboration, about the literal rather than the config.
if G_UID > 0x7FFFFFFF:
    raise ValueError("G_UID must fit in a VHDL natural, i.e. be at most 0x7FFFFFFF.")

# 0 < baud rate < samp_clk/32(Warning) < samp_clk/16(Error)
if G_BAUD_RATE <= 0:
    raise ValueError("Baud rate must be a positive integer.")
else:
    if G_BAUD_RATE >= G_AXIL_CLK_FREQ / 16:
        raise ValueError("Baud rate must be less than axil_ckl_freq/16.")
    elif G_BAUD_RATE >= G_AXIL_CLK_FREQ / 32:
        print("Warning: Baud rate is greater than axil_ckl_freq/32. This may cause issues.")

# Read back the configuration values for verification
for var_name, var_value in [
    ("G_SAMP_CLK_FREQ", G_SAMP_CLK_FREQ),
    ("G_AXIL_CLK_FREQ", G_AXIL_CLK_FREQ),
    ("G_EXTERNAL_TRIG", G_EXTERNAL_TRIG),
    ("G_SAMP_BUFF_DEPTH", G_SAMP_BUFF_DEPTH),
    ("G_UID", G_UID),
    ("GEN_TYPE", GEN_TYPE),
    ("G_UART_RX_FIFO_DEPTH", G_UART_RX_FIFO_DEPTH),
    ("G_UART_TX_FIFO_DEPTH", G_UART_TX_FIFO_DEPTH),
    ("G_BAUD_RATE", G_BAUD_RATE)
]:
    print(f"{var_name}: {var_value}")
#####################################################################

# Portmap configuration #############################################
# Read the user portmap file
with open(PORTMAP_FILE, "r") as portmap_file:
    portmap_lines = portmap_file.readlines()

# Create a list of dictionaries for each probe from the portmap
probes = []
for line in portmap_lines:
    if line.strip() and not line.startswith("#"):
        probe_info = line.strip().split(",")
        if len(probe_info) != 3:
            raise ValueError(f"Invalid portmap line: {line.strip()}")
        probe_name, probe_width_str, probe_type = probe_info
        try:
            probe_width = int(probe_width_str)
        except ValueError:
            raise ValueError(f"Invalid width for probe '{probe_name}': {probe_width_str}")

        # Verify that the probe type is one of the expected values
        if probe_type == "inout":
            sys.exit(INOUT_HELP.format(name=probe_name))

        if probe_type not in PROBE_TYPES:
            raise ValueError(
                f"Invalid type for probe '{probe_name}': {probe_type}. "
                f"Expected one of {', '.join(PROBE_TYPES)}."
            )

        if probe_width <= 0:
            raise ValueError(f"Width for probe '{probe_name}' must be a positive integer.")

        probes.append({
            "name": probe_name,
            "width": probe_width,
            "type": probe_type
        })

if not probes:
    raise ValueError(f"No probes listed in {PORTMAP_FILE}, the core needs at least one.")

duplicates = {p["name"] for p in probes if [q["name"] for q in probes].count(p["name"]) > 1}
if duplicates:
    raise ValueError(f"Duplicate probe names in the portmap: {', '.join(sorted(duplicates))}")

# Read back the probes for verification
for probe in probes:
    print(f"Probe: {probe['name']}, Width: {probe['width']}, Type: {probe['type']}")

G_PROBE_WIDTH = sum(probe['width'] for probe in probes )

print(f"G_PROBE_WIDTH:{G_PROBE_WIDTH}")

# Bit position of every probe inside w_probe. The portmap is packed LSB
# first, so the first listed signal owns the low bits. Reported here only,
# the drivers read the same portmap and redo this themselves.
bit_offset = 0
for probe in probes:
    probe["lsb"] = bit_offset
    probe["msb"] = bit_offset + probe["width"] - 1
    bit_offset += probe["width"]
    print(f"  w_probe({probe['msb']} downto {probe['lsb']}) : {probe['name']}")
#####################################################################

# Code generation ###################################################
# Every generated block is inserted at a ^^XX directive. See the code
# generation section of codegen/README.md for the directive table.

def side_probes(mirrored):
    """The probes that get a port on the requested side.

    A 'mon' probe is a parallel tap, so it exists on the slave side only.
    Everything else is mirrored onto both.
    """
    if mirrored:
        return [probe for probe in probes if probe["type"] in PASS_THROUGH_TYPES]

    return probes


def declaration_block(indent, mirrored):
    """Port declarations for one side of the probe.

    mirrored=False gives the slave side, i.e. the directions exactly as the
    portmap lists them. mirrored=True gives the master side.
    """
    selected = side_probes(mirrored)
    if not selected:
        return []

    prefix = "probe_master_" if mirrored else "probe_slave_"
    names = [prefix + probe["name"] for probe in selected]
    name_width = max(len(name) for name in names)

    lines = []
    for probe, name in zip(selected, names):
        if mirrored:
            direction = probe_type_mirror(probe["type"])
        elif probe["type"] == "mon":
            # A tap is read, never driven
            direction = "in"
        else:
            direction = probe["type"]
        lines.append(
            f"{indent}{name:<{name_width}} : {direction:<5} {vhdl_type(probe['width'])};"
        )

    return lines


def mapping_block(indent, mirrored):
    """Port map associations for one side of the probe."""
    selected = side_probes(mirrored)
    if not selected:
        return []

    prefix = "probe_master_" if mirrored else "probe_slave_"
    names = [prefix + probe["name"] for probe in selected]
    name_width = max(len(name) for name in names)

    return [f"{indent}{name:<{name_width}} => {name}," for name in names]


def shorting_block(indent):
    """Pass through between the slave and the master side of the probe.

    'mon' probes are absent here on purpose: a parallel tap has no master
    side and the core must never drive the bus it is watching.
    """
    targets = []
    for probe in probes:
        if probe["type"] == "in":
            # Driven by the probed link's master, forwarded to its slave
            targets.append((f"probe_master_{probe['name']}", f"probe_slave_{probe['name']}"))
        elif probe["type"] == "out":
            # Driven by the probed link's slave, forwarded back to its master
            targets.append((f"probe_slave_{probe['name']}", f"probe_master_{probe['name']}"))

    if not targets:
        return [f"{indent}-- Every probe is a parallel tap, nothing to pass through."]

    name_width = max(len(dst) for dst, _ in targets)

    return [f"{indent}{dst:<{name_width}} <= {src};" for dst, src in targets]


def muxing_block(indent):
    """The w_probe concatenation.

    Leftmost operand is the MSB, so the portmap is walked in reverse: the
    first listed signal has to land in the low bits.
    """
    sources = [driving_side(probe) for probe in reversed(probes)]

    lead = f"{indent}w_probe <= "
    lines = [f"{lead}{sources[0]}"]
    for source in sources[1:]:
        lines.append(f"{' ' * len(lead)}& {source}")
    lines[-1] += ";"

    return lines


# Directive -> block builder. The indentation is taken from the directive
# line itself, so the same builder serves the entity and the component
# declaration even though they sit at different depths.
DIRECTIVE_BUILDERS = {
    "^^DI": lambda indent: declaration_block(indent, mirrored=False),
    "^^DO": lambda indent: declaration_block(indent, mirrored=True),
    "^^MI": lambda indent: mapping_block(indent, mirrored=False),
    "^^MO": lambda indent: mapping_block(indent, mirrored=True),
    "^^SH": shorting_block,
    "^^MX": muxing_block
}

DIRECTIVE_RE = re.compile(r"\^\^([A-Z]{2})")
COMMENT_RE = re.compile(r"^\s*--")


def apply_directives(lines, source_name):
    """Expand every ^^XX directive found in lines.

    The generated block goes after the directive's comment header, i.e.
    after the run of comment lines that immediately follows the directive
    line. That keeps the block's own heading and its closing rule above the
    generated code instead of buried in it.
    """
    out = []
    seen = []

    idx = 0
    while idx < len(lines):
        line = lines[idx]
        out.append(line)

        match = DIRECTIVE_RE.search(line)
        if match is None:
            idx += 1
            continue

        directive = "^^" + match.group(1)
        if directive not in DIRECTIVE_BUILDERS:
            raise ValueError(f"{source_name}: unknown directive {directive}")

        indent = line[:len(line) - len(line.lstrip())]

        # Carry over the rest of the comment header untouched
        idx += 1
        while idx < len(lines) and COMMENT_RE.match(lines[idx]):
            out.append(lines[idx])
            idx += 1

        out.extend(DIRECTIVE_BUILDERS[directive](indent))
        seen.append(directive)

    return out, seen


GENERIC_VALUES = {
    "G_SAMP_CLK_FREQ": G_SAMP_CLK_FREQ,
    "G_AXIL_CLK_FREQ": G_AXIL_CLK_FREQ,
    "G_EXTERNAL_TRIG": G_EXTERNAL_TRIG,
    "G_PROBE_WIDTH": G_PROBE_WIDTH,
    "G_SAMP_BUFF_DEPTH": G_SAMP_BUFF_DEPTH,
    "G_UID": G_UID,
    "G_UART_RX_FIFO_DEPTH": G_UART_RX_FIFO_DEPTH,
    "G_UART_TX_FIFO_DEPTH": G_UART_TX_FIFO_DEPTH,
    "G_BAUD_RATE": G_BAUD_RATE
}


def apply_generics(lines):
    """Rewrite the default of every generic named in the configuration.

    Only declarations that already carry a default are touched, which
    confines this to the entity: the component declarations in the wrapper
    have no ':=' and are left alone.
    """
    patterns = [
        (name, re.compile(rf"^(\s*{name}\s*:\s*\w+\s*:=\s*)([^;\s]+)(.*)$"), value)
        for name, value in GENERIC_VALUES.items()
    ]

    out = []
    for line in lines:
        for _, pattern, value in patterns:
            match = pattern.match(line)
            if match:
                line = f"{match.group(1)}{value}{match.group(3)}"
                break
        out.append(line)

    return out


# Source files. The bare core is always generated, the UART wrapper and the
# blocks it instantiates only when the configuration asks for it.
CORE_FILES = ["libre_ila.vhdl"]
UART_FILES = ["fifo.vhdl", "uart.vhdl", "libre_ila_uart.vhdl"]

# Files carrying directives. Everything else is copied verbatim.
TEMPLATED_FILES = {
    "libre_ila.vhdl": ["^^DI", "^^DO", "^^SH", "^^MX"],
    "libre_ila_uart.vhdl": ["^^DI", "^^DO", "^^MI", "^^MO"]
}

source_files = CORE_FILES + (UART_FILES if GEN_TYPE == 1 else [])

print()
print(f"GEN_TYPE {GEN_TYPE}: generating {', '.join(source_files)}")

generated = {}

for file_name in source_files:
    source_path = os.path.join(HDL_DIRECTORY, file_name)
    if not os.path.isfile(source_path):
        sys.exit(f"error: no such source file: {source_path}")

    if file_name not in TEMPLATED_FILES:
        generated[file_name] = None  # copied verbatim
        continue

    with open(source_path, "r") as source_file:
        lines = source_file.read().splitlines()

    lines = apply_generics(lines)
    lines, seen = apply_directives(lines, file_name)

    # Every directive the file is supposed to carry has to have been hit,
    # and each exactly as often as the template repeats it. A silently
    # dropped block would elaborate as an unconnected port much later.
    expected = TEMPLATED_FILES[file_name]
    missing = [d for d in expected if d not in seen]
    if missing:
        sys.exit(f"error: {file_name}: directives never found: {', '.join(missing)}")

    generated[file_name] = "\n".join(lines) + "\n"

if DRY_RUN:
    print()
    print("Dry run, nothing written. Would write to " + OUTPUT_DIR + ":")
    for file_name, content in generated.items():
        if content is None:
            print(f"  {file_name} (copied verbatim)")
        else:
            print(f"  {file_name} ({len(content.splitlines())} lines)")
    sys.exit(0)

os.makedirs(OUTPUT_DIR, exist_ok=True)

for file_name, content in generated.items():
    output_path = os.path.join(OUTPUT_DIR, file_name)
    if content is None:
        shutil.copyfile(os.path.join(HDL_DIRECTORY, file_name), output_path)
        print(f"Copied  {output_path}")
    else:
        with open(output_path, "w") as output_file:
            output_file.write(content)
        print(f"Written {output_path}")
#####################################################################
