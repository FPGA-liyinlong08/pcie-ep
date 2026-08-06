SIM ?= verilator
TOPLEVEL_LANG := verilog

PROJECT_DIR := $(abspath ../../..)
TOPLEVEL := kcu105_reset_ctrl
MODULE := test_kcu105_refclk_reset
SIM_BUILD ?= sim_build

ifeq ($(NEGATIVE_STUB),1)
VERILOG_SOURCES := $(CURDIR)/kcu105_reset_ctrl_stub.sv
else
VERILOG_SOURCES := \
	$(PROJECT_DIR)/rtl/common/pcie_reset_sync.sv \
	$(PROJECT_DIR)/rtl/phy/kcu105_reset_ctrl.sv
endif

COMPILE_ARGS += -Wall -Wno-fatal -Wno-TIMESCALEMOD

export PCLK_PERIOD_NS ?= 16
export PCLK_PHASE_NS ?= 0
export K01_RANDOM_RESETS ?= 1000
export K01_RANDOM_PHY_RESETS ?= 250
export K01_RANDOM_SEED ?= 20260806
export CCACHE_DISABLE := 1

include $(shell cocotb-config --makefiles)/Makefile.sim
