SIM ?= verilator
TOPLEVEL_LANG := verilog

PROJECT_DIR := $(abspath ../../..)
TOPLEVEL := pcie_clk_reset_ctrl
MODULE := test_pcie_clk_reset
SIM_BUILD ?= sim_build

ifeq ($(NEGATIVE_STUB),1)
VERILOG_SOURCES := $(CURDIR)/pcie_clk_reset_stub.sv
else
VERILOG_SOURCES := \
	$(PROJECT_DIR)/rtl/common/pcie_reset_sync.sv \
	$(PROJECT_DIR)/rtl/common/pcie_bit_sync.sv \
	$(PROJECT_DIR)/rtl/common/pcie_clk_reset_ctrl.sv
endif

COMPILE_ARGS += -Wall -Wno-fatal

include $(shell cocotb-config --makefiles)/Makefile.sim

