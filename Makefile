# File: Makefile
# Author: Y.U.P. (yashparitkar)
# Last Modified: 2026-07-29 Wed
#
# This is project file makefile

#

TEST_DIRS := $(wildcard tests/0*/)
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

.PHONY: all configure sim clean $(TEST_DIRS) $(DOC_DIRS)

all: sim

# configure: bring the stock build of the core up to date
configure: $(GEN_STAMP)

# The default portmap and configuration, i.e. the stock AXI4S probe. The
# tests read this directory instead of hdl/ so that what is simulated is
# what the generator actually emits.
$(GEN_STAMP): $(GEN_DEPS)
	python3 $(CODEGEN)
	@touch $@

# sim: runs all the simulations in tests/ and generates waveforms:
sim: configure
	@echo "Running all the simulations..."
	@for d in $(TEST_DIRS); do $(MAKE) -C $$d sim || exit 1; done

# clean: cleans up all the generated files in the project, recursing into
# every test/doc directory that has its own Makefile with a clean target
clean:
	echo "Cleaning up the project..."
	for d in $(DOC_DIRS) $(TEST_DIRS); do $(MAKE) -C $$d clean; done
	rm -rf $(GEN_AXIS) $(GEN_USER)
