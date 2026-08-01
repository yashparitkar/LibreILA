This checks `drivers/python/vcd.py`: the portmap parsing that turns `portmap.csv` into a bit layout, and the VCD writing that turns raw samples back into named signals.

Two things make this worth testing rather than eyeballing a waveform.

The first is that the portmap is parsed **twice** in this project, once by [code_generator.py](../../../codegen/code_generator.py) to build the hardware and once by `vcd.py` to name the bits coming back out of it. Its own comment says so: *"Reported here only, the drivers read the same portmap and redo this themselves."* Nothing links the two parsers, so `TestPortmap` pins the driver's copy to the generator's rules, quirks included — a `#` is only a comment in column 0, and fields are not whitespace stripped, so `axis_tdata, 64, in` is rejected by both. A driver that accepted a file the generator rejects would name signals for a core that cannot be built.

The second is that a wrong bit layout does not look like an error. It produces a waveform, just one where the boundaries fall in the wrong places, so `TestProbeLayout` pins the stock 67-bit AXI4S build against the table in [datasheet.tex](../../../docs/tex/datasheet.tex) — `axis_tdata` 63:0, `tlast` 64, `tvalid` 65, `tready` 66 — and `TestPortmapCheck` covers the width cross-check that catches a `portmap.csv` which has drifted from the synthesised core.

`parse_vcd` in `tb.py` is a second, independent reader of the format, in the same spirit as `FakeWrapper` in [00_pkt_format](../00_pkt_format/README.md) being a second implementation of the wrapper's parser. The round trip through it is what proves the delta encoding actually reconstructs the capture rather than merely looking plausible.

Worth knowing about the cases it covers:

* A signal that never changes is written **once**, in `$dumpvars`, and never again. That is the whole point of the encoding: a full buffer of a mostly idle bus should not cost a line per sample.
* The last sample always gets its `#t`, even when nothing changed there, or the trace would appear to stop at the final edge and the capture would look shorter than it is.
* The trigger is a synthetic 1-bit wire that pulses for exactly one sample. VCD has no marker concept, so this is the only way to carry the trigger position into a viewer.
* Identifier codes roll over to two characters past 94 signals, which a wide portmap reaches.

Unlike `00_pkt_format` this test installs no pyserial stub, because `vcd.py` imports neither `serial` nor `driver`. `test_the_vcd_path_needs_no_pyserial` asserts that directly, which is stronger than stubbing it would be.
