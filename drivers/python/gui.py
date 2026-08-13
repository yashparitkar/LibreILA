#####################################################################
# File: gui.py
# Author: Y.U.P. (yashparitkar)
# Created: 2026-07-24 Fri 19:49
# Last Modified: 2026-08-05 Wed 16:42
#
# Description: ILA graphical interface
#   One tab per device, each owning a session.Session for as long as the tab
#   lives. Everything goes through session.py, so this file is only widgets,
#   the event loop, and the one-thread-per-session rule the serial link imposes.
#
#   The GUI is implemented using PySide6.
#
# Copyright 2026 Yash Paritkar
# SPDX-License-Identifier: CERN-OHL-P-2.0
#####################################################################

import os
import shutil
import subprocess

from serial.tools import list_ports

from PySide6.QtCore import Qt, QThread, QTimer, Signal
from PySide6.QtGui import QColor, QFont, QPalette
from PySide6.QtWidgets import (QApplication, QComboBox, QDialog, QDialogButtonBox,
                               QFormLayout, QGroupBox, QHBoxLayout, QLabel, QLineEdit,
                               QMainWindow, QProgressBar, QPushButton, QScrollArea,
                               QSlider, QSpinBox, QTabWidget, QVBoxLayout, QWidget)

import driver
import session
import trigger

# One packet per poll, so ARMED -> TRIGGERED -> DONE is seen, not inferred.
POLL_INTERVAL_MS = 250

# Qt's own Fusion light values, set explicitly rather than left to the desktop,
# so a dark system theme does not repaint the window half way.
_LIGHT_COLOURS = {
    QPalette.Window          : "#efefef",
    QPalette.WindowText      : "#000000",
    QPalette.Base            : "#ffffff",
    QPalette.AlternateBase   : "#f7f7f7",
    QPalette.ToolTipBase     : "#ffffdc",
    QPalette.ToolTipText     : "#000000",
    QPalette.Text            : "#000000",
    QPalette.Button          : "#efefef",
    QPalette.ButtonText      : "#000000",
    QPalette.BrightText      : "#ff0000",
    QPalette.Link            : "#0000ff",
    QPalette.Highlight       : "#308cc6",
    QPalette.HighlightedText : "#ffffff"
}

_DISABLED_COLOURS = {
    QPalette.WindowText : "#787878",
    QPalette.Text       : "#787878",
    QPalette.ButtonText : "#787878"
}

# The one place colour carries meaning rather than decoration, so it is kept to
# the status field and picked to read on the light background above.
STATUS_COLOURS = {
    "IDLE"      : "#5c5c5c",
    "ARMED"     : "#b8860b",
    "TRIGGERED" : "#1a6fb0",
    "DONE"      : "#2e7d32"
}

# The other two places colour means something: a pattern the core would refuse,
# and whether the connect button is about to open or close the port.
BAD_PATTERN_COLOUR = "#c62828"
CONNECT_COLOUR     = "#1a6fb0"
DISCONNECT_COLOUR  = "#c62828"

BAUD_RATES = [9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600]

DEFAULT_CAPTURE = os.path.join(driver.DEFAULT_OUTPUT_DIR, "libre_ila.vcd")

# What to do about a refusal, in this front end's words. session.py states the
# fact and stops, because the answer is a flag on the command line and a button
# here. libre_ila._libre_ila_reason_hint is the other half of this.
_GUI_REASON_HINT = {
    session.REASON_NOT_DONE : "Arm the ILA, or force the trigger if it is armed and the "
                              "condition has not come up.",
    session.REASON_TIMEOUT  : "Force the trigger to end the wait.",
    session.REASON_PORTMAP  : "Point the GUI at the portmap.csv the core was generated from."
}


# Helpers ###########################################################
def view_waveform(viewer, path):
    """
    view_waveform: Open a capture in the user's waveform viewer.

    viewer: The viewer command, e.g. "gtkwave".
    path: The .vcd to open.

    returns: None
    """

    if shutil.which(viewer) is None:
        raise FileNotFoundError(f"{viewer} is not on the PATH")

    if not os.path.exists(path):
        raise FileNotFoundError(f"{path} does not exist yet, capture something first")

    # Not tracked and not waited on, the viewer outlives whatever happens here
    # next. A list rather than a string, so a path with a space in it works.
    subprocess.Popen([viewer, path])


def describe(err):
    """
    describe: An OperationError as a line for the user.

    err: The session.OperationError.

    returns: The message, with this front end's remedy where there is one.
    """

    hint = _GUI_REASON_HINT.get(err.reason)

    return f"{err} {hint}" if hint else str(err)


def engineering(hz):
    """
    engineering: A frequency in engineering units.

    hz: The frequency in Hz.

    returns: The frequency as a string, e.g. "100 MHz".
    """

    for limit, suffix in ((1e9, "GHz"), (1e6, "MHz"), (1e3, "kHz")):
        if hz >= limit:
            return f"{hz / limit:g} {suffix}"

    return f"{hz} Hz"


def light_palette():
    """
    light_palette: Qt's Fusion light palette, built explicitly.

    parameters: None

    returns: The QPalette.
    """

    palette = QPalette()

    for role, colour in _LIGHT_COLOURS.items():
        palette.setColor(role, QColor(colour))

    for role, colour in _DISABLED_COLOURS.items():
        palette.setColor(QPalette.Disabled, role, QColor(colour))

    return palette


def available_ports(extra=None):
    """
    available_ports: The serial ports pyserial can see.

    extra: A port to include even if it is absent, so a stored device keeps its
        own port in the list.

    returns: The port names, ascending.
    """

    ports = {port.device for port in list_ports.comports()}

    if extra:
        ports.add(extra)

    return sorted(ports)


# Capture worker ####################################################
class CaptureWorker(QThread):
    """
    CaptureWorker: The readout, off the thread that serves the event loop.

    A full buffer is seconds on the link. While this runs nothing else may
    touch the session, so the tab stops its poll timer for the duration.
    """

    progressed = Signal(int, int)
    captured   = Signal(dict)
    failed     = Signal(str)

    def __init__(self, ila, path, parent=None):
        super().__init__(parent)

        self.ila  = ila
        self.path = path

    def run(self):
        try:
            self.captured.emit(self.ila.capture(self.path, progress=self.progressed.emit))
        except session.OperationError as err:
            self.failed.emit(describe(err))
        except (RuntimeError, ValueError, OSError, TimeoutError) as err:
            self.failed.emit(str(err))


# Device tab ########################################################
class DeviceTab(QWidget):
    """
    DeviceTab: One device, and the one session that reaches it.

    Built disconnected, which is what a DISCONNECTED tab is and why
    session.Session does not open a port in its constructor.
    """

    title_changed = Signal()

    def __init__(self, uid, serial_port, baud, portmap, waveform_viewer, parent=None, debug=False):
        super().__init__(parent)

        self.uid             = uid
        self.portmap         = portmap
        self.waveform_viewer = waveform_viewer
        self.worker          = None

        # Set before _build, since building the pane wires up signals that
        # call mark_edited as soon as a default lands in a widget
        self._trigger_edited = False

        self.ila = session.Session(serial_port, baud=baud, portmap_path=portmap, uid=uid,
                                   debug=debug)

        self._build()

        self.poll_timer = QTimer(self)
        self.poll_timer.setInterval(POLL_INTERVAL_MS)
        self.poll_timer.timeout.connect(self.poll)

        self.refresh()

    # Layout ########################################################
    def _build(self):
        """
        _build: Lay the tab out.

        parameters: None

        returns: None
        """

        layout = QHBoxLayout(self)

        layout.addWidget(self._trigger_pane(), stretch=3)
        layout.addWidget(self._right_rail(), stretch=1)

    def _trigger_pane(self):
        """
        _trigger_pane: The trigger half of the tab.

        parameters: None

        returns: The widget.
        """

        box    = QGroupBox("Trigger")
        layout = QVBoxLayout(box)

        layout.addLayout(self._trigger_type_row())
        layout.addLayout(self._trigger_position_row())
        layout.addLayout(self._sequence_stage_row())
        layout.addWidget(self._conditions_box(), stretch=1)
        layout.addLayout(self._trigger_buttons())

        return box

    def _trigger_type_row(self):
        """
        _trigger_type_row: Level or edge, and which edge.

        parameters: None

        returns: The layout.
        """

        # Two controls for the three states set_trigger takes, because that is
        # what TRIG_CFG is: EDGE decides whether FALLING means anything at all,
        # which the register map spells "read only when EDGE is 1".
        self.level_edge_combo = QComboBox()
        self.level_edge_combo.addItems(["level ⎍", "edge _/⎺"])
        self.level_edge_combo.currentIndexChanged.connect(self._on_level_edge_changed)

        self.direction_combo = QComboBox()
        self.direction_combo.addItems(["rising  ↑", "falling  ↓"])
        self.direction_combo.currentIndexChanged.connect(self.mark_edited)

        row = QHBoxLayout()
        row.addWidget(QLabel("Trigger type"))
        row.addWidget(self.level_edge_combo)
        row.addWidget(self.direction_combo)
        row.addStretch()

        return row

    def _trigger_position_row(self):
        """
        _trigger_position_row: Where the trigger sits in the buffer.

        parameters: None

        returns: The layout.
        """

        # Ranged 0..0 until a core says how deep its buffer is
        self.position_spin = QSpinBox()
        self.position_spin.setRange(0, 0)

        self.position_slider = QSlider(Qt.Horizontal)
        self.position_slider.setRange(0, 0)

        # Each drives the other, so whichever is easier to reach is the one to
        # use. The guard stops the two signals bouncing off each other.
        self.position_spin.valueChanged.connect(self._on_position_spun)
        self.position_slider.valueChanged.connect(self._on_position_slid)

        self._position_syncing = False

        row = QHBoxLayout()
        row.addWidget(QLabel("Trigger position"))
        row.addWidget(self.position_spin)
        row.addWidget(self.position_slider, stretch=1)
        row.addWidget(QLabel("samples"))

        return row

    def _sequence_stage_row(self):
        """
        _sequence_stage_row: The sequencer, which this core does not have.

        parameters: None

        returns: The layout.

        Drawn and disabled rather than left out, so the gap stays visible.
        There are no sequencer registers at all: TRIG_CFG defines bits 2:0 and
        REGISTER_MAP.csv reserves the rest.
        """

        why = "the sequencer needs core v2.0+, this build has no sequencer registers"

        self.stage_spin = QSpinBox()
        self.stage_spin.setRange(0, 0)

        self.stage_buttons = [QPushButton(str(stage)) for stage in range(3)]

        row = QHBoxLayout()
        row.addWidget(QLabel("Sequence stage"))
        row.addWidget(self.stage_spin)
        row.addWidget(QLabel("Quick jump"))

        for button in self.stage_buttons:
            button.setMaximumWidth(40)
            row.addWidget(button)

        row.addStretch()

        self.sequencer_widgets = [self.stage_spin] + self.stage_buttons

        for widget in self.sequencer_widgets:
            widget.setEnabled(False)
            widget.setToolTip(why)

        return row

    def _conditions_box(self):
        """
        _conditions_box: One row per probe, in portmap order.

        parameters: None

        returns: The widget.
        """

        box    = QGroupBox("Conditions")
        layout = QVBoxLayout(box)

        self.reduction_combo = QComboBox()
        self.reduction_combo.addItems(session.REDUCTIONS)
        self.reduction_combo.currentIndexChanged.connect(self.mark_edited)

        header = QHBoxLayout()
        header.addWidget(QLabel("X is a don't care, order is the portmap's"))
        header.addStretch()
        header.addWidget(QLabel("Condition type"))
        header.addWidget(self.reduction_combo)

        # Scrollable, since a portmap can list far more signals than fit
        self.rows_widget = QWidget()
        self.rows_layout = QVBoxLayout(self.rows_widget)
        self.rows_layout.setAlignment(Qt.AlignTop)

        self.conditions_scroll = QScrollArea()
        self.conditions_scroll.setWidgetResizable(True)
        self.conditions_scroll.setWidget(self.rows_widget)

        self.conditions_hint = QLabel("connect to read the portmap")

        layout.addLayout(header)
        layout.addWidget(self.conditions_hint)
        layout.addWidget(self.conditions_scroll, stretch=1)

        # {name: (radix combo, pattern field)}, rebuilt whenever a core answers
        self.condition_rows = {}

        return box

    def _trigger_buttons(self):
        """
        _trigger_buttons: Read the trigger back, or write the pane to the core.

        parameters: None

        returns: The layout.
        """

        self.read_trigger_button = QPushButton("Read trigger from core")
        self.read_trigger_button.clicked.connect(self.read_trigger)

        self.apply_trigger_button = QPushButton("Apply trigger to core")
        self.apply_trigger_button.clicked.connect(self.apply_trigger)

        row = QHBoxLayout()
        row.addWidget(self.read_trigger_button)
        row.addWidget(self.apply_trigger_button)

        return row

    def _right_rail(self):
        """
        _right_rail: The serial, information, status and capture boxes.

        parameters: None

        returns: The widget.
        """

        rail   = QWidget()
        layout = QVBoxLayout(rail)

        layout.addWidget(self._serial_box())
        layout.addWidget(self._info_box())
        layout.addWidget(self._status_box())
        layout.addWidget(self._capture_box())
        layout.addStretch()

        return rail

    def _serial_box(self):
        box    = QGroupBox("Serial status")
        layout = QVBoxLayout(box)

        self.port_combo = QComboBox()
        self.port_combo.setEditable(True)
        self.port_combo.addItems(available_ports(self.ila.serial_port))
        self.port_combo.setCurrentText(self.ila.serial_port)

        self.baud_combo = QComboBox()
        self.baud_combo.setEditable(True)
        self.baud_combo.addItems([str(baud) for baud in BAUD_RATES])
        self.baud_combo.setCurrentText(str(self.ila.baud))

        self.link_label = QLabel("disconnected")

        self.connect_button = QPushButton("Connect")
        self.connect_button.clicked.connect(self.toggle_connection)

        layout.addWidget(self.port_combo)
        layout.addWidget(self.baud_combo)
        layout.addWidget(self.link_label)
        layout.addWidget(self.connect_button)

        return box

    def _info_box(self):
        box    = QGroupBox("ILA information")
        layout = QFormLayout(box)

        self.uid_label   = QLabel(str(self.uid))
        self.width_label = QLabel("-")
        self.depth_label = QLabel("-")
        self.freq_label  = QLabel("-")

        layout.addRow("ILA UID", self.uid_label)
        layout.addRow("Probe width", self.width_label)
        layout.addRow("Sampling buffer depth", self.depth_label)
        layout.addRow("Sampling frequency", self.freq_label)

        return box

    def _status_box(self):
        box    = QGroupBox("ILA status")
        layout = QVBoxLayout(box)

        self.status_label = QLabel("-")
        self.status_label.setAlignment(Qt.AlignCenter)

        self.arm_button    = QPushButton("Arm")
        self.disarm_button = QPushButton("Disarm")
        self.force_button  = QPushButton("Force trigger")

        self.arm_button.clicked.connect(self.arm)
        self.disarm_button.clicked.connect(self.disarm)
        self.force_button.clicked.connect(self.force_trigger)

        buttons = QHBoxLayout()
        buttons.addWidget(self.arm_button)
        buttons.addWidget(self.disarm_button)
        buttons.addWidget(self.force_button)

        layout.addWidget(self.status_label)
        layout.addLayout(buttons)

        return box

    def _capture_box(self):
        box    = QGroupBox("Capture")
        layout = QVBoxLayout(box)

        self.format_combo = QComboBox()
        self.format_combo.addItem("vcd")

        self.path_edit = QLineEdit(DEFAULT_CAPTURE)

        self.save_button = QPushButton("Save")
        self.save_button.clicked.connect(self.save_capture)

        self.progress = QProgressBar()
        self.progress.setRange(0, 100)
        self.progress.setValue(0)

        self.view_button = QPushButton("Open with gtkwave")
        self.view_button.clicked.connect(self.open_waveform)

        top = QHBoxLayout()
        top.addWidget(self.format_combo)
        top.addWidget(self.save_button)

        layout.addLayout(top)
        layout.addWidget(self.path_edit)
        layout.addWidget(self.progress)
        layout.addWidget(self.view_button)

        return box

    # Connection ####################################################
    @property
    def title(self):
        """
        title: What the tab strip calls this device.

        parameters: None

        returns: The title, e.g. "CONNECTED ILA7".
        """

        return f"{'CONNECTED' if self.ila.is_connected else 'DISCONNECTED'} ILA{self.uid}"

    def toggle_connection(self):
        """
        toggle_connection: Open the port, or let go of it.

        parameters: None

        returns: None
        """

        if self.ila.is_connected:
            self.stop()
            self.ila.disconnect()

            # The rows describe a portmap checked against a core that is no
            # longer answering, so they go rather than sit there looking valid
            self.clear_conditions()
        else:
            # Whatever the boxes say now, the user may have picked another port
            self.ila.serial_port = self.port_combo.currentText().strip()

            try:
                self.ila.baud = int(self.baud_combo.currentText())
            except ValueError:
                self.report(f"'{self.baud_combo.currentText()}' is not a baud rate")
                return

            if not self.guard(self.ila.connect):
                return

            self.refresh()

            # Needs the connection, since Session.probes checks the portmap
            # against the width the core reports
            if self.build_conditions():
                self.read_trigger()

        self.refresh()
        self.title_changed.emit()

    def stop(self):
        """
        stop: Put the tab down, waiting for a capture still running.

        parameters: None

        returns: None
        """

        self.poll_timer.stop()

        if self.worker is not None:
            self.worker.wait()
            self.worker = None

    # Operations ####################################################
    def guard(self, call):
        """
        guard: Run one session operation, reporting whatever it refuses.

        call: The bound method to run.

        returns: True if it went through.
        """

        # The poll would otherwise land a status read between this operation's
        # request and its reply, and the wrapper cannot tell the two apart
        was_polling = self.poll_timer.isActive()
        self.poll_timer.stop()

        try:
            call()
        except session.OperationError as err:
            self.report(describe(err))
            return False
        except (RuntimeError, ValueError, OSError, TimeoutError) as err:
            # The driver already names the port in these
            self.report(str(err))
            return False
        finally:
            if was_polling:
                self.poll_timer.start()

        return True

    def arm(self):
        if self.guard(self.ila.arm):
            self.refresh()

    def disarm(self):
        if self.guard(self.ila.disarm):
            self.refresh()

    def force_trigger(self):
        if self.guard(self.ila.force_trigger):
            self.refresh()

    # The trigger pane ##############################################
    def _on_level_edge_changed(self, _index=0):
        """
        _on_level_edge_changed: Follow the level/edge toggle.

        parameters: None

        returns: None
        """

        # A level trigger has no direction, and the core does not look at
        # FALLING without EDGE, so the combo says nothing in level mode
        self.direction_combo.setEnabled(self.level_edge_combo.currentIndex() == 1)

        self.mark_edited()

    def _on_position_spun(self, value):
        if self._position_syncing:
            return

        self._position_syncing = True
        self.position_slider.setValue(value)
        self._position_syncing = False

        self.mark_edited()

    def _on_position_slid(self, value):
        if self._position_syncing:
            return

        self._position_syncing = True
        self.position_spin.setValue(value)
        self._position_syncing = False

        self.mark_edited()

    @property
    def trigger_type(self):
        """
        trigger_type: The pane's trigger type, as set_trigger spells it.

        parameters: None

        returns: "level", "rising" or "falling".
        """

        if self.level_edge_combo.currentIndex() == 0:
            return "level"

        return "rising" if self.direction_combo.currentIndex() == 0 else "falling"

    def set_trigger_type(self, trigger_type):
        """
        set_trigger_type: Put the pane into one of the three states.

        trigger_type: "level", "rising" or "falling".

        returns: None
        """

        self.level_edge_combo.setCurrentIndex(0 if trigger_type == "level" else 1)

        if trigger_type in ("rising", "falling"):
            self.direction_combo.setCurrentIndex(0 if trigger_type == "rising" else 1)

    def mark_edited(self, *_):
        """
        mark_edited: Note that the pane no longer matches the core.

        parameters: None

        returns: None

        Nothing is written until Apply, so the pane has to say so rather than
        imply the core is holding what is on screen.
        """

        self._trigger_edited = True

        if hasattr(self, "apply_trigger_button"):
            self.apply_trigger_button.setText("Apply trigger to core *")

    def clear_edited(self):
        """
        clear_edited: Note that the pane and the core agree again.

        parameters: None

        returns: None
        """

        self._trigger_edited = False

        self.apply_trigger_button.setText("Apply trigger to core")

    def build_conditions(self):
        """
        build_conditions: One row per probe, from the portmap the core matches.

        parameters: None

        returns: True if the table was built.

        Session.probes checks the portmap against the width the core reports,
        so this needs a connection and is what catches a portmap that has
        drifted from the synthesised core.
        """

        self.clear_conditions()

        probes = []

        def load():
            probes.extend(self.ila.probes())

        if not self.guard(load):
            self.conditions_hint.setText("no usable portmap, see the message below")
            return False

        for probe in probes:
            name    = probe["name"]
            monospace = QFont("monospace")

            radix_combo = QComboBox()
            radix_combo.addItems(trigger.RADICES)
            radix_combo.setCurrentText(trigger.DEFAULT_RADIX)

            pattern_edit = QLineEdit(trigger.ANY)
            pattern_edit.setFont(monospace)

            # Reformatting is local arithmetic, so the radix changes what the
            # row says without touching the core
            radix_combo.currentTextChanged.connect(
                lambda new, n=name: self._on_radix_changed(n, new))

            pattern_edit.textEdited.connect(self.mark_edited)

            label = QLabel(f"{name}[{probe['msb']}:{probe['lsb']}]")
            label.setMinimumWidth(180)

            row = QHBoxLayout()
            row.addWidget(label)
            row.addWidget(radix_combo)
            row.addWidget(pattern_edit, stretch=1)

            holder = QWidget()
            holder.setLayout(row)

            self.rows_layout.addWidget(holder)

            self.condition_rows[name] = {
                "radix"      : radix_combo,
                "pattern"    : pattern_edit,
                "width"      : probe["width"],
                "holder"     : holder,
                # What the text is currently written in, so a radix change
                # knows what to read it as before rewriting it
                "last_radix" : trigger.DEFAULT_RADIX
            }

        self.conditions_hint.setText(f"{len(probes)} signals, "
                                     f"{sum(p['width'] for p in probes)} probe bits")

        return True

    def clear_conditions(self):
        """
        clear_conditions: Take the table down.

        parameters: None

        returns: None
        """

        for row in self.condition_rows.values():
            self.rows_layout.removeWidget(row["holder"])
            row["holder"].deleteLater()

        self.condition_rows = {}

        self.conditions_hint.setText("connect to read the portmap")

    def _on_radix_changed(self, name, new_radix):
        """
        _on_radix_changed: Rewrite one row in a different base.

        name: The signal whose row changed.
        new_radix: The radix now chosen.

        returns: None
        """

        row = self.condition_rows[name]

        try:
            value, mask = trigger.parse_pattern(row["pattern"].text(), row["width"],
                                                row["last_radix"])
        except ValueError:
            # Half typed, so there is nothing to convert. Leave the text alone
            # and let Apply be the thing that complains about it.
            row["last_radix"] = new_radix
            return

        row["pattern"].setText(trigger.format_pattern(value, mask, row["width"], new_radix))
        row["last_radix"] = new_radix

    def patterns(self):
        """
        patterns: What the table says, per signal.

        parameters: None

        returns: ({name: pattern}, {name: radix}).
        """

        return ({name: row["pattern"].text() for name, row in self.condition_rows.items()},
                {name: row["radix"].currentText() for name, row in self.condition_rows.items()})

    def read_trigger(self):
        """
        read_trigger: Show the trigger the core is holding.

        parameters: None

        returns: None
        """

        cfg = {}

        def read():
            cfg.update(self.ila.get_trigger())

        if not self.guard(read):
            return

        self.set_trigger_type(cfg["trigger_type"])
        self.reduction_combo.setCurrentText(cfg["reduction"])
        self.position_spin.setValue(cfg["position"])

        if self.condition_rows:
            _, radices = self.patterns()

            shown = trigger.vector_to_patterns(cfg["condition"], cfg["mask"],
                                               self.ila.probes(), radices)

            for name, text in shown.items():
                self.condition_rows[name]["pattern"].setText(text)
                self._mark_row(name, bad=False)

        # The pane now says exactly what the core does
        self.clear_edited()

    def apply_trigger(self):
        """
        apply_trigger: Write the whole pane to the core.

        parameters: None

        returns: None

        As one unit, the way configure_trigger writes it. A pattern that does
        not parse stops the write entirely rather than leaving the core holding
        half of what is on screen.
        """

        if not self.ila.is_connected:
            self.report(f"not connected to {self.ila.serial_port}")
            return

        patterns, radices = self.patterns()

        try:
            condition, mask = trigger.patterns_to_vector(patterns, self.ila.probes(), radices)
        except session.OperationError as err:
            self.report(describe(err))
            return
        except ValueError as err:
            # patterns_to_vector names the signal, so the row can be found
            self.report(str(err))
            self._mark_bad_row(str(err))
            return

        for name in self.condition_rows:
            self._mark_row(name, bad=False)

        def write():
            self.ila.set_trigger(condition=condition, mask=mask,
                                 trigger_type=self.trigger_type,
                                 reduction=self.reduction_combo.currentText())
            self.ila.set_trigger_position(self.position_spin.value())

        if not self.guard(write):
            return

        self.clear_edited()
        self.report(f"trigger set: condition 0x{condition:x}, mask 0x{mask:x}, "
                    f"{self.reduction_combo.currentText()}, {self.trigger_type}, "
                    f"position {self.position_spin.value()}")

    def _mark_row(self, name, bad):
        """
        _mark_row: Show or clear the mark on one row.

        name: The signal's row.
        bad: Whether its pattern was refused.

        returns: None
        """

        self.condition_rows[name]["pattern"].setStyleSheet(
            f"border: 1px solid {BAD_PATTERN_COLOUR};" if bad else "")

    def _mark_bad_row(self, message):
        """
        _mark_bad_row: Outline whichever row the message names.

        message: What patterns_to_vector said.

        returns: None
        """

        for name in self.condition_rows:
            self._mark_row(name, bad=message.startswith(f"{name}:"))

    def save_capture(self):
        """
        save_capture: Read the capture out on a worker thread.

        parameters: None

        returns: None
        """

        if not self.ila.is_connected:
            self.report(f"not connected to {self.ila.serial_port}")
            return

        if self.worker is not None:
            self.report("a capture is already running")
            return

        path = self.path_edit.text().strip() or DEFAULT_CAPTURE

        # The poll and the readout would otherwise interleave on one port, and
        # the wrapper cannot tell two overlapping requests apart
        self.poll_timer.stop()

        self.progress.setValue(0)

        self.worker = CaptureWorker(self.ila, path, self)
        self.worker.progressed.connect(self.on_progress)
        self.worker.captured.connect(self.on_captured)
        self.worker.failed.connect(self.on_capture_failed)
        self.worker.finished.connect(self.on_capture_done)

        self.refresh()

        self.worker.start()

    def on_progress(self, read, total):
        self.progress.setValue(100 * read // total)

    def on_captured(self, result):
        self.report(f"wrote {result['path']}: {result['samples']} samples, "
                    f"trigger at {result['trigger_index']}")

    def on_capture_failed(self, message):
        self.progress.setValue(0)
        self.report(message)

    def on_capture_done(self):
        """
        on_capture_done: Pick the session back up once the worker has finished.

        parameters: None

        returns: None
        """

        self.worker = None

        self.refresh()

    def open_waveform(self):
        try:
            view_waveform(self.waveform_viewer, self.path_edit.text().strip())
        except (FileNotFoundError, OSError) as err:
            self.report(str(err))

    # Display #######################################################
    def poll(self):
        """
        poll: One status read, on the timer.

        parameters: None

        returns: None
        """

        # The readout runs on its own thread and owns the port while it does
        if self.worker is not None:
            return

        try:
            status = self.ila.status()
        except (session.OperationError, RuntimeError, ValueError, OSError, TimeoutError) as err:
            # A cable pulled out mid poll would otherwise repeat forever
            self.poll_timer.stop()
            self.report(str(err))
            return

        elapsed = self.ila.armed_for()

        if status == "ARMED" and elapsed is not None:
            self.status_label.setText(f"{status} ({elapsed:.1f} s)")
        else:
            self.status_label.setText(status)

        self.status_label.setStyleSheet(
            f"font-weight: bold; color: {STATUS_COLOURS.get(status, '#000000')};")

    def refresh(self):
        """
        refresh: Bring every widget back in line with the session.

        parameters: None

        returns: None
        """

        connected = self.ila.is_connected
        busy      = self.worker is not None

        self.connect_button.setText("Disconnect" if connected else "Connect")
        self.connect_button.setEnabled(not busy)
        self.connect_button.setStyleSheet(
            f"color: {DISCONNECT_COLOUR};" if connected else f"color: {CONNECT_COLOUR};")

        self.link_label.setText("connected" if connected else "disconnected")

        self.port_combo.setEnabled(not connected)
        self.baud_combo.setEnabled(not connected)

        for widget in (self.arm_button, self.disarm_button, self.force_button,
                       self.save_button, self.read_trigger_button,
                       self.apply_trigger_button, self.level_edge_combo,
                       self.reduction_combo, self.position_spin, self.position_slider):
            widget.setEnabled(connected and not busy)

        # A level trigger has no direction whatever the connection is doing
        self.direction_combo.setEnabled(connected and not busy
                                        and self.level_edge_combo.currentIndex() == 1)

        if connected:
            self.width_label.setText(f"{self.ila.probe_width} bits")
            self.depth_label.setText(f"{self.ila.samp_buff_depth} samples")
            self.freq_label.setText(engineering(self.ila.samp_freq_hz))

            # The buffer depth is what bounds the trigger position, and only a
            # core can say what it is
            depth = self.ila.samp_buff_depth

            self._position_syncing = True
            self.position_spin.setRange(0, depth - 1)
            self.position_slider.setRange(0, depth - 1)
            self._position_syncing = False
        else:
            for label in (self.width_label, self.depth_label, self.freq_label):
                label.setText("-")

            self._position_syncing = True
            self.position_spin.setRange(0, 0)
            self.position_slider.setRange(0, 0)
            self._position_syncing = False

            self.status_label.setText("-")
            self.status_label.setStyleSheet("")

        self._set_polling(connected and not busy)

    def _set_polling(self, wanted):
        """
        _set_polling: Start or stop the status timer.

        wanted: Whether the tab should be polling.

        returns: None
        """

        if wanted and not self.poll_timer.isActive():
            self.poll_timer.start()
            self.poll()
        elif not wanted and self.poll_timer.isActive():
            self.poll_timer.stop()

    def report(self, message):
        """
        report: Say something in the window's status bar.

        message: The line to show.

        returns: None
        """

        window = self.window()

        if isinstance(window, QMainWindow):
            window.statusBar().showMessage(message, 10000)


# Adding a device ###################################################
class AddDeviceDialog(QDialog):
    """
    AddDeviceDialog: Connect to a core, read its UID back and store it.

    The same store --add-device writes, so a device added here is reachable
    with --device and the other way round.
    """

    def __init__(self, device_dir, parent=None, debug=False):
        super().__init__(parent)

        self.setWindowTitle("Add a LibreILA device")

        self.device_dir = device_dir
        self.debug      = debug
        self.uid        = None

        self.port_combo = QComboBox()
        self.port_combo.setEditable(True)
        self.port_combo.addItems(available_ports())

        self.baud_combo = QComboBox()
        self.baud_combo.setEditable(True)
        self.baud_combo.addItems([str(baud) for baud in BAUD_RATES])
        self.baud_combo.setCurrentText("115200")

        self.message = QLabel("")
        self.message.setWordWrap(True)

        buttons = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        buttons.accepted.connect(self.add)
        buttons.rejected.connect(self.reject)

        layout = QFormLayout(self)
        layout.addRow("Serial port", self.port_combo)
        layout.addRow("Baud rate", self.baud_combo)
        layout.addRow(self.message)
        layout.addRow(buttons)

    def add(self):
        """
        add: Connect, read the UID and write the store.

        parameters: None

        returns: None
        """

        port = self.port_combo.currentText().strip()

        try:
            baud = int(self.baud_combo.currentText())
        except ValueError:
            self.message.setText(f"'{self.baud_combo.currentText()}' is not a baud rate")
            return

        ila = session.Session(port, baud=baud, debug=self.debug)

        try:
            ila.connect()

            uid = ila.uid

            # Separated from the link errors the same way the command line
            # separates them: the core answered, so a failure here is the
            # filesystem's and naming the cable would misdirect
            try:
                session.save_device(uid, port, baud, self.device_dir)
            except OSError as err:
                self.message.setText(f"reached the core, but could not write the store: {err}")
                return
        except session.OperationError as err:
            self.message.setText(describe(err))
            return
        except (RuntimeError, ValueError, OSError, TimeoutError) as err:
            self.message.setText(str(err))
            return
        finally:
            ila.disconnect()

        self.uid = uid

        self.accept()


# Main window #######################################################
class MainWindow(QMainWindow):
    """
    MainWindow: The tab strip, one tab per stored device.
    """

    def __init__(self, waveform_viewer, device_dir, portmap, debug=False, parent=None):
        super().__init__(parent)

        self.setWindowTitle("LibreILA")

        self.waveform_viewer = waveform_viewer
        self.device_dir      = device_dir
        self.portmap         = portmap
        self.debug           = debug

        self.tabs = QTabWidget()
        self.tabs.setTabsClosable(True)
        self.tabs.tabCloseRequested.connect(self.close_tab)

        self.add_button = QPushButton("+ ADD TAB")
        self.add_button.clicked.connect(self.add_device)

        # Not the tab bar's corner widget: that collapses to zero height along
        # with the bar itself when there are no tabs yet, which is every run
        # against an empty device store, leaving no way to add the first one.
        top = QHBoxLayout()
        top.addStretch()
        top.addWidget(self.add_button)

        central = QWidget()
        layout  = QVBoxLayout(central)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.addLayout(top)
        layout.addWidget(self.tabs)

        self.setCentralWidget(central)

        # The store is relative to the working directory unless it was given
        # one, so say where the tabs came from rather than leaving an empty
        # strip unexplained
        self.statusBar().showMessage(f"devices from {os.path.abspath(device_dir)}")

        self.load_devices()

    def load_devices(self):
        """
        load_devices: Build a tab for every device in the store.

        parameters: None

        returns: None
        """

        for uid in session.list_devices(self.device_dir):
            try:
                serial_port, baud = session.load_device(uid, self.device_dir)
            except session.OperationError:
                # A hand edited file that no longer parses. The store is meant
                # to be editable, so skip it rather than refusing to open.
                continue

            self.add_tab(uid, serial_port, baud)

    def add_tab(self, uid, serial_port, baud):
        """
        add_tab: Put one device on the tab strip.

        uid: The UID the core reports.
        serial_port: The port it answers on.
        baud: The baud rate it answers at.

        returns: The tab.
        """

        tab = DeviceTab(uid, serial_port, baud, self.portmap, self.waveform_viewer,
                       debug=self.debug, parent=self)

        tab.title_changed.connect(self.retitle)

        self.tabs.addTab(tab, tab.title)

        return tab

    def tab_for(self, uid):
        """
        tab_for: The tab showing one device, if it has one.

        uid: The UID to look for.

        returns: The tab, or None.
        """

        for index in range(self.tabs.count()):
            if self.tabs.widget(index).uid == uid:
                return self.tabs.widget(index)

        return None

    def retitle(self):
        """
        retitle: Bring every tab's title back in line with its session.

        parameters: None

        returns: None
        """

        for index in range(self.tabs.count()):
            self.tabs.setTabText(index, self.tabs.widget(index).title)

    def add_device(self):
        """
        add_device: Ask for a device, store it and give it a tab.

        parameters: None

        returns: None
        """

        dialog = AddDeviceDialog(self.device_dir, debug=self.debug, parent=self)

        if dialog.exec() != QDialog.Accepted:
            return

        existing = self.tab_for(dialog.uid)

        if existing is not None:
            # One tab per device: two sessions on one port would fight over it,
            # and the UID is what says they are the same core
            self.tabs.setCurrentWidget(existing)
            self.statusBar().showMessage(f"ILA{dialog.uid} already has a tab", 10000)
            return

        serial_port, baud = session.load_device(dialog.uid, self.device_dir)

        self.tabs.setCurrentWidget(self.add_tab(dialog.uid, serial_port, baud))

    def close_tab(self, index):
        """
        close_tab: Let go of one device.

        index: The tab to close.

        returns: None

        The stored device is left alone, so closing a tab is not forgetting the
        core. --reset is what removes it.
        """

        tab = self.tabs.widget(index)

        tab.stop()
        tab.ila.disconnect()

        self.tabs.removeTab(index)

        tab.deleteLater()

    def closeEvent(self, event):
        """
        closeEvent: Put every session down on the way out.

        event: The close event.

        returns: None
        """

        for index in range(self.tabs.count()):
            tab = self.tabs.widget(index)

            tab.stop()
            tab.ila.disconnect()

        super().closeEvent(event)


def run_gui(waveform_viewer, device_dir, portmap, debug=False):
    """
    run_gui: Open the window and run until it closes.

    waveform_viewer: The command --waveform-viewer named.
    device_dir: Where the device store lives.
    portmap: The portmap.csv the cores were generated from.
    debug: Log every tab's UART transactions to driver.DEBUG_LOG_FILENAME.

    returns: None
    """

    app = QApplication.instance() or QApplication([])

    # Fusion so the window looks the same everywhere, and light explicitly on
    # both the modern hint and the palette, since a platform that ignores the
    # hint would otherwise hand back the desktop's dark colours.
    app.setStyle("Fusion")
    app.styleHints().setColorScheme(Qt.ColorScheme.Light)
    app.setPalette(light_palette())

    window = MainWindow(waveform_viewer, device_dir, portmap, debug=debug)
    window.resize(1100, 800)
    window.show()

    app.exec()
