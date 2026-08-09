TOPLEVEL_LANG ?= verilog
SIM ?= verilator
TOPLEVEL = demo_axil_slave
MODULE = test_demo_axil_slave
export CCACHE_DISABLE := 1
export RANDOM_SEED ?= 20260810

COMPILE_ARGS += --timing -Wall -Wno-TIMESCALEMOD
EXTRA_ARGS += --timing

ifeq ($(K10_NEGATIVE_STUB),1)
VERILOG_SOURCES = $(CURDIR)/demo_axil_slave_bad_stub.sv
SIM_BUILD = sim_build_negative
COMPILE_ARGS += -Wno-DECLFILENAME
else
VERILOG_SOURCES = $(CURDIR)/../../../rtl/tl/demo_axil_slave.sv
SIM_BUILD = sim_build
endif

export COCOTB_RESULTS_FILE ?= results.xml

include $(shell cocotb-config --makefiles)/Makefile.sim

clean::
	rm -rf sim_build sim_build_negative results.xml results_negative.xml
	rm -f k10_negative_marker.txt k10_random_evidence.txt
