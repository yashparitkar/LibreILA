This covers `drivers/python/trigger.py`, the translation between per-signal patterns and the flat condition/mask pair the core compares.

The X is the point: a don't-care digit is a mask bit cleared, so one string per signal carries both halves of the trigger vector.

* A don't care is worth one **digit**, not one bit — an `X` in hex clears four mask bits.
* `uint`/`int` cannot express a partial don't care, but an all-X pattern is accepted in every radix, since "not compared" is mask zero. That is what closes the round trip.
* Formatting falls back to binary rather than printing a number that describes a different trigger.
* A pattern wider than its signal is refused, not trimmed — the core compares the padding.
* `test_every_value_of_a_narrow_signal_round_trips` sweeps all 16 values × 16 masks × 4 radices at 4 bits.

Whole-word tests run against the stock 67-bit AXI4S portmap, checking the README's worked example: `axis_tvalid` is bit 65, so condition `0x20000000000000000`.

No pyserial stub and no Qt, because `trigger.py` imports neither — asserted against the source directly.
