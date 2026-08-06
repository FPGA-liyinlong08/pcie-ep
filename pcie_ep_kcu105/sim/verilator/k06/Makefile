TOPLEVEL_LANG = verilog
SIM ?= verilator
ifeq ($(ARB_TEST),1)
TOPLEVEL = k06_arbiter_test_top
MODULE = test_k06_arbiters
else
TOPLEVEL = k06_dll_replay_test_top
MODULE = test_pcie_dll_replay
endif
export CCACHE_DISABLE = 1

COMPILE_ARGS += --timing -Wall -Wno-fatal -Wno-TIMESCALEMOD -Wno-DECLFILENAME

ifeq ($(ARB_TEST),1)
VERILOG_SOURCES = \
	$(PWD)/../../../rtl/dll/pcie_dllp_tx_arbiter.sv \
	$(PWD)/../../../rtl/dll/pcie_dll_mac_tx_arbiter.sv \
	$(PWD)/k06_arbiter_test_top.sv
else ifeq ($(NEGATIVE_STUB),1)
VERILOG_SOURCES = $(PWD)/pcie_dll_replay_bad_stub.sv
else
VERILOG_SOURCES = \
	$(PWD)/../../../rtl/common/pcie_reset_sync.sv \
	$(PWD)/../../../rtl/dll/pcie_crc_stream.sv \
	$(PWD)/../../../rtl/dll/pcie_crc32_lcrc.sv \
	$(PWD)/../../../rtl/dll/pcie_dll_replay.sv \
	$(PWD)/k06_dll_replay_test_top.sv
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
