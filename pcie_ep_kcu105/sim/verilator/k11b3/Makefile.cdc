SIM ?= verilator
TOPLEVEL_LANG := verilog

PROJECT_DIR := $(abspath ../../..)
TOPLEVEL := pcie_link_loss_cdc_test_top
MODULE := test_pcie_link_loss_cdc
SIM_BUILD ?= sim_build_cdc

VERILOG_SOURCES := \
	$(PROJECT_DIR)/rtl/common/pcie_link_loss_trigger.sv \
	$(PROJECT_DIR)/rtl/common/pcie_cdc_pulse.sv \
	$(CURDIR)/pcie_link_loss_cdc_test_top.sv
COMPILE_ARGS += -Wall -Wno-fatal -Wno-TIMESCALEMOD

include $(shell cocotb-config --makefiles)/Makefile.sim
