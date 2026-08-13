TOPLEVEL_LANG := verilog
SIM ?= verilator
PROJECT_DIR := $(abspath ../../..)
TOPLEVEL := k12_behavioral_partner_top
MODULE := test_k12_integration
SIM_BUILD ?= sim_build
COMPILE_ARGS += --timing -Wall -Wno-fatal -Wno-TIMESCALEMOD
VERILOG_SOURCES := $(PROJECT_DIR)/rtl/common/pcie_retrain_cdc_mailbox.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_recovery_speed_ctrl.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_equalization_ctrl.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_recovery_ts_guard.sv \
	$(CURDIR)/k12_behavioral_partner_top.sv
include $(shell cocotb-config --makefiles)/Makefile.sim

.PHONY: checker-selftest
checker-selftest:
	@rm -f results_negative.xml k12_integration_negative_observed.txt
	@$(MAKE) K12_INTEGRATION_NEGATIVE=1 TESTCASE=checker_detects_early_partner_done SIM_BUILD=sim_build_negative_k12_integration COCOTB_RESULTS_FILE=results_negative.xml results_negative.xml
	@grep -q '<failure' results_negative.xml
	@grep -Fxq 'K12_INTEGRATION_NEGATIVE_OBSERVED ordered_set_boundary' k12_integration_negative_observed.txt
	@echo "K12_INTEGRATION_CHECKER_SELFTEST_PASS ordered_set_boundary=1"
