TOPLEVEL_LANG = verilog
SIM ?= verilator
export CCACHE_DISABLE = 1
export RANDOM_SEED ?= 20260807

TOPLEVEL = k09_tlp_test_top
MODULE = test_k09_tlp_integration
COMPILE_ARGS += --timing -Wall -Wno-TIMESCALEMOD

VERILOG_SOURCES = \
	$(CURDIR)/../../../rtl/tl/pcie_tlp_codec.sv \
	$(CURDIR)/../../../rtl/tl/pcie_cfg_space.sv \
	$(CURDIR)/../../../rtl/tl/pcie_bar_axil_master.sv \
	$(CURDIR)/k09_tlp_test_top.sv

include $(shell cocotb-config --makefiles)/Makefile.sim
