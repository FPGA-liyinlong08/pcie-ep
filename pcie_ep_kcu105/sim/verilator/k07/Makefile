TOPLEVEL_LANG = verilog
SIM ?= verilator
TOPLEVEL = pcie_tlp_codec
MODULE = test_pcie_tlp_codec
export CCACHE_DISABLE = 1

COMPILE_ARGS += --timing -Wall -Wno-TIMESCALEMOD

ifeq ($(NEGATIVE_STUB),1)
COMPILE_ARGS += -Wno-DECLFILENAME
VERILOG_SOURCES = $(CURDIR)/pcie_tlp_codec_bad_stub.sv
else
VERILOG_SOURCES = $(CURDIR)/../../../rtl/tl/pcie_tlp_codec.sv
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
