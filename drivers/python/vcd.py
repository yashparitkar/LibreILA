#####################################################################
# File: vcd.py
# Author: Y.U.P. (yashparitkar)
# Created: 2026-08-01 Sat 15:02
# Last Modified: 2026-08-01 Sat 15:02
#
# Description: ILA sample decoding file
#   This file turns what the driver reads off the core into named signals.
#   driver.py stops at raw 32 bit words on purpose, so the portmap parsing
#   and the VCD writing both live here.
#
#   Nothing in this file imports pyserial, so it can be exercised without a
#   core, a port or a stub standing in for one.
#
# Copyright 2026 Yash Paritkar
# SPDX-License-Identifier: CERN-OHL-P-2.0
#####################################################################

import os

# The portmap is the single definition of the probe bit order, and the
# generator writes the hardware from it. It is deliberately re-parsed here
# rather than handed over from codegen, see the comment at
# codegen/code_generator.py:325-327: one file describes the probe for the
# hardware and for the host at once, and neither side caches the other's
# reading of it.
PROBE_TYPES = ["in", "out", "mon"]

# The generator refuses inout for a reason worth repeating rather than
# pointing at, since this is the copy a driver user hits first.
INOUT_HELP = """\
probe '{name}' is declared inout. A bidirectional line cannot be passed
  through with a signal assignment, so the portmap lists the unidirectional
  signals the tristate is built from instead, e.g. for a QPI flash
  qspi_sio_o,4,in / qspi_sio_oe,1,in / qspi_sio_i,4,out. Where the bus
  cannot be spliced in series at all, tap it in parallel with 'mon'.
  See the code generation section of codegen/README.md."""

# VCD identifier codes are the printable ASCII range, 33 ('!') to 126 ('~')
_VCD_ID_FIRST = 33
_VCD_ID_COUNT = 94

# The synthetic signal that marks the trigger sample. VCD has no notion of a
# marker, so the trigger is carried as a wire that pulses for exactly the one
# sample it fired on, which every viewer will show and search for.
_TRIGGER_SIGNAL = "trigger"


def _ident(index):
    """
    _ident: VCD identifier code for the nth declared variable.

    index: The zero based position of the variable in the declaration order.

    returns: The identifier string.
    """

    code = ""

    # 94 codes fit in one character, anything past that rolls into a second
    while True:
        code += chr(_VCD_ID_FIRST + index % _VCD_ID_COUNT)
        index = index // _VCD_ID_COUNT - 1

        if index < 0:
            return code


def load_portmap(path):
    """
    load_portmap: Read portmap.csv and work out each signal's place in the probe word.

    path: Path to the portmap csv.

    returns: A list of dicts with name, width, type, lsb and msb, in the order
    the signals are listed in the file.
    """

    with open(path, "r") as portmap_file:
        portmap_lines = portmap_file.readlines()

    probes = []

    # The same acceptance rules as codegen/code_generator.py:280-302. The
    # startswith is deliberately not applied to the stripped line, so an
    # indented '#' is an error on both sides rather than a comment on one.
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

            if probe_type == "inout":
                raise ValueError(INOUT_HELP.format(name=probe_name))

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
        raise ValueError(f"No probes listed in {path}, the core needs at least one.")

    duplicates = {p["name"] for p in probes if [q["name"] for q in probes].count(p["name"]) > 1}
    if duplicates:
        raise ValueError(f"Duplicate probe names in the portmap: {', '.join(sorted(duplicates))}")

    # Packed LSB first in the listed order, so the first signal owns the low
    # bits. This mirrors the w_probe concatenation the generator emits.
    bit_offset = 0
    for probe in probes:
        probe["lsb"]  = bit_offset
        probe["msb"]  = bit_offset + probe["width"] - 1
        bit_offset   += probe["width"]

    return probes


def portmap_width(probes):
    """
    portmap_width: Total probe width the portmap describes.

    probes: The list load_portmap returned.

    returns: The sum of the probe widths, i.e. G_PROBE_WIDTH.
    """

    return sum(probe["width"] for probe in probes)


def check_portmap(probes, probe_width):
    """
    check_portmap: Verify the portmap against the width the core reports.

    probes: The list load_portmap returned.
    probe_width: The probe width read back from the core.

    returns: None
    """

    mapped = portmap_width(probes)

    # Without this the bits still slice cleanly, just at the wrong
    # boundaries, and the capture comes back looking like a plausible
    # waveform rather than an error. It is the one check that catches a
    # portmap that has drifted from the synthesised core.
    if mapped != probe_width:
        raise ValueError(f"the portmap describes {mapped} probe bits but the core reports "
                         f"{probe_width}. The portmap does not match the synthesised core, "
                         f"regenerate it or point --portmap at the one the core was built from")


def unpack_sample(row, probes):
    """
    unpack_sample: Split one sample's raw words into per signal values.

    row: One entry of the samples list read_data returned, n_lanes 32 bit words.
    probes: The list load_portmap returned.

    returns: A list of integer values, one per probe, in portmap order.
    """

    # The lanes are little endian across the probe word, lane 0 carries bit 0
    word = 0
    for lane, value in enumerate(row):
        word |= (value & 0xffffffff) << (32 * lane)

    return [(word >> probe["lsb"]) & ((1 << probe["width"]) - 1) for probe in probes]


def _format_value(value, width, ident):
    """
    _format_value: One VCD value change.

    value: The value to emit.
    width: The width of the signal in bits.
    ident: The signal's VCD identifier code.

    returns: The value change line.
    """

    # Scalars carry no space between the value and the identifier, vectors do
    if width == 1:
        return f"{value & 1}{ident}"

    return f"b{value:b} {ident}"


def write_vcd(path, samples, trig_idx, probes, samp_freq_hz):
    """
    write_vcd: Write the captured samples out as a VCD.

    path: Path of the vcd file to write.
    samples: The samples read_data returned, oldest first.
    trig_idx: The row the trigger fired on, as read_data rebased it.
    probes: The list load_portmap returned.
    samp_freq_hz: The sampling clock frequency the core reports, in Hz.

    returns: None
    """

    if not samples:
        raise ValueError("no samples to write, the capture is empty")

    if samp_freq_hz <= 0:
        raise ValueError(f"the core reports a sampling clock of {samp_freq_hz} Hz")

    if trig_idx < 0 or trig_idx >= len(samples):
        raise ValueError(f"trigger index {trig_idx} is outside the {len(samples)} samples captured")

    # Picoseconds keep the step an exact integer for every clock that divides
    # into 1e12, which covers the round numbers a sampling domain actually
    # runs at. 100 MHz lands on 10000 ps.
    period_ps = round(1e12 / samp_freq_hz)

    # The trigger wire is declared last so it never shifts the probe
    # identifiers when the portmap changes.
    idents         = [_ident(i) for i in range(len(probes) + 1)]
    trigger_ident  = idents[-1]

    # The default output directory need not exist yet, and a path the caller
    # gave is theirs to have made
    directory = os.path.dirname(path)

    if directory:
        os.makedirs(directory, exist_ok=True)

    with open(path, "w") as vcd_file:
        vcd_file.write("$timescale 1ps $end\n")
        vcd_file.write("$scope module libre_ila $end\n")

        for probe, ident in zip(probes, idents):
            vcd_file.write(f"$var wire {probe['width']} {ident} {probe['name']} $end\n")

        vcd_file.write(f"$var wire 1 {trigger_ident} {_TRIGGER_SIGNAL} $end\n")
        vcd_file.write("$upscope $end\n")
        vcd_file.write("$enddefinitions $end\n")

        previous = None
        last     = len(samples) - 1

        for index, row in enumerate(samples):
            values  = unpack_sample(row, probes)
            trigger = 1 if index == trig_idx else 0

            if previous is None:
                # The first timestep states every signal, the rest only say
                # what moved, which is what keeps a full buffer of a mostly
                # idle bus small.
                vcd_file.write(f"#{index * period_ps}\n")
                vcd_file.write("$dumpvars\n")

                for probe, ident, value in zip(probes, idents, values):
                    vcd_file.write(_format_value(value, probe["width"], ident) + "\n")

                vcd_file.write(_format_value(trigger, 1, trigger_ident) + "\n")
                vcd_file.write("$end\n")
            else:
                changes = [_format_value(value, probe["width"], ident)
                           for probe, ident, value, was
                           in zip(probes, idents, values, previous[0])
                           if value != was]

                if trigger != previous[1]:
                    changes.append(_format_value(trigger, 1, trigger_ident))

                # A sample where nothing moved needs no timestep at all. The
                # last one is written even when empty, otherwise the trace
                # would appear to stop at the final edge rather than at the
                # end of the buffer, and the capture would look shorter than
                # it is.
                if changes or index == last:
                    vcd_file.write(f"#{index * period_ps}\n")
                    vcd_file.writelines(line + "\n" for line in changes)

            previous = (values, trigger)
