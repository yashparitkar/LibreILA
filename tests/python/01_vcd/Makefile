UNIT       := vcd.py
TOP        := tb
PYTHON     := python3
DRIVER_DIR := ../../../drivers/python

.PHONY: all sim clean

all: sim

# Host side test, it checks the portmap parsing and the VCD writing against a
# second reader of the same file. No GHDL and no generated core, and unlike
# 00_pkt_format not even a pyserial stub: vcd.py imports neither driver.py nor
# serial, which this test asserts.
sim:
	$(PYTHON) $(TOP).py

clean:
	rm -rf __pycache__ $(DRIVER_DIR)/__pycache__
