#####################################################################
# File: session.py
# Author: Y.U.P. (yashparitkar)
# Created: 2026-08-04 Tue 23:12
# Last Modified: 2026-08-05 Wed 08:18
#
# Description: ILA host side session
#   One connection to one core, and every operation a front end can ask of it.
#   driver.py speaks the register map, vcd.py names the bits, and this file is
#   what sits between the two and whatever is driving the tool.
#
#   One session may only be touched by one thread at a time. The wrapper is a
#   request/response protocol over a single port and _transact flushes the input
#   buffer on the way in, so two overlapping operations desync the wrapper and
#   each other. Sessions are independent of one another, one port each.
#
# Copyright 2026 Yash Paritkar
# SPDX-License-Identifier: CERN-OHL-P-2.0
#####################################################################

import glob
import os
import re
import time

import driver
import vcd

# One file per device, named by the UID the core reports, holding a single
# "port,baud" line. The UID is what tells two cores in one system apart, so it
# is what a device is selected on. The store lives here rather than in the CLI
# because both front ends read it: a core added on the command line should come
# up as a tab, and one added in a tab should be reachable with --device.
DEVICE_FILE_GLOB = "libre_ila_device*.txt"
DEVICE_FILE_RE   = re.compile(r"^libre_ila_device(\d+)\.txt$")

# The directory the store defaults to. Relative on purpose, so the command line
# keeps the behaviour it documents; a front end that is not started from a
# working directory the user chose should pass one explicitly.
DEFAULT_DEVICE_DIR = driver.DEFAULT_OUTPUT_DIR

# Why an operation failed, in terms of the host's own reasoning rather than of
# what any one front end does about it. libre_ila.py maps these onto POSIX exit
# statuses and gui.py onto whatever it shows the user; that mapping is the one
# thing the two cannot share, which is why it is not in here.
#
# They are fine grained enough to say what to do about it, not just what went
# wrong, because what to do about it is spelled differently in each front end: a
# capture that has not finished is answered with --wait-done on the command line
# and with a button in a window. So the message here states the fact and stops,
# and the front end keys its own remedy off the reason.
REASON_USAGE            = "usage"
REASON_DEVICE_NOT_FOUND = "device-not-found"
REASON_PORTMAP          = "portmap"
REASON_PORTMAP_MISMATCH = "portmap-mismatch"
REASON_TIMEOUT          = "timeout"
REASON_NOT_DONE         = "not-done"

TRIGGER_TYPES = ["level", "rising", "falling"]
REDUCTIONS    = ["and", "or"]


class OperationError(Exception):
    """
    An operation the host refused or could not complete, with a symbolic reason.

    Raised where the host worked out that something was wrong: a trigger value
    that would not do what it says, a portmap that does not match the core, a
    readout asked for before the capture finished. Errors that come from the
    driver keep the exception driver.py raised for them, since a link error or
    a refused register write is already reported precisely there.
    """

    def __init__(self, message, reason):
        super().__init__(message)
        self.reason = reason


# Device store ######################################################
def device_path(uid, directory=DEFAULT_DEVICE_DIR):
    """
    device_path: Name of the file holding one device's connection details.

    uid: The UID the core reports.
    directory: The directory the store lives in.

    returns: The path to the device file.
    """

    # Normalised so a directory given as "./capture" or "capture/" reads the
    # same way in the messages the user sees and in the store's own listing
    return os.path.normpath(os.path.join(directory, f"libre_ila_device{uid}.txt"))


def save_device(uid, serial_port, baud, directory=DEFAULT_DEVICE_DIR):
    """
    save_device: Record how to reach a device.

    uid: The UID the core reports.
    serial_port: The port the core answers on.
    baud: The baud rate it answers at.
    directory: The directory the store lives in.

    returns: The path written.
    """

    path = device_path(uid, directory)

    os.makedirs(directory, exist_ok=True)

    with open(path, "w") as device_file:
        device_file.write(f"{serial_port},{baud}\n")

    return path


def load_device(uid, directory=DEFAULT_DEVICE_DIR):
    """
    load_device: Read back how to reach a device.

    uid: The UID of the device wanted.
    directory: The directory the store lives in.

    returns: (serial_port, baud)
    """

    path = device_path(uid, directory)

    try:
        with open(path, "r") as device_file:
            line = device_file.readline().strip()
    except FileNotFoundError:
        raise OperationError(f"no device {uid} here ({path} does not exist). Add one with "
                             f"--add-device --serial-port <port>.",
                             REASON_DEVICE_NOT_FOUND)

    fields = line.split(",")

    # The file is meant to be hand editable, so a mangled one gets a message
    # naming it rather than a traceback out of int()
    if len(fields) != 2 or not fields[0].strip():
        raise OperationError(f"{path} should hold one 'port,baud' line, found: {line!r}",
                             REASON_DEVICE_NOT_FOUND)

    try:
        baud = int(fields[1])
    except ValueError:
        raise OperationError(f"{path} has a non numeric baud rate: {fields[1]!r}",
                             REASON_DEVICE_NOT_FOUND)

    return fields[0].strip(), baud


def list_devices(directory=DEFAULT_DEVICE_DIR):
    """
    list_devices: The UIDs of every stored device.

    directory: The directory the store lives in.

    returns: The UIDs, ascending. A front end that opens one view per device
    builds its list from this rather than from the order they were added.
    """

    uids = []

    for path in glob.glob(os.path.join(directory, DEVICE_FILE_GLOB)):
        match = DEVICE_FILE_RE.match(os.path.basename(path))

        if match:
            uids.append(int(match.group(1)))

    return sorted(uids)


def remove_devices(directory=DEFAULT_DEVICE_DIR):
    """
    remove_devices: Forget every stored device.

    directory: The directory the store lives in.

    returns: The list of paths removed.
    """

    removed = []

    # Matched against the glob and then the pattern, so a file that merely
    # starts with the prefix is left alone. Nothing here shells out.
    for path in sorted(glob.glob(os.path.join(directory, DEVICE_FILE_GLOB))):
        if DEVICE_FILE_RE.match(os.path.basename(path)):
            os.remove(path)
            removed.append(os.path.normpath(path))

    return removed


def status_name(status):
    """
    status_name: Human readable form of a driver status code.

    status: The value driver.get_status returned.

    returns: The name, e.g. "ARMED".
    """

    for name, value in driver._libre_ila_status.items():
        if value == status:
            return name.replace("LIBRE_ILA_STATUS_", "")

    return str(status)


def decode_trigger_mode(mode):
    """
    decode_trigger_mode: Split a TRIG_CFG word into the two things it says.

    mode: The TRIG_CFG word read back from the core.

    returns: (reduction, trigger_type), the same spellings the setters take.
    """

    reduction = "or" if mode & driver._libre_ila_trig_mode["LIBRE_ILA_TRIG_MODE_OR"] else "and"

    if not mode & driver._libre_ila_trig_mode["LIBRE_ILA_TRIG_EDGE"]:
        trigger_type = "level"
    elif mode & driver._libre_ila_trig_mode["LIBRE_ILA_TRIG_FALLING"]:
        trigger_type = "falling"
    else:
        trigger_type = "rising"

    return reduction, trigger_type


# Session ###########################################################
class Session:
    """
    One core, for as long as a front end wants to hold it open.

    Built disconnected, so a view can exist for a device that is not answering
    yet, which is what a tab titled DISCONNECTED is. connect() opens the port
    and reads the identity block; every operation below needs that to have
    happened, and says so rather than opening a port behind the caller's back.
    """

    def __init__(self, serial_port, baud=115200, portmap_path=None, uid=None, debug=False):
        """
        serial_port: The port the core answers on.
        baud: The baud rate it answers at.
        portmap_path: The portmap.csv the core was generated from, needed only
            by capture() and probes().
        uid: The UID this session is expected to reach, if it came out of the
            device store. Checked on connect, since a port that has been
            re-enumerated can point at a different core than it did.
        debug: Log every UART transaction to driver.DEBUG_LOG_FILENAME.
        """

        self.serial_port  = serial_port
        self.baud         = baud
        self.portmap_path = portmap_path
        self.expected_uid = uid
        self.debug        = debug

        self.ila      = None
        self._probes  = None
        self._armed_at = None

    # Connection ####################################################
    @property
    def is_connected(self):
        """
        is_connected: Whether the port is open and the core has answered.

        parameters: None

        returns: True or False.
        """

        return self.ila is not None

    def connect(self):
        """
        connect: Open the port and read what the core says it is.

        Deliberately does no error translation. A missing or busy port arrives
        as the OSError pyserial raised, a core that is not there as the magic
        key RuntimeError driver.py raises, and both name the port already.

        parameters: None

        returns: None
        """

        if self.is_connected:
            return

        ila = driver.LibreILA_Driver(self.serial_port, baudrate=self.baud, debug=self.debug)

        # A stored device is reached by UID, so a port that now answers as a
        # different core is worth catching here rather than letting the caller
        # configure the wrong ILA. Ports get renumbered, UIDs do not.
        if self.expected_uid is not None and ila.UID != self.expected_uid:
            ila.close()

            raise OperationError(f"{self.serial_port} answers as UID {ila.UID}, not "
                                 f"{self.expected_uid}. The port may have been renumbered, "
                                 f"add the device again.",
                                 REASON_DEVICE_NOT_FOUND)

        self.ila       = ila
        self._armed_at = None

    def disconnect(self):
        """
        disconnect: Close the port, leaving the core as it is.

        Nothing is written on the way out. A capture armed here stays armed and
        can be read back by a later session, which is the whole reason the host
        keeps no state worth saving.

        parameters: None

        returns: None
        """

        if self.ila is not None:
            self.ila.close()

            self.ila       = None
            self._armed_at = None

    def _require_connection(self):
        """
        _require_connection: The driver, or a refusal naming what is missing.

        parameters: None

        returns: The connected driver.
        """

        if not self.is_connected:
            raise OperationError(f"not connected to {self.serial_port}", REASON_USAGE)

        return self.ila

    # What the core says it is #######################################
    # Read once at connect and cached in the driver, so these cost nothing on
    # the wire and a front end can put them in a label without thinking about
    # it. Everything that does cost a packet is a method below.
    @property
    def uid(self):
        return self._require_connection().UID

    @property
    def probe_width(self):
        return self._require_connection().PROBE_WIDTH

    @property
    def samp_buff_depth(self):
        return self._require_connection().SAMP_BUFF_DEPTH

    @property
    def samp_freq_hz(self):
        return self._require_connection().SAMP_FREQ_HZ

    @property
    def stride_width(self):
        return self._require_connection().stride_width

    @property
    def n_lanes(self):
        return self._require_connection().n_lanes

    def info(self):
        """
        info: What the core reports about itself.

        parameters: None

        returns: A dict of the identity block, the geometry that follows from
        it, and the current status. One packet, for the status.
        """

        ila = self._require_connection()

        return {
            "serial_port"     : self.serial_port,
            "baud"            : self.baud,
            "uid"             : ila.UID,
            "probe_width"     : ila.PROBE_WIDTH,
            "samp_buff_depth" : ila.SAMP_BUFF_DEPTH,
            "samp_freq_hz"    : ila.SAMP_FREQ_HZ,
            "stride_width"    : ila.stride_width,
            "n_lanes"         : ila.n_lanes,
            "status"          : status_name(ila.get_status())
        }

    def status(self):
        """
        status: The state the core is in.

        parameters: None

        returns: One of IDLE, ARMED, TRIGGERED, DONE. One packet, so this is
        the call a front end polls on a timer.
        """

        return status_name(self._require_connection().get_status())

    def armed_for(self):
        """
        armed_for: Seconds since this session armed the core.

        The one piece of state the core genuinely does not hold: it reports that
        it is armed, not how long it has been. So this is host side, and it
        knows nothing about an ILA that some other session armed, which is why
        it returns None rather than zero when it has no timestamp.

        parameters: None

        returns: The elapsed seconds, or None if this session did not arm it.
        """

        if self._armed_at is None:
            return None

        return time.time() - self._armed_at

    # The portmap ####################################################
    def probes(self):
        """
        probes: The portmap, checked against the core.

        Loaded on first use and kept, since the file describes the synthesised
        core and cannot change under a connection that is still valid. A front
        end that lets the user pick a different portmap makes a new session.

        parameters: None

        returns: The probe list vcd.load_portmap produced.
        """

        if self._probes is not None:
            return self._probes

        ila = self._require_connection()

        if self.portmap_path is None:
            raise OperationError("no portmap given, so the probe bits cannot be named",
                                 REASON_PORTMAP)

        try:
            probes = vcd.load_portmap(self.portmap_path)
        except FileNotFoundError:
            raise OperationError(f"no portmap at {self.portmap_path}. Point --portmap at the "
                                 f"file the core was generated from.",
                                 REASON_PORTMAP)
        except ValueError as err:
            raise OperationError(f"{self.portmap_path}: {err}", REASON_PORTMAP)

        try:
            vcd.check_portmap(probes, ila.PROBE_WIDTH)
        except ValueError as err:
            raise OperationError(str(err), REASON_PORTMAP_MISMATCH)

        self._probes = probes

        return probes

    # The trigger ####################################################
    def _split(self, value):
        """
        _split: Spread one number across the stride as 32 bit words.

        value: The bit pattern.

        returns: The words, LSB word first.
        """

        return [(value >> (32 * i)) & 0xffffffff for i in range(self.stride_width)]

    def _pack(self, words):
        """
        _pack: Join a trigger vector's words back into one number.

        words: The words, LSB word first.

        returns: The value as an integer.
        """

        return sum(word << (32 * i) for i, word in enumerate(words))

    def get_trigger(self):
        """
        get_trigger: The trigger setup, read back out of the core.

        parameters: None

        returns: A dict with condition and mask as whole numbers, mode as the
        raw TRIG_CFG word, and reduction, trigger_type and position decoded.
        """

        cfg  = self._require_connection().get_trigger_configuration()
        mode = cfg["trigger_mode"]

        reduction, trigger_type = decode_trigger_mode(mode)

        return {
            "condition"    : self._pack(cfg["trigger_cond"]),
            "mask"         : self._pack(cfg["trigger_mask"]),
            "mode"         : mode,
            "reduction"    : reduction,
            "trigger_type" : trigger_type,
            "position"     : cfg["trigger_position"]
        }

    def set_trigger(self, condition=None, mask=None, trigger_type=None, reduction=None):
        """
        set_trigger: Apply whichever trigger fields were given, keeping the rest.

        condition: The bit pattern the probe word is compared against, as one
            number covering the whole probe word, or None to keep it.
        mask: Which of its bits are compared, same form, or None to keep it.
        trigger_type: One of TRIGGER_TYPES, or None to keep it.
        reduction: One of REDUCTIONS, or None to keep it.

        returns: The dict get_trigger would now return, without re-reading it.
        """

        ila = self._require_connection()

        for name, value, allowed in (("trigger type", trigger_type, TRIGGER_TYPES),
                                     ("reduction", reduction, REDUCTIONS)):
            if value is not None and value not in allowed:
                raise OperationError(f"{name} {value!r} is not one of "
                                     f"{', '.join(allowed)}",
                                     REASON_USAGE)

        limit = 1 << ila.PROBE_WIDTH

        for name, value in (("trigger condition", condition), ("trigger mask", mask)):
            if value is not None and value < 0:
                raise OperationError(f"the {name} is negative. It is a bit pattern, not a "
                                     f"signed number.",
                                     REASON_USAGE)

            # A bit set above the probe width is not merely ignored. The core
            # zero extends the sample to the full stride before comparing, so a
            # mask bit up there fires an or trigger on the very first sample and
            # stops an and trigger from ever firing.
            if value is not None and value >= limit:
                raise OperationError(f"the {name} 0x{value:x} sets bits above the core's "
                                     f"{ila.PROBE_WIDTH} bit probe. The trigger compares the "
                                     f"padding too, so those bits would break it rather than "
                                     f"be ignored.",
                                     REASON_USAGE)

        # configure_trigger writes the condition, the mask and the mode as one
        # unit, so a call that sets only one of them reads the other two back
        # out of the core first. Nothing is left half written, and nothing has
        # to be remembered between calls.
        current = ila.get_trigger_configuration()

        cond = current["trigger_cond"] if condition is None else self._split(condition)
        bits = current["trigger_mask"] if mask is None else self._split(mask)
        mode = current["trigger_mode"]

        # The two dimensions of TRIG_CFG are independent, and one not mentioned
        # keeps whatever the core already had.
        if reduction is not None:
            if reduction == "or":
                mode |= driver._libre_ila_trig_mode["LIBRE_ILA_TRIG_MODE_OR"]
            else:
                mode &= ~driver._libre_ila_trig_mode["LIBRE_ILA_TRIG_MODE_OR"]

        if trigger_type is not None:
            edge    = driver._libre_ila_trig_mode["LIBRE_ILA_TRIG_EDGE"]
            falling = driver._libre_ila_trig_mode["LIBRE_ILA_TRIG_FALLING"]

            mode &= ~(edge | falling)

            if trigger_type == "rising":
                mode |= edge
            elif trigger_type == "falling":
                mode |= edge | falling

        ila.configure_trigger(cond, bits, mode)

        applied_reduction, applied_type = decode_trigger_mode(mode)

        return {
            "condition"    : self._pack(cond),
            "mask"         : self._pack(bits),
            "mode"         : mode,
            "reduction"    : applied_reduction,
            "trigger_type" : applied_type,
            "position"     : current["trigger_position"]
        }

    def set_trigger_position(self, position):
        """
        set_trigger_position: Move the trigger within the buffer.

        position: Where the trigger sits, in samples. 0 keeps the whole buffer
            for post trigger samples, depth-1 keeps it all for pre trigger ones.

        returns: None
        """

        ila = self._require_connection()

        # driver.set_trigger_position raises ValueError for this, which is right
        # for a library. A front end wants the same refusal in the same shape as
        # every other one it has to report, so it is checked here too.
        if position < 0 or position >= ila.SAMP_BUFF_DEPTH:
            raise OperationError(f"trigger position {position} is outside the "
                                 f"{ila.SAMP_BUFF_DEPTH} sample window",
                                 REASON_USAGE)

        ila.set_trigger_position(position)

    # Running a capture ##############################################
    def arm(self):
        """
        arm: Start sampling and wait for the trigger.

        parameters: None

        returns: None
        """

        self._require_connection().arm()

        self._armed_at = time.time()

    def force_trigger(self):
        """
        force_trigger: Trigger an armed core regardless of the condition.

        parameters: None

        returns: None
        """

        self._require_connection().force_trigger()

    def disarm(self):
        """
        disarm: Cancel a capture in progress.

        parameters: None

        returns: None
        """

        self._require_connection().disarm()

        self._armed_at = None

    def wait_done(self, timeout):
        """
        wait_done: Block until the capture completes.

        Blocking, and a busy poll at that, so this is for a front end that has
        nothing else to do while it waits. An event driven one polls status() on
        a timer instead, which it wants anyway to keep a state display honest.

        timeout: How long to wait, in seconds.

        returns: None
        """

        ila = self._require_connection()

        try:
            ila.wait_done(timeout)
        except TimeoutError:
            # driver._recv raises TimeoutError for a dead link too, so this one
            # is caught where its meaning is known
            raise OperationError(f"the ILA did not reach DONE within {timeout} s. It is "
                                 f"{status_name(ila.get_status())}; the condition may not "
                                 f"have come up.",
                                 REASON_TIMEOUT)

    def capture(self, path, progress=None):
        """
        capture: Read the completed capture out and write it as a VCD.

        path: Where to write the .vcd.
        progress: Called as progress(words_read, words_total) as the buffer
            comes in, or None. The readout is the one operation here that takes
            seconds rather than a packet, so it is also the only one worth
            reporting on; a front end with an event loop runs it off the thread
            that serves that loop and reports from here.

        returns: A dict with the path, the sample count, the probe width and
        the row the trigger fired on.
        """

        ila = self._require_connection()

        # Before the readout rather than after it, so a portmap that does not
        # match the core costs nothing instead of a full buffer over the wire
        probes = self.probes()

        status = ila.get_status()

        if status != driver._libre_ila_status["LIBRE_ILA_STATUS_DONE"]:
            raise OperationError(f"the ILA is {status_name(status)}, not DONE, so the buffer "
                                 f"is still being written.",
                                 REASON_NOT_DONE)

        samples, trig_idx = ila.read_data(progress=progress)

        vcd.write_vcd(path, samples, trig_idx, probes, ila.SAMP_FREQ_HZ)

        return {
            "path"          : path,
            "samples"       : len(samples),
            "probe_width"   : ila.PROBE_WIDTH,
            "trigger_index" : trig_idx
        }
