UNIT       := libre_ila_uart
TOP        := tb
SRC        := ../../hdl/$(UNIT).vhdl tb.vhdl
WORKDIR    := work
GHDLFLAGS  := --std=08 --workdir=$(WORKDIR)
WAVE       := $(TOP).ghw

.PHONY: all sim wave clean

all: sim

$(WORKDIR):
	mkdir -p $(WORKDIR)

sim: $(WORKDIR)
	ghdl -a $(GHDLFLAGS) $(SRC)
	ghdl -e $(GHDLFLAGS) $(TOP)
	ghdl -r $(GHDLFLAGS) $(TOP) --wave=$(WAVE)

wave: sim
	gtkwave $(WAVE) &

clean:
	rm -rf $(WORKDIR) $(WAVE) $(TOP)