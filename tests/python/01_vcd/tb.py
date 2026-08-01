#####################################################################
# File: tb.py
# Author: Y.U.P. (yashparitkar)
# Created: 2026-08-01 Sat 15:48
# Last Modified: 2026-08-01 Sat 15:48
#
# Description: Portmap and VCD test for the python driver
#   Checks drivers/python/vcd.py: the portmap parsing against the rules
#   codegen/code_generator.py enforces, and the VCD writing against a
#   second reader of the format. Host side, no GHDL, no generated core
#   and no pyserial.
#
# Copyright 2026 Yash Paritkar
# SPDX-License-Identifier: CERN-OHL-P-2.0
#####################################################################

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "drivers", "python"))

import vcd

_REPO_ROOT      = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..")
_PORTMAP        = os.path.join(_REPO_ROOT, "codegen", "portmap.csv")
_DEFAULT_PORTMAP = os.path.join(_REPO_ROOT, "codegen", "templates", "default_portmap.csv")

# The stock AXI4S build, 64 bits of TDATA plus the three signalling bits
_PROBE_WIDTH = 67
_FREQ_HZ     = 100000000

# 67 bits needs three lanes, which is what makes the reassembly worth testing:
# a probe value crosses two lane boundaries on its way back.
_N_LANES = 3

def stock_portmap():
    """
    stock_portmap: The reference AXI4S portmap as text.

    parameters: None

    returns: The file contents, comments and all.
    """

    return ("# signal,width,type\n"
            "axis_tdata,64,in\n"
            "axis_tlast,1,in\n"
            "axis_tvalid,1,in\n"
            "axis_tready,1,out\n")

def parse_from_text(text):
    """
    parse_from_text: Run load_portmap over a string.

    text: The portmap contents.

    returns: The probe list load_portmap produced.
    """

    with tempfile.TemporaryDirectory() as directory:
        path = os.path.join(directory, "portmap.csv")

        with open(path, "w") as portmap_file:
            portmap_file.write(text)

        return vcd.load_portmap(path)

def pack(values, probes):
    """
    pack: Build the lane words one sample of the given values would arrive as.

    values: The per signal values, in portmap order.
    probes: The probe list load_portmap produced.

    returns: The lane words, LSB lane first.

    This is the inverse of vcd.unpack_sample, written out separately so a
    round trip through it cannot agree with a shared mistake.
    """

    word = 0
    for probe, value in zip(probes, values):
        word |= (value & ((1 << probe["width"]) - 1)) << probe["lsb"]

    n_lanes = (vcd.portmap_width(probes) + 31) // 32

    return [(word >> (32 * lane)) & 0xffffffff for lane in range(n_lanes)]

def write_to_string(samples, trig_idx, probes, freq=_FREQ_HZ):
    """
    write_to_string: Run write_vcd and hand back what it wrote.

    samples: The samples, oldest first.
    trig_idx: The row the trigger fired on.
    probes: The probe list load_portmap produced.
    freq: The sampling clock frequency in Hz.

    returns: The VCD text.
    """

    with tempfile.TemporaryDirectory() as directory:
        path = os.path.join(directory, "out.vcd")

        vcd.write_vcd(path, samples, trig_idx, probes, freq)

        with open(path, "r") as vcd_file:
            return vcd_file.read()

def parse_vcd(text):
    """
    parse_vcd: Read a VCD back, independently of the code that wrote it.

    text: The VCD contents.

    returns: (declarations, timeline, timescale) where declarations maps a
    signal name to (width, identifier), timeline is a list of
    (time, {name: value}) with the value of every signal at that time, and
    timescale is the $timescale body.

    Deliberately a second implementation rather than a reuse of anything in
    vcd.py: a round trip through the writer's own assumptions would prove
    nothing about the file a waveform viewer sees.
    """

    declarations = {}
    by_ident     = {}
    timescale    = None
    timeline     = []
    current      = {}
    time         = None

    for line in text.splitlines():
        line = line.strip()

        if not line:
            continue

        if line.startswith("$timescale"):
            timescale = line.split(None, 1)[1].rsplit("$end", 1)[0].strip()
        elif line.startswith("$var"):
            # $var wire <width> <ident> <name> $end
            fields = line.split()
            width, ident, name = int(fields[2]), fields[3], fields[4]

            declarations[name] = (width, ident)
            by_ident[ident]    = name
        elif line.startswith("$") or line.startswith("#") is False and not line:
            continue
        elif line.startswith("#"):
            if time is not None:
                timeline.append((time, dict(current)))

            time = int(line[1:])
        elif time is not None:
            if line.startswith("b"):
                value, ident = line[1:].split()
                current[by_ident[ident]] = int(value, 2)
            elif line[0] in "01":
                current[by_ident[line[1:]]] = int(line[0])

    if time is not None:
        timeline.append((time, dict(current)))

    return declarations, timeline, timescale


class TestNoPyserial(unittest.TestCase):
    """
    TestNoPyserial: vcd.py's independence from the link layer.
    """

    def test_the_vcd_path_needs_no_pyserial(self):
        # 00_pkt_format has to stub serial to import driver.py. This module
        # deliberately does not, and asserting it is stronger than stubbing:
        # it fails the day vcd.py grows an import it does not need.
        self.assertNotIn("serial", sys.modules)
        self.assertNotIn("driver", sys.modules)


class TestPortmap(unittest.TestCase):
    """
    TestPortmap: The acceptance rules, pinned against the parse in
    codegen/code_generator.py:280-315. The two are separate implementations of
    one file format, so a file one accepts the other has to accept too.
    """

    def test_the_shipped_portmaps_parse(self):
        for path in (_PORTMAP, _DEFAULT_PORTMAP):
            with self.subTest(portmap=os.path.basename(path)):
                probes = vcd.load_portmap(path)

                self.assertEqual([p["name"] for p in probes],
                                 ["axis_tdata", "axis_tlast", "axis_tvalid", "axis_tready"])
                self.assertEqual(vcd.portmap_width(probes), _PROBE_WIDTH)

    def test_blank_lines_and_comments_are_skipped(self):
        probes = parse_from_text("# a comment\n\n   \naxis_tdata,64,in\n\n# another\n")

        self.assertEqual(len(probes), 1)
        self.assertEqual(probes[0]["name"], "axis_tdata")

    def test_an_indented_comment_is_an_error(self):
        # The generator tests startswith on the unstripped line, so an indented
        # '#' reaches the field split there and must reach it here too
        with self.assertRaises(ValueError):
            parse_from_text("axis_tdata,64,in\n  # indented\n")

    def test_fields_are_not_whitespace_stripped(self):
        # ' in' is not in PROBE_TYPES, on both sides of the project
        with self.assertRaises(ValueError):
            parse_from_text("axis_tdata, 64, in\n")

    def test_a_missing_trailing_newline_is_fine(self):
        probes = parse_from_text("axis_tdata,64,in")

        self.assertEqual(len(probes), 1)

    def test_the_field_count_is_exact(self):
        for line in ("axis_tdata,64\n", "axis_tdata,64,in,extra\n", "axis_tdata\n"):
            with self.subTest(line=line.strip()):
                with self.assertRaises(ValueError):
                    parse_from_text(line)

    def test_the_width_must_be_a_positive_integer(self):
        for width in ("0", "-1", "one", "1.5", ""):
            with self.subTest(width=width):
                with self.assertRaises(ValueError):
                    parse_from_text(f"axis_tdata,{width},in\n")

    def test_every_accepted_type_is_accepted(self):
        for probe_type in ("in", "out", "mon"):
            with self.subTest(type=probe_type):
                probes = parse_from_text(f"sig,1,{probe_type}\n")

                self.assertEqual(probes[0]["type"], probe_type)

    def test_an_unknown_type_is_rejected(self):
        with self.assertRaises(ValueError):
            parse_from_text("sig,1,inuot\n")

    def test_inout_is_rejected_with_its_own_message(self):
        # The generator exits with INOUT_HELP rather than the generic type
        # error, because the fix is a portmap rewrite and not a typo
        with self.assertRaises(ValueError) as caught:
            parse_from_text("qspi_sio,4,inout\n")

        self.assertIn("qspi_sio", str(caught.exception))
        self.assertIn("mon", str(caught.exception))

    def test_duplicate_names_are_rejected(self):
        with self.assertRaises(ValueError) as caught:
            parse_from_text("sig,1,in\nsig,2,in\n")

        self.assertIn("sig", str(caught.exception))

    def test_an_empty_portmap_is_rejected(self):
        with self.assertRaises(ValueError):
            parse_from_text("# nothing but a comment\n")


class TestProbeLayout(unittest.TestCase):
    """
    TestProbeLayout: Where each signal sits in the probe word, pinned against
    the table in docs/tex/datasheet.tex:343-360 and the w_probe concatenation
    in codegen/gen_axis/libre_ila.vhdl:355-358. A layout that is wrong here
    does not raise, it produces a plausible looking waveform with the
    boundaries in the wrong places.
    """

    def test_the_stock_layout(self):
        probes = vcd.load_portmap(_PORTMAP)
        layout = {p["name"]: (p["msb"], p["lsb"]) for p in probes}

        self.assertEqual(layout["axis_tdata"], (63, 0))
        self.assertEqual(layout["axis_tlast"], (64, 64))
        self.assertEqual(layout["axis_tvalid"], (65, 65))
        self.assertEqual(layout["axis_tready"], (66, 66))

    def test_the_first_signal_owns_the_low_bits(self):
        probes = parse_from_text("first,4,in\nsecond,8,in\nthird,1,in\n")

        self.assertEqual((probes[0]["lsb"], probes[0]["msb"]), (0, 3))
        self.assertEqual((probes[1]["lsb"], probes[1]["msb"]), (4, 11))
        self.assertEqual((probes[2]["lsb"], probes[2]["msb"]), (12, 12))

    def test_the_ranges_are_contiguous_and_sum_to_the_width(self):
        probes = parse_from_text("a,3,in\nb,17,in\nc,44,mon\nd,1,out\n")

        expected = 0
        for probe in probes:
            self.assertEqual(probe["lsb"], expected)
            expected = probe["msb"] + 1

        self.assertEqual(expected, vcd.portmap_width(probes))


class TestPortmapCheck(unittest.TestCase):
    """
    TestPortmapCheck: The cross-check against the width the core reports. This
    is the only thing standing between a portmap that has drifted from the
    synthesised core and a capture that reads as real data.
    """

    def test_a_matching_width_passes(self):
        vcd.check_portmap(vcd.load_portmap(_PORTMAP), _PROBE_WIDTH)

    def test_a_mismatch_names_both_numbers(self):
        probes = vcd.load_portmap(_PORTMAP)

        with self.assertRaises(ValueError) as caught:
            vcd.check_portmap(probes, 128)

        message = str(caught.exception)

        self.assertIn("67", message)
        self.assertIn("128", message)


class TestUnpack(unittest.TestCase):
    """
    TestUnpack: Reassembling one sample's lane words into signal values. The
    stock probe is 67 bits over 3 lanes, so tlast/tvalid/tready live in lane 2
    and a naive single word implementation loses them.
    """

    def test_the_stock_probe_across_three_lanes(self):
        probes = vcd.load_portmap(_PORTMAP)
        row    = pack([0xdeadbeefcafe0001, 1, 0, 1], probes)

        self.assertEqual(len(row), _N_LANES)
        self.assertEqual(vcd.unpack_sample(row, probes), [0xdeadbeefcafe0001, 1, 0, 1])

    def test_a_value_spanning_a_lane_boundary(self):
        # 40 bits starting at bit 8 covers the whole of lane 0's top half and
        # runs into lane 1
        probes = parse_from_text("low,8,in\nwide,40,in\n")
        row    = pack([0xa5, 0x123456789a], probes)

        self.assertEqual(vcd.unpack_sample(row, probes), [0xa5, 0x123456789a])

    def test_padding_above_the_probe_width_is_ignored(self):
        probes = vcd.load_portmap(_PORTMAP)
        row    = pack([0, 0, 0, 0], probes)

        # The hardware pads the 67 bit word out to the stride, and read_data
        # hands over n_lanes words, so the top of the last lane is not ours
        row[-1] |= 0xfffffff8

        self.assertEqual(vcd.unpack_sample(row, probes), [0, 0, 0, 0])

    def test_every_bit_position_round_trips(self):
        probes = vcd.load_portmap(_PORTMAP)

        for bit in range(_PROBE_WIDTH):
            with self.subTest(bit=bit):
                values = [(1 << bit) >> p["lsb"] & ((1 << p["width"]) - 1)
                          if p["lsb"] <= bit <= p["msb"] else 0
                          for p in probes]

                self.assertEqual(vcd.unpack_sample(pack(values, probes), probes), values)


class TestVcdHeader(unittest.TestCase):
    """
    TestVcdHeader: The declarations a viewer reads before any value change.
    """

    def setUp(self):
        self.probes = vcd.load_portmap(_PORTMAP)
        self.text   = write_to_string([pack([0, 0, 0, 0], self.probes)], 0, self.probes)

    def test_the_sections_come_in_order(self):
        positions = [self.text.index(section) for section in
                     ("$timescale", "$scope", "$var", "$upscope", "$enddefinitions")]

        self.assertEqual(positions, sorted(positions))

    def test_every_probe_is_declared_with_its_width_in_portmap_order(self):
        declarations, _, _ = parse_vcd(self.text)

        # dicts keep insertion order, so this checks the order too
        names = [name for name in declarations if name != "trigger"]

        self.assertEqual(names, [p["name"] for p in self.probes])

        for probe in self.probes:
            self.assertEqual(declarations[probe["name"]][0], probe["width"])

    def test_the_identifiers_are_unique_and_printable(self):
        declarations, _, _ = parse_vcd(self.text)
        idents             = [ident for _, ident in declarations.values()]

        self.assertEqual(len(idents), len(set(idents)))

        for ident in idents:
            for character in ident:
                self.assertTrue(33 <= ord(character) <= 126, ident)

    def test_the_timescale_makes_one_sample_a_round_number(self):
        _, timeline, timescale = parse_vcd(self.text)

        self.assertEqual(timescale, "1ps")

        # 100 MHz is 10 ns, which is 10000 ps exactly
        probes  = self.probes
        samples = [pack([i, 0, 0, 0], probes) for i in range(3)]
        _, timeline, _ = parse_vcd(write_to_string(samples, 0, probes))

        self.assertEqual([time for time, _ in timeline], [0, 10000, 20000])

    def test_identifiers_roll_over_past_94_signals(self):
        # 94 printable codes fit in one character, so a wide portmap needs two
        probes = parse_from_text("".join(f"sig{i},1,in\n" for i in range(120)))
        text   = write_to_string([pack([0] * 120, probes)], 0, probes)

        declarations, _, _ = parse_vcd(text)

        self.assertEqual(len(declarations), 121)  # 120 probes plus the trigger
        self.assertTrue(any(len(ident) > 1 for _, ident in declarations.values()))


class TestVcdBody(unittest.TestCase):
    """
    TestVcdBody: The value changes, checked by reading the file back with
    parse_vcd rather than by matching the writer's own output.
    """

    def setUp(self):
        self.probes = vcd.load_portmap(_PORTMAP)

        # tdata counts, tvalid comes up at 2, tlast pulses on 5, tready idles
        self.values = [[i, 1 if i == 5 else 0, 1 if i >= 2 else 0, 0] for i in range(8)]
        self.samples = [pack(v, self.probes) for v in self.values]

    def test_the_capture_round_trips(self):
        _, timeline, _ = parse_vcd(write_to_string(self.samples, 3, self.probes))

        self.assertEqual(len(timeline), 8)

        for (_, state), expected in zip(timeline, self.values):
            self.assertEqual([state[p["name"]] for p in self.probes], expected)

    def test_a_constant_signal_is_written_once(self):
        text = write_to_string(self.samples, 3, self.probes)

        declarations, _, _ = parse_vcd(text)
        ident              = declarations["axis_tready"][1]

        # tready never moves, so it appears in $dumpvars and nowhere else
        self.assertEqual(sum(1 for line in text.splitlines()
                             if line.strip().endswith(ident) and len(line.strip()) == 2), 1)

    def test_a_sample_with_no_change_costs_no_timestep(self):
        # Eight identical samples with the trigger on the last one, so samples
        # 1 to 6 move nothing at all. Only the first, and the last because the
        # trace has to keep its length, earn a #t.
        flat = [pack([0, 0, 0, 0], self.probes)] * 8
        text = write_to_string(flat, 7, self.probes)

        times = [line for line in text.splitlines() if line.startswith("#")]

        self.assertEqual(times, ["#0", "#70000"])

    def test_the_trace_ends_at_the_last_sample(self):
        # Nothing moves after sample 5, but the capture is 8 long and a viewer
        # should show all of it
        text = write_to_string(self.samples, 3, self.probes)
        _, timeline, _ = parse_vcd(text)

        self.assertEqual(timeline[-1][0], 7 * 10000)

    def test_scalars_and_vectors_are_formatted_differently(self):
        text = write_to_string(self.samples, 3, self.probes)
        declarations, _, _ = parse_vcd(text)

        # Only the value changes, the $var lines carry the same characters
        body = text.split("$enddefinitions $end", 1)[1]

        tdata_ident = declarations["axis_tdata"][1]
        tlast_ident = declarations["axis_tlast"][1]

        # a vector is 'b<bits> <id>', a scalar is '<0|1><id>' with no space
        self.assertIn(f"b1 {tdata_ident}", body)
        self.assertIn(f"1{tlast_ident}", body)
        self.assertNotIn(f"1 {tlast_ident}", body)

    def test_a_single_sample_capture(self):
        _, timeline, _ = parse_vcd(write_to_string(self.samples[:1], 0, self.probes))

        self.assertEqual(len(timeline), 1)
        self.assertEqual(timeline[0][0], 0)


class TestVcdTrigger(unittest.TestCase):
    """
    TestVcdTrigger: The synthetic marker. VCD has no notion of a trigger, so it
    is carried as a wire that is high for exactly the sample it fired on.
    """

    def setUp(self):
        self.probes  = vcd.load_portmap(_PORTMAP)
        self.samples = [pack([i, 0, 0, 0], self.probes) for i in range(8)]

    def test_the_marker_pulses_on_the_trigger_sample(self):
        for trig_idx in (0, 1, 4, 7):
            with self.subTest(trig_idx=trig_idx):
                _, timeline, _ = parse_vcd(write_to_string(self.samples, trig_idx, self.probes))

                high = [index for index, (_, state) in enumerate(timeline)
                        if state["trigger"] == 1]

                self.assertEqual(high, [trig_idx])

    def test_the_marker_is_declared_last(self):
        declarations, _, _ = parse_vcd(write_to_string(self.samples, 0, self.probes))

        # Declared after the probes so adding a signal to the portmap does not
        # shift the identifiers of the ones already there
        self.assertEqual(list(declarations)[-1], "trigger")


class TestVcdErrors(unittest.TestCase):
    """
    TestVcdErrors: The inputs that cannot produce a meaningful file.
    """

    def setUp(self):
        self.probes = vcd.load_portmap(_PORTMAP)

    def test_an_empty_capture_is_rejected(self):
        with self.assertRaises(ValueError):
            write_to_string([], 0, self.probes)

    def test_a_trigger_outside_the_capture_is_rejected(self):
        samples = [pack([0, 0, 0, 0], self.probes)] * 4

        for trig_idx in (-1, 4, 100):
            with self.subTest(trig_idx=trig_idx):
                with self.assertRaises(ValueError):
                    write_to_string(samples, trig_idx, self.probes)

    def test_a_core_reporting_no_sampling_clock_is_rejected(self):
        # driver.py checks the probe width and the depth on construction but
        # not the frequency, so a zero can reach here and would divide by zero
        samples = [pack([0, 0, 0, 0], self.probes)]

        for freq in (0, -1):
            with self.subTest(freq=freq):
                with self.assertRaises(ValueError):
                    write_to_string(samples, 0, self.probes, freq)


if __name__ == "__main__":
    unittest.main(verbosity=2)
