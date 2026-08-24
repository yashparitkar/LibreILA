#!/usr/bin/env python3
#####################################################################
# File: libre_ila.py
# Author: Y.U.P. (yashparitkar)
# Created: 2026-07-24 Fri 19:48
# Last Modified: 2026-08-04 Tue 22:50
#
# Description: ILA command line interface
#   This is the entry point. It wires the command line to session.py, which
#   holds one connection to one core and every operation that can be asked of
#   it, over driver.py for the register map and vcd.py for the signal names.
#
#   Every flag below is a verb, and they are applied in one fixed order
#   whatever order they are given in, see EXECUTION_ORDER. That order is the
#   capture lifecycle, so a whole capture fits in one invocation and equally
#   well across several: nothing about the session is held on the host, the
#   core itself is the record of what was configured and what was caught.
#
#   Which is why this file builds a session, runs its verbs and drops it, while
#   the GUI keeps one open per tab. The lifetime is the only difference between
#   the two front ends, so everything except the lifetime lives in session.py
#   and everything in here is the command line and the printing.
#
#   The GUI is not wired up yet, --gui reports that and exits.
#
# Copyright 2026 Yash Paritkar
# SPDX-License-Identifier: CERN-OHL-P-2.0
#####################################################################

import argparse
import os
import sys

import driver
import session

# Exit statuses. These are POSIX process statuses, so they have to be small
# and positive: sys.exit(-1) reaches the shell as 255, which is the value a
# caller reads as "killed by a signal".
_libre_ila_main_status = {
    "LIBRE_ILA_MAIN_STATUS_SUCCESS"             : 0,
    "LIBRE_ILA_MAIN_STATUS_USAGE"               : 2,
    "LIBRE_ILA_MAIN_STATUS_ERROR_ADDING_DEVICE" : 3,
    "LIBRE_ILA_MAIN_STATUS_DEVICE_NOT_FOUND"    : 4,
    "LIBRE_ILA_MAIN_STATUS_PROBEMAP_NOT_FOUND"  : 5,
    "LIBRE_ILA_MAIN_STATUS_PROBEMAP_MISMATCH"   : 6,
    "LIBRE_ILA_MAIN_STATUS_LINK_ERROR"          : 7,
    "LIBRE_ILA_MAIN_STATUS_TIMEOUT"             : 8,
    "LIBRE_ILA_MAIN_STATUS_HARDWARE_ERROR"      : 9,
    "LIBRE_ILA_MAIN_STATUS_GUI_UNAVAILABLE"     : 10
}

# What a session's refusal means as a process status. session.py reasons about
_libre_ila_reason_status = {
    session.REASON_USAGE            : _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_USAGE"],
    session.REASON_DEVICE_NOT_FOUND : _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_DEVICE_NOT_FOUND"],
    session.REASON_PORTMAP          : _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_PROBEMAP_NOT_FOUND"],
    session.REASON_PORTMAP_MISMATCH : _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_PROBEMAP_MISMATCH"],
    session.REASON_TIMEOUT          : _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_TIMEOUT"],
    session.REASON_NOT_DONE         : _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_HARDWARE_ERROR"]
}

# What to do about it, in this front end's own vocabulary. The session states
# the fact and stops, because the answer to a capture that has not finished is a
# flag here and a button in the GUI, and only the front end knows which.
_libre_ila_reason_hint = {
    session.REASON_NOT_DONE : "Add --wait-done, or --force-trigger if it is armed and the "
                              "condition has not come up.",
    session.REASON_TIMEOUT  : "--force-trigger ends the wait."
}

SCRIPT_DIR      = os.path.dirname(os.path.abspath(__file__))
DEFAULT_PORTMAP = os.path.join(SCRIPT_DIR, os.pardir, os.pardir, "codegen", "portmap.csv")
DEFAULT_VCD     = os.path.join(driver.DEFAULT_OUTPUT_DIR, "libre_ila.vcd")

EXECUTION_ORDER = """\
The flags are verbs. Whatever order they are given in, they run in this one:

  1  --reset                     forget every stored device, then stop
  2  --list-devices              print the stored devices, then stop
  3  --add-device                store the device on --serial-port, then stop
  4  (connect to --device)
  5  --info                      print what the core reports, then stop
  6  --disarm                     cancel a capture still in progress
  7  --set-trigger-condition
     --set-trigger-mask
     --set-trigger-type
     --set-trigger-reduction     merged into one trigger write
  8  --set-trigger-position
  9  --get-trigger-configuration read the trigger back out of the core
  10 --arm
  11 --force-trigger
  12 --wait-done
  13 --read-data                 write the .vcd

So a whole capture is one line:

  libre_ila.py --set-trigger-condition 0x20000000000000000 \\
               --set-trigger-mask 0x20000000000000000 \\
               --set-trigger-type rising --arm --wait-done --read-data

and, because the core holds the state and not this tool, splitting it across
invocations works just as well: --arm now, --read-data whenever. --disarm runs
first for the same reason, so retrying a capture with a different trigger is
also one line."""


class CliError(Exception):
    """An error worth reporting as a message and an exit status, not a traceback."""

    def __init__(self, message, status):
        super().__init__(message)
        self.status = status


def _trigger_value(text):
    """
    _trigger_value: Parse a trigger condition or mask off the command line.

    text: The value as given, in any base python accepts.

    returns: The value as an integer.
    """

    try:
        value = int(text, 0)
    except ValueError:
        raise argparse.ArgumentTypeError(f"'{text}' is not an integer. Give a bit pattern as "
                                         f"0x..., 0b... or plain decimal.")

    if value < 0:
        raise argparse.ArgumentTypeError(f"'{text}' is negative. A trigger value is a bit "
                                         f"pattern, not a signed number.")

    return value


def build_parser():
    """
    build_parser: Build the command line parser.

    parameters: None

    returns: The argparse.ArgumentParser.
    """

    parser = argparse.ArgumentParser(
        prog="libre_ila.py",
        description="Drive a LibreILA core over its UART wrapper.",
        epilog=EXECUTION_ORDER,
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    ## GUI arguments
    parser.add_argument(
        "--gui",
        action="store_true",
        help="Enable GUI and use graphical interface",
    )

    parser.add_argument(
        "--waveform-viewer",
        type=str,
        default="gtkwave",
        help="Specify the waveform viewer to use (default: gtkwave)",
    )

    ## Device management
    parser.add_argument(
        "--reset",
        action="store_true",
        help="Deletes all LibreILA device instance",
    )

    parser.add_argument(
        "--list-devices",
        action="store_true",
        help="Print the UID, port and baud rate of every stored device, then stop. These are "
             "the UIDs --device takes",
    )

    parser.add_argument(
        "--add-device",
        action="store_true",
        help="Add a new LibreILA device instance with the specified serial port and baud rate",
    )

    parser.add_argument(
        "--device",
        type=int,
        default=0,
        help="Which stored device to talk to, selected by the UID the core reports, not by "
             "the order they were added (default: 0, which is what a core built without a "
             "G_UID reports)",
    )

    parser.add_argument(
        "--serial-port",
        type=str,
        default="/dev/ttyUSB0",
        help="Specify the serial port to use (default: /dev/ttyUSB0)",
    )

    parser.add_argument(
        "--baud",
        type=int,
        default=115200,
        help="Specify the baud rate to use (default: 115200)",
    )

    parser.add_argument(
        "--device-dir",
        type=str,
        default=session.DEFAULT_DEVICE_DIR,
        help=f"Where the libre_ila_device<UID>.txt files live (default: {session.DEFAULT_DEVICE_DIR}/ "
             f"under the working directory). "
             "The GUI reads the same store, so a device added on either side is visible to "
             "the other, which only holds if both are pointed at the same place",
    )

    parser.add_argument(
        "--debug",
        action="store_true",
        help=f"Log every UART transaction (request and response bytes) to "
             f"{driver.DEBUG_LOG_FILENAME}, appended to on every run",
    )

    ## Reading the core
    parser.add_argument(
        "--info",
        action="store_true",
        help="Print the LibreILA device information and exit",
    )

    parser.add_argument(
        "--get-trigger-configuration",
        action="store_true",
        help="Read the trigger configuration from the LibreILA device and print it",
    )

    ## Configuring the trigger
    parser.add_argument(
        "--set-trigger-position",
        type=int,
        help="Set the trigger position in the LibreILA device (in samples)",
    )

    parser.add_argument(
        "--set-trigger-condition",
        type=_trigger_value,
        help="Bit pattern the probe word is compared against, as one number (0x..., 0b... or "
             "decimal). Bit 0 is the first signal listed in the portmap",
    )

    parser.add_argument(
        "--set-trigger-mask",
        type=_trigger_value,
        help="Which bits of the condition are compared, same format. A zero mask never fires in "
             "'or' mode, and fires on the first sample in 'and' mode",
    )

    parser.add_argument(
        "--set-trigger-type",
        choices=["level", "rising", "falling"],
        help="Whether the condition triggers while it holds (level) or on the transition into "
             "it (rising/falling)",
    )

    parser.add_argument(
        "--set-trigger-reduction",
        choices=["and", "or"],
        help="Whether every masked bit has to match (and) or any one of them (or)",
    )

    ## Running a capture
    parser.add_argument(
        "--arm",
        action="store_true",
        help="Arm the ILA so it starts sampling and waits for the trigger",
    )

    parser.add_argument(
        "--force-trigger",
        action="store_true",
        help="Trigger an armed ILA regardless of the condition",
    )

    parser.add_argument(
        "--disarm",
        action="store_true",
        help="Cancel a capture in progress and put the ILA back to idle",
    )

    parser.add_argument(
        "--wait-done",
        type=float,
        nargs="?",
        const=10.0,
        metavar="SECONDS",
        help="Wait for the capture to complete, up to SECONDS (default: 10)",
    )

    parser.add_argument(
        "--read-data",
        action="store_true",
        help="Read the captured samples and write them out as a .vcd",
    )

    parser.add_argument(
        "-o", "--output",
        type=str,
        default=DEFAULT_VCD,
        help=f"Where --read-data writes the .vcd (default: {DEFAULT_VCD})",
    )

    parser.add_argument(
        "--portmap",
        type=str,
        default=DEFAULT_PORTMAP,
        help="The portmap.csv the core was generated from, used to name the signals in the "
             ".vcd (default: codegen/portmap.csv)",
    )

    return parser


def cmd_reset(args):
    """
    cmd_reset: Forget every stored device.

    args: The parsed command line.

    returns: An exit status.
    """

    removed = session.remove_devices(args.device_dir)

    if removed:
        for path in removed:
            print(f"removed {path}")
    else:
        print("no stored devices to remove")

    return _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_SUCCESS"]


def cmd_list_devices(args):
    """
    cmd_list_devices: Print the stored devices.

    No port is opened. This is the store, i.e. what --device can name, not what
    is currently plugged in, and a UID here only reaches a core if the port it
    was added on still answers as that UID.

    args: The parsed command line.

    returns: An exit status.
    """

    uids = session.list_devices(args.device_dir)

    if not uids:
        print(f"no stored devices in {args.device_dir}. Add one with --add-device "
              f"--serial-port <port>.")

        return _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_SUCCESS"]

    print(f"stored devices in {args.device_dir}:")

    # The files are hand editable, so one mangled entry is reported against its
    # UID and the rest of the listing still prints.
    broken = False

    for uid in uids:
        try:
            serial_port, baud = session.load_device(uid, args.device_dir)
        except session.OperationError as err:
            broken = True

            print(f"  UID {uid:<6} unreadable: {err}")
            continue

        print(f"  UID {uid:<6} {serial_port:<16} {baud} baud")

    if broken:
        return _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_DEVICE_NOT_FOUND"]

    return _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_SUCCESS"]


def cmd_add_device(args):
    """
    cmd_add_device: Connect to a core and remember how to reach it.

    args: The parsed command line.

    returns: An exit status.
    """

    ila = session.Session(args.serial_port, baud=args.baud, debug=args.debug)

    ila.connect()

    try:
        uid = ila.uid

        # Separated from the link errors above deliberately. By this point the
        # core has answered, so a failure here is the filesystem's and saying
        # "link error" would send the user to check the wrong cable.
        try:
            path = session.save_device(uid, args.serial_port, args.baud, args.device_dir)
        except OSError as err:
            raise CliError(f"reached the core on {args.serial_port}, but could not write "
                           f"{session.device_path(uid, args.device_dir)}: {err}",
                           _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_ERROR_ADDING_DEVICE"])
    finally:
        ila.disconnect()

    print(f"added device {uid} on {args.serial_port} at {args.baud} baud, saved to {path}")

    # G_UID is optional and defaults to zero, so two stock cores both land
    # here. Worth saying so at the one moment the user is looking.
    if uid == 0:
        print("note: this core reports UID 0, which is what leaving G_UID unset means. Give "
              "each core its own G_UID to keep several of them apart.")

    return _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_SUCCESS"]


def cmd_gui(args):
    """
    cmd_gui: Hand over to the graphical interface.

    args: The parsed command line.

    returns: An exit status.
    """

    # Only the import is caught. PySide6 is an optional dependency and its
    # absence is worth a message naming the packages, but once the GUI is
    # running its failures are its own and reporting them as "not available"
    # would send the user to --help over a bug.
    try:
        import gui
    except ImportError as err:
        raise CliError(f"the GUI needs PySide6 ({err}). Install it with 'sudo apt install "
                       f"python3-pyside6.qtwidgets python3-pyside6.qtgui', or if your distro "
                       f"doesn't package it (e.g. Ubuntu 22.04), 'pip install PySide6'. "
                       f"Otherwise use the command line, see --help.",
                       _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_GUI_UNAVAILABLE"])

    gui.run_gui(args.waveform_viewer, args.device_dir, args.portmap, debug=args.debug)

    return _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_SUCCESS"]


def do_info(ila):
    """
    do_info: Print what the core reports about itself.

    ila: The connected session.

    returns: None
    """

    info = ila.info()

    print("LibreILA Device Information:")
    print(f"  Serial Port: {info['serial_port']}")
    print(f"  Baud Rate: {info['baud']}")
    print(f"  Device ID: {info['uid']}")
    print(f"  Probe Width: {info['probe_width']} bits")
    print(f"  Sample Buffer Depth: {info['samp_buff_depth']} samples")
    print(f"  Sampling Clock: {info['samp_freq_hz']} Hz")
    print(f"  Register Stride: {info['stride_width']} words "
          f"({info['n_lanes']} carry probe bits)")
    print(f"  Status: {info['status']}")


def do_set_trigger(ila, args):
    """
    do_set_trigger: Apply whichever trigger settings were given.

    ila: The connected session.
    args: The parsed command line.

    returns: None
    """

    applied = ila.set_trigger(condition=args.set_trigger_condition,
                              mask=args.set_trigger_mask,
                              trigger_type=args.set_trigger_type,
                              reduction=args.set_trigger_reduction)

    print(f"trigger set: condition 0x{applied['condition']:x}, "
          f"mask 0x{applied['mask']:x}, TRIG_CFG 0x{applied['mode']:x}")


def do_get_trigger(ila):
    """
    do_get_trigger: Print the trigger setup read back out of the core.

    ila: The connected session.

    returns: None
    """

    cfg = ila.get_trigger()

    print("Trigger configuration:")
    print(f"  Condition: 0x{cfg['condition']:x}")
    print(f"  Mask: 0x{cfg['mask']:x}")
    print(f"  TRIG_CFG: 0x{cfg['mode']:x} ({cfg['reduction']}, {cfg['trigger_type']})")
    print(f"  Position: {cfg['position']} samples")


def _read_progress(words_read, words_total):
    """
    _read_progress: Report how much of the sample buffer has come in.

    words_read: The words read so far.
    words_total: The words the readout covers.

    returns: None
    """

    print(f"\r  {100 * words_read // words_total}% ({words_read}/{words_total} words)",
          end="", file=sys.stderr)

    if words_read == words_total:
        print(file=sys.stderr)


def do_read_data(ila, args):
    """
    do_read_data: Read the capture out and write it as a VCD.

    ila: The connected session.
    args: The parsed command line.

    returns: None
    """

    # The whole buffer comes back over the serial link a packet at a time,
    # which is seconds rather than milliseconds on a stock build, so say what
    # is happening before going quiet.
    words = ila.samp_buff_depth * ila.stride_width
    print(f"reading {ila.samp_buff_depth} samples ({words} words) from {ila.serial_port} "
          f"at {ila.baud} baud...", file=sys.stderr)

    # Only where there is someone to watch it. Redirected stderr gets the line
    # above and then the result, with no carriage returns through the middle.
    progress = _read_progress if sys.stderr.isatty() else None

    result = ila.capture(args.output, progress=progress)

    print(f"wrote {result['path']}: {result['samples']} samples, "
          f"{result['probe_width']} probe bits, trigger at sample {result['trigger_index']}")
    print(f"open it with: {args.waveform_viewer} {result['path']}")


def run(args, parser):
    """
    run: Carry out whichever verbs were given, in EXECUTION_ORDER.

    args: The parsed command line.
    parser: The parser, so a run with no verb at all can print its help.

    returns: An exit status.
    """

    if args.reset:
        return cmd_reset(args)

    if args.gui:
        return cmd_gui(args)

    if args.list_devices:
        return cmd_list_devices(args)

    if args.add_device:
        return cmd_add_device(args)

    sets_trigger = any(value is not None for value in (args.set_trigger_condition,
                                                       args.set_trigger_mask,
                                                       args.set_trigger_type,
                                                       args.set_trigger_reduction))

    verbs = (args.info or args.get_trigger_configuration or args.arm or args.force_trigger
             or args.disarm or args.read_data or sets_trigger
             or args.set_trigger_position is not None
             or args.wait_done is not None)

    # Nothing to do is not an error, but opening a port and closing it again
    # would be a strange way to say so.
    if not verbs:
        parser.print_help()
        return _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_USAGE"]

    serial_port, baud = session.load_device(args.device, args.device_dir)

    # One session for the whole invocation, opened here and dropped at the end.
    # The GUI keeps the same object alive for as long as its tab is connected,
    # which is the only thing the two front ends do differently.
    ila = session.Session(serial_port, baud=baud, portmap_path=args.portmap,
                          uid=args.device, debug=args.debug)

    ila.connect()

    try:
        if args.info:
            do_info(ila)
            return _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_SUCCESS"]

        if args.disarm:
            ila.disarm()
            print("disarmed")

        if sets_trigger:
            do_set_trigger(ila, args)

        if args.set_trigger_position is not None:
            ila.set_trigger_position(args.set_trigger_position)
            print(f"trigger position set to {args.set_trigger_position} samples")

        # After the writes, so it reports what was just asked for
        if args.get_trigger_configuration:
            do_get_trigger(ila)

        if args.arm:
            ila.arm()
            print("armed")

        if args.force_trigger:
            ila.force_trigger()
            print("trigger forced")

        if args.wait_done is not None:
            ila.wait_done(args.wait_done)

            print("capture complete")

        if args.read_data:
            do_read_data(ila, args)
    finally:
        ila.disconnect()

    return _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_SUCCESS"]


def main(argv=None):
    """
    main: Parse the command line and run it.

    argv: The arguments, or None to take them from sys.argv.

    returns: An exit status.
    """

    parser = build_parser()
    args   = parser.parse_args(argv)

    # Only the failures that are understood become a message. A NameError or
    # an AttributeError is a bug in this tool and still earns a traceback,
    # which is what the bare excepts here used to hide.
    try:
        return run(args, parser)
    except CliError as err:
        print(f"E: {err}", file=sys.stderr)
        return err.status
    except session.OperationError as err:
        # The session worked out what was wrong and said so. All that is left is
        # naming the flag that answers it and the status a shell should read.
        hint = _libre_ila_reason_hint.get(err.reason)

        print(f"E: {err}{' ' + hint if hint else ''}", file=sys.stderr)
        return _libre_ila_reason_status[err.reason]
    except RuntimeError as err:
        # The driver raises this for a magic key mismatch, an already armed
        # ILA, or a forced trigger on one that is not armed
        print(f"E: {err}", file=sys.stderr)
        return _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_HARDWARE_ERROR"]
    except ValueError as err:
        print(f"E: {err}", file=sys.stderr)
        return _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_USAGE"]
    except (TimeoutError, OSError) as err:
        # serial.SerialException is an OSError, so a missing or busy port
        # lands here without this file importing pyserial at all
        print(f"E: {err}", file=sys.stderr)
        return _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_LINK_ERROR"]
    except KeyboardInterrupt:
        print("interrupted", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
