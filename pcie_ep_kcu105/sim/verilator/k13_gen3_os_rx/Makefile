SIM ?= verilator
TOPLEVEL_LANG := verilog
PROJECT_DIR := $(abspath ../../..)
TOPLEVEL := k13_gen3_os_rx_test_top
MODULE := test_pcie_gen3_os_rx
SIM_BUILD ?= sim_build

COMPILE_ARGS += --timing -Wall -Wno-fatal -Wno-TIMESCALEMOD
export CCACHE_DISABLE := 1
VERILOG_SOURCES := \
	$(PROJECT_DIR)/rtl/phy/pcie_gen3_scrambler32.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_gen3_os_rx.sv \
	$(CURDIR)/k13_gen3_os_rx_test_top.sv

include $(shell cocotb-config --makefiles)/Makefile.sim
