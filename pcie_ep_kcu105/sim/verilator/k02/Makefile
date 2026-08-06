SIM ?= verilator
TOPLEVEL_LANG := verilog

PROJECT_DIR := $(abspath ../../..)
TOPLEVEL := kcu105_pcie_phy_wrapper
MODULE := test_kcu105_pcie_phy_wrapper
SIM_BUILD ?= sim_build

ifeq ($(NEGATIVE_STUB),1)
VERILOG_SOURCES := $(CURDIR)/kcu105_pcie_phy_wrapper_bad_stub.sv
else
VERILOG_SOURCES := \
	$(CURDIR)/xilinx_primitive_stubs.sv \
	$(CURDIR)/pcie_phy_x1_gen3_behavioral_stub.sv \
	$(PROJECT_DIR)/rtl/common/pcie_reset_sync.sv \
	$(PROJECT_DIR)/rtl/phy/kcu105_reset_ctrl.sv \
	$(PROJECT_DIR)/rtl/phy/kcu105_refclk_reset.sv \
	$(PROJECT_DIR)/rtl/phy/kcu105_pcie_phy_wrapper.sv
endif

COMPILE_ARGS += -Wall -Wno-fatal -Wno-TIMESCALEMOD -Wno-DECLFILENAME

export K02_RANDOM_VECTORS ?= 10000
export K02_RANDOM_SEED ?= 20260806
export CCACHE_DISABLE := 1

include $(shell cocotb-config --makefiles)/Makefile.sim
