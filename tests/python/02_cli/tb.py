#####################################################################
# File: tb.py
# Author: Y.U.P. (yashparitkar)
# Created: 2026-08-01 Sat 16:05
# Last Modified: 2026-08-01 Sat 16:05
#
# Description: Command line test for the python driver
#   Drives drivers/python/libre_ila.py end to end against the model of
#   the UART wrapper that 00_pkt_format validates. Host side, no GHDL,
#   no generated core and no real port.
#
# Copyright 2026 Yash Paritkar
# SPDX-License-Identifier: CERN-OHL-P-2.0
#####################################################################

import contextlib
import importlib.util
import io
import os
import subprocess
import sys
import tempfile
import unittest

_HERE      = os.path.dirname(os.path.abspath(__file__))
_REPO_ROOT = os.path.join(_HERE, "..", "..", "..")

sys.path.insert(0, os.path.join(_REPO_ROOT, "drivers", "python"))

# FakeWrapper models p_main in hdl/libre_ila_uart.vhdl and 00_pkt_format is
# what proves it right, so it is imported rather than copied: two models of one
# state machine would drift the moment the packet format moved. Loading that
# module also installs its pyserial stub, which is what keeps this test off any
# real /dev node.
_pkt_format_spec = importlib.util.spec_from_file_location(
    "pkt_format_tb", os.path.join(_HERE, "..", "00_pkt_format", "tb.py"))
pkt = importlib.util.module_from_spec(_pkt_format_spec)
_pkt_format_spec.loader.exec_module(pkt)

import libre_ila
import vcd

_PORTMAP     = os.path.join(_REPO_ROOT, "codegen", "portmap.csv")
_PROBE_WIDTH = 67
_DEPTH       = 8
_FREQ_HZ     = 100000000
_UID         = 0x0badc0de

# The register map for a 67 bit probe: 8 output registers, then 4 + 2 * stride
# input ones with stride 4, so the sample buffer starts at (8 + 12) * 4.
_STRIDE          = 4
_STATUS          = 0x00
_TRIG_IDX        = 0x18
_FRST_IDX        = 0x1c
_TRIG_POS        = 0x20
_TRIG_CFG        = 0x28
_TRIG_COND       = 0x30
_TRIG_MASK       = 0x40
_SAMP_BUFF_BASE  = 0x50

_STATUS_DONE = 0x7  # ARMED | TRIGD | DONE

def staged_wrapper(depth=_DEPTH, width=_PROBE_WIDTH, uid=_UID, status=_STATUS_DONE):
    """
    staged_wrapper: A FakeWrapper holding a finished capture.

    depth: The sample buffer depth the core is to report.
    width: The probe width the core is to report.
    uid: The instance identity the core is to report.
    status: The STATUS register contents.

    returns: The FakeWrapper.

    The buffer counts in axis_tdata and brings axis_tvalid up at sample 2, so a
    readout that loses a lane or slices at the wrong offset does not agree with
    it by accident.
    """

    wrapper = pkt.FakeWrapper()
    wrapper.mem.update(pkt.identity_regs(width, depth, _FREQ_HZ, uid))

    for index in range(depth):
        word = index | ((1 if index >= 2 else 0) << 65)

        for lane in range(_STRIDE):
            wrapper.mem[_SAMP_BUFF_BASE + (index * _STRIDE + lane) * 4] = \
                    (word >> (32 * lane)) & 0xffffffff

    wrapper.mem[_TRIG_IDX] = 3
    wrapper.mem[_FRST_IDX] = 0
    wrapper.mem[_STATUS]   = status

    return wrapper

def run_cli(*argv, wrapper=None):
    """
    run_cli: Run one command line against a staged wrapper.

    argv: The command line arguments.
    wrapper: The FakeWrapper to answer, or None for a freshly staged one.

    returns: (status, stdout, stderr)
    """

    pkt._pending_port = wrapper if wrapper is not None else staged_wrapper()

    out = io.StringIO()
    err = io.StringIO()

    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        status = libre_ila.main(list(argv))

    return status, out.getvalue(), err.getvalue()


class TempCwd(unittest.TestCase):
    """
    TempCwd: A base class that runs each test in its own empty directory.

    The device store is a file per core in the working directory, so a test
    that writes one must not leave it behind for the next.
    """

    def setUp(self):
        self._origin    = os.getcwd()
        self._directory = tempfile.TemporaryDirectory()

        os.chdir(self._directory.name)

    def tearDown(self):
        os.chdir(self._origin)
        self._directory.cleanup()

    def add_device(self, uid=_UID, port="/dev/fake", baud=115200):
        """
        add_device: Store a device the way --add-device would.

        uid: The UID the core reports.
        port: The port to record.
        baud: The baud rate to record.

        returns: The path written.
        """

        return libre_ila.save_device(uid, port, baud)


class TestNoImportSideEffects(unittest.TestCase):
    """
    TestNoImportSideEffects: The entry point keeps its .py extension so it can
    be imported and tested, which only pays off if importing it does nothing.
    """

    def test_importing_does_not_parse_argv(self):
        # The sketch called parse_args() at module scope, which would consume
        # this test runner's own argv the moment the module was imported
        self.assertIn("libre_ila", sys.modules)
        self.assertTrue(hasattr(libre_ila, "main"))
        self.assertTrue(hasattr(libre_ila, "build_parser"))

    def test_the_parser_builds_and_covers_every_verb(self):
        parser  = libre_ila.build_parser()
        options = {action.dest for action in parser._actions}

        for verb in ("reset", "add_device", "device", "info", "set_trigger_position",
                     "set_trigger_condition", "set_trigger_mask", "set_trigger_type",
                     "set_trigger_reduction", "get_trigger_configuration", "arm",
                     "force_trigger", "disarm", "wait_done", "read_data", "output",
                     "portmap"):
            with self.subTest(verb=verb):
                self.assertIn(verb, options)


class TestExitStatuses(unittest.TestCase):
    """
    TestExitStatuses: What a shell actually sees. A process status is an
    unsigned byte, so the sketch's -1 and -2 arrived as 255 and 254, which is
    the range reserved for death by signal.
    """

    def test_every_status_survives_a_process_exit(self):
        for name, value in libre_ila._libre_ila_main_status.items():
            with self.subTest(status=name):
                self.assertGreaterEqual(value, 0)
                self.assertLessEqual(value, 125)

                # Round trip it through a real interpreter rather than trusting
                # the range check, because the range is the reason not the rule
                completed = subprocess.run([sys.executable, "-c",
                                            f"import sys; sys.exit({value})"])

                self.assertEqual(completed.returncode, value)

    def test_the_statuses_are_distinct(self):
        values = list(libre_ila._libre_ila_main_status.values())

        self.assertEqual(len(values), len(set(values)))


class TestDeviceStore(TempCwd):
    """
    TestDeviceStore: The file per core that records how to reach it. Selection
    is by the UID the core reports, not by the order devices were added.
    """

    def test_a_device_round_trips(self):
        self.add_device(_UID, "/dev/ttyUSB3", 921600)

        self.assertEqual(libre_ila.load_device(_UID), ("/dev/ttyUSB3", 921600))

    def test_the_file_is_named_for_the_uid(self):
        path = self.add_device(1234)

        self.assertEqual(path, "libreila_device1234.txt")
        self.assertTrue(os.path.exists(path))

    def test_add_device_stores_the_uid_the_core_reports(self):
        status, out, _ = run_cli("--add-device", "--serial-port", "/dev/fake")

        self.assertEqual(status, 0)
        self.assertIn(str(_UID), out)
        self.assertTrue(os.path.exists(f"libreila_device{_UID}.txt"))

    def test_a_device_that_cannot_be_saved_is_not_a_link_error(self):
        # The core answered, so the failure is the filesystem's. Reporting it
        # as a link error would send the user to check the wrong cable.
        os.chmod(os.getcwd(), 0o500)

        try:
            status, _, err = run_cli("--add-device", "--serial-port", "/dev/fake")
        finally:
            os.chmod(os.getcwd(), 0o700)

        self.assertEqual(status, libre_ila._libre_ila_main_status[
            "LIBRE_ILA_MAIN_STATUS_ERROR_ADDING_DEVICE"])
        self.assertIn("/dev/fake", err)

    def test_every_status_the_cli_documents_is_reachable(self):
        # A status nothing returns is a documented behaviour that cannot
        # happen, which is worse than one that is missing
        with open(os.path.join(_REPO_ROOT, "drivers", "python", "libre_ila.py")) as source:
            text = source.read()

        for name in libre_ila._libre_ila_main_status:
            with self.subTest(status=name):
                self.assertIn(f'_libre_ila_main_status["{name}"]', text)

    def test_a_missing_device_is_named_in_the_error(self):
        status, _, err = run_cli("--device", "42", "--info")

        self.assertEqual(status,
                         libre_ila._libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_DEVICE_NOT_FOUND"])
        self.assertIn("42", err)
        self.assertIn("--add-device", err)

    def test_a_mangled_device_file_is_reported_not_traced(self):
        for contents in ("", "nonsense\n", "/dev/ttyUSB0\n", "/dev/ttyUSB0,fast\n",
                         ",115200\n", "a,b,c\n"):
            with self.subTest(contents=contents.strip()):
                with open(f"libreila_device{_UID}.txt", "w") as device_file:
                    device_file.write(contents)

                status, _, err = run_cli("--device", str(_UID), "--info")

                self.assertEqual(status, libre_ila._libre_ila_main_status[
                    "LIBRE_ILA_MAIN_STATUS_DEVICE_NOT_FOUND"])
                self.assertIn(f"libreila_device{_UID}.txt", err)

    def test_reset_removes_stored_devices(self):
        self.add_device(0)
        self.add_device(_UID)

        status, out, _ = run_cli("--reset")

        self.assertEqual(status, 0)
        self.assertFalse(os.path.exists("libreila_device0.txt"))
        self.assertFalse(os.path.exists(f"libreila_device{_UID}.txt"))

    def test_reset_leaves_everything_else_alone(self):
        # --reset takes no argument and matches a pattern, so what it does not
        # match matters as much as what it does
        neighbours = ["notes.txt", "libreila_device.txt", "libreila_deviceX.txt",
                      "libreila_devices.txt", "libreila_device0.txt.bak", "capture.vcd"]

        for name in neighbours:
            with open(name, "w") as neighbour:
                neighbour.write("keep me\n")

        self.add_device(7)

        status, _, _ = run_cli("--reset")

        self.assertEqual(status, 0)
        self.assertFalse(os.path.exists("libreila_device7.txt"))

        for name in neighbours:
            with self.subTest(neighbour=name):
                self.assertTrue(os.path.exists(name))

    def test_reset_on_an_empty_directory_is_not_an_error(self):
        status, out, _ = run_cli("--reset")

        self.assertEqual(status, 0)
        self.assertIn("no stored devices", out)


class TestUsage(TempCwd):
    """
    TestUsage: What happens before a port is ever opened.
    """

    def test_no_verb_prints_help_and_does_not_connect(self):
        status, out, _ = run_cli()

        self.assertEqual(status, libre_ila._libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_USAGE"])
        self.assertIn("--arm", out)

    def test_a_negative_trigger_value_is_refused(self):
        with self.assertRaises(SystemExit):
            run_cli("--set-trigger-condition", "-1")

    def test_trigger_values_accept_every_base(self):
        parser = libre_ila.build_parser()

        for text, expected in (("0x2a", 42), ("0b101010", 42), ("42", 42), ("0o52", 42)):
            with self.subTest(text=text):
                args = parser.parse_args(["--set-trigger-condition", text])

                self.assertEqual(args.set_trigger_condition, expected)

    def test_the_gui_is_reported_as_unavailable(self):
        # gui.py is still a sketch and raises SyntaxError rather than
        # ImportError, so a narrow except would let it escape as a traceback
        status, _, err = run_cli("--gui")

        self.assertEqual(status, libre_ila._libre_ila_main_status[
            "LIBRE_ILA_MAIN_STATUS_GUI_UNAVAILABLE"])
        self.assertIn("--help", err)


class TestInfo(TempCwd):
    """
    TestInfo: Reporting what the core says about itself.
    """

    def test_info_reports_the_geometry_read_back(self):
        self.add_device()

        status, out, _ = run_cli("--device", str(_UID), "--info")

        self.assertEqual(status, 0)
        self.assertIn(str(_PROBE_WIDTH), out)
        self.assertIn(str(_DEPTH), out)
        self.assertIn(str(_FREQ_HZ), out)
        self.assertIn("DONE", out)

    def test_info_needs_no_portmap(self):
        # Nothing about --info depends on the signal names, so a broken or
        # missing portmap must not stop it
        self.add_device()

        status, _, _ = run_cli("--device", str(_UID), "--info",
                               "--portmap", "/nonexistent/portmap.csv")

        self.assertEqual(status, 0)

    def test_the_status_names_each_state(self):
        self.add_device()

        for raw, name in ((0x0, "IDLE"), (0x1, "ARMED"), (0x3, "TRIGGERED"), (0x7, "DONE")):
            with self.subTest(status=name):
                _, out, _ = run_cli("--device", str(_UID), "--info",
                                    wrapper=staged_wrapper(status=raw))

                self.assertIn(name, out)


class TestTriggerRange(TempCwd):
    """
    TestTriggerRange: Values that do not fit the probe.

    The core zero extends each sample to the full register stride before
    comparing it (trig_samp_word <= resize(...) in hdl/libre_ila.vhdl), so a
    mask bit above the probe width is compared against a hardwired zero. In or
    mode that fires the trigger on the first sample, in and mode it stops the
    trigger firing at all. Neither looks like an error, so the CLI refuses it.
    """

    def test_a_value_inside_the_probe_is_accepted(self):
        self.add_device()

        status, _, _ = run_cli("--device", str(_UID),
                               "--set-trigger-mask", hex((1 << _PROBE_WIDTH) - 1))

        self.assertEqual(status, 0)

    def test_a_value_above_the_probe_is_refused(self):
        self.add_device()

        for flag in ("--set-trigger-condition", "--set-trigger-mask"):
            with self.subTest(flag=flag):
                status, _, err = run_cli("--device", str(_UID), flag, hex(1 << _PROBE_WIDTH))

                self.assertEqual(status, libre_ila._libre_ila_main_status[
                    "LIBRE_ILA_MAIN_STATUS_USAGE"])
                self.assertIn(str(_PROBE_WIDTH), err)

    def test_nothing_is_written_when_the_value_is_refused(self):
        self.add_device()

        wrapper = staged_wrapper()

        run_cli("--device", str(_UID), "--set-trigger-mask", hex(1 << _PROBE_WIDTH),
                wrapper=wrapper)

        # The check runs before configure_trigger, so the core keeps whatever
        # it had rather than half a new setup
        self.assertEqual([packet for packet in wrapper.packets if packet[0] == "w"], [])


class TestTriggerMerge(TempCwd):
    """
    TestTriggerMerge: configure_trigger writes the condition, the mask and the
    mode together, so setting one of them has to read the other two back out of
    the core first. This is what makes the register block being readable useful
    rather than merely possible.
    """

    def setUp(self):
        super().setUp()
        self.add_device()

        self.wrapper = staged_wrapper()

        # A trigger the core is already holding
        self.wrapper.mem[_TRIG_COND] = 0xaaaa5555
        self.wrapper.mem[_TRIG_MASK] = 0xffff0000
        self.wrapper.mem[_TRIG_CFG]  = 0x1          # or, level

    def read_back(self):
        """
        read_back: The trigger the wrapper is holding now.

        parameters: None

        returns: (condition, mask, mode)
        """

        return (self.wrapper.mem[_TRIG_COND],
                self.wrapper.mem[_TRIG_MASK],
                self.wrapper.mem[_TRIG_CFG])

    def test_setting_only_the_mask_keeps_the_condition_and_the_mode(self):
        status, _, _ = run_cli("--device", str(_UID), "--set-trigger-mask", "0xff",
                               wrapper=self.wrapper)

        self.assertEqual(status, 0)
        self.assertEqual(self.read_back(), (0xaaaa5555, 0xff, 0x1))

    def test_setting_only_the_type_keeps_the_reduction(self):
        status, _, _ = run_cli("--device", str(_UID), "--set-trigger-type", "rising",
                               wrapper=self.wrapper)

        self.assertEqual(status, 0)

        # or survives, edge is added
        self.assertEqual(self.read_back(), (0xaaaa5555, 0xffff0000, 0x3))

    def test_setting_only_the_reduction_keeps_the_type(self):
        self.wrapper.mem[_TRIG_CFG] = 0x2   # and, rising

        status, _, _ = run_cli("--device", str(_UID), "--set-trigger-reduction", "or",
                               wrapper=self.wrapper)

        self.assertEqual(status, 0)
        self.assertEqual(self.read_back()[2], 0x3)

    def test_each_trigger_type_sets_the_right_bits(self):
        for trigger_type, expected in (("level", 0x0), ("rising", 0x2), ("falling", 0x6)):
            with self.subTest(type=trigger_type):
                wrapper = staged_wrapper()
                wrapper.mem[_TRIG_CFG] = 0x6    # start from falling every time

                run_cli("--device", str(_UID), "--set-trigger-reduction", "and",
                        "--set-trigger-type", trigger_type, wrapper=wrapper)

                self.assertEqual(wrapper.mem[_TRIG_CFG], expected)

    def test_falling_always_carries_the_edge_bit(self):
        # configure_trigger rejects FALLING without EDGE, so the CLI must never
        # be able to ask for one
        wrapper = staged_wrapper()

        status, _, _ = run_cli("--device", str(_UID), "--set-trigger-type", "falling",
                               wrapper=wrapper)

        self.assertEqual(status, 0)
        self.assertEqual(wrapper.mem[_TRIG_CFG] & 0x6, 0x6)

    def test_a_wide_condition_is_split_across_the_stride(self):
        # Bit 65 is axis_tvalid in the stock portmap, so it lands in word 2
        status, _, _ = run_cli("--device", str(_UID),
                               "--set-trigger-condition", hex(1 << 65),
                               "--set-trigger-mask", hex(1 << 65),
                               wrapper=self.wrapper)

        self.assertEqual(status, 0)
        self.assertEqual(self.wrapper.mem[_TRIG_COND + 0], 0)
        self.assertEqual(self.wrapper.mem[_TRIG_COND + 4], 0)
        self.assertEqual(self.wrapper.mem[_TRIG_COND + 8], 0x2)
        self.assertEqual(self.wrapper.mem[_TRIG_COND + 12], 0)

    def test_the_trigger_reads_back_the_way_it_was_written(self):
        run_cli("--device", str(_UID), "--set-trigger-condition", "0x1234",
                "--set-trigger-mask", "0xffff", "--set-trigger-type", "falling",
                "--set-trigger-reduction", "or", wrapper=self.wrapper)

        status, out, _ = run_cli("--device", str(_UID), "--get-trigger-configuration",
                                 wrapper=self.wrapper)

        self.assertEqual(status, 0)
        self.assertIn("0x1234", out)
        self.assertIn("0xffff", out)
        self.assertIn("or", out)
        self.assertIn("falling", out)

    def test_the_trigger_position_is_written(self):
        status, _, _ = run_cli("--device", str(_UID), "--set-trigger-position", "5",
                               wrapper=self.wrapper)

        self.assertEqual(status, 0)
        self.assertEqual(self.wrapper.mem[_TRIG_POS], 5)

    def test_a_trigger_position_outside_the_buffer_is_refused(self):
        status, _, err = run_cli("--device", str(_UID), "--set-trigger-position",
                                 str(_DEPTH), wrapper=self.wrapper)

        self.assertEqual(status, libre_ila._libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_USAGE"])
        self.assertIn(str(_DEPTH), err)


class TestCapture(TempCwd):
    """
    TestCapture: Arming, waiting and reading the buffer out as a VCD.
    """

    def setUp(self):
        super().setUp()
        self.add_device()

    def test_read_data_writes_a_vcd_naming_the_portmap_signals(self):
        status, out, _ = run_cli("--device", str(_UID), "--read-data",
                                 "-o", "cap.vcd", "--portmap", _PORTMAP)

        self.assertEqual(status, 0)
        self.assertTrue(os.path.exists("cap.vcd"))

        with open("cap.vcd") as capture:
            text = capture.read()

        for name in ("axis_tdata", "axis_tlast", "axis_tvalid", "axis_tready", "trigger"):
            with self.subTest(signal=name):
                self.assertIn(name, text)

        self.assertIn("trigger at sample 3", out)

    def test_the_capture_carries_the_staged_samples(self):
        run_cli("--device", str(_UID), "--read-data", "-o", "cap.vcd", "--portmap", _PORTMAP)

        with open("cap.vcd") as capture:
            text = capture.read()

        probes = vcd.load_portmap(_PORTMAP)
        idents = {}

        for line in text.splitlines():
            if line.startswith("$var"):
                fields = line.split()
                idents[fields[4]] = fields[3]

        # axis_tdata counts 0..7 and axis_tvalid comes up at sample 2
        self.assertIn(f"b111 {idents['axis_tdata']}", text)
        self.assertIn(f"1{idents['axis_tvalid']}", text)

    def test_reading_before_done_is_refused(self):
        for raw, name in ((0x0, "IDLE"), (0x1, "ARMED"), (0x3, "TRIGGERED")):
            with self.subTest(status=name):
                status, _, err = run_cli("--device", str(_UID), "--read-data",
                                         "--portmap", _PORTMAP,
                                         wrapper=staged_wrapper(status=raw))

                self.assertEqual(status, libre_ila._libre_ila_main_status[
                    "LIBRE_ILA_MAIN_STATUS_HARDWARE_ERROR"])
                self.assertIn(name, err)
                self.assertIn("--wait-done", err)

    def test_a_portmap_that_does_not_match_the_core_is_refused(self):
        with open("wrong.csv", "w") as portmap:
            portmap.write("only_signal,32,in\n")

        status, _, err = run_cli("--device", str(_UID), "--read-data", "--portmap", "wrong.csv")

        self.assertEqual(status, libre_ila._libre_ila_main_status[
            "LIBRE_ILA_MAIN_STATUS_PROBEMAP_MISMATCH"])
        self.assertIn("32", err)
        self.assertIn(str(_PROBE_WIDTH), err)

    def test_a_missing_portmap_is_named(self):
        status, _, err = run_cli("--device", str(_UID), "--read-data",
                                 "--portmap", "/nonexistent/portmap.csv")

        self.assertEqual(status, libre_ila._libre_ila_main_status[
            "LIBRE_ILA_MAIN_STATUS_PROBEMAP_NOT_FOUND"])
        self.assertIn("/nonexistent/portmap.csv", err)

    def test_nothing_is_read_when_the_portmap_is_wrong(self):
        # The portmap is checked before the readout, so a mismatch costs
        # nothing instead of a whole buffer over the wire
        wrapper = staged_wrapper()

        with open("wrong.csv", "w") as portmap:
            portmap.write("only_signal,32,in\n")

        run_cli("--device", str(_UID), "--read-data", "--portmap", "wrong.csv",
                wrapper=wrapper)

        reads = [packet for packet in wrapper.packets if packet[2] >= _SAMP_BUFF_BASE]

        self.assertEqual(reads, [])

    def test_arming_reports_and_writes_arm_ft(self):
        wrapper = staged_wrapper(status=0x0)

        status, out, _ = run_cli("--device", str(_UID), "--arm", wrapper=wrapper)

        self.assertEqual(status, 0)
        self.assertIn("armed", out)

    def test_arming_an_armed_ila_is_refused(self):
        # A second write to ARM_FT would force a trigger instead
        status, _, err = run_cli("--device", str(_UID), "--arm",
                                 wrapper=staged_wrapper(status=0x1))

        self.assertEqual(status, libre_ila._libre_ila_main_status[
            "LIBRE_ILA_MAIN_STATUS_HARDWARE_ERROR"])
        self.assertIn("already armed", err)

    def test_forcing_a_trigger_on_an_idle_ila_is_refused(self):
        status, _, err = run_cli("--device", str(_UID), "--force-trigger",
                                 wrapper=staged_wrapper(status=0x0))

        self.assertEqual(status, libre_ila._libre_ila_main_status[
            "LIBRE_ILA_MAIN_STATUS_HARDWARE_ERROR"])
        self.assertIn("not armed", err)

    def test_disarming_reports_and_writes_disarm(self):
        wrapper = staged_wrapper(status=0x1)

        status, out, _ = run_cli("--device", str(_UID), "--disarm", wrapper=wrapper)

        self.assertEqual(status, 0)
        self.assertIn("disarmed", out)

    def test_disarming_an_idle_ila_is_refused(self):
        status, _, err = run_cli("--device", str(_UID), "--disarm",
                                 wrapper=staged_wrapper(status=0x0))

        self.assertEqual(status, libre_ila._libre_ila_main_status[
            "LIBRE_ILA_MAIN_STATUS_HARDWARE_ERROR"])
        self.assertIn("no capture to cancel", err)

    def test_wait_done_returns_at_once_when_already_done(self):
        status, out, _ = run_cli("--device", str(_UID), "--wait-done", "0.1")

        self.assertEqual(status, 0)
        self.assertIn("capture complete", out)

    def test_wait_done_times_out_with_the_state_it_is_stuck_in(self):
        status, _, err = run_cli("--device", str(_UID), "--wait-done", "0.05",
                                 wrapper=staged_wrapper(status=0x1))

        self.assertEqual(status, libre_ila._libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_TIMEOUT"])
        self.assertIn("ARMED", err)
        self.assertIn("--force-trigger", err)


class TestExecutionOrder(TempCwd):
    """
    TestExecutionOrder: The flags are verbs and run in one fixed order whatever
    order they are given in, so a whole capture is one invocation.
    """

    def setUp(self):
        super().setUp()
        self.add_device()

    def test_a_whole_capture_in_one_invocation(self):
        wrapper = staged_wrapper()

        status, out, _ = run_cli("--device", str(_UID),
                                 "--read-data", "-o", "cap.vcd",
                                 "--wait-done", "0.1",
                                 "--set-trigger-condition", hex(1 << 65),
                                 "--set-trigger-mask", hex(1 << 65),
                                 "--set-trigger-type", "rising",
                                 "--portmap", _PORTMAP,
                                 wrapper=wrapper)

        self.assertEqual(status, 0)

        # Given back to front on the command line, still applied in order:
        # the trigger was configured, the wait completed and the file exists
        self.assertEqual(wrapper.mem[_TRIG_COND + 8], 0x2)
        self.assertIn("capture complete", out)
        self.assertTrue(os.path.exists("cap.vcd"))

    def test_the_configuration_is_read_back_after_it_is_written(self):
        wrapper = staged_wrapper()

        status, out, _ = run_cli("--device", str(_UID),
                                 "--get-trigger-configuration",
                                 "--set-trigger-mask", "0x1234",
                                 wrapper=wrapper)

        self.assertEqual(status, 0)

        # --get-trigger-configuration runs after the writes, so it reports what
        # was just asked for rather than what was there before
        self.assertIn("0x1234", out)


if __name__ == "__main__":
    unittest.main(verbosity=2)
