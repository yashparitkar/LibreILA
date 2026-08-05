UNIT       := trigger.py
TOP        := tb
PYTHON     := python3
DRIVER_DIR := ../../../drivers/python

.PHONY: all sim clean

all: sim

# Host side test of the per signal trigger patterns. Neither Qt nor pyserial is
# imported by the unit or by this file, so it runs anywhere python3 does.
sim:
	$(PYTHON) $(TOP).py

clean:
	rm -rf __pycache__ $(DRIVER_DIR)/__pycache__
