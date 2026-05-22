############################
# Minimal 470-style Makefile
############################

.DEFAULT_GOAL := help

# List your modules here (names must match verilog/<name>.sv and test/<name>_test.sv)
MODULES := adder mac systolic_array tpu

COMMON_RTL := verilog/mac.sv verilog/activation_buffer.sv verilog/weight_buffer.sv verilog/tpu_command_queue.sv verilog/tpu_scheduler.sv verilog/tpu_controller.sv verilog/systolic_array.sv

# Tool script (must exist in your repo)
TCL_SCRIPT := synth/470synth.tcl

# Gate-level stdcell lib (works on CAEN; change if elsewhere)
LIB := /usr/caen/misc/class/eecs470/lib/verilog/lec25dscc25.v

# Clock period (ns)
CLOCK_PERIOD ?= 30.0

# If you're on CAEN, module load gives you VCS/DC. Keep this since you said
# "I need to use the 470 tcl cause this is how i get access to those tools."
LOAD_TOOLS = module load vcs/2023.12-SP2-1 verdi/2023.12-SP2-1 synopsys-synth &&

# VCS compile commands
VCS_COMMON = vcs -sverilog -full64 -kdb -lca -nc -debug_access+all \
	+define+CLOCK_PERIOD=$(CLOCK_PERIOD) +incdir+verilog/includes +incdir+verilog

VCS_SIM = $(VCS_COMMON)
VCS_SYN = $(VCS_COMMON) +define+SYNTH

RUN_VERDI = -gui=verdi -verdi_opts "-ultra"

SIM_RUN_FLAGS ?= +vcs+vcd

VCD_DIR := vcd

# Dirs
BUILD_DIR := build
SYN_DIR   := synth

$(BUILD_DIR) $(SYN_DIR) $(VCD_DIR):
	mkdir -p $@

####################
# --- User targets
####################

help:
	@echo ""
	@echo "Targets:"
	@echo "  make <module>            # compile + run RTL testbench"
	@echo "  make <module>.verdi      # run RTL sim in Verdi"
	@echo "  make <module>.syn        # run DC to create synth/<module>.vg"
	@echo "  make <module>.syn.run    # compile + run gate-level sim"
	@echo ""
	@echo "Modules: $(MODULES)"
	@echo ""

.PHONY: help

#########################################
# --- RTL sim: make adder (compile+run)
#########################################

# Build sim executable: build/<module>.simv
$(MODULES:%=$(BUILD_DIR)/%.simv): $(BUILD_DIR)/%.simv: verilog/%.sv test/%_test.sv $(COMMON_RTL) verilog/sys_defs.svh | $(BUILD_DIR)
	@echo "==> [VCS] Building RTL sim $@"
	@$(LOAD_TOOLS) $(VCS_SIM) $(filter-out verilog/$*.sv,$(COMMON_RTL)) verilog/$*.sv test/$*_test.sv -o $@

# Run sim: make <module>
$(MODULES): %: $(BUILD_DIR)/%.simv
	@echo "==> [RUN] RTL sim for $*"
	@cd $(BUILD_DIR) && ./$(notdir $<) $(SIM_RUN_FLAGS) +dumpfile=../$(VCD_DIR)/$*.vcd | tee $*.out
	@echo "==> Output: $(BUILD_DIR)/$*.out"

# Verdi: make <module>.verdi
$(MODULES:%=%.verdi): %.verdi: $(BUILD_DIR)/%.simv
	@echo "==> [VERDI] RTL sim for $*"
	@cd $(BUILD_DIR) && ./$(notdir $<) $(RUN_VERDI)

.PHONY: $(MODULES) $(MODULES:%=%.verdi)

#########################################
# --- Synthesis: make adder.syn
#########################################

# DC output: synth/<module>.vg
$(MODULES:%=$(SYN_DIR)/%.vg): $(SYN_DIR)/%.vg: verilog/%.sv $(COMMON_RTL) verilog/sys_defs.svh $(TCL_SCRIPT) | $(SYN_DIR)
	@echo "==> [DC] Synthesizing $* -> $@"
	@cd $(SYN_DIR) && \
	  $(LOAD_TOOLS) \
	  MODULE=$* \
	  CLOCK_PERIOD=$(CLOCK_PERIOD) \
	  SOURCES="$(abspath $(filter-out verilog/$*.sv,$(COMMON_RTL)) verilog/$*.sv)" \
	  dc_shell-t -f $(notdir $(TCL_SCRIPT)) | tee $*_synth.out

# Convenience target: make <module>.syn
$(MODULES:%=%.syn): %.syn: $(SYN_DIR)/%.vg
	@echo "==> Done: $<"

.PHONY: $(MODULES:%=%.syn)

#########################################
# --- Gate-level sim: make adder.syn.run
#########################################

# Build gate sim executable: build/<module>.syn.simv
$(MODULES:%=$(BUILD_DIR)/%.syn.simv): $(BUILD_DIR)/%.syn.simv: test/%_test.sv $(SYN_DIR)/%.vg | $(BUILD_DIR)
	@echo "==> [VCS] Building gate-level sim $@"
	@$(LOAD_TOOLS) $(VCS_SYN) $^ $(LIB) -o $@

# Run gate sim: make <module>.syn.run
$(MODULES:%=%.syn.run): %.syn.run: $(BUILD_DIR)/%.syn.simv
	@echo "==> [RUN] Gate-level sim for $*"
	@cd $(BUILD_DIR) && ./$(notdir $<) $(SIM_RUN_FLAGS) +dumpfile=../$(VCD_DIR)/$*.vcd | tee $*.out
	@echo "==> Output: $(BUILD_DIR)/$*.syn.out"

.PHONY: $(MODULES:%=%.syn.run)

####################
# --- Cleanup
####################

clean:
	rm -rf $(BUILD_DIR) $(SYN_DIR)/*.vg $(SYN_DIR)/*_synth.out
.PHONY: clean
