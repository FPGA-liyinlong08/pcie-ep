SIM ?= verilator
TOPLEVEL_LANG := verilog

PROJECT_DIR := $(abspath ../../..)
TOPLEVEL := k03_command_boundary_test_top
MODULE := test_pcie_ltssm_mac_gen1
SIM_BUILD ?= sim_build

ifeq ($(NEGATIVE_STUB),1)
TOPLEVEL := pcie_ltssm_mac_gen1
VERILOG_SOURCES := $(CURDIR)/pcie_ltssm_mac_gen1_bad_stub.sv
else
VERILOG_SOURCES := \
	$(PROJECT_DIR)/rtl/phy/pcie_phy_command_ctrl.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_gen12_scrambler.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_gen1_rx_symbol_aligner.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_gen1_os_rx.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_gen1_os_tx.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_gen3_scrambler32.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_gen3_os_rx.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_gen3_rcvrlock_ctrl.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_gen3_os_tx.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_gen1_framer.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_ltssm_mac_gen1.sv \
	$(CURDIR)/k03_command_boundary_test_top.sv
endif

COMPILE_ARGS += -Wall -Wno-fatal -Wno-TIMESCALEMOD
COMPILE_ARGS += -GDETECT_QUIET_CYCLES=4
COMPILE_ARGS += -GDETECT_TIMEOUT_CYCLES=64
# Polling.Active必须发送至少1024个TS1；Gen1/16-bit PIPE下为8192个pclk。
# 留出状态进入和测试驱动余量，同时保持仿真超时足够短。
COMPILE_ARGS += -GTRAIN_TIMEOUT_CYCLES=10000
COMPILE_ARGS += -GHOT_RESET_CYCLES=8
COMPILE_ARGS += -GG9_WAIT_REMOTE_DETECT=$(G9_WAIT_REMOTE_DETECT)
COMPILE_ARGS += -GG9_WAIT_REMOTE_DETECT_CYCLES=$(G9_WAIT_REMOTE_DETECT_CYCLES)

export K03_RANDOM_TRAININGS ?= 100
export K03_RANDOM_PACKETS ?= 2000
export K03_RANDOM_SEED ?= 20260806
export G9_WAIT_REMOTE_DETECT ?= 0
export G9_WAIT_REMOTE_DETECT_CYCLES ?= 32
export CCACHE_DISABLE := 1

include $(shell cocotb-config --makefiles)/Makefile.sim
