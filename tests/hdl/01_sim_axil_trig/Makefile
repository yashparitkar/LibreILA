UNIT       := libre_ila
TOP        := tb
CODEGEN    := ../../../codegen/code_generator.py
GEN_DIR    := ../../../codegen/gen_axis
GEN_STAMP  := $(GEN_DIR)/.stamp
CORE       := $(GEN_DIR)/$(UNIT).vhdl
WORKROOT   := work
# Without this ghdl runs on past a failed assertion and still exits 0, which
# would let a bench report a mismatch and the build call it a pass.
RUNFLAGS   := --assert-level=error

# The trigger position sweep. The bench is the same one for all three, only
# C_TRIG_IDX differs: the first slot of the sample buffer, its last slot, and
# a point inside it. Each entry gets its own work directory holding its own
# patched copy of tb.vhdl, so the three builds sit side by side instead of
# overwriting each other and can be run in parallel with -j.
VARIANTS            := trig_0 trig_depth trig_3
TRIG_IDX_trig_0     := 0
TRIG_IDX_trig_depth := C_SAMP_BUFF_DEPTH - 1
TRIG_IDX_trig_3     := 3

SIM_TARGETS  := $(addprefix sim-,$(VARIANTS))
WAVE_TARGETS := $(addprefix wave-,$(VARIANTS))

# Everything the stock build is made of. Touch any of it and the next sim
# regenerates gen_axis/, touch none of it and the generator does not run at
# all, so back to back sims stay cheap.
GEN_DEPS   := $(CODEGEN) $(wildcard ../../../hdl/*.vhdl) $(wildcard ../../../codegen/templates/*.csv)

.PHONY: all sim wave clean $(SIM_TARGETS) $(WAVE_TARGETS)

all: sim

# The generator writes several files at once, so a stamp carries the
# timestamp rather than any one of them.
$(GEN_STAMP): $(GEN_DEPS)
	python3 $(CODEGEN)
	@touch $@

sim: $(SIM_TARGETS)

# One run per trigger position. The value is substituted into the copy that
# lands in the work directory, tb.vhdl itself stays a complete testbench that
# analyses on its own. The grep is there because a silent sed miss would leave
# all three runs testing the same position and still passing.
$(SIM_TARGETS): sim-%: $(GEN_STAMP)
	@echo "=== 01_sim_axil_trig: C_TRIG_IDX = $(TRIG_IDX_$*) ($*) ==="
	mkdir -p $(WORKROOT)/$*
	sed 's|^\( *constant C_TRIG_IDX  *: *natural *:= *\).*;|\1$(TRIG_IDX_$*);|' tb.vhdl > $(WORKROOT)/$*/tb.vhdl
	@grep -q '^ *constant C_TRIG_IDX  *: *natural *:= *$(TRIG_IDX_$*);' $(WORKROOT)/$*/tb.vhdl || \
	  { echo "C_TRIG_IDX was not patched, check its declaration in tb.vhdl"; exit 1; }
	ghdl -a --std=08 --workdir=$(WORKROOT)/$* $(CORE) $(WORKROOT)/$*/tb.vhdl
	ghdl -e --std=08 --workdir=$(WORKROOT)/$* $(TOP)
	ghdl -r --std=08 --workdir=$(WORKROOT)/$* $(TOP) $(RUNFLAGS) --wave=$(WORKROOT)/$*/$(TOP).ghw

# make wave opens all three, make wave-trig_0 just the one.
wave: $(WAVE_TARGETS)

$(WAVE_TARGETS): wave-%: sim-%
	gtkwave $(WORKROOT)/$*/$(TOP).ghw &

clean:
	rm -rf $(WORKROOT) $(TOP) *.ghw
