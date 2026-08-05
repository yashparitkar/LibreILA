UNIT       := gui.py
TOP        := tb
DEMO       := demo
SHOTS      := shots
DRIVER_DIR := ../../../drivers/python
VENV := ../../../venv-libreila

# PySide6 resolution: use the system python3 if it already has the widget
# packages, otherwise venv-libreila/ at the repo root if that's been set up
# (Ubuntu 22.04 predates PySide6's apt packaging, so a venv is how it gets
# installed there), otherwise fall back to python3 anyway and let check-pyside6
# below explain what's missing.
ifeq ($(shell python3 -c "import PySide6.QtWidgets" 2>/dev/null && echo yes),yes)
  PYTHON := python3
else ifneq ($(wildcard $(VENV)/bin/python3),)
  PYTHON := $(VENV)/bin/python3
else
  PYTHON := python3
endif

.PHONY: all sim gui shots clean check-pyside6

all: sim

# check-pyside6: prints where PySide6 is missing from, before the recipe below
# runs and either works or (sim only) hits tb.py's own skip.
check-pyside6:
	@$(PYTHON) -c "import PySide6.QtWidgets" >/dev/null 2>&1 || \
	  echo "PySide6 not found for python3 or in $(VENV)/; install it with:" \
	       "python3 -m venv $(VENV) && $(VENV)/bin/pip install PySide6"

# Host side test of the graphical front end, run offscreen so it needs no
# display. PySide6's widget packages are a GUI-only dependency, so this skips
# rather than fails where they are absent.
sim: check-pyside6
	QT_QPA_PLATFORM=offscreen $(PYTHON) $(TOP).py

# gui: open the real GUI against fake cores, no hardware and no display server
# tricks. This is the one to run to look at it. Not part of sim, it blocks.
gui: check-pyside6
	$(PYTHON) $(DEMO).py

# shots: the same thing offscreen, written out as .png so a change to the
# layout can be looked at without a display
shots: check-pyside6
	$(PYTHON) $(DEMO).py --shots $(SHOTS)

clean:
	rm -rf __pycache__ $(SHOTS) $(DRIVER_DIR)/__pycache__
