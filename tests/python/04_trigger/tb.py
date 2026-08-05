#!/usr/bin/env python3
#####################################################################
# File: tb.py
# Author: Y.U.P. (yashparitkar)
# Created: 2026-08-05 Wed 10:14
# Last Modified: 2026-08-05 Wed 10:14
#
# Description: Trigger pattern test
#   Covers drivers/python/trigger.py, the translation between per signal
#   patterns and the flat condition/mask pair the core compares. No Qt and
#   no pyserial, the same way 01_vcd needs neither.
#
# Copyright 2026 Yash Paritkar
# SPDX-License-Identifier: CERN-OHL-P-2.0
#####################################################################

import os
import sys
import unittest

_HERE      = os.path.dirname(os.path.abspath(__file__))
_REPO_ROOT = os.path.join(_HERE, "..", "..", "..")

sys.path.insert(0, os.path.join(_REPO_ROOT, "drivers", "python"))

import trigger
import vcd

_PORTMAP = os.path.join(_REPO_ROOT, "codegen", "portmap.csv")

# The stock AXI4S build: tdata 63:0, tlast 64, tvalid 65, tready 66
_PROBE_WIDTH = 67


def stock_probes():
    """
    stock_probes: The reference portmap, as the drivers read it.

    parameters: None

    returns: The probe list vcd.load_portmap produced.
    """

    return vcd.load_portmap(_PORTMAP)


class TestParsePattern(unittest.TestCase):
    """
    TestParsePattern: One signal's pattern into the two halves of a trigger.
    """

    def test_a_binary_pattern_splits_into_value_and_mask(self):
        # The mockup's own example, 0b00101xxxx00111 on a 15 bit signal
        value, mask = trigger.parse_pattern("0b00101xxxx00111", 15)

        self.assertEqual(value, 0b000101000000111)
        self.assertEqual(mask,  0b011111000011111)

    def test_a_hex_dont_care_covers_four_bits(self):
        # The digit is what carries the don't care, so one X in hex is four
        # bits and one X in binary is one
        value, mask = trigger.parse_pattern("0xdeadXeef", 32)

        self.assertEqual(value, 0xdead0eef)
        self.assertEqual(mask,  0xffff0fff)

    def test_every_dont_care_spelling_is_accepted(self):
        for text in ("XXXX", "xxxx", "----", "xX-x"):
            with self.subTest(pattern=text):
                self.assertEqual(trigger.parse_pattern(text, 4), (0, 0))

    def test_an_empty_pattern_matches_anything(self):
        # An untouched row of the conditions table, which must not narrow the
        # trigger just by being there
        self.assertEqual(trigger.parse_pattern("", 8), (0, 0))
        self.assertEqual(trigger.parse_pattern("   ", 8), (0, 0))

    def test_underscores_group_digits(self):
        self.assertEqual(trigger.parse_pattern("0b0010_1xxx", 8),
                         trigger.parse_pattern("0b00101xxx", 8))

    def test_the_radix_says_what_a_bare_pattern_means(self):
        # The conditions table has a radix per row, so the row is what decides
        self.assertEqual(trigger.parse_pattern("11", 8, "bin"), (0b11, 0b11))
        self.assertEqual(trigger.parse_pattern("11", 8, "hex"), (0x11, 0xff))
        self.assertEqual(trigger.parse_pattern("11", 8, "uint"), (11, 0xff))

    def test_a_prefix_overrides_the_radix(self):
        # Pasting 0xdead into a binary row means hex, not an error
        self.assertEqual(trigger.parse_pattern("0xff", 8, "bin"), (0xff, 0xff))
        self.assertEqual(trigger.parse_pattern("0b11", 8, "hex"), (0b11, 0b11))
        self.assertEqual(trigger.parse_pattern("0d42", 8, "bin"), (42, 0xff))

    def test_int_is_twos_complement_in_the_signals_own_width(self):
        # -1 on a 4 bit signal is the 1111 the core actually compares
        self.assertEqual(trigger.parse_pattern("-1", 4, "int"), (0b1111, 0b1111))
        self.assertEqual(trigger.parse_pattern("-8", 4, "int"), (0b1000, 0b1111))
        self.assertEqual(trigger.parse_pattern("7", 4, "int"),  (0b0111, 0b1111))

    def test_a_number_compares_every_bit(self):
        # uint and int have no digit worth a whole number of bits, so there is
        # nothing an X could name and the whole signal is compared
        for radix in ("uint", "int"):
            with self.subTest(radix=radix):
                _, mask = trigger.parse_pattern("1", 8, radix)

                self.assertEqual(mask, 0xff)


class TestParseRefusals(unittest.TestCase):
    """
    TestParseRefusals: What a pattern is not allowed to say. Every one of these
    is a mistake that would otherwise reach the core as a working trigger for
    something other than what was meant.
    """

    def test_a_pattern_wider_than_its_signal_is_refused(self):
        # Not trimmed: the core compares the padding above the probe, so a
        # pattern that does not fit breaks the trigger rather than being ignored
        with self.assertRaises(ValueError):
            trigger.parse_pattern("0b111", 2)

        with self.assertRaises(ValueError):
            trigger.parse_pattern("0xff", 4)

        with self.assertRaises(ValueError):
            trigger.parse_pattern("256", 8, "uint")

    def test_a_dont_care_in_a_number_is_refused(self):
        for radix in ("uint", "int"):
            with self.subTest(radix=radix):
                with self.assertRaises(ValueError) as caught:
                    trigger.parse_pattern("1X", 8, radix)

                self.assertIn("0b", str(caught.exception))

    def test_a_negative_uint_is_refused(self):
        with self.assertRaises(ValueError) as caught:
            trigger.parse_pattern("-1", 8, "uint")

        self.assertIn("int", str(caught.exception))

    def test_a_signed_value_out_of_range_is_refused(self):
        # 4 signed bits reach -8..7, so both ends are worth pinning
        for text in ("-9", "8"):
            with self.subTest(pattern=text):
                with self.assertRaises(ValueError):
                    trigger.parse_pattern(text, 4, "int")

    def test_a_digit_of_the_wrong_base_is_named(self):
        with self.assertRaises(ValueError) as caught:
            trigger.parse_pattern("0b12", 8)

        self.assertIn("2", str(caught.exception))

    def test_a_prefix_with_no_digits_is_refused(self):
        for text in ("0b", "0x", "0d"):
            with self.subTest(pattern=text):
                with self.assertRaises(ValueError):
                    trigger.parse_pattern(text, 8)

    def test_an_unknown_radix_is_refused(self):
        with self.assertRaises(ValueError):
            trigger.parse_pattern("1", 8, "octal")

    def test_a_zero_width_signal_is_refused(self):
        with self.assertRaises(ValueError):
            trigger.parse_pattern("1", 0)


class TestFormatPattern(unittest.TestCase):
    """
    TestFormatPattern: Writing the core's trigger back out as patterns. The
    rule throughout is that the text has to describe the trigger the core is
    actually holding, even where the chosen radix cannot express it.
    """

    def test_an_unmasked_signal_reads_as_one_x(self):
        # Better than sixty four of them on axis_tdata
        self.assertEqual(trigger.format_pattern(0, 0, 64), trigger.ANY)

    def test_a_fully_masked_signal_reads_in_its_radix(self):
        self.assertEqual(trigger.format_pattern(0xff, 0xff, 8, "hex"), "0xff")
        self.assertEqual(trigger.format_pattern(0xff, 0xff, 8, "uint"), "255")
        self.assertEqual(trigger.format_pattern(0xff, 0xff, 8, "int"), "-1")
        self.assertEqual(trigger.format_pattern(0b1010, 0b1111, 4, "bin"), "0b1010")

    def test_a_partial_mask_falls_back_to_binary(self):
        # uint cannot say "some bits", and printing 42 for a trigger that only
        # compares half of them would describe a trigger the core is not holding
        text = trigger.format_pattern(0b1010, 0b1100, 4, "uint")

        self.assertEqual(text, "0b10XX")

    def test_a_mask_splitting_a_hex_digit_falls_back_to_binary(self):
        # One hex digit spans four bits, so a mask that cuts through one cannot
        # be written in hex at all
        text = trigger.format_pattern(0b1111_1010, 0b1111_1100, 8, "hex")

        self.assertEqual(text, "0b111110XX")

    def test_a_hex_digit_fully_masked_or_fully_free_stays_hex(self):
        self.assertEqual(trigger.format_pattern(0xa0, 0xf0, 8, "hex"), "0xaX")

    def test_an_odd_width_still_gets_a_top_digit(self):
        # The stock probe is 67 bits, so rounding the digit count down would
        # silently drop the top three
        text = trigger.format_pattern(1 << 66, (1 << 67) - 1, 67, "hex")

        value, mask = trigger.parse_pattern(text, 67, "hex")

        self.assertEqual(value, 1 << 66)
        self.assertEqual(mask, (1 << 67) - 1)


class TestRoundTrip(unittest.TestCase):
    """
    TestRoundTrip: format then parse has to land back where it started, since
    the conditions table reads the core, shows it, and writes it back.
    """

    def test_every_radix_round_trips(self):
        cases = (
            ("0b00101xxxx00111", 15, "bin"),
            ("0xdeadXeef",       32, "hex"),
            ("deadbeef",         32, "hex"),
            ("1",                 1, "bin"),
            ("",                  4, "bin"),
            ("42",                8, "uint"),
            ("-3",                8, "int"),
            ("XXXX",              4, "bin"),
        )

        for text, width, radix in cases:
            with self.subTest(pattern=text, radix=radix):
                value, mask = trigger.parse_pattern(text, width, radix)

                formatted = trigger.format_pattern(value, mask, width, radix)

                self.assertEqual(trigger.parse_pattern(formatted, width, radix),
                                 (value, mask))

    def test_every_value_of_a_narrow_signal_round_trips(self):
        # Exhaustive at 4 bits, over every mask as well as every value, which
        # is the only way to catch a digit boundary that is wrong in one case
        for radix in trigger.RADICES:
            for value in range(16):
                for mask in range(16):
                    with self.subTest(radix=radix, value=value, mask=mask):
                        text = trigger.format_pattern(value, mask, 4, radix)

                        # Only the compared bits are recoverable, the rest is
                        # what the don't care threw away
                        back_value, back_mask = trigger.parse_pattern(text, 4, radix)

                        self.assertEqual(back_mask, mask)
                        self.assertEqual(back_value & mask, value & mask)


class TestWholeProbeWord(unittest.TestCase):
    """
    TestWholeProbeWord: Assembling the per signal patterns into the pair
    session.Session.set_trigger takes, against the stock 67 bit AXI4S build.
    """

    def setUp(self):
        self.probes = stock_probes()

    def test_the_reference_trigger_matches_the_readme(self):
        # The README's worked example: axis_tvalid is bit 65, so triggering on
        # it is condition 0x20000000000000000 with the same mask
        condition, mask = trigger.patterns_to_vector({"axis_tvalid": "1"}, self.probes)

        self.assertEqual(condition, 0x20000000000000000)
        self.assertEqual(mask,      0x20000000000000000)

    def test_a_signal_left_out_is_a_dont_care(self):
        # A table only carries the rows someone filled in
        condition, mask = trigger.patterns_to_vector({}, self.probes)

        self.assertEqual(condition, 0)
        self.assertEqual(mask, 0)

    def test_each_signal_lands_at_its_own_offset(self):
        condition, mask = trigger.patterns_to_vector({"axis_tdata":  "0x1",
                                                      "axis_tlast":  "1",
                                                      "axis_tready": "1"},
                                                     self.probes,
                                                     {"axis_tdata": "hex"})

        # "0x1" is one hex digit, so only the low four bits of the 64 bit
        # axis_tdata are compared and the rest of it stays a don't care
        self.assertEqual(condition, (1 << 66) | (1 << 64) | 0x1)
        self.assertEqual(mask,      (1 << 66) | (1 << 64) | 0xf)

    def test_nothing_reaches_above_the_probe_width(self):
        condition, mask = trigger.patterns_to_vector({name: "0" if width == 1 else "0x0"
                                                      for name, width
                                                      in ((p["name"], p["width"])
                                                          for p in self.probes)},
                                                     self.probes,
                                                     {"axis_tdata": "hex"})

        self.assertLess(condition, 1 << _PROBE_WIDTH)
        self.assertLess(mask, 1 << _PROBE_WIDTH)

    def test_an_unknown_signal_is_refused(self):
        with self.assertRaises(ValueError) as caught:
            trigger.patterns_to_vector({"axis_tvlaid": "1"}, self.probes)

        self.assertIn("axis_tvlaid", str(caught.exception))

    def test_a_bad_pattern_names_the_signal_it_is_on(self):
        # Twenty rows and a message saying only "does not fit" would send the
        # user looking through all of them
        with self.assertRaises(ValueError) as caught:
            trigger.patterns_to_vector({"axis_tlast": "0b11"}, self.probes)

        self.assertIn("axis_tlast", str(caught.exception))

    def test_the_whole_word_round_trips_through_the_table(self):
        patterns = {"axis_tdata":  "0x00000000deadbeef",
                    "axis_tlast":  "0b1",
                    "axis_tvalid": "0bX",
                    "axis_tready": "0b0"}

        radices = {"axis_tdata": "hex"}

        condition, mask = trigger.patterns_to_vector(patterns, self.probes, radices)

        self.assertEqual(trigger.vector_to_patterns(condition, mask, self.probes, radices),
                         {"axis_tdata":  "0x00000000deadbeef",
                          "axis_tlast":  "0b1",
                          "axis_tvalid": trigger.ANY,
                          "axis_tready": "0b0"})

    def test_reading_the_core_back_gives_a_row_per_probe(self):
        patterns = trigger.vector_to_patterns(0, 0, self.probes)

        self.assertEqual(sorted(patterns), sorted(p["name"] for p in self.probes))


class TestNoHeavyImports(unittest.TestCase):
    """
    TestNoHeavyImports: The translator is shared, so it has to load on a
    machine with neither the GUI packages nor a serial port.
    """

    def test_the_translator_needs_no_qt_and_no_pyserial(self):
        # Asserted directly rather than by stubbing them, which is stronger:
        # stubbing would pass even if the import were there
        with open(os.path.join(_REPO_ROOT, "drivers", "python", "trigger.py")) as source:
            text = source.read()

        for unwanted in ("PySide6", "import serial", "import driver", "import vcd"):
            with self.subTest(imports=unwanted):
                self.assertNotIn(unwanted, text)


if __name__ == "__main__":
    print("04_trigger: per signal trigger patterns")
    unittest.main(verbosity=2)
