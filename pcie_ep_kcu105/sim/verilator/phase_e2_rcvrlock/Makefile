SIM := verilator
TOPLEVEL_LANG := verilog
TOPLEVEL := phase_e2_rcvrlock_test_top
MODULE := test_phase_e2_rcvrlock

PROJECT_DIR := $(abspath ../../..)
VERILOG_SOURCES := \
	$(PROJECT_DIR)/rtl/phy/pcie_gen3_rcvrlock_ctrl.sv \
	$(CURDIR)/phase_e2_rcvrlock_test_top.sv

COMPILE_ARGS += -Wall -Wno-fatal -Wno-TIMESCALEMOD

include $(shell cocotb-config --makefiles)/Makefile.sim
