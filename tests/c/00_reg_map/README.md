# 00_reg_map

The baremetal driver compiled and run on the host, checked against the register
map rather than against itself.

## Why it can run at all

`drivers/baremetal/core_libre_ila.c` reaches the hardware only through the four
`HW_*_reg()` accessors, so backing those with a flat array is enough to run the
whole driver anywhere a C compiler does. `stub/` supplies what the PolarFire SoC
toolchain would have: the `HAL_*_reg()` macros, `addr_t`, and `readmtime()`.
None of it is Microchip's code, the HAL macros are reimplemented because the
contract they impose is itself part of what is under test:

> `HAL_get_32bit_reg(BASE, REG_NAME)` pastes `REG_NAME##_REG_OFFSET` at
> preprocess time. An offset worked out at runtime cannot go through it.

That is the constraint the whole map ordering answers. Offsets in
`core_libre_ila_regs.h` are relative to their block, and the part that moves
with the probe width lives in the block's base address instead, so every named
register keeps using `HAL_*` and only the two indexed blocks, the trigger mask
words and the sample buffer, go through `HW_*` with a computed address.

## What it covers

Register indices are computed in `tb.c` from the map in the
[datasheet](../../../docs/datasheet.pdf), not taken from the driver, so a driver that derives
them wrong disagrees with this file instead of agreeing with itself. Same
principle as `identity_regs()` in `tests/python/00_pkt_format`.

| Case | What it pins |
|------|--------------|
| `geometry` | `init()` derives lanes, stride and all four block bases from what the core reports, nothing from a `#define` |
| `control writes` | `TRIG_POS`/`ARM_FT`/`TRIG_CFG`/`TRIG_COND` land in the input block, `TRIG_MASK` a whole stride above `TRIG_COND` |
| `argument checks` | wrong word counts, undefined `TRIG_CFG` bits, `FALLING` without `EDGE`, NULL arguments — and that a refused call writes nothing |
| `init rejections` | bad magic key, and a width or depth the HDL could not have been elaborated with |
| `status` | `DONE`/`TRIGD`/`ARMED` decode order, the arm and force-trigger guards, and that `wait_done` times out |
| `readout` | circular buffer unrolled from the oldest sample, trigger index rebased onto that ordering, stride padding dropped |
| `second instance` | two cores of different probe widths driven from one binary |
| `sizing macros` | `LIBRE_ILA_*_FOR()` agree with the stride the driver derives at runtime, across nine widths |

The `second instance` case is the one that could not have passed before the
register map was reordered and the offsets moved into the instance. While the
offsets were macros they came from a single global width, so a second core of a
different width had nowhere to put its geometry and `init()` on it would have
had to fail.

## Running it

```sh
make sim        # from here, or `make sim-c` from the project root
```

`make sim` at the project root runs this alongside the python tests before the
GHDL simulations, since both take milliseconds.

## Confirming it still bites

The suite was checked against three injected regressions, each of which it
catches:

* `mask_base` computed with a fixed stride instead of the instance's — fails
  `second instance`
* `read_data` accepting an over-sized buffer instead of an exact one — fails
  `readout`, which is the case where the buffer gets filled at one row length
  and indexed at another
* an input-block write aimed at the peripheral base instead of `ip_base` —
  fails `control writes`

Worth repeating that exercise after changing anything in the addressing. A test
that cannot fail is not covering anything.
