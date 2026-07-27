# File: Makefile
# Author: Y.U.P. (paritkary25)
# Last Modified: 2026-07-27 Mon 15:59
#
# This is project file makefile

#

TEST_DIRS := $(wildcard tests/0*/)
DOC_DIRS  := docs/tex

.PHONY: all configure sim clean $(TEST_DIRS) $(DOC_DIRS)

all: all configure sim clean

# configure: configure the the project
configure:

# sim: runs all the simulations in tests/ and generates waveforms:
sim:

# clean: cleans up all the generated files in the project, recursing into
# every test/doc directory that has its own Makefile with a clean target
clean:
	echo "Cleaning up the project..."
	for d in $(DOC_DIRS) $(TEST_DIRS); do $(MAKE) -C $$d clean; done
	rm -rf gen

