This covers `drivers/python/gui.py`, driven offscreen against the wrapper model [00_pkt_format](../00_pkt_format/README.md) validates.

```
make sim     # the tests, offscreen
make gui     # open the real GUI against fake cores, no hardware needed
make shots   # the same, rendered to shots/*.png
```

`make gui` is the one to run to look at it. `demo.py` puts two fake cores in a throwaway device store and starts the real `run_gui`, so nothing here needs a board.

* **One port per tab** is the property the whole design rests on, so `Port` counts opens: a connect, five polls, a trigger read, arm and force must come to **one**.
* **The poll timer stops for the whole readout.** Both are requests on one port and `_transact` flushes the input buffer, so an overlapping poll would desync the wrapper.
* **A tab starts disconnected** — opening the window opens no ports.
* **Refusals reach the status bar, not the event loop.** Disarming an idle core raises `RuntimeError` in the driver; the window has to survive it.
* `test_a_capture_before_done_is_reported_with_its_remedy` is the reason mechanism end to end: the session says "not DONE", the GUI adds the button to press.

PySide6 splits into one package per Qt module, so QtCore says nothing about QtWidgets. The suite skips where the widget packages are absent, since `make sim-python` is documented as needing python3 and nothing else. `gui` is imported *outside* that guard on purpose — a `gui.py` that will not import is a failure, not a reason to skip.
