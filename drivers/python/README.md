# LibreILA Python driver
This directory contains the python driver for the LibreILA IP. The driver is used to control the LibreILA when instantiated as libre_ila_uart.vhdl

| File | What it is |
|------|------------|
| [libre_ila.py](libre_ila.py) | The command line front end. Every verb below lives here |
| [session.py](session.py) | One connection to one core, and every operation either front end can ask of it |
| [driver.py](driver.py) | The register map over UART. Knows nothing about what the probe bits mean |
| [vcd.py](vcd.py) | The portmap and the VCD. Turns raw samples back into named signals |
| [trigger.py](trigger.py) | Per-signal trigger patterns, `0b00101xxxx` and the like, to and from the condition/mask pair |
| [gui.py](gui.py) | The graphical front end, `--gui` |

`session.py` sits between the front ends and the two layers below, because the front ends disagree about **lifetime and nothing else**. The command line builds a session, runs its verbs and drops it, so a capture still spans invocations by leaving the state in the core. The GUI keeps one alive per tab, because a window that reopened the port on every button press would pay for the identity block each time and could not hold the port across two actions at all.

Neither of those is a different design. The core is the record either way; a session is just how long the host keeps the port open while reading it. So nothing in `session.py` prints, exits or knows what a widget is: a failure the host reasoned about becomes an `OperationError` carrying a symbolic reason, and the front end decides whether that reason is an exit status or a line in a status bar. The messages state the fact and stop, because the answer to a capture that has not finished is `--wait-done` here and a button there.

**One session may only be touched by one thread at a time.** The wrapper is a request/response protocol over a single port and `_transact` flushes the input buffer on the way in, so two overlapping operations desync the wrapper and each other. Sessions are independent of one another, one port each. `Session.capture` takes a `progress` callback for the same reason: the readout is the one operation that takes seconds rather than a packet, so an event driven front end runs it off the thread serving its event loop. `Session.wait_done` is the blocking alternative and is for a front end with nothing else to do, since it polls in a loop. An event driven one polls `Session.status` on a timer instead, which it wants anyway to keep a state display honest.

## Requirements
Following packages are required:
* pyserial: `sudo apt install python3-serial`
* PySide6, for `--gui` only: `sudo apt install python3-pyside6.qtwidgets python3-pyside6.qtgui`

PySide6 ships one package per Qt module on Debian and Ubuntu, so `python3-pyside6` is not a package and `python3-pyside6.qtcore` on its own is not enough. Everything except `--gui` works without either.

Ubuntu 22.04 predates PySide6's apt packaging, so those packages don't exist there; use `pip install PySide6` instead. The root [Makefile](../../Makefile) and [tests/python/05_gui](../../tests/python/05_gui/) both resolve PySide6 from `venv-libreila` at the repo root if it's set up: `python3 -m venv venv-libreila && ./venv-libreila/bin/pip install PySide6`.

## Usage
Tell the tool about a core once, then talk to it by the UID it reports:

```
./libre_ila.py --add-device --serial-port /dev/ttyUSB0 --baud 115200
./libre_ila.py --device 0 --info
```

`--add-device` connects, reads the UID back and writes `capture/libre_ila_device<UID>.txt`, holding one `port,baud` line. `--reset` forgets every stored device, and `--device-dir` puts the store somewhere else.

Everything these tools write lands in `capture/` under the working directory — the device store, the `.vcd` and `--debug`'s log — so a run leaves one directory behind rather than scattering files. It is created when something is written, never on import, and `make clean` at the repo root removes the one a run from here leaves.

The GUI will read the same store, so a core added on the command line comes up as a tab and one added in a tab is reachable with `--device` — which only holds while both are pointed at the same place. That is what `--device-dir` is for: the working directory is the right default for a tool run from a shell and the wrong one for a window started from a desktop entry.

**`--device` selects by UID, not by the order devices were added.** A core built without a `G_UID` reports 0, which is why `--device` defaults to 0. Give each core in a system its own `G_UID` in [configuration.csv](../../codegen/configuration.csv) and they stay apart.

### Running a capture
The flags are verbs. Whatever order they are given in, they are applied in this one:

| # | Flag | Behaviour |
|---|------|-----------|
| 1 | `--reset` | forget every stored device, then stop |
| 2 | `--add-device` | store the device on `--serial-port`, then stop |
| 3 | | connect to `--device` |
| 4 | `--info` | print what the core reports, then stop |
| 5 | `--disarm` | cancel a capture in progress, before the trigger writes so a retry is one line |
| 6 | `--set-trigger-condition` / `--set-trigger-mask` / `--set-trigger-type` / `--set-trigger-reduction` | merged into one trigger write |
| 7 | `--set-trigger-position` | where the trigger sits in the buffer, in samples |
| 8 | `--get-trigger-configuration` | read the trigger back out of the core |
| 9 | `--arm` | |
| 10 | `--force-trigger` | |
| 11 | `--wait-done [SECONDS]` | default 10 |
| 12 | `--read-data` | write the `.vcd` to `--output` |

So a whole capture is one line:

```
./libre_ila.py --set-trigger-condition 0x20000000000000000 \
               --set-trigger-mask 0x20000000000000000 \
               --set-trigger-type rising --arm --wait-done --read-data -o cap.vcd
```

and splitting it across invocations works just as well — `--arm` now, `--read-data` whenever. Nothing about the session is kept on the host: the core holds the trigger setup, the state and the samples, and the driver reads its whole register map back out of the core at startup. That is also why re-synthesising with a different probe width needs no change here.

### Configuring the trigger
`--set-trigger-condition` is the pattern the probe word is compared against and `--set-trigger-mask` picks which of its bits are compared. Both take one number in any base — `0x...`, `0b...`, `0o...` or decimal — covering the whole probe word, and **do not use the portmap**: bit 0 is the first signal listed there. For the stock AXI4S build `axis_tvalid` is bit 65, so triggering on it rising is:

```
--set-trigger-condition 0x20000000000000000 --set-trigger-mask 0x20000000000000000 \
--set-trigger-type rising
```

`--set-trigger-type` is `level`, `rising` or `falling`, and `--set-trigger-reduction` is `and` (every masked bit matches) or `or` (any one of them). They are independent, and whichever you leave out keeps whatever the core already had — the trigger registers read back, so setting one field does not disturb the rest.

A value with bits above the probe width is refused rather than trimmed. The core zero-extends each sample to the full register stride before comparing, so a mask bit up in the padding fires an `or` trigger on the very first sample and stops an `and` trigger from firing at all.

### The .vcd
`--read-data` names the signals from `portmap.csv`, found via `--portmap` and defaulting to [codegen/portmap.csv](../../codegen/portmap.csv). The widths it describes must add up to the probe width the core reports, or the readout is refused — that check is what catches a portmap which has drifted from the synthesised core, since the bits would otherwise still slice cleanly, just at the wrong boundaries.

Note that `code_generator.py` defaults `--portmap` to `templates/default_portmap.csv` while the driver defaults to `codegen/portmap.csv`. They ship identical, but if you edit one, pass `--portmap` to both tools.

The file is delta encoded: the first sample states every signal, after that only what moved. Timestamps are in picoseconds, one sample apart at the sampling clock the core reports. The trigger is carried as an extra 1-bit wire named `trigger` that pulses for exactly the sample it fired on, since VCD has no marker of its own.

### The GUI
`./libre_ila.py --gui` opens one tab per stored device, titled `CONNECTED ILA<UID>` or `DISCONNECTED ILA<UID>`. A tab owns one session for as long as it lives, so the port is opened once and held rather than reopened per button press.

It reads the same device store as `--device`, so `--device-dir` has to agree between the two. `--waveform-viewer` and `--portmap` are passed through.

To see it without hardware, `make gui` in [tests/python/05_gui](../../tests/python/05_gui/) runs it against fake cores.

This first pass covers connect, arm, disarm, force trigger, capture with a progress bar, gtkwave, and a read-only view of the trigger. The per-signal conditions table is next; the translator behind it is already in [trigger.py](trigger.py).

### Debugging the link
`--debug` logs every UART transaction to `capture/libre_ila.log`. It works with every verb and with `--gui`, where all tabs share the one file.

```
2026-08-13 12:49:30 /dev/ttyACM0 connect baudrate=115200
2026-08-13 12:49:30 /dev/ttyACM0 TX read  addr=0x00000004 count=5 bytes=55 05 00 00 00 04
2026-08-13 12:49:30 /dev/ttyACM0 RX header bytes=aa 85 00 00 00 04
2026-08-13 12:49:30 /dev/ttyACM0 RX payload words=0xb01dface 0x05f5e100 0x00000043 0x00000800 0x00000000
```

Every line carries the port, so two tabs writing at once stay apart, and the file is appended to and flushed per line, so a run that hangs or is killed still leaves everything up to that point on disk.

`ERR` lines carry the failure, and a `RESYNC dropped N stale bytes` line follows one when the driver drained the link to get back in step. **The byte counts are worth reading, not just the errors:** the wrapper answers a read with a 6 byte header and 4 bytes per word, so a reply that is short or long for the request it followed says the two ends disagree about which request is being served, rather than that one reply got corrupted.

### Exit statuses
| | |
|---|---|
| 0 | success |
| 2 | usage error |
| 3 | could not add the device |
| 4 | no such stored device, or its file is unreadable |
| 5 | no portmap |
| 6 | the portmap does not match the core |
| 7 | link error: no port, busy port, timeout or a desynced reply |
| 8 | the capture did not reach DONE in time |
| 9 | the core refused the operation, e.g. arming an armed ILA or disarming an idle one |
| 10 | the GUI is not available |

## Setting the signal mapping
The signal mapping is read from the portmap.csv file. It has three columns, namely, signal, width, type.

`type` is the direction the signal has on the core's `probe_slave_` side, which is the side facing the **master** of the probed link. So for AXI4S the portmap carries the directions an AXI4S **slave** would have: TVALID in, TREADY out.

The signals are written LSB aligned, i.e., if the stride of the AXI registers is 2, then we have 63:0 signals. The signal with range 3:0 should be written first, then signal 4:4.

* signal: the name of the signal to be displayed in the .vcd
* width: width of the signal in bits
* type: `in`, `out` or `mon`. `mon` is a parallel tap, present on the slave side only. `inout` is not accepted, see the code generation section of [codegen/README.md](../../codegen/README.md) for why and what to use instead.

For example, the portmap.csv file for the AXI4S will be as follows:
```portmap.csv
axis_tdata,64,in
axis_tlast,1,in
axis_tvalid,1,in
axis_tready,1,out
```

Blank lines and lines starting with `#` are skipped, but only in column 0, and the fields are not whitespace stripped — `axis_tdata, 64, in` is rejected. Both are true of the generator's parser too, deliberately: this file is parsed once to build the hardware and once to read it back, and the two have to accept exactly the same set of files.
