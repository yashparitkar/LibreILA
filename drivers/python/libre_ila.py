#!/usr/bin/env python3
#####################################################################
# File: libre_ila.py
# Author: Y.U.P. (yashparitkar)
# Created: 2026-07-24 Fri 19:48
# Last Modified: 2026-08-01 Sat 15:31
#
# Description: ILA command line interface
#   This is the entry point. It wires the command line to driver.py, which
#   speaks the register map over UART, and to vcd.py, which turns the raw
#   samples back into named signals.
#
#   Every flag below is a verb, and they are applied in one fixed order
#   whatever order they are given in, see EXECUTION_ORDER. That order is the
#   capture lifecycle, so a whole capture fits in one invocation and equally
#   well across several: nothing about the session is held on the host, the
#   core itself is the record of what was configured and what was caught.
#
#   The GUI is not wired up yet, --gui reports that and exits.
#
# Copyright 2026 Yash Paritkar
# SPDX-License-Identifier: CERN-OHL-P-2.0
#####################################################################

import argparse
import glob
import os
import re
import sys

import driver
import vcd

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

SCRIPT_DIR      = os.path.dirname(os.path.abspath(__file__))
DEFAULT_PORTMAP = os.path.join(SCRIPT_DIR, os.pardir, os.pardir, "codegen", "portmap.csv")
DEFAULT_VCD     = "libreila_capture.vcd"

# One file per device, named by the UID the core reports, holding a single
# "port,baud" line. The UID is what tells two cores in one system apart, so
# it is what --device selects on.
DEVICE_FILE_GLOB = "libreila_device*.txt"
DEVICE_FILE_RE   = re.compile(r"^libreila_device(\d+)\.txt$")

EXECUTION_ORDER = """\
The flags are verbs. Whatever order they are given in, they run in this one:

  1  --reset                     forget every stored device, then stop
  2  --add-device                store the device on --serial-port, then stop
  3  (connect to --device)
  4  --info                      print what the core reports, then stop
  5  --set-trigger-condition
     --set-trigger-mask
     --set-trigger-type
     --set-trigger-reduction     merged into one trigger write
  6  --set-trigger-position
  7  --get-trigger-configuration read the trigger back out of the core
  8  --arm
  9  --force-trigger
  10 --wait-done
  11 --read-data                 write the .vcd

So a whole capture is one line:

  libre_ila.py --set-trigger-condition 0x20000000000000000 \\
               --set-trigger-mask 0x20000000000000000 \\
               --set-trigger-type rising --arm --wait-done --read-data

and, because the core holds the state and not this tool, splitting it across
invocations works just as well: --arm now, --read-data whenever."""


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


def device_path(uid):
    """
    device_path: Name of the file holding one device's connection details.

    uid: The UID the core reports.

    returns: The path, relative to the working directory.
    """

    return f"libreila_device{uid}.txt"


def save_device(uid, serial_port, baud):
    """
    save_device: Record how to reach a device.

    uid: The UID the core reports.
    serial_port: The port the core answers on.
    baud: The baud rate it answers at.

    returns: The path written.
    """

    path = device_path(uid)

    with open(path, "w") as device_file:
        device_file.write(f"{serial_port},{baud}\n")

    return path


def load_device(uid):
    """
    load_device: Read back how to reach a device.

    uid: The UID given to --device.

    returns: (serial_port, baud)
    """

    path = device_path(uid)

    try:
        with open(path, "r") as device_file:
            line = device_file.readline().strip()
    except FileNotFoundError:
        raise CliError(f"no device {uid} here ({path} does not exist). Add one with "
                       f"--add-device --serial-port <port>.",
                       _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_DEVICE_NOT_FOUND"])

    fields = line.split(",")

    # The file is meant to be hand editable, so a mangled one gets a message
    # naming it rather than a traceback out of int()
    if len(fields) != 2 or not fields[0].strip():
        raise CliError(f"{path} should hold one 'port,baud' line, found: {line!r}",
                       _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_DEVICE_NOT_FOUND"])

    try:
        baud = int(fields[1])
    except ValueError:
        raise CliError(f"{path} has a non numeric baud rate: {fields[1]!r}",
                       _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_DEVICE_NOT_FOUND"])

    return fields[0].strip(), baud


def remove_devices():
    """
    remove_devices: Forget every stored device.

    parameters: None

    returns: The list of paths removed.
    """

    removed = []

    # Matched against the glob and then the pattern, so a file that merely
    # starts with the prefix is left alone. Nothing here shells out.
    for path in sorted(glob.glob(DEVICE_FILE_GLOB)):
        if DEVICE_FILE_RE.match(os.path.basename(path)):
            os.remove(path)
            removed.append(path)

    return removed


def load_probes(portmap_path, probe_width):
    """
    load_probes: Read the portmap and check it against the core.

    portmap_path: Path to portmap.csv.
    probe_width: The probe width the core reports.

    returns: The probe list vcd.load_portmap produced.
    """

    try:
        probes = vcd.load_portmap(portmap_path)
    except FileNotFoundError:
        raise CliError(f"no portmap at {portmap_path}. Point --portmap at the file the core "
                       f"was generated from.",
                       _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_PROBEMAP_NOT_FOUND"])
    except ValueError as err:
        raise CliError(f"{portmap_path}: {err}",
                       _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_PROBEMAP_NOT_FOUND"])

    try:
        vcd.check_portmap(probes, probe_width)
    except ValueError as err:
        raise CliError(str(err),
                       _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_PROBEMAP_MISMATCH"])

    return probes


def status_name(status):
    """
    status_name: Human readable form of a driver status code.

    status: The value get_status returned.

    returns: The name, e.g. "ARMED".
    """

    for name, value in driver._libre_ila_status.items():
        if value == status:
            return name.replace("LIBRE_ILA_STATUS_", "")

    return str(status)


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
        help="Which bits of the condition are compared, same format. A zero mask never triggers",
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


def cmd_reset():
    """
    cmd_reset: Forget every stored device.

    parameters: None

    returns: An exit status.
    """

    removed = remove_devices()

    if removed:
        for path in removed:
            print(f"removed {path}")
    else:
        print("no stored devices to remove")

    return _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_SUCCESS"]


def cmd_add_device(args):
    """
    cmd_add_device: Connect to a core and remember how to reach it.

    args: The parsed command line.

    returns: An exit status.
    """

    ila = driver.LibreILA_Driver(args.serial_port, baudrate=args.baud)

    try:
        uid = ila.UID

        # Separated from the link errors above deliberately. By this point the
        # core has answered, so a failure here is the filesystem's and saying
        # "link error" would send the user to check the wrong cable.
        try:
            path = save_device(uid, args.serial_port, args.baud)
        except OSError as err:
            raise CliError(f"reached the core on {args.serial_port}, but could not write "
                           f"{device_path(uid)}: {err}",
                           _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_ERROR_ADDING_DEVICE"])
    finally:
        ila.close()

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

    # gui.py is still a sketch and does not parse, so this catches whatever it
    # raises rather than only the ImportError it would raise once finished.
    try:
        import gui

        run_gui = getattr(gui, "run_gui", None)

        if run_gui is None:
            raise AttributeError("gui.py defines no run_gui()")

        run_gui(args.waveform_viewer)
    except Exception as err:
        raise CliError(f"the GUI is not available yet ({type(err).__name__}: {err}). "
                       f"Everything it would do is on the command line, see --help.",
                       _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_GUI_UNAVAILABLE"])

    return _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_SUCCESS"]


def do_info(ila, serial_port, baud):
    """
    do_info: Print what the core reports about itself.

    ila: The connected driver.
    serial_port: The port it was reached on.
    baud: The baud rate it was reached at.

    returns: None
    """

    print("LibreILA Device Information:")
    print(f"  Serial Port: {serial_port}")
    print(f"  Baud Rate: {baud}")
    print(f"  Device ID: {ila.UID}")
    print(f"  Probe Width: {ila.PROBE_WIDTH} bits")
    print(f"  Sample Buffer Depth: {ila.SAMP_BUFF_DEPTH} samples")
    print(f"  Sampling Clock: {ila.SAMP_FREQ_HZ} Hz")
    print(f"  Register Stride: {ila.stride_width} words ({ila.n_lanes} carry probe bits)")
    print(f"  Status: {status_name(ila.get_status())}")


def _pack(words):
    """
    _pack: Join a trigger vector's words back into one number for printing.

    words: The words, LSB word first.

    returns: The value as an integer.
    """

    return sum(word << (32 * i) for i, word in enumerate(words))


def do_set_trigger(ila, args):
    """
    do_set_trigger: Apply whichever trigger settings were given.

    ila: The connected driver.
    args: The parsed command line.

    returns: None
    """

    # configure_trigger writes the condition, the mask and the mode as one
    # unit, so a run that sets only one of them reads the other two back out
    # of the core first. Nothing is left half written, and nothing has to be
    # remembered between invocations.
    current = ila.get_trigger_configuration()

    cond = current["trigger_cond"]
    mask = current["trigger_mask"]
    mode = current["trigger_mode"]

    limit = 1 << ila.PROBE_WIDTH

    for name, value in (("--set-trigger-condition", args.set_trigger_condition),
                        ("--set-trigger-mask", args.set_trigger_mask)):
        # A bit set above the probe width is not merely ignored. The core zero
        # extends the sample to the full stride before comparing, so a mask
        # bit up there fires an or trigger on the very first sample and stops
        # an and trigger from ever firing.
        if value is not None and value >= limit:
            raise CliError(f"{name} 0x{value:x} sets bits above the core's {ila.PROBE_WIDTH} "
                           f"bit probe. The trigger compares the padding too, so those bits "
                           f"would break it rather than be ignored.",
                           _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_USAGE"])

    if args.set_trigger_condition is not None:
        cond = [(args.set_trigger_condition >> (32 * i)) & 0xffffffff
                for i in range(ila.stride_width)]

    if args.set_trigger_mask is not None:
        mask = [(args.set_trigger_mask >> (32 * i)) & 0xffffffff
                for i in range(ila.stride_width)]

    # The two dimensions of TRIG_CFG are independent, and one not mentioned
    # keeps whatever the core already had.
    if args.set_trigger_reduction is not None:
        if args.set_trigger_reduction == "or":
            mode |= driver._libre_ila_trig_mode["LIBRE_ILA_TRIG_MODE_OR"]
        else:
            mode &= ~driver._libre_ila_trig_mode["LIBRE_ILA_TRIG_MODE_OR"]

    if args.set_trigger_type is not None:
        edge    = driver._libre_ila_trig_mode["LIBRE_ILA_TRIG_EDGE"]
        falling = driver._libre_ila_trig_mode["LIBRE_ILA_TRIG_FALLING"]

        mode &= ~(edge | falling)

        if args.set_trigger_type == "rising":
            mode |= edge
        elif args.set_trigger_type == "falling":
            mode |= edge | falling

    ila.configure_trigger(cond, mask, mode)

    print(f"trigger set: condition 0x{_pack(cond):x}, mask 0x{_pack(mask):x}, "
          f"TRIG_CFG 0x{mode:x}")


def do_get_trigger(ila):
    """
    do_get_trigger: Print the trigger setup read back out of the core.

    ila: The connected driver.

    returns: None
    """

    cfg  = ila.get_trigger_configuration()
    mode = cfg["trigger_mode"]

    reduction = "or" if mode & driver._libre_ila_trig_mode["LIBRE_ILA_TRIG_MODE_OR"] else "and"

    if not mode & driver._libre_ila_trig_mode["LIBRE_ILA_TRIG_EDGE"]:
        trigger_type = "level"
    elif mode & driver._libre_ila_trig_mode["LIBRE_ILA_TRIG_FALLING"]:
        trigger_type = "falling"
    else:
        trigger_type = "rising"

    print("Trigger configuration:")
    print(f"  Condition: 0x{_pack(cfg['trigger_cond']):x}")
    print(f"  Mask: 0x{_pack(cfg['trigger_mask']):x}")
    print(f"  TRIG_CFG: 0x{mode:x} ({reduction}, {trigger_type})")
    print(f"  Position: {cfg['trigger_position']} samples")


def do_read_data(ila, args, serial_port, baud):
    """
    do_read_data: Read the capture out and write it as a VCD.

    ila: The connected driver.
    args: The parsed command line.
    serial_port: The port it was reached on.
    baud: The baud rate it was reached at.

    returns: None
    """

    # Before the readout rather than after it, so a portmap that does not
    # match the core costs nothing instead of a full buffer over the wire
    probes = load_probes(args.portmap, ila.PROBE_WIDTH)

    status = ila.get_status()

    if status != driver._libre_ila_status["LIBRE_ILA_STATUS_DONE"]:
        raise CliError(f"the ILA is {status_name(status)}, not DONE, so the buffer is still "
                       f"being written. Add --wait-done, or --force-trigger if it is armed "
                       f"and the condition has not come up.",
                       _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_HARDWARE_ERROR"])

    # The whole buffer comes back over the serial link a packet at a time,
    # which is seconds rather than milliseconds on a stock build, so say what
    # is happening before going quiet.
    words = ila.SAMP_BUFF_DEPTH * ila.stride_width
    print(f"reading {ila.SAMP_BUFF_DEPTH} samples ({words} words) from {serial_port} "
          f"at {baud} baud...", file=sys.stderr)

    samples, trig_idx = ila.read_data()

    vcd.write_vcd(args.output, samples, trig_idx, probes, ila.SAMP_FREQ_HZ)

    print(f"wrote {args.output}: {len(samples)} samples, {ila.PROBE_WIDTH} probe bits, "
          f"trigger at sample {trig_idx}")
    print(f"open it with: {args.waveform_viewer} {args.output}")


def run(args, parser):
    """
    run: Carry out whichever verbs were given, in EXECUTION_ORDER.

    args: The parsed command line.
    parser: The parser, so a run with no verb at all can print its help.

    returns: An exit status.
    """

    if args.reset:
        return cmd_reset()

    if args.gui:
        return cmd_gui(args)

    if args.add_device:
        return cmd_add_device(args)

    sets_trigger = any(value is not None for value in (args.set_trigger_condition,
                                                       args.set_trigger_mask,
                                                       args.set_trigger_type,
                                                       args.set_trigger_reduction))

    verbs = (args.info or args.get_trigger_configuration or args.arm or args.force_trigger
             or args.read_data or sets_trigger or args.set_trigger_position is not None
             or args.wait_done is not None)

    # Nothing to do is not an error, but opening a port and closing it again
    # would be a strange way to say so.
    if not verbs:
        parser.print_help()
        return _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_USAGE"]

    serial_port, baud = load_device(args.device)

    ila = driver.LibreILA_Driver(serial_port, baudrate=baud)

    try:
        if args.info:
            do_info(ila, serial_port, baud)
            return _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_SUCCESS"]

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
            try:
                ila.wait_done(args.wait_done)
            except TimeoutError:
                # driver._recv raises TimeoutError for a dead link too, so
                # this one is caught where its meaning is known
                raise CliError(f"the ILA did not reach DONE within {args.wait_done} s. It is "
                               f"{status_name(ila.get_status())}; the condition may not have "
                               f"come up, and --force-trigger ends the wait.",
                               _libre_ila_main_status["LIBRE_ILA_MAIN_STATUS_TIMEOUT"])

            print("capture complete")

        if args.read_data:
            do_read_data(ila, args, serial_port, baud)
    finally:
        ila.close()

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
