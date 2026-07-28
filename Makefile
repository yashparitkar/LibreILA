# File: Makefile
# Author: Y.U.P. (paritkary25)
# Last Modified: 2026-07-27 Mon 21:07
#
# This is project file makefile

#

TEST_DIRS := $(wildcard tests/0*/)
DOC_DIRS  := docs/tex
GEN_DIRS := $(wildcard gen/*)

.PHONY: all configure sim clean $(TEST_DIRS) $(DOC_DIRS)

all: sim

# configure: configure the the project
configure:

# sim: runs all the simulations in tests/ and generates waveforms:
sim: configure 
	@echo "Running all the simulations..."
	@for d in $(TEST_DIRS); do $(MAKE) -C $$d sim || exit 1; done

# clean: cleans up all the generated files in the project, recursing into
# every test/doc directory that has its own Makefile with a clean target
clean:
	echo "Cleaning up the project..."
	for d in $(DOC_DIRS) $(TEST_DIRS); do $(MAKE) -C $$d clean; done
	rm -rf  $(GEN_DIRS)

