SIM ?= verilator
TOPLEVEL_LANG := verilog
PROJECT_DIR := $(abspath ../../..)
TOPLEVEL := pcie_gen12_scrambler
MODULE := test_pcie_gen12_scrambler
SIM_BUILD ?= sim_build

ifeq ($(NEGATIVE_STUB),1)
VERILOG_SOURCES := $(CURDIR)/pcie_gen12_scrambler_bad_stub.sv
else
VERILOG_SOURCES := $(PROJECT_DIR)/rtl/phy/pcie_gen12_scrambler.sv
endif

COMPILE_ARGS += -Wall -Wno-fatal -Wno-TIMESCALEMOD
export CCACHE_DISABLE := 1
include $(shell cocotb-config --makefiles)/Makefile.sim
