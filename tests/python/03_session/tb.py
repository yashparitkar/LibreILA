#!/usr/bin/env python3
#####################################################################
# File: tb.py
# Author: Y.U.P. (yashparitkar)
# Created: 2026-08-05 Wed 00:12
# Last Modified: 2026-08-05 Wed 00:12
#
# Description: Session test for the python driver
#   Covers drivers/python/session.py, the layer both front ends drive.
#   02_cli reaches it through argparse and one connection per invocation,
#   which is the command line's lifetime; what is untested there is the
#   other one, a session held open across many operations the way the GUI
#   holds one per tab. Host side, no GHDL, no generated core, no real port.
#
# Copyright 2026 Yash Paritkar
# SPDX-License-Identifier: CERN-OHL-P-2.0
#####################################################################

import importlib.util
import os
import sys
import tempfile
import unittest

_HERE      = os.path.dirname(os.path.abspath(__file__))
_REPO_ROOT = os.path.join(_HERE, "..", "..", "..")

sys.path.insert(0, os.path.join(_REPO_ROOT, "drivers", "python"))

# The same model of the wrapper 00_pkt_format proves right, imported rather than
# copied for the same reason 02_cli imports it. Loading it also installs the
# pyserial stub, which is what keeps this test off any real /dev node.
_pkt_format_spec = importlib.util.spec_from_file_location(
    "pkt_format_tb", os.path.join(_HERE, "..", "00_pkt_format", "tb.py"))
pkt = importlib.util.module_from_spec(_pkt_format_spec)
_pkt_format_spec.loader.exec_module(pkt)

import session

_PORTMAP     = os.path.join(_REPO_ROOT, "codegen", "portmap.csv")
_PROBE_WIDTH = 67
_DEPTH       = 8
_FREQ_HZ     = 100000000
_UID         = 0x0badc0de

# The register map for a 67 bit probe: 8 output registers, then 4 + 2 * stride
# input ones with stride 4, so the sample buffer starts at (8 + 12) * 4.
_STRIDE         = 4
_STATUS         = 0x00
_MGCKEY         = 0x04
_UID_REG        = 0x14
_TRIG_IDX       = 0x18
_FRST_IDX       = 0x1c
_SAMP_BUFF_BASE = 0x50

_STATUS_IDLE = 0x0
_STATUS_DONE = 0x7  # ARMED | TRIGD | DONE


def staged_wrapper(status=_STATUS_DONE, uid=_UID, depth=_DEPTH, width=_PROBE_WIDTH):
    """
    staged_wrapper: A FakeWrapper a session can be pointed at.

    status: The STATUS register contents.
    uid: The instance identity the core is to report.
    depth: The sample buffer depth the core is to report.
    width: The probe width the core is to report.

    returns: The FakeWrapper.
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


class Port:
    """
    Port: Counts how many times a session opened one.

    The whole reason session.py exists is that the GUI must not open a port per
    action, and a count is the only way to check that rather than assume it.
    """

    def __init__(self, wrapper):
        self.wrapper = wrapper
        self.opens   = 0

    def __enter__(self):
        self._previous = sys.modules["serial"].Serial

        def open_port(port, baudrate=115200, timeout=None):
            self.opens += 1
            return self.wrapper

        sys.modules["serial"].Serial = open_port

        return self

    def __exit__(self, *_):
        sys.modules["serial"].Serial = self._previous


def connected(wrapper, portmap=_PORTMAP, uid=None):
    """
    connected: A session already connected to a staged wrapper.

    wrapper: The FakeWrapper to answer it.
    portmap: The portmap path to give it.
    uid: The UID to expect, or None not to check.

    returns: (session, Port), the Port left open so the caller can count.
    """

    port = Port(wrapper)
    port.__enter__()

    ila = session.Session("/dev/fake", baud=115200, portmap_path=portmap, uid=uid)
    ila.connect()

    return ila, port


class TempCwd(unittest.TestCase):
    """
    TempCwd: A base class that runs each test in its own empty directory.

    The device store is a file per core in the working directory by default, so
    a test that writes one must not leave it behind for the next.
    """

    def setUp(self):
        self._origin    = os.getcwd()
        self._directory = tempfile.TemporaryDirectory()

        os.chdir(self._directory.name)

    def tearDown(self):
        os.chdir(self._origin)
        self._directory.cleanup()


class TestLifetime(unittest.TestCase):
    """
    TestLifetime: A session is built disconnected and connects on demand, which
    is what lets a view exist for a device that is not answering yet.
    """

    def test_a_new_session_is_not_connected(self):
        ila = session.Session("/dev/fake")

        self.assertFalse(ila.is_connected)

    def test_nothing_works_before_connecting(self):
        ila = session.Session("/dev/fake")

        for name, call in (("status", ila.status),
                           ("info", ila.info),
                           ("get_trigger", ila.get_trigger),
                           ("arm", ila.arm),
                           ("disarm", ila.disarm),
                           ("force_trigger", ila.force_trigger)):
            with self.subTest(operation=name):
                with self.assertRaises(session.OperationError) as caught:
                    call()

                self.assertEqual(caught.exception.reason, session.REASON_USAGE)
                self.assertIn("/dev/fake", str(caught.exception))

    def test_connecting_reads_the_identity_block_once(self):
        wrapper = staged_wrapper()

        with Port(wrapper) as port:
            ila = session.Session("/dev/fake")
            ila.connect()

            self.assertTrue(ila.is_connected)
            self.assertEqual(port.opens, 1)

            # MGCKEY, SAMP_CLK_FREQ, WIDTH, DEPTH and UID are five registers in
            # a row, so the whole identity block is one packet
            identity = [p for p in wrapper.packets if p[2] == _MGCKEY]

            self.assertEqual(identity, [("r", 5, _MGCKEY)])

    def test_the_geometry_comes_off_the_core(self):
        wrapper = staged_wrapper()
        ila, port = connected(wrapper)

        try:
            self.assertEqual(ila.uid, _UID)
            self.assertEqual(ila.probe_width, _PROBE_WIDTH)
            self.assertEqual(ila.samp_buff_depth, _DEPTH)
            self.assertEqual(ila.samp_freq_hz, _FREQ_HZ)
            self.assertEqual(ila.n_lanes, 3)
            self.assertEqual(ila.stride_width, _STRIDE)
        finally:
            port.__exit__()

    def test_disconnecting_closes_the_port_and_writes_nothing(self):
        wrapper = staged_wrapper()
        ila, port = connected(wrapper)

        try:
            before = list(wrapper.packets)

            ila.disconnect()

            self.assertFalse(ila.is_connected)
            self.assertTrue(wrapper.closed)

            # A capture left armed has to survive the host letting go of it,
            # which is the whole reason nothing is written on the way out
            self.assertEqual(wrapper.packets, before)
        finally:
            port.__exit__()

    def test_connecting_twice_opens_one_port(self):
        wrapper = staged_wrapper()

        with Port(wrapper) as port:
            ila = session.Session("/dev/fake")
            ila.connect()
            ila.connect()

            self.assertEqual(port.opens, 1)

    def test_disconnecting_twice_is_not_an_error(self):
        wrapper = staged_wrapper()
        ila, port = connected(wrapper)

        try:
            ila.disconnect()
            ila.disconnect()

            self.assertFalse(ila.is_connected)
        finally:
            port.__exit__()

    def test_a_port_answering_as_another_core_is_refused(self):
        # Ports get renumbered between boots, UIDs do not. A session built from
        # the device store therefore checks what answered.
        wrapper = staged_wrapper(uid=0x11111111)

        with Port(wrapper):
            ila = session.Session("/dev/fake", uid=_UID)

            with self.assertRaises(session.OperationError) as caught:
                ila.connect()

            self.assertEqual(caught.exception.reason, session.REASON_DEVICE_NOT_FOUND)
            self.assertFalse(ila.is_connected)

            # And the port it opened to find out is closed again
            self.assertTrue(wrapper.closed)


class TestOnePortManyOperations(unittest.TestCase):
    """
    TestOnePortManyOperations: The property the GUI depends on. Reopening the
    port per action would pay for the identity block every time and could not
    hold the port across two actions at all.
    """

    def test_a_whole_capture_runs_on_one_connection(self):
        wrapper = staged_wrapper(status=_STATUS_IDLE)

        with Port(wrapper) as port:
            ila = session.Session("/dev/fake", portmap_path=_PORTMAP)
            ila.connect()

            ila.set_trigger(condition=1 << 65, mask=1 << 65, trigger_type="rising")
            ila.set_trigger_position(2)
            ila.get_trigger()
            ila.status()
            ila.info()
            ila.arm()

            # The wrapper models the register file, not the state machine, so
            # the finished capture is staged rather than waited for
            wrapper.mem[_STATUS] = _STATUS_DONE

            ila.capture(os.path.join(tempfile.mkdtemp(), "cap.vcd"))
            ila.disconnect()

            self.assertEqual(port.opens, 1)

    def test_the_identity_block_is_not_re_read_per_operation(self):
        wrapper = staged_wrapper()
        ila, port = connected(wrapper)

        try:
            for _ in range(10):
                ila.status()
                ila.get_trigger()

            identity = [p for p in wrapper.packets if p[2] == _MGCKEY]

            self.assertEqual(len(identity), 1)
        finally:
            port.__exit__()

    def test_a_status_poll_is_a_single_packet(self):
        # A front end polls this on a timer to keep a state display honest, so
        # what it costs is worth pinning
        wrapper = staged_wrapper()
        ila, port = connected(wrapper)

        try:
            wrapper.packets.clear()
            ila.status()

            self.assertEqual(wrapper.packets, [("r", 1, _STATUS)])
        finally:
            port.__exit__()


class TestArmedTimer(unittest.TestCase):
    """
    TestArmedTimer: The one piece of state the core does not hold. It reports
    that it is armed, not how long it has been.
    """

    def test_an_unarmed_session_has_no_elapsed_time(self):
        wrapper = staged_wrapper(status=_STATUS_IDLE)
        ila, port = connected(wrapper)

        try:
            self.assertIsNone(ila.armed_for())
        finally:
            port.__exit__()

    def test_arming_starts_the_clock_and_disarming_stops_it(self):
        wrapper = staged_wrapper(status=_STATUS_IDLE)
        ila, port = connected(wrapper)

        try:
            ila.arm()

            elapsed = ila.armed_for()

            self.assertIsNotNone(elapsed)
            self.assertGreaterEqual(elapsed, 0.0)

            wrapper.mem[_STATUS] = 0x1  # ARMED, so there is a capture to cancel
            ila.disarm()

            self.assertIsNone(ila.armed_for())
        finally:
            port.__exit__()

    def test_a_fresh_session_knows_nothing_of_an_already_armed_core(self):
        # Host side state cannot survive the process, and pretending otherwise
        # would put a wrong number on a display rather than no number
        wrapper = staged_wrapper(status=0x1)
        ila, port = connected(wrapper)

        try:
            self.assertEqual(ila.status(), "ARMED")
            self.assertIsNone(ila.armed_for())
        finally:
            port.__exit__()


class TestCaptureProgress(unittest.TestCase):
    """
    TestCaptureProgress: The readout is the one operation that takes seconds
    rather than a packet, so it is the only one that reports on itself.
    """

    def test_progress_runs_up_to_the_word_count(self):
        wrapper = staged_wrapper()
        ila, port = connected(wrapper)

        seen = []

        try:
            ila.capture(os.path.join(tempfile.mkdtemp(), "cap.vcd"),
                        progress=lambda read, total: seen.append((read, total)))
        finally:
            port.__exit__()

        self.assertTrue(seen)

        words = _DEPTH * _STRIDE

        # One total throughout, monotonic, and ending exactly at it, since a
        # progress bar that never fills is worse than none
        self.assertEqual({total for _, total in seen}, {words})
        self.assertEqual([read for read, _ in seen], sorted(read for read, _ in seen))
        self.assertEqual(seen[-1], (words, words))

    def test_a_capture_without_a_callback_still_works(self):
        wrapper = staged_wrapper()
        ila, port = connected(wrapper)

        try:
            result = ila.capture(os.path.join(tempfile.mkdtemp(), "cap.vcd"))
        finally:
            port.__exit__()

        self.assertEqual(result["samples"], _DEPTH)
        self.assertEqual(result["probe_width"], _PROBE_WIDTH)
        self.assertEqual(result["trigger_index"], 3)


class TestReasons(unittest.TestCase):
    """
    TestReasons: What a front end keys its own reporting off. A message is for
    a human and a reason is for the code, so the reason is what is pinned.
    """

    def test_each_refusal_carries_its_reason(self):
        wrapper = staged_wrapper(status=_STATUS_IDLE)
        ila, port = connected(wrapper)

        try:
            cases = (
                ("trigger type",     session.REASON_USAGE,
                 lambda: ila.set_trigger(trigger_type="sideways")),
                ("reduction",        session.REASON_USAGE,
                 lambda: ila.set_trigger(reduction="xor")),
                ("negative value",   session.REASON_USAGE,
                 lambda: ila.set_trigger(condition=-1)),
                ("above the probe",  session.REASON_USAGE,
                 lambda: ila.set_trigger(mask=1 << _PROBE_WIDTH)),
                ("position",         session.REASON_USAGE,
                 lambda: ila.set_trigger_position(_DEPTH)),
                ("not done",         session.REASON_NOT_DONE,
                 lambda: ila.capture("unreachable.vcd")),
            )

            for name, reason, call in cases:
                with self.subTest(case=name):
                    with self.assertRaises(session.OperationError) as caught:
                        call()

                    self.assertEqual(caught.exception.reason, reason)
        finally:
            port.__exit__()

    def test_a_missing_portmap_is_named(self):
        wrapper = staged_wrapper()
        ila, port = connected(wrapper, portmap="/nonexistent/portmap.csv")

        try:
            with self.assertRaises(session.OperationError) as caught:
                ila.probes()

            self.assertEqual(caught.exception.reason, session.REASON_PORTMAP)
            self.assertIn("/nonexistent/portmap.csv", str(caught.exception))
        finally:
            port.__exit__()

    def test_a_portmap_that_does_not_match_the_core_is_refused(self):
        directory = tempfile.mkdtemp()
        path      = os.path.join(directory, "wrong.csv")

        with open(path, "w") as portmap:
            portmap.write("only_signal,32,in\n")

        wrapper = staged_wrapper()
        ila, port = connected(wrapper, portmap=path)

        try:
            with self.assertRaises(session.OperationError) as caught:
                ila.probes()

            self.assertEqual(caught.exception.reason, session.REASON_PORTMAP_MISMATCH)
        finally:
            port.__exit__()

    def test_a_session_with_no_portmap_says_so(self):
        wrapper = staged_wrapper()
        ila, port = connected(wrapper, portmap=None)

        try:
            with self.assertRaises(session.OperationError) as caught:
                ila.probes()

            self.assertEqual(caught.exception.reason, session.REASON_PORTMAP)
        finally:
            port.__exit__()

    def test_the_portmap_is_read_once(self):
        wrapper = staged_wrapper()
        ila, port = connected(wrapper)

        try:
            self.assertIs(ila.probes(), ila.probes())
        finally:
            port.__exit__()

    def test_nothing_is_read_when_the_capture_is_not_done(self):
        # The portmap check and the status check both come before the readout,
        # so a refused capture costs nothing instead of a whole buffer
        wrapper = staged_wrapper(status=0x1)
        ila, port = connected(wrapper)

        try:
            wrapper.packets.clear()

            with self.assertRaises(session.OperationError):
                ila.capture("unreachable.vcd")

            buffer_reads = [p for p in wrapper.packets if p[2] >= _SAMP_BUFF_BASE]

            self.assertEqual(buffer_reads, [])
        finally:
            port.__exit__()

    def test_every_reason_the_session_defines_is_raised_somewhere(self):
        # A reason nothing raises is a case a front end has to handle that
        # cannot happen, which is worse than one that is missing
        with open(os.path.join(_REPO_ROOT, "drivers", "python", "session.py")) as source:
            text = source.read()

        reasons = [name for name in dir(session) if name.startswith("REASON_")]

        self.assertTrue(reasons)

        for name in reasons:
            with self.subTest(reason=name):
                # Compared as a boolean rather than with assertIn, which would
                # print the whole module on a failure
                self.assertTrue(f"{name})" in text,
                                f"{name} is defined but nothing raises it")

    def test_a_refusal_mid_session_never_names_a_flag(self):
        """
        The layering invariant. The session states the fact and stops, because
        the answer to a capture that has not finished is --wait-done on the
        command line and a button in a window, and a message naming either would
        be wrong in the other front end. libre_ila._libre_ila_reason_hint is
        where the flags live.
        """

        wrapper = staged_wrapper(status=0x1)
        ila, port = connected(wrapper)

        refusals = (
            lambda: ila.set_trigger(trigger_type="sideways"),
            lambda: ila.set_trigger(reduction="xor"),
            lambda: ila.set_trigger(condition=-1),
            lambda: ila.set_trigger(mask=1 << _PROBE_WIDTH),
            lambda: ila.set_trigger_position(_DEPTH),
            lambda: ila.capture("unreachable.vcd"),
            lambda: ila.wait_done(0.01),
        )

        try:
            for call in refusals:
                with self.assertRaises(session.OperationError) as caught:
                    call()

                message = str(caught.exception)

                with self.subTest(message=message):
                    self.assertNotIn("--", message)
        finally:
            port.__exit__()


class TestDeviceStore(TempCwd):
    """
    TestDeviceStore: The file per core both front ends read. A device added on
    the command line should come up as a tab, and one added in a tab should be
    reachable with --device, which only holds while there is one store.
    """

    def test_a_device_round_trips(self):
        session.save_device(_UID, "/dev/ttyUSB3", 921600)

        self.assertEqual(session.load_device(_UID), ("/dev/ttyUSB3", 921600))

    def test_the_default_directory_does_not_decorate_the_name(self):
        # The path goes into messages the user reads, and "./libreila_device0.txt"
        # says nothing the bare name does not
        self.assertEqual(session.device_path(0), "libreila_device0.txt")

    def test_a_directory_can_be_given(self):
        directory = tempfile.mkdtemp()

        path = session.save_device(5, "/dev/ttyUSB0", 115200, directory)

        self.assertEqual(path, os.path.join(directory, "libreila_device5.txt"))
        self.assertTrue(os.path.exists(path))
        self.assertEqual(session.load_device(5, directory), ("/dev/ttyUSB0", 115200))

        # And it is not in the working directory, which is the point
        self.assertFalse(os.path.exists("libreila_device5.txt"))

    def test_devices_are_listed_by_uid_ascending(self):
        for uid in (77, 3, 0x0badc0de, 1):
            session.save_device(uid, "/dev/fake", 115200)

        self.assertEqual(session.list_devices(), [1, 3, 77, 0x0badc0de])

    def test_an_empty_store_lists_nothing(self):
        self.assertEqual(session.list_devices(), [])

    def test_listing_ignores_a_file_that_merely_starts_with_the_prefix(self):
        session.save_device(9, "/dev/fake", 115200)

        with open("libreila_devices.txt", "w") as stray:
            stray.write("not a device\n")

        with open("libreila_device_backup.txt", "w") as stray:
            stray.write("not a device either\n")

        self.assertEqual(session.list_devices(), [9])

    def test_reset_leaves_a_file_that_merely_starts_with_the_prefix(self):
        session.save_device(9, "/dev/fake", 115200)

        with open("libreila_devices.txt", "w") as stray:
            stray.write("not a device\n")

        removed = session.remove_devices()

        self.assertEqual(removed, ["libreila_device9.txt"])
        self.assertTrue(os.path.exists("libreila_devices.txt"))

    def test_a_mangled_device_file_is_reported_not_traced(self):
        for contents in ("", "nonsense\n", "/dev/ttyUSB0\n", "/dev/ttyUSB0,fast\n",
                         ",115200\n", "a,b,c\n"):
            with self.subTest(contents=contents.strip()):
                with open("libreila_device1.txt", "w") as device_file:
                    device_file.write(contents)

                with self.assertRaises(session.OperationError) as caught:
                    session.load_device(1)

                self.assertEqual(caught.exception.reason, session.REASON_DEVICE_NOT_FOUND)

    def test_a_missing_device_names_the_file_it_looked_for(self):
        with self.assertRaises(session.OperationError) as caught:
            session.load_device(42)

        self.assertEqual(caught.exception.reason, session.REASON_DEVICE_NOT_FOUND)
        self.assertIn("libreila_device42.txt", str(caught.exception))


class TestTriggerDecode(unittest.TestCase):
    """
    TestTriggerDecode: TRIG_CFG carries two independent things and the front
    ends both need them apart, so the split is here rather than in either.
    """

    def test_every_mode_word_round_trips(self):
        for mode, expected in ((0x0, ("and", "level")),
                               (0x1, ("or",  "level")),
                               (0x2, ("and", "rising")),
                               (0x3, ("or",  "rising")),
                               (0x6, ("and", "falling")),
                               (0x7, ("or",  "falling"))):
            with self.subTest(mode=mode):
                self.assertEqual(session.decode_trigger_mode(mode), expected)

    def test_setting_one_field_keeps_the_other(self):
        wrapper = staged_wrapper(status=_STATUS_IDLE)
        ila, port = connected(wrapper)

        try:
            ila.set_trigger(trigger_type="falling", reduction="or")

            applied = ila.set_trigger(reduction="and")

            self.assertEqual(applied["trigger_type"], "falling")
            self.assertEqual(applied["reduction"], "and")

            # And it says the same thing when read back off the core
            self.assertEqual(ila.get_trigger()["trigger_type"], "falling")
        finally:
            port.__exit__()

    def test_a_wide_condition_survives_the_round_trip(self):
        wrapper = staged_wrapper(status=_STATUS_IDLE)
        ila, port = connected(wrapper)

        try:
            value = (1 << 65) | (1 << 33) | 0xdeadbeef

            ila.set_trigger(condition=value, mask=value)

            read_back = ila.get_trigger()

            self.assertEqual(read_back["condition"], value)
            self.assertEqual(read_back["mask"], value)
        finally:
            port.__exit__()

    def test_the_status_names_each_state(self):
        for raw, name in ((0x0, "IDLE"), (0x1, "ARMED"), (0x3, "TRIGGERED"), (0x7, "DONE")):
            with self.subTest(status=name):
                wrapper = staged_wrapper(status=raw)
                ila, port = connected(wrapper)

                try:
                    self.assertEqual(ila.status(), name)
                    self.assertEqual(ila.info()["status"], name)
                finally:
                    port.__exit__()


if __name__ == "__main__":
    print("03_session: the session layer both front ends drive")
    unittest.main(verbosity=2)
