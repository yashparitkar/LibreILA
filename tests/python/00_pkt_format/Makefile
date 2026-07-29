UNIT       := driver.py
TOP        := tb
PYTHON     := python3
DRIVER_DIR := ../../../drivers/python

.PHONY: all sim clean

all: sim

# Host side test, it checks the python driver's packet format against a model
# of the wrapper's parser. No GHDL and no generated core, so unlike the other
# test directories this one has no dependency on codegen/gen_axis.
sim:
	$(PYTHON) $(TOP).py

clean:
	rm -rf __pycache__ $(DRIVER_DIR)/__pycache__
