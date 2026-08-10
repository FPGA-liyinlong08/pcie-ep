TOPLEVEL_LANG = verilog
SIM = verilator
TOPLEVEL = k11a_bridge_test_top
MODULE = test_k11a_bridge
COMPILE_ARGS += --timing -Wall -Wno-fatal -Wno-TIMESCALEMOD

ifeq ($(NEGATIVE_STUB),1)
VERILOG_SOURCES = $(PWD)/pcie_tlp_async_bridge_bad_stub.sv
else
VERILOG_SOURCES = \
  /home/wx/Documents/AXI/prj_wb2axip_master/wb2axip-master/rtl/afifo.v \
  $(PWD)/../../../rtl/common/pcie_reset_sync.sv \
  $(PWD)/../../../rtl/common/pcie_gray_sync.sv \
  $(PWD)/../../../rtl/common/pcie_async_pkt_fifo.sv \
  $(PWD)/../../../rtl/common/pcie_async_event_fifo.sv \
  $(PWD)/../../../rtl/common/pcie_tlp_async_bridge.sv \
  $(PWD)/k11a_bridge_test_top.sv
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
