TOPLEVEL_LANG ?= verilog
SIM ?= verilator
TOPLEVEL ?= pcie_bar_axil_master
MODULE ?= test_pcie_bar_axil_master
export CCACHE_DISABLE := 1
export RANDOM_SEED ?= 20260807

COMPILE_ARGS += --timing -Wall -Wno-TIMESCALEMOD
EXTRA_ARGS += --timing

ifeq ($(K09_NEGATIVE_STUB),1)
VERILOG_SOURCES = $(PWD)/pcie_bar_axil_master_bad_stub.sv
SIM_BUILD = sim_build_negative
else
VERILOG_SOURCES = $(PWD)/../../../rtl/tl/pcie_bar_axil_master.sv
SIM_BUILD = sim_build
endif

export COCOTB_RESULTS_FILE ?= results.xml

include $(shell cocotb-config --makefiles)/Makefile.sim

clean::
	rm -rf sim_build sim_build_negative results.xml results_negative.xml
	rm -f k09_negative_marker.txt k09_random_evidence.txt
