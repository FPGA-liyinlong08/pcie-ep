SIM ?= verilator
TOPLEVEL_LANG := verilog

PROJECT_DIR := $(abspath ../../..)
TOPLEVEL := pcie_ltssm_mac_gen1
MODULE := test_pcie_ltssm_mac_gen1
SIM_BUILD ?= sim_build

ifeq ($(NEGATIVE_STUB),1)
VERILOG_SOURCES := $(CURDIR)/pcie_ltssm_mac_gen1_bad_stub.sv
else
VERILOG_SOURCES := \
	$(PROJECT_DIR)/rtl/phy/pcie_gen1_os_rx.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_gen1_os_tx.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_gen1_framer.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_ltssm_mac_gen1.sv
endif

COMPILE_ARGS += -Wall -Wno-fatal -Wno-TIMESCALEMOD
COMPILE_ARGS += -GDETECT_QUIET_CYCLES=4
COMPILE_ARGS += -GDETECT_TIMEOUT_CYCLES=64
COMPILE_ARGS += -GTRAIN_TIMEOUT_CYCLES=512
COMPILE_ARGS += -GHOT_RESET_CYCLES=8

export K03_RANDOM_TRAININGS ?= 100
export K03_RANDOM_PACKETS ?= 2000
export K03_RANDOM_SEED ?= 20260806
export CCACHE_DISABLE := 1

include $(shell cocotb-config --makefiles)/Makefile.sim
