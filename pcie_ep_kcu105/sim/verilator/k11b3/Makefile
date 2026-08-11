SIM ?= verilator
TOPLEVEL_LANG := verilog

PROJECT_DIR := $(abspath ../../..)
TOPLEVEL := pcie_link_loss_trigger
MODULE := test_pcie_link_loss_trigger
SIM_BUILD ?= sim_build

VERILOG_SOURCES := $(PROJECT_DIR)/rtl/common/pcie_link_loss_trigger.sv
COMPILE_ARGS += -Wall -Wno-fatal -Wno-TIMESCALEMOD

include $(shell cocotb-config --makefiles)/Makefile.sim
