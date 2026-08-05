#!/usr/bin/env python3
#####################################################################
# File: tb.py
# Author: Y.U.P. (yashparitkar)
# Created: 2026-08-05 Wed 11:20
# Last Modified: 2026-08-05 Wed 11:20
#
# Description: GUI test for the python driver
#   Drives drivers/python/gui.py offscreen against the model of the UART
#   wrapper 00_pkt_format validates. Skipped where PySide6's widget packages
#   are absent, since those are a GUI-only dependency.
#
# Copyright 2026 Yash Paritkar
# SPDX-License-Identifier: CERN-OHL-P-2.0
#####################################################################

import importlib.util
import os
import sys
import tempfile
import types
import unittest

_HERE      = os.path.dirname(os.path.abspath(__file__))
_REPO_ROOT = os.path.join(_HERE, "..", "..", "..")

sys.path.insert(0, os.path.join(_REPO_ROOT, "drivers", "python"))

# Before Qt is imported, or it picks the desktop's platform and wants a display
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

# The same model of the wrapper 02_cli and 03_session use, imported rather than
# copied. Loading it also installs the pyserial stub that keeps this off any
# real /dev node.
_pkt_format_spec = importlib.util.spec_from_file_location(
    "pkt_format_tb", os.path.join(_HERE, "..", "00_pkt_format", "tb.py"))
pkt = importlib.util.module_from_spec(_pkt_format_spec)
_pkt_format_spec.loader.exec_module(pkt)

import session
import trigger

# 00_pkt_format's pyserial stub carries only Serial, since that is all driver.py
# needs. gui.py also enumerates ports, so the submodule that lives under goes in
# here rather than there.
_serial_stub          = sys.modules["serial"]
_serial_stub.__path__ = []

_tools      = types.ModuleType("serial.tools")
_list_ports = types.ModuleType("serial.tools.list_ports")

_list_ports.comports = lambda: []
_tools.list_ports    = _list_ports
_serial_stub.tools   = _tools

sys.modules["serial.tools"]            = _tools
sys.modules["serial.tools.list_ports"] = _list_ports

# PySide6 splits into one package per Qt module, so QtCore being present says
# nothing about QtWidgets. make sim-python is documented as needing python3 and
# nothing else, so a machine without the GUI packages skips rather than fails.
try:
    from PySide6.QtCore import QDeadlineTimer, QEventLoop
    from PySide6.QtWidgets import QApplication, QDialog

    HAS_QT = True
    QT_WHY = ""
except ImportError as err:
    HAS_QT = False
    QT_WHY = f"PySide6 widget packages not installed ({err})"

# Outside the guard deliberately. A gui.py that will not import is a failure and
# not a reason to skip, and folding it in with PySide6 would hide exactly that.
if HAS_QT:
    import gui

_PORTMAP     = os.path.join(_REPO_ROOT, "codegen", "portmap.csv")
_PROBE_WIDTH = 67
_DEPTH       = 8
_FREQ_HZ     = 100000000
_UID         = 0x0badc0de

_STRIDE         = 4
_STATUS         = 0x00
_MGCKEY         = 0x04
_TRIG_IDX       = 0x18
_FRST_IDX       = 0x1c
_SAMP_BUFF_BASE = 0x50

_STATUS_IDLE = 0x0
_STATUS_DONE = 0x7  # ARMED | TRIGD | DONE


def staged_wrapper(status=_STATUS_DONE, uid=_UID, depth=_DEPTH, width=_PROBE_WIDTH):
    """
    staged_wrapper: A FakeWrapper a tab can be pointed at.

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
    Port: Counts how many times a tab opened one.

    The GUI holding one port per tab rather than reopening per action is the
    whole reason session.py exists, and a count is the only way to check it.
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


def pump(milliseconds=50):
    """
    pump: Let the event loop run for a while.

    milliseconds: How long to keep serving events.

    returns: None
    """

    deadline = QDeadlineTimer(milliseconds)

    while not deadline.hasExpired():
        QApplication.processEvents(QEventLoop.AllEvents, 10)


@unittest.skipUnless(HAS_QT, QT_WHY)
class GuiTest(unittest.TestCase):
    """
    GuiTest: A base class giving each test an application, an empty device
    store to work in, and a staged core to talk to.
    """

    @classmethod
    def setUpClass(cls):
        # One QApplication for the whole process, Qt allows no more
        cls.app = QApplication.instance() or QApplication([])

    def setUp(self):
        self._origin    = os.getcwd()
        self._directory = tempfile.TemporaryDirectory()

        os.chdir(self._directory.name)

        self.wrapper = staged_wrapper()
        self.port    = Port(self.wrapper)

        self.port.__enter__()

        self.window = None

    def tearDown(self):
        if self.window is not None:
            self.window.close()
            self.window.deleteLater()

        pump(10)

        self.port.__exit__()

        os.chdir(self._origin)
        self._directory.cleanup()

    def open_window(self, viewer="gtkwave"):
        """
        open_window: Build the main window against the current store.

        viewer: The waveform viewer to hand it.

        returns: The window.
        """

        self.window = gui.MainWindow(viewer, ".", _PORTMAP)

        return self.window

    def connected_tab(self):
        """
        connected_tab: One stored device, given a tab and connected.

        parameters: None

        returns: The DeviceTab.
        """

        session.save_device(_UID, "/dev/fake", 115200)

        tab = self.open_window().tabs.widget(0)
        tab.toggle_connection()

        return tab


class TestTabStrip(GuiTest):
    """
    TestTabStrip: The tab strip is built from the device store, which is the
    same store the command line's --add-device writes.
    """

    def test_an_empty_store_opens_with_no_tabs(self):
        self.assertEqual(self.open_window().tabs.count(), 0)

    def test_one_tab_per_stored_device(self):
        for uid in (3, 77, _UID):
            session.save_device(uid, "/dev/fake", 115200)

        window = self.open_window()

        self.assertEqual(window.tabs.count(), 3)
        self.assertEqual([window.tabs.widget(i).uid for i in range(3)], [3, 77, _UID])

    def test_a_tab_starts_disconnected(self):
        session.save_device(_UID, "/dev/fake", 115200)

        window = self.open_window()
        tab    = window.tabs.widget(0)

        # Built disconnected, so no port is opened just by opening the window
        self.assertFalse(tab.ila.is_connected)
        self.assertEqual(self.port.opens, 0)
        self.assertEqual(window.tabs.tabText(0), f"DISCONNECTED ILA{_UID}")

    def test_connecting_flips_the_title(self):
        session.save_device(_UID, "/dev/fake", 115200)

        window = self.open_window()
        tab    = window.tabs.widget(0)

        tab.toggle_connection()

        self.assertTrue(tab.ila.is_connected)
        self.assertEqual(window.tabs.tabText(0), f"CONNECTED ILA{_UID}")

        tab.toggle_connection()

        self.assertFalse(tab.ila.is_connected)
        self.assertEqual(window.tabs.tabText(0), f"DISCONNECTED ILA{_UID}")

    def test_a_mangled_device_file_is_skipped_not_fatal(self):
        # The store is meant to be hand editable, so one bad entry must not
        # stop the window opening
        session.save_device(_UID, "/dev/fake", 115200)

        with open("libreila_device5.txt", "w") as broken:
            broken.write("nonsense\n")

        window = self.open_window()

        self.assertEqual(window.tabs.count(), 1)
        self.assertEqual(window.tabs.widget(0).uid, _UID)

    def test_closing_a_tab_disconnects_but_keeps_the_device(self):
        tab    = self.connected_tab()
        window = self.window

        window.close_tab(0)

        self.assertEqual(window.tabs.count(), 0)
        self.assertTrue(self.wrapper.closed)

        # Closing a tab is not forgetting the core, --reset is what does that
        self.assertEqual(session.list_devices("."), [_UID])

    def test_closing_the_window_puts_every_session_down(self):
        tab = self.connected_tab()

        self.window.close()

        self.assertFalse(tab.ila.is_connected)


class TestOnePortPerTab(GuiTest):
    """
    TestOnePortPerTab: The property the whole design rests on. A window that
    reopened the port per button press would pay for the identity block every
    time and could not hold the port across two actions at all.
    """

    def test_a_whole_session_opens_the_port_once(self):
        tab = self.connected_tab()

        tab.read_trigger()
        tab.poll()
        tab.arm()
        tab.force_trigger()
        tab.poll()

        self.assertEqual(self.port.opens, 1)

    def test_the_identity_block_is_read_once(self):
        tab = self.connected_tab()

        for _ in range(5):
            tab.poll()
            tab.read_trigger()

        identity = [p for p in self.wrapper.packets if p[2] == _MGCKEY]

        self.assertEqual(len(identity), 1)


class TestStatus(GuiTest):
    """
    TestStatus: The status field, and the timer that keeps it honest.
    """

    def test_polling_shows_the_state_the_core_is_in(self):
        tab = self.connected_tab()

        for raw, name in ((_STATUS_IDLE, "IDLE"), (0x1, "ARMED"),
                          (0x3, "TRIGGERED"), (_STATUS_DONE, "DONE")):
            with self.subTest(status=name):
                self.wrapper.mem[_STATUS] = raw

                tab.poll()

                self.assertIn(name, tab.status_label.text())

    def test_the_timer_runs_only_while_connected(self):
        session.save_device(_UID, "/dev/fake", 115200)

        tab = self.open_window().tabs.widget(0)

        self.assertFalse(tab.poll_timer.isActive())

        tab.toggle_connection()
        self.assertTrue(tab.poll_timer.isActive())

        tab.toggle_connection()
        self.assertFalse(tab.poll_timer.isActive())

    def test_an_armed_core_carries_its_elapsed_time(self):
        tab = self.connected_tab()

        self.wrapper.mem[_STATUS] = _STATUS_IDLE
        tab.arm()

        self.wrapper.mem[_STATUS] = 0x1
        tab.poll()

        # armed_for is host side, so the tab that armed it is the one that can
        # show a number
        self.assertRegex(tab.status_label.text(), r"ARMED \(\d+\.\d s\)")

    def test_a_link_that_dies_stops_the_timer(self):
        # Otherwise a pulled cable repeats the same error forever
        tab = self.connected_tab()

        def broken(*_, **__):
            raise OSError("the port went away")

        self.wrapper.write = broken

        tab.poll()

        self.assertFalse(tab.poll_timer.isActive())


class TestControls(GuiTest):
    """
    TestControls: Arm, disarm and force trigger reaching the core, and being
    refused where the core refuses them.
    """

    def test_arming_writes_arm_ft(self):
        tab = self.connected_tab()

        self.wrapper.mem[_STATUS] = _STATUS_IDLE
        self.wrapper.packets.clear()

        tab.arm()

        self.assertIn("w", [kind for kind, _, _ in self.wrapper.packets])

    def test_disarming_an_idle_core_is_reported_not_raised(self):
        tab = self.connected_tab()

        self.wrapper.mem[_STATUS] = _STATUS_IDLE

        # driver.disarm raises RuntimeError here, and the window has to survive
        # it rather than let it reach the event loop
        tab.disarm()

        self.assertIn("no capture to cancel", self.window.statusBar().currentMessage())

    def test_forcing_an_unarmed_core_is_reported_not_raised(self):
        tab = self.connected_tab()

        self.wrapper.mem[_STATUS] = _STATUS_IDLE

        tab.force_trigger()

        self.assertIn("not armed", self.window.statusBar().currentMessage())

    def test_the_controls_are_dead_while_disconnected(self):
        session.save_device(_UID, "/dev/fake", 115200)

        tab = self.open_window().tabs.widget(0)

        for widget in (tab.arm_button, tab.disarm_button, tab.force_button,
                       tab.save_button, tab.read_trigger_button):
            self.assertFalse(widget.isEnabled())

    def test_reading_the_trigger_shows_what_the_core_holds(self):
        tab = self.connected_tab()

        tab.ila.set_trigger(condition=1 << 65, mask=1 << 65, trigger_type="rising",
                            reduction="or")
        tab.ila.set_trigger_position(3)

        tab.read_trigger()

        self.assertEqual(tab.trigger_type, "rising")
        self.assertEqual(tab.reduction_combo.currentText(), "or")
        self.assertEqual(tab.position_spin.value(), 3)

        # Bit 65 is axis_tvalid, so that is the row that carries the 1
        self.assertEqual(tab.condition_rows["axis_tvalid"]["pattern"].text(), "0b1")
        self.assertEqual(tab.condition_rows["axis_tdata"]["pattern"].text(), trigger.ANY)


class TestConditionsTable(GuiTest):
    """
    TestConditionsTable: One row per probe, and the patterns they carry.
    """

    def test_the_table_is_empty_until_a_core_answers(self):
        # Session.probes checks the portmap against the width the core reports,
        # so there is nothing honest to show while disconnected
        session.save_device(_UID, "/dev/fake", 115200)

        tab = self.open_window().tabs.widget(0)

        self.assertEqual(tab.condition_rows, {})

    def test_connecting_builds_a_row_per_probe_in_portmap_order(self):
        tab = self.connected_tab()

        self.assertEqual(list(tab.condition_rows),
                         ["axis_tdata", "axis_tlast", "axis_tvalid", "axis_tready"])

    def test_disconnecting_takes_the_table_down(self):
        tab = self.connected_tab()

        self.assertTrue(tab.condition_rows)

        tab.toggle_connection()

        self.assertEqual(tab.condition_rows, {})

    def test_a_portmap_that_does_not_match_the_core_leaves_the_table_empty(self):
        # Better than rows drawn against the wrong bit boundaries, which would
        # look like a working trigger for something else
        session.save_device(_UID, "/dev/fake", 115200)

        window = gui.MainWindow("gtkwave", ".", _PORTMAP)
        self.window = window

        # A core whose width the stock portmap cannot describe
        self.port.wrapper = staged_wrapper(width=32)

        tab = window.tabs.widget(0)
        tab.toggle_connection()

        self.assertEqual(tab.condition_rows, {})
        self.assertIn("portmap", window.statusBar().currentMessage())

    def test_a_radix_change_rewrites_the_row_and_touches_no_registers(self):
        tab = self.connected_tab()

        row = tab.condition_rows["axis_tdata"]
        row["pattern"].setText("0b1010")

        self.wrapper.packets.clear()

        row["radix"].setCurrentText("hex")

        # "0b1010" names four bits of a 64 bit signal, so the other sixty stay
        # don't cares and the hex form has to say so rather than invent zeros
        self.assertEqual(row["pattern"].text(), "0xXXXXXXXXXXXXXXXa")
        self.assertEqual(self.wrapper.packets, [])

    def test_a_half_typed_pattern_survives_a_radix_change(self):
        # Nothing to convert, so the text is left alone for Apply to complain
        # about rather than being silently mangled
        tab = self.connected_tab()

        row = tab.condition_rows["axis_tdata"]
        row["pattern"].setText("0b12")

        row["radix"].setCurrentText("hex")

        self.assertEqual(row["pattern"].text(), "0b12")


class TestApplyTrigger(GuiTest):
    """
    TestApplyTrigger: The pane reaching the core, as one write.
    """

    def test_apply_writes_every_part_of_the_trigger(self):
        tab = self.connected_tab()

        tab.condition_rows["axis_tvalid"]["pattern"].setText("1")
        tab.condition_rows["axis_tdata"]["radix"].setCurrentText("hex")
        tab.condition_rows["axis_tdata"]["pattern"].setText("0x00000000deadbeef")

        tab.level_edge_combo.setCurrentIndex(1)       # edge
        tab.direction_combo.setCurrentIndex(1)        # falling
        tab.reduction_combo.setCurrentText("or")
        tab.position_spin.setValue(5)

        tab.apply_trigger()

        cfg = tab.ila.get_trigger()

        self.assertEqual(cfg["condition"], (1 << 65) | 0xdeadbeef)
        self.assertEqual(cfg["mask"], (1 << 65) | 0xffffffffffffffff)
        self.assertEqual(cfg["trigger_type"], "falling")
        self.assertEqual(cfg["reduction"], "or")
        self.assertEqual(cfg["position"], 5)

    def test_the_reference_trigger_matches_the_readme(self):
        # axis_tvalid rising is the worked example the driver README gives
        tab = self.connected_tab()

        tab.condition_rows["axis_tvalid"]["pattern"].setText("1")
        tab.level_edge_combo.setCurrentIndex(1)
        tab.direction_combo.setCurrentIndex(0)

        tab.apply_trigger()

        cfg = tab.ila.get_trigger()

        self.assertEqual(cfg["condition"], 0x20000000000000000)
        self.assertEqual(cfg["mask"], 0x20000000000000000)
        self.assertEqual(cfg["trigger_type"], "rising")

    def test_a_bad_pattern_writes_nothing_at_all(self):
        # The whole point of applying as a unit: the core must not end up
        # holding half of what is on screen
        tab = self.connected_tab()

        tab.condition_rows["axis_tlast"]["pattern"].setText("0b11")

        self.wrapper.packets.clear()

        tab.apply_trigger()

        self.assertEqual([p for p in self.wrapper.packets if p[0] == "w"], [])
        self.assertIn("axis_tlast", self.window.statusBar().currentMessage())

    def test_a_bad_pattern_marks_its_own_row_only(self):
        tab = self.connected_tab()

        tab.condition_rows["axis_tlast"]["pattern"].setText("0b11")

        tab.apply_trigger()

        self.assertIn(gui.BAD_PATTERN_COLOUR,
                      tab.condition_rows["axis_tlast"]["pattern"].styleSheet())
        self.assertEqual(tab.condition_rows["axis_tdata"]["pattern"].styleSheet(), "")

    def test_a_row_stops_being_marked_once_it_parses(self):
        tab = self.connected_tab()

        tab.condition_rows["axis_tlast"]["pattern"].setText("0b11")
        tab.apply_trigger()

        tab.condition_rows["axis_tlast"]["pattern"].setText("1")
        tab.apply_trigger()

        self.assertEqual(tab.condition_rows["axis_tlast"]["pattern"].styleSheet(), "")

    def test_an_edit_is_marked_until_it_is_applied(self):
        tab = self.connected_tab()

        self.assertFalse(tab._trigger_edited)

        tab.condition_rows["axis_tvalid"]["pattern"].textEdited.emit("1")

        self.assertTrue(tab._trigger_edited)
        self.assertIn("*", tab.apply_trigger_button.text())

        tab.condition_rows["axis_tvalid"]["pattern"].setText("1")
        tab.apply_trigger()

        self.assertFalse(tab._trigger_edited)
        self.assertNotIn("*", tab.apply_trigger_button.text())

    def test_a_trigger_round_trips_through_the_core(self):
        tab = self.connected_tab()

        tab.condition_rows["axis_tdata"]["radix"].setCurrentText("hex")
        tab.condition_rows["axis_tdata"]["pattern"].setText("0x00000000dead0eef")
        tab.condition_rows["axis_tready"]["pattern"].setText("0")

        tab.apply_trigger()
        tab.read_trigger()

        # Read back in the radix the row was left in
        self.assertEqual(tab.condition_rows["axis_tdata"]["pattern"].text(),
                         "0x00000000dead0eef")
        self.assertEqual(tab.condition_rows["axis_tready"]["pattern"].text(), "0b0")
        self.assertEqual(tab.condition_rows["axis_tlast"]["pattern"].text(), trigger.ANY)

    def test_applying_while_disconnected_is_reported(self):
        session.save_device(_UID, "/dev/fake", 115200)

        tab = self.open_window().tabs.widget(0)

        tab.apply_trigger()

        self.assertIn("not connected", self.window.statusBar().currentMessage())


class TestTriggerControls(GuiTest):
    """
    TestTriggerControls: Trigger type, condition type and trigger position.
    """

    def test_the_three_trigger_types_map_onto_the_two_combos(self):
        tab = self.connected_tab()

        for trigger_type in session.TRIGGER_TYPES:
            with self.subTest(trigger_type=trigger_type):
                tab.set_trigger_type(trigger_type)

                self.assertEqual(tab.trigger_type, trigger_type)

    def test_a_level_trigger_has_no_direction(self):
        # The core does not look at FALLING without EDGE, so the combo says
        # nothing in level mode
        tab = self.connected_tab()

        tab.level_edge_combo.setCurrentIndex(0)
        self.assertFalse(tab.direction_combo.isEnabled())

        tab.level_edge_combo.setCurrentIndex(1)
        self.assertTrue(tab.direction_combo.isEnabled())

    def test_the_position_spin_and_slider_stay_in_step(self):
        tab = self.connected_tab()

        tab.position_spin.setValue(6)
        self.assertEqual(tab.position_slider.value(), 6)

        tab.position_slider.setValue(2)
        self.assertEqual(tab.position_spin.value(), 2)

    def test_the_position_range_comes_from_the_core(self):
        tab = self.connected_tab()

        self.assertEqual(tab.position_spin.maximum(), _DEPTH - 1)
        self.assertEqual(tab.position_slider.maximum(), _DEPTH - 1)

        # Out of range is refused by the widget rather than by the core
        tab.position_spin.setValue(_DEPTH + 100)

        self.assertEqual(tab.position_spin.value(), _DEPTH - 1)

    def test_the_position_range_collapses_when_disconnected(self):
        tab = self.connected_tab()
        tab.toggle_connection()

        self.assertEqual(tab.position_spin.maximum(), 0)

    def test_the_trigger_controls_are_dead_while_disconnected(self):
        session.save_device(_UID, "/dev/fake", 115200)

        tab = self.open_window().tabs.widget(0)

        for widget in (tab.apply_trigger_button, tab.level_edge_combo,
                       tab.reduction_combo, tab.position_spin, tab.position_slider):
            self.assertFalse(widget.isEnabled())


class TestSequencer(GuiTest):
    """
    TestSequencer: Drawn, and disabled, because the core has no sequencer.
    """

    def test_the_sequencer_controls_are_disabled(self):
        # TRIG_CFG defines bits 2:0 and REGISTER_MAP.csv reserves the rest, so
        # there is nothing behind these
        tab = self.connected_tab()

        for widget in tab.sequencer_widgets:
            self.assertFalse(widget.isEnabled())

    def test_the_sequencer_says_why_it_is_disabled(self):
        tab = self.connected_tab()

        for widget in tab.sequencer_widgets:
            self.assertIn("v2.0", widget.toolTip())

    def test_the_quick_jump_covers_three_stages(self):
        tab = self.connected_tab()

        self.assertEqual([button.text() for button in tab.stage_buttons], ["0", "1", "2"])


class TestCapture(GuiTest):
    """
    TestCapture: The readout, which is the one operation long enough to need a
    thread of its own.
    """

    def wait_for_capture(self, tab, timeout_ms=5000):
        """
        wait_for_capture: Serve the event loop until the worker is finished.

        tab: The DeviceTab running it.
        timeout_ms: How long to wait before giving up.

        returns: None
        """

        deadline = QDeadlineTimer(timeout_ms)

        while tab.worker is not None and not deadline.hasExpired():
            QApplication.processEvents(QEventLoop.AllEvents, 10)

        self.assertIsNone(tab.worker, "the capture never finished")

    def test_a_capture_writes_a_vcd_and_fills_the_bar(self):
        tab = self.connected_tab()

        tab.path_edit.setText("capture.vcd")
        tab.save_capture()

        self.wait_for_capture(tab)

        self.assertTrue(os.path.exists("capture.vcd"))
        self.assertEqual(tab.progress.value(), 100)
        self.assertIn("capture.vcd", self.window.statusBar().currentMessage())

    def test_the_poll_timer_is_stopped_for_the_whole_readout(self):
        # A poll overlapping the readout would desync the wrapper, since both
        # are requests on one port and _transact flushes the input buffer
        tab = self.connected_tab()

        self.assertTrue(tab.poll_timer.isActive())

        tab.path_edit.setText("capture.vcd")
        tab.save_capture()

        self.assertFalse(tab.poll_timer.isActive())

        self.wait_for_capture(tab)

        # And picked back up once the worker is done
        self.assertTrue(tab.poll_timer.isActive())

    def test_the_controls_are_dead_while_capturing(self):
        tab = self.connected_tab()

        tab.path_edit.setText("capture.vcd")
        tab.save_capture()

        self.assertFalse(tab.save_button.isEnabled())
        self.assertFalse(tab.arm_button.isEnabled())

        self.wait_for_capture(tab)

        self.assertTrue(tab.save_button.isEnabled())

    def test_a_capture_before_done_is_reported_with_its_remedy(self):
        tab = self.connected_tab()

        self.wrapper.mem[_STATUS] = 0x1  # ARMED

        tab.path_edit.setText("capture.vcd")
        tab.save_capture()

        self.wait_for_capture(tab)

        message = self.window.statusBar().currentMessage()

        # The session states the fact and the GUI names the button, which is
        # the whole point of the reason mechanism
        self.assertIn("not DONE", message)
        self.assertIn("force the trigger", message.lower())
        self.assertFalse(os.path.exists("capture.vcd"))

    def test_capturing_while_disconnected_is_reported(self):
        session.save_device(_UID, "/dev/fake", 115200)

        tab = self.open_window().tabs.widget(0)

        tab.save_capture()

        self.assertIn("not connected", self.window.statusBar().currentMessage())


class TestAddDevice(GuiTest):
    """
    TestAddDevice: The dialog writes the same store --add-device writes.
    """

    def test_adding_a_device_stores_the_uid_the_core_reports(self):
        window = self.open_window()

        dialog = gui.AddDeviceDialog(".", window)
        dialog.port_combo.setCurrentText("/dev/fake")
        dialog.baud_combo.setCurrentText("115200")

        dialog.add()

        self.assertEqual(dialog.result(), QDialog.Accepted)
        self.assertEqual(dialog.uid, _UID)
        self.assertEqual(session.list_devices("."), [_UID])
        self.assertEqual(session.load_device(_UID, "."), ("/dev/fake", 115200))

    def test_the_dialog_lets_go_of_the_port(self):
        # It connects only to read the UID back, and the tab is what holds the
        # port afterwards
        dialog = gui.AddDeviceDialog(".", self.open_window())
        dialog.port_combo.setCurrentText("/dev/fake")

        dialog.add()

        self.assertTrue(self.wrapper.closed)

    def test_a_bad_baud_rate_is_reported_in_the_dialog(self):
        dialog = gui.AddDeviceDialog(".", self.open_window())
        dialog.port_combo.setCurrentText("/dev/fake")
        dialog.baud_combo.setCurrentText("quickly")

        dialog.add()

        self.assertNotEqual(dialog.result(), QDialog.Accepted)
        self.assertIn("baud", dialog.message.text())

    def test_a_core_that_does_not_answer_is_reported_in_the_dialog(self):
        # An empty wrapper answers zero to everything, so the magic key is wrong
        self.port.wrapper = pkt.FakeWrapper()

        dialog = gui.AddDeviceDialog(".", self.open_window())
        dialog.port_combo.setCurrentText("/dev/fake")

        dialog.add()

        self.assertNotEqual(dialog.result(), QDialog.Accepted)
        self.assertIn("magic key", dialog.message.text())
        self.assertEqual(session.list_devices("."), [])


class TestHelpers(GuiTest):
    """
    TestHelpers: The parts of the GUI that are not widgets.
    """

    def test_a_missing_viewer_is_named(self):
        with self.assertRaises(FileNotFoundError) as caught:
            gui.view_waveform("no-such-viewer-here", "anything.vcd")

        self.assertIn("no-such-viewer-here", str(caught.exception))

    def test_a_missing_capture_is_named_before_the_viewer_runs(self):
        with self.assertRaises(FileNotFoundError) as caught:
            gui.view_waveform("sh", "nothing-was-captured.vcd")

        self.assertIn("nothing-was-captured.vcd", str(caught.exception))

    def test_frequencies_read_in_engineering_units(self):
        self.assertEqual(gui.engineering(100000000), "100 MHz")
        self.assertEqual(gui.engineering(50000), "50 kHz")
        self.assertEqual(gui.engineering(2500000000), "2.5 GHz")
        self.assertEqual(gui.engineering(400), "400 Hz")

    def test_a_reason_the_gui_knows_gets_its_own_remedy(self):
        for reason in (session.REASON_NOT_DONE, session.REASON_TIMEOUT):
            with self.subTest(reason=reason):
                err = session.OperationError("something went wrong.", reason)

                self.assertIn("force the trigger", gui.describe(err).lower())

    def test_a_reason_the_gui_has_no_remedy_for_is_passed_through(self):
        err = session.OperationError("not connected to /dev/fake", session.REASON_USAGE)

        self.assertEqual(gui.describe(err), "not connected to /dev/fake")

    def test_no_gui_message_names_a_command_line_flag(self):
        # The mirror of the same rule in 03_session: the session states the
        # fact, and this front end's remedies name buttons, not flags
        for reason, hint in gui._GUI_REASON_HINT.items():
            with self.subTest(reason=reason):
                self.assertNotIn("--", hint)

    def test_the_palette_is_light(self):
        palette = gui.light_palette()

        window = palette.color(gui.QPalette.Window)
        text   = palette.color(gui.QPalette.WindowText)

        # Light means the window is brighter than the text on it, which is the
        # thing a dark desktop theme would otherwise invert
        self.assertGreater(window.lightness(), text.lightness())
        self.assertGreater(window.lightness(), 200)


if __name__ == "__main__":
    print("05_gui: the graphical front end, offscreen")
    unittest.main(verbosity=2)
