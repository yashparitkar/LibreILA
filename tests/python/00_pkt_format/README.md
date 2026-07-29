This checks the python driver's `read_regs`/`write_regs` against a byte level model of the wrapper's packet parser, so the two ends of the UART link cannot drift apart without a test failing.

Unlike the rest of `tests/`, this one runs on the host: no GHDL, no `codegen/gen_axis`, and pyserial is stubbed out so nothing opens a real port. `make sim` is just `python3 tb.py`.

`FakeWrapper` mirrors `p_main` in [libre_ila_uart.vhdl](../../../hdl/libre_ila_uart.vhdl), and the expected request bytes are the ones the reference procedures `uart_ila_read`/`uart_ila_write` in [06_sim_libre_ila_uart](../../hdl/06_sim_libre_ila_uart/tb.vhdl) put on the wire. If the packet format changes, that testbench and this one both have to change with it.

Worth knowing about the cases it covers:

* The response header comes back on a **write** as well as a read, so a write that does not drain its 6 byte ack desyncs the next transaction.
* `#words` is a 7 bit field, so transfers longer than 127 words are split across packets. Every full sample buffer readout takes this path, a stock 2048 deep buffer at stride 4 is 8192 words, or 65 packets.
* Timeouts and desyncs both raise, and `TimeoutError` is a subclass of `OSError`, so a caller that restarts on a lost transaction needs only one except clause.
