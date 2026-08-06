SIM ?= verilator
TOPLEVEL_LANG := verilog

ROOT_DIR := $(abspath ../..)
VERILOG_SOURCES := $(ROOT_DIR)/sim/common/m00_smoke.sv
TOPLEVEL := m00_smoke
MODULE := test_m00_smoke

COMPILE_ARGS += -Wall -Wno-fatal

include $(shell cocotb-config --makefiles)/Makefile.sim

