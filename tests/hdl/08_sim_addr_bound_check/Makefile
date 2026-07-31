UNIT       := libre_ila
TOP        := tb
CODEGEN    := ../../../codegen/code_generator.py
GEN_DIR    := ../../../codegen/gen_axis
GEN_STAMP  := $(GEN_DIR)/.stamp
SRC        := $(GEN_DIR)/$(UNIT).vhdl tb.vhdl
WORKDIR    := work
GHDLFLAGS  := --std=08 --workdir=$(WORKDIR)
WAVE       := $(TOP).ghw

# Everything the stock build is made of. Touch any of it and the next sim
# regenerates gen_axis/, touch none of it and the generator does not run at
# all, so back to back sims stay cheap.
GEN_DEPS   := $(CODEGEN) $(wildcard ../../../hdl/*.vhdl) $(wildcard ../../../codegen/templates/*.csv)

.PHONY: all sim wave clean

all: sim

$(WORKDIR):
	mkdir -p $(WORKDIR)

# The generator writes several files at once, so a stamp carries the
# timestamp rather than any one of them.
$(GEN_STAMP): $(GEN_DEPS)
	python3 $(CODEGEN)
	@touch $@

sim: $(WORKDIR) $(GEN_STAMP)
	ghdl -a $(GHDLFLAGS) $(SRC)
	ghdl -e $(GHDLFLAGS) $(TOP)
	ghdl -r $(GHDLFLAGS) $(TOP) --wave=$(WAVE)

wave: sim
	gtkwave $(WAVE) &

clean:
	rm -rf $(WORKDIR) $(WAVE) $(TOP)
