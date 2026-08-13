TOPLEVEL_LANG := verilog
SIM ?= verilator

PROJECT_DIR := $(abspath ../../..)
TOPLEVEL := pcie_retrain_cdc_mailbox
MODULE := test_k12a_cdc_mailbox
SIM_BUILD ?= sim_build

COMPILE_ARGS += --timing -Wall -Wno-fatal -Wno-TIMESCALEMOD
VERILOG_SOURCES := $(PROJECT_DIR)/rtl/common/pcie_retrain_cdc_mailbox.sv

ifeq ($(NEGATIVE_STUB),1)
VERILOG_SOURCES := $(CURDIR)/pcie_retrain_cdc_mailbox_bad_stub.sv
endif

include $(shell cocotb-config --makefiles)/Makefile.sim

.PHONY: checker-selftest
checker-selftest:
	@rm -f results_negative.xml k12a_negative_checker_observed.txt
	@$(MAKE) NEGATIVE_STUB=1 K12A_NEGATIVE_STUB=1 TESTCASE=checker_marker_for_negative_stub \
		SIM_BUILD=sim_build_negative COCOTB_RESULTS_FILE=results_negative.xml \
		results_negative.xml
	@grep -q '<failure' results_negative.xml
	@grep -Fxq 'K12A_NEGATIVE_CHECKER_OBSERVED valid_hold' \
		k12a_negative_checker_observed.txt
	@echo "K12_CHECKER_SELFTEST_PASS valid_hold=1 payload_atomic=1 overflow=1"
