TOPLEVEL_LANG = verilog
SIM ?= verilator
TOPLEVEL = k04_crc_test_top
MODULE = test_pcie_crc
export CCACHE_DISABLE = 1

COMPILE_ARGS += --timing -Wall -Wno-fatal -Wno-TIMESCALEMOD -Wno-DECLFILENAME

ifeq ($(NEGATIVE_STUB),1)
VERILOG_SOURCES = $(PWD)/pcie_crc_bad_stub.sv
else
VERILOG_SOURCES = \
	$(PWD)/../../../rtl/dll/pcie_crc_stream.sv \
	$(PWD)/../../../rtl/dll/pcie_crc16_dllp.sv \
	$(PWD)/../../../rtl/dll/pcie_crc32_lcrc.sv \
	$(PWD)/k04_crc_test_top.sv
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
