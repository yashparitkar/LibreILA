# full/
Placeholder. This is meant to become the end to end test: cocotb driving the
generated core in simulation from the python side, through the same UART
wrapper the python driver talks to on real hardware, rather than through
`hdl/`'s testbenches or `python/`'s stubbed wrapper model.

Needs ghdl (or another cocotb-supported simulator), the generated core, and
cocotb — see `check-cocotb` in the root [Makefile](../../Makefile).

Nothing is wired up yet. Structure, and how this relates to `hdl/` and
`python/`, TBD once cocotb is better understood.
