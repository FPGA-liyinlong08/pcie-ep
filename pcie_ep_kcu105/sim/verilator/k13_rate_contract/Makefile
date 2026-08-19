TOPLEVEL_LANG := verilog
SIM ?= verilator
PROJECT_DIR := $(abspath ../../..)
TOPLEVEL := pcie_phy_rate_contract
MODULE := test_k13_rate_contract
SIM_BUILD ?= sim_build

# SystemVerilog timing + 关闭致命警告
# 仿真用短参数：
#   RATE_TIMEOUT_CYCLES=200   (~2 us @ 10 ns clock)
#   GEN1_RELEASE_GAP_CYCLES=10  (100 ns，10x 真实 10 us 缩比)
COMPILE_ARGS += --timing -Wall -Wno-fatal -Wno-TIMESCALEMOD
COMPILE_ARGS += -GRATE_TIMEOUT_CYCLES=200
COMPILE_ARGS += -GGEN1_RELEASE_GAP_CYCLES=10

VERILOG_SOURCES := $(PROJECT_DIR)/rtl/phy/pcie_phy_rate_contract.sv

include $(shell cocotb-config --makefiles)/Makefile.sim
