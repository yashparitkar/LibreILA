# File: Makefile
# Author: Y.U.P. (yashparitkar)
# Last Modified: 2026-08-05 Wed 15:41
#
# This is project file makefile

# tests/ is split by what a test needs to run, not by what it covers. The GHDL
# simulations under tests/hdl/ need ghdl and the generated core, the host side
# tests under tests/python/ and tests/c/ need neither, so the three can be run
# separately. A directory counts as a test if it carries its own Makefile,
# which keeps the numbering a convention rather than something the build
# depends on.
HDL_TEST_DIRS := $(dir $(wildcard tests/hdl/*/Makefile))
PY_TEST_DIRS  := $(dir $(wildcard tests/python/*/Makefile))
C_TEST_DIRS   := $(dir $(wildcard tests/c/*/Makefile))
TEST_DIRS     := $(HDL_TEST_DIRS) $(PY_TEST_DIRS) $(C_TEST_DIRS)
DOC_DIRS  := docs/tex
CODEGEN   := codegen/code_generator.py
GEN_AXIS  := codegen/gen_axis
GEN_USER  := codegen/gen
GEN_STAMP := $(GEN_AXIS)/.stamp

# Everything the stock build is made of. Touch any of it and configure
# regenerates gen_axis/, touch none of it and the generator does not run at
# all. The test Makefiles carry the same rule, so running a single test
# directly stays just as up to date as going through this file.
GEN_DEPS  := $(CODEGEN) $(wildcard hdl/*.vhdl) $(wildcard codegen/templates/*.csv)

# One venv for whatever optional dependency the system python3 doesn't have:
# PySide6 (Ubuntu 22.04 predates its apt packaging) and, later, cocotb.
# tests/python/05_gui carries the actual PySide6 resolution logic and needs to
# run standalone anyway; this is a placeholder for a future top level gui
# target, which will want the same venv.
VENV := venv-libreila

.PHONY: all configure sim sim-hdl sim-python sim-c check-pyside6 check-cocotb clean $(TEST_DIRS) $(DOC_DIRS)

all: sim

# configure: bring the stock build of the core up to date
configure: $(GEN_STAMP)

# The default portmap and configuration, i.e. the stock AXI4S probe. The
# tests read this directory instead of hdl/ so that what is simulated is
# what the generator actually emits.
$(GEN_STAMP): $(GEN_DEPS)
	python3 $(CODEGEN)
	@touch $@

# sim: runs every test in tests/ and generates waveforms. The host side tests
# go first, they take milliseconds, so a broken packet format or register map
# fails here instead of after the simulations have run.
sim: sim-python sim-c sim-hdl

# sim-hdl: the GHDL simulations, these need ghdl and the generated core
sim-hdl: configure
	@echo "Running the HDL simulations..."
	@for d in $(HDL_TEST_DIRS); do $(MAKE) -C $$d sim || exit 1; done

# sim-python: the host side tests, no ghdl and no generated core, so this
# target is the one to run when the toolchain is not available
sim-python:
	@echo "Running the host side tests..."
	@for d in $(PY_TEST_DIRS); do $(MAKE) -C $$d sim || exit 1; done

# sim-c: the baremetal driver compiled and run on the host against a stubbed
# HAL, so it needs a C compiler and nothing from the PolarFire toolchain
sim-c:
	@echo "Running the baremetal driver tests..."
	@for d in $(C_TEST_DIRS); do $(MAKE) -C $$d sim || exit 1; done

# check-pyside6: not part of any build, just tells the user how to get PySide6
check-pyside6:
	@python3 -c "import PySide6.QtWidgets" >/dev/null 2>&1 || [ -x $(VENV)/bin/python3 ] || \
	  { echo "PySide6 not found for python3 or in $(VENV)/."; \
	    echo "Install it with: python3 -m venv $(VENV) && $(VENV)/bin/pip install PySide6"; }

# check-cocotb: not part of any build yet, tells the user how to get cocotb.
# tests/full/ will want it once there is something there to run with it.
check-cocotb:
	@python3 -c "import cocotb" >/dev/null 2>&1 || [ -x $(VENV)/bin/python3 ] || \
	  { echo "cocotb not found for python3 or in $(VENV)/."; \
	    echo "Install it with: python3 -m venv $(VENV) && $(VENV)/bin/pip install cocotb"; }

# Where the python driver writes the device store, the .vcd and --debug's log.
# It follows the working directory, so clean only knows about the one a run
# from drivers/python leaves behind.
CAPTURE := drivers/python/capture

# clean: cleans up all the generated files in the project, recursing into
# every test/doc directory that has its own Makefile with a clean target
clean:
	echo "Cleaning up the project..."
	for d in $(DOC_DIRS) $(TEST_DIRS); do $(MAKE) -C $$d clean; done
	rm -rf $(GEN_AXIS) $(GEN_USER) $(CAPTURE)
