TOPLEVEL_LANG := verilog
SIM ?= verilator
PROJECT_DIR := $(abspath ../../..)
TOPLEVEL := pcie_recovery_speed_ctrl
MODULE := test_k12b_speed
SIM_BUILD ?= sim_build
COMPILE_ARGS += --timing -Wall -Wno-fatal -Wno-TIMESCALEMOD -GSPEED_TIMEOUT_CYCLES=4
VERILOG_SOURCES := $(PROJECT_DIR)/rtl/phy/pcie_recovery_speed_ctrl.sv

ifeq ($(NEGATIVE_STUB),1)
VERILOG_SOURCES := $(CURDIR)/pcie_recovery_speed_ctrl_bad_stub.sv
endif

include $(shell cocotb-config --makefiles)/Makefile.sim

.PHONY: checker-selftest
checker-selftest:
	@rm -f results_negative.xml k12b_negative_checker_observed.txt
	@$(MAKE) NEGATIVE_STUB=1 K12B_NEGATIVE_STUB=1 TESTCASE=checker_detects_early_phy_done SIM_BUILD=sim_build_negative_k12b COCOTB_RESULTS_FILE=results_negative.xml results_negative.xml
	@grep -q '<failure' results_negative.xml
	@grep -Fxq 'K12B_NEGATIVE_CHECKER_OBSERVED phy_done_order' k12b_negative_checker_observed.txt
	@echo "K12_CHECKER_SELFTEST_PASS speed_done_order=1 fallback=1"
