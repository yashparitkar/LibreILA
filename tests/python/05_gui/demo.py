#!/usr/bin/env python3
#####################################################################
# File: demo.py
# Author: Y.U.P. (yashparitkar)
# Created: 2026-08-05 Wed 11:58
# Last Modified: 2026-08-05 Wed 11:58
#
# Description: Run the GUI against fake cores
#   The real gui.py, with the wrapper model 00_pkt_format validates standing
#   in for hardware. "make gui" opens it, "make shots" renders it offscreen.
#
# Copyright 2026 Yash Paritkar
# SPDX-License-Identifier: CERN-OHL-P-2.0
#####################################################################

import argparse
import importlib.util
import os
import sys
import tempfile
import types

_HERE      = os.path.dirname(os.path.abspath(__file__))
_REPO_ROOT = os.path.join(_HERE, "..", "..", "..")

sys.path.insert(0, os.path.join(_REPO_ROOT, "drivers", "python"))

_PORTMAP = os.path.join(_REPO_ROOT, "codegen", "portmap.csv")

# A stock build, with a buffer big enough that the readout takes long enough to
# watch the progress bar move
_PROBE_WIDTH = 67
_DEPTH       = 1024
_FREQ_HZ     = 100000000
_STRIDE      = 4

_STATUS         = 0x00
_TRIG_IDX       = 0x18
_FRST_IDX       = 0x1c
_SAMP_BUFF_BASE = 0x50

_STATUS_IDLE = 0x0
_STATUS_DONE = 0x7

_UIDS = [7, 85, 0x0badc0de]


def build_core(pkt, uid, status):
    """
    build_core: One fake core, with something recognisable in its buffer.

    pkt: The loaded 00_pkt_format module.
    uid: The UID it should report.
    status: The STATUS register contents.

    returns: The FakeWrapper.
    """

    wrapper = pkt.FakeWrapper()
    wrapper.mem.update(pkt.identity_regs(_PROBE_WIDTH, _DEPTH, _FREQ_HZ, uid))

    # A counter on tdata with tvalid and tlast moving, so the capture looks
    # like a bus rather than a flat line in the viewer
    for index in range(_DEPTH):
        word = ((index & 0xffff)
                | ((index % 7 != 0) << 65)
                | ((index % 11 == 0) << 64))

        for lane in range(_STRIDE):
            wrapper.mem[_SAMP_BUFF_BASE + (index * _STRIDE + lane) * 4] = \
                    (word >> (32 * lane)) & 0xffffffff

    wrapper.mem[_TRIG_IDX] = _DEPTH // 2
    wrapper.mem[_FRST_IDX] = 0
    wrapper.mem[_STATUS]   = status

    return wrapper


def install_fake_serial(cores):
    """
    install_fake_serial: Point pyserial at the fake cores.

    cores: {port name: FakeWrapper}.

    returns: None

    00_pkt_format's stub already replaced serial.Serial; this keeps one core
    per port so a tab talks to the same registers every time, and adds the
    port enumeration gui.py reads.
    """

    stub = sys.modules["serial"]

    stub.__path__ = []
    stub.Serial   = lambda port, baudrate=115200, timeout=None: cores[port]

    tools      = types.ModuleType("serial.tools")
    list_ports = types.ModuleType("serial.tools.list_ports")

    port_info = type("PortInfo", (), {"__init__": lambda self, device:
                                      setattr(self, "device", device)})

    list_ports.comports = lambda: [port_info(name) for name in cores]
    tools.list_ports    = list_ports
    stub.tools          = tools

    sys.modules["serial.tools"]            = tools
    sys.modules["serial.tools.list_ports"] = list_ports


def take_shots(gui, directory):
    """
    take_shots: Render the window at each step of a capture.

    gui: The imported gui module.
    directory: Where to write the .png files.

    returns: None
    """

    from PySide6.QtCore import Qt
    from PySide6.QtWidgets import QApplication

    app = QApplication.instance() or QApplication([])

    app.setStyle("Fusion")
    app.styleHints().setColorScheme(Qt.ColorScheme.Light)
    app.setPalette(gui.light_palette())

    window = gui.MainWindow("gtkwave", ".", _PORTMAP)
    window.resize(1100, 800)
    window.show()

    os.makedirs(directory, exist_ok=True)

    def shot(name):
        app.processEvents()
        window.grab().save(os.path.join(directory, name))
        print(f"wrote {os.path.join(directory, name)}")

    shot("01-disconnected.png")

    tab = window.tabs.widget(0)
    tab.toggle_connection()
    shot("02-connected.png")

    # Set a trigger the way a person would, through the pane rather than the
    # session, so the shot shows the table doing its job
    tab.condition_rows["axis_tvalid"]["pattern"].setText("1")
    tab.condition_rows["axis_tlast"]["pattern"].setText("X")
    tab.condition_rows["axis_tdata"]["radix"].setCurrentText("hex")
    tab.condition_rows["axis_tdata"]["pattern"].setText("0xXXXXXXXXdead0eef")

    tab.level_edge_combo.setCurrentIndex(1)
    tab.direction_combo.setCurrentIndex(0)
    tab.reduction_combo.setCurrentText("and")
    tab.position_spin.setValue(_DEPTH // 2)

    shot("03-trigger-edited.png")

    tab.apply_trigger()
    tab.read_trigger()
    shot("04-trigger-applied.png")

    tab.ila.ila.write_regs(_STATUS, [0x1])
    tab.poll()
    shot("05-armed.png")

    tab.ila.ila.write_regs(_STATUS, [_STATUS_DONE])
    tab.poll()

    tab.path_edit.setText("demo.vcd")
    tab.save_capture()

    while tab.worker is not None:
        app.processEvents()

    shot("06-captured.png")

    print(f"capture: demo.vcd, {os.path.getsize('demo.vcd')} bytes")


def main():
    parser = argparse.ArgumentParser(description="Run the LibreILA GUI against fake cores.")

    parser.add_argument("--shots", metavar="DIR",
                        help="render the window offscreen into DIR instead of opening it")
    parser.add_argument("--devices", type=int, default=2,
                        help="how many fake cores to put in the store (default: 2)")

    args = parser.parse_args()

    if args.shots:
        os.environ["QT_QPA_PLATFORM"] = "offscreen"

    # Imported for its wrapper model and its pyserial stub, the same way tb.py
    # does, so the demo cannot drift from what the tests check
    spec = importlib.util.spec_from_file_location(
        "pkt_format_tb", os.path.join(_HERE, "..", "00_pkt_format", "tb.py"))
    pkt = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(pkt)

    uids  = _UIDS[:max(1, args.devices)]
    cores = {}

    for index, uid in enumerate(uids):
        # The first one comes up with a finished capture, so there is something
        # to read out without arming anything first
        cores[f"/dev/ttyFAKE{index}"] = build_core(
            pkt, uid, _STATUS_DONE if index == 0 else _STATUS_IDLE)

    install_fake_serial(cores)

    import gui
    import session

    # Its own directory, so the demo never touches a real device store
    work = tempfile.mkdtemp(prefix="libreila-demo-")

    os.chdir(work)

    for port, uid in zip(cores, uids):
        session.save_device(uid, port, 115200)

    print(f"demo store: {work}")

    for port, uid in zip(cores, uids):
        print(f"  ILA{uid} on {port}")

    if args.shots:
        take_shots(gui, os.path.abspath(os.path.join(_HERE, args.shots)))
    else:
        gui.run_gui("gtkwave", ".", _PORTMAP)

    return 0


if __name__ == "__main__":
    sys.exit(main())
