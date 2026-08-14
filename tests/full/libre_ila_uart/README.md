# libre_ila_uart full hardware test

## What this test is for

This test runs LibreILA end to end on a real FPGA:

```text
probed AXI4Stream link -> sampling buffer -> AXI4-Lite/APB registers -> UART -> host driver -> VCD
```

A VCD that matches the traffic that was asked for is the pass criterion: it is only possible if the probe packing, trigger comparator, buffer addressing, register map, UART framing, driver byte order and VCD writer all agree.

## Why axi4smaster_pktgen is the stimulus

The data comes from `axi4smaster_pktgen` ([IP source](https://github.com/yashparitkar/hdl_lib/tree/main/axi4smaster_pktgen)), which produces traffic that is known before the capture is taken, so the waveform can be checked:

- TDATA is a counter, so a dropped, duplicated or byte-swapped sample breaks the sequence.
- TLAST lands at a known period; a misplaced one means the wrong bit is being probed.
- Density gaps TVALID, giving the trigger an edge and proving idle cycles are sampled too.
- TREADY is real back-pressure, so the capture shows the handshake the design saw.
- 64 bits of TDATA plus TLAST, TVALID and TREADY is 67 bits — not a multiple of the 32-bit readback
  word, the awkward case, on purpose.

## Configuration under test

From the built design, not the VHDL defaults:

| Parameter | Value |
|---|---|
| Board / device | PolarFire SoC Discovery Kit, MPFS095T-1FCSG325E |
| `G_PROBE_WIDTH` | 67 (TDATA[63:0], TLAST, TVALID, TREADY) |
| `G_SAMP_BUFF_DEPTH` | 2048 samples |
| `G_SAMP_CLK_FREQ` / `G_AXIL_CLK_FREQ` | 100 MHz / 100 MHz |
| `G_BAUD_RATE` | 115200 |
| `G_UID` | 0 |
| `G_EXTERNAL_TRIG` | 0 |
| Libero / SoftConsole | v2025.2 / v2022.2 |

The design also carries the MSS, a heartbeat IP and the pktgen. The MSS UART drives the pktgen
menu; a USB-TTL adapter carries the LibreILA link to the host.

## Running it

Chapter 2 (*Getting Started*) of [`docs/manual.pdf`](../../../docs/manual.pdf) has the step by step instructions with screenshots - pktgen settings, trigger and all

## Expected result

ILA status goes `ARMED` to `DONE` as soon as the transfer is fired, and the saved VCD holds a 2048-sample window (20.47 us at 100 MHz) with the trigger marker at the position that was set, so
pre- and post-trigger data are both present. TDATA counts up, TLAST sits on the packet boundaries,
TVALID is gapped by the requested density. A stalled readback, a shifted trigger position or
scrambled TDATA is a failure of the chain, not of the stimulus.

## Directory structure

```text
libre_ila_uart/
├── libre_ila_uart_libero    : Libero full project
├── libre_ila_uart_sc        : Softconsole project
├── ref.axi4smaster_pktgen   : Symlink to the stimulus IP source
├── ref.LibreILA_full.zip    : Archived reference build
└── README.md                : This file
```
