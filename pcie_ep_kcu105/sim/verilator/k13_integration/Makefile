TOPLEVEL_LANG := verilog
SIM ?= verilator
PROJECT_DIR := $(abspath ../../..)
TOPLEVEL := k13_ltssm_partner_top
MODULE := test_k13_integration
SIM_BUILD ?= sim_build
COMPILE_ARGS += --timing -Wall -Wno-fatal -Wno-TIMESCALEMOD
K13_RXEQ_BOOTSTRAP ?= 1
COMPILE_ARGS += -GK13_RXEQ_BOOTSTRAP=$(K13_RXEQ_BOOTSTRAP)
VERILOG_SOURCES := \
	$(PROJECT_DIR)/rtl/common/pcie_retrain_cdc_mailbox.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_phy_rate_contract.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_recovery_speed_ctrl.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_equalization_ctrl.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_recovery_ts_guard.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_k13_production_ctrl.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_gen12_scrambler.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_gen1_rx_symbol_aligner.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_gen1_os_rx.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_gen1_os_tx.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_gen3_scrambler32.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_gen3_os_rx.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_gen3_os_tx.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_gen1_framer.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_ltssm_mac_gen1.sv \
	$(CURDIR)/k13_ltssm_partner_top.sv
include $(shell cocotb-config --makefiles)/Makefile.sim
