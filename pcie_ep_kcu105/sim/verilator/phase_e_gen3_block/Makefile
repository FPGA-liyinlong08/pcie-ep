SIM := verilator
TOPLEVEL_LANG := verilog
TOPLEVEL := phase_e_gen3_block_test_top
MODULE := test_phase_e_gen3_block

PROJECT_DIR := $(abspath ../../..)
VERILOG_SOURCES := \
	$(PROJECT_DIR)/rtl/phy/pcie_gen3_scrambler32.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_gen3_os_rx.sv \
	$(PROJECT_DIR)/rtl/phy/pcie_gen3_os_tx.sv \
	$(CURDIR)/phase_e_gen3_block_test_top.sv

COMPILE_ARGS += -Wall -Wno-fatal -Wno-TIMESCALEMOD -Wno-DECLFILENAME

include $(shell cocotb-config --makefiles)/Makefile.sim
