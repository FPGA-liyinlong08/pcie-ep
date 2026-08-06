SIM ?= verilator
TOPLEVEL_LANG := verilog

PROJECT_DIR := $(abspath ../../..)
AFIFO_RTL ?= /home/wx/Documents/AXI/prj_wb2axip_master/wb2axip-master/rtl/afifo.v
TOPLEVEL := pcie_async_pkt_fifo
MODULE := test_pcie_async_pkt_fifo
SIM_BUILD ?= sim_build
LGFIFO ?= 9

ifeq ($(NEGATIVE_STUB),1)
VERILOG_SOURCES := $(CURDIR)/pcie_async_pkt_fifo_stub.sv
else
VERILOG_SOURCES := \
	$(AFIFO_RTL) \
	$(PROJECT_DIR)/rtl/common/pcie_reset_sync.sv \
	$(PROJECT_DIR)/rtl/common/pcie_gray_sync.sv \
	$(PROJECT_DIR)/rtl/common/pcie_async_pkt_fifo.sv
endif

COMPILE_ARGS += -Wall -Wno-fatal -Wno-TIMESCALEMOD
COMPILE_ARGS += -GLGFIFO=$(LGFIFO)

export S_PERIOD_NS ?= 16
export M_PERIOD_NS ?= 4
export M_PHASE_NS ?= 0
export M02_COCOTB_PACKETS ?= 1000
export M02_RANDOM_SEED ?= 20260806
export CCACHE_DISABLE := 1

include $(shell cocotb-config --makefiles)/Makefile.sim
