TOPLEVEL_LANG := verilog
SIM ?= verilator
PROJECT_DIR := $(abspath ../../..)
TOPLEVEL := k13_production_ctrl_test_top
MODULE := test_k13_ctrl
SIM_BUILD ?= sim_build
COMPILE_ARGS += --timing -Wall -Wno-fatal -Wno-TIMESCALEMOD
K13_RXEQ_BOOTSTRAP ?= 1
COMPILE_ARGS += -GK13_RXEQ_BOOTSTRAP=$(K13_RXEQ_BOOTSTRAP)
VERILOG_SOURCES := $(PROJECT_DIR)/rtl/common/pcie_retrain_cdc_mailbox.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_recovery_speed_ctrl.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_equalization_ctrl.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_recovery_ts_guard.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_k13_production_ctrl.sv \
	$(CURDIR)/k13_production_ctrl_test_top.sv
include $(shell cocotb-config --makefiles)/Makefile.sim
