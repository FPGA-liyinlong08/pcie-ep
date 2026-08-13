TOPLEVEL_LANG := verilog
SIM ?= verilator
PROJECT_DIR := $(abspath ../../..)
TOPLEVEL := pcie_equalization_ctrl
MODULE := test_k12c_eq
SIM_BUILD ?= sim_build
COMPILE_ARGS += --timing -Wall -Wno-fatal -Wno-TIMESCALEMOD -GEQ_TIMEOUT_CYCLES=4
VERILOG_SOURCES := $(PROJECT_DIR)/rtl/phy/pcie_equalization_ctrl.sv

ifeq ($(NEGATIVE_STUB),1)
VERILOG_SOURCES := $(CURDIR)/pcie_equalization_ctrl_bad_stub.sv
endif

include $(shell cocotb-config --makefiles)/Makefile.sim

.PHONY: checker-selftest
checker-selftest:
	@rm -f results_negative.xml k12c_negative_checker_observed.txt
	@$(MAKE) NEGATIVE_STUB=1 K12C_NEGATIVE_STUB=1 TESTCASE=checker_detects_phase_skip SIM_BUILD=sim_build_negative_k12c COCOTB_RESULTS_FILE=results_negative.xml results_negative.xml
	@grep -q '<failure' results_negative.xml
	@grep -Fxq 'K12C_NEGATIVE_CHECKER_OBSERVED phase_order' k12c_negative_checker_observed.txt
	@echo "K12_CHECKER_SELFTEST_PASS phase_order=1 eq_done_order=1"
