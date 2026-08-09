TOPLEVEL_LANG = verilog
SIM ?= verilator
export CCACHE_DISABLE = 1
export K08_NEGATIVE_STUB := $(NEGATIVE_STUB)

COMPILE_ARGS += --timing -Wall -Wno-TIMESCALEMOD

ifeq ($(NEGATIVE_STUB),1)
TOPLEVEL = pcie_cfg_space
MODULE = test_pcie_cfg_space
COMPILE_ARGS += -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL
VERILOG_SOURCES = $(CURDIR)/pcie_cfg_space_bad_stub.sv
else ifeq ($(INTEGRATION),1)
TOPLEVEL = k08_cfg_tlp_test_top
MODULE = test_k08_tlp_integration
VERILOG_SOURCES = \
	$(CURDIR)/../../../rtl/tl/pcie_tlp_codec.sv \
	$(CURDIR)/../../../rtl/tl/pcie_cfg_space.sv \
	$(CURDIR)/k08_cfg_tlp_test_top.sv
else
TOPLEVEL = pcie_cfg_space
MODULE = test_pcie_cfg_space
VERILOG_SOURCES = $(CURDIR)/../../../rtl/tl/pcie_cfg_space.sv
endif

include $(shell cocotb-config --makefiles)/Makefile.sim

.PHONY: checker-selftest
checker-selftest:
	@rm -f results_negative.xml negative_checker_observed.txt
	@$(MAKE) NEGATIVE_STUB=1 \
		TESTCASE=identity_and_bar_probe_guard \
		SIM_BUILD=sim_build_negative \
		COCOTB_RESULTS_FILE=results_negative.xml \
		results_negative.xml
	@grep -q '<failure' results_negative.xml
	@grep -Fxq 'K08_NEGATIVE_CHECKER_OBSERVED identity bar be' \
		negative_checker_observed.txt
	@echo "K08_CHECKER_SELFTEST_PASS guards=identity,bar,be"
