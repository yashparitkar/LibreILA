UNIT       := libre_ila.py
TOP        := tb
PYTHON     := python3
DRIVER_DIR := ../../../drivers/python

.PHONY: all sim clean

all: sim

# Host side test, it drives the command line end to end against the same model
# of the wrapper 00_pkt_format checks the packet format with. No GHDL, no
# generated core and no real port, so every verb runs here.
sim:
	$(PYTHON) $(TOP).py

clean:
	rm -rf __pycache__ $(DRIVER_DIR)/__pycache__
