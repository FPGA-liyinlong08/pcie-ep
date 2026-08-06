TOPLEVEL_LANG = verilog
SIM ?= verilator
TOPLEVEL = k05_dllp_fc_test_top
MODULE = test_pcie_dllp_fc
export CCACHE_DISABLE = 1

COMPILE_ARGS += --timing -Wall -Wno-fatal -Wno-TIMESCALEMOD -Wno-DECLFILENAME

ifeq ($(NEGATIVE_STUB),1)
VERILOG_SOURCES = $(PWD)/pcie_dllp_fc_bad_stub.sv
else
VERILOG_SOURCES = \
	$(PWD)/../../../rtl/common/pcie_reset_sync.sv \
	$(PWD)/../../../rtl/dll/pcie_crc_stream.sv \
	$(PWD)/../../../rtl/dll/pcie_crc16_dllp.sv \
	$(PWD)/../../../rtl/dll/pcie_fc_local_credit_pool.sv \
	$(PWD)/../../../rtl/dll/pcie_dllp_codec.sv \
	$(PWD)/../../../rtl/dll/pcie_dllp_fc_manager.sv \
	$(PWD)/../../../rtl/dll/pcie_dllp_fc.sv \
	$(PWD)/k05_dllp_fc_test_top.sv
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
