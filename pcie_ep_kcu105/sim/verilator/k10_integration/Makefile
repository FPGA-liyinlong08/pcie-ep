TOPLEVEL_LANG ?= verilog
SIM ?= verilator
TOPLEVEL = k10_bar_demo_top
MODULE = test_k10_bar_demo_integration
export CCACHE_DISABLE := 1
export RANDOM_SEED ?= 20260810

COMPILE_ARGS += --timing -Wall -Wno-TIMESCALEMOD
EXTRA_ARGS += --timing
VERILOG_SOURCES = \
	$(CURDIR)/../../../rtl/tl/pcie_bar_axil_master.sv \
	$(CURDIR)/../../../rtl/tl/demo_axil_slave.sv \
	$(CURDIR)/k10_bar_demo_top.sv
export COCOTB_RESULTS_FILE ?= results_k10_integration.xml

include $(shell cocotb-config --makefiles)/Makefile.sim

clean::
	rm -rf sim_build results_k10_integration.xml
