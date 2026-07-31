# File: Makefile
# Author: Y.U.P. (yashparitkar)
#
# Host build of the baremetal driver. No cross toolchain and no ghdl, the HAL
# is stubbed under stub/ and the register file is an array, so this runs
# anywhere a C compiler does.

CC        ?= cc
DRIVER    := ../../../drivers/baremetal
STUB      := stub
TOP       := tb
SRC       := $(TOP).c $(STUB)/fake_regs.c $(DRIVER)/core_libre_ila.c
CFLAGS    := -std=c99 -Wall -Wextra -Wpedantic -Wshadow -O1
INCLUDES  := -I$(DRIVER) -I$(STUB) -I$(STUB)/hal

.PHONY: all sim clean

all: sim

# The driver's own headers come first on the include path, the stub only
# supplies what the PolarFire SoC toolchain would have.
$(TOP): $(SRC) $(wildcard $(STUB)/*.h) $(wildcard $(STUB)/hal/*.h) \
        $(DRIVER)/core_libre_ila.h $(DRIVER)/core_libre_ila_regs.h
	$(CC) $(CFLAGS) $(INCLUDES) $(SRC) -o $@

sim: $(TOP)
	./$(TOP)

clean:
	rm -f $(TOP)
