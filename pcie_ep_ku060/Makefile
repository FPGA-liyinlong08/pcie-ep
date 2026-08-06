.PHONY: m00 m00-verilator m00-pcie-model m00-vcs \
	m01-checker-selftest m01-lint m01-verilator m01-vcs m01-vivado m01 \
	m02-checker-selftest m02-afifo-check m02-lint m02-verilator \
	m02-verilator-signoff m02-vcs m02-vivado m02 clean

PYTHON ?= python3

m00: m00-verilator m00-pcie-model m00-vcs

m00-verilator:
	$(MAKE) -C sim/verilator TESTCASE=reset_and_count

m00-pcie-model:
	$(MAKE) -C sim/verilator TESTCASE=pcie_model_objects
	$(PYTHON) sim/common/check_pcie_model.py

m00-vcs:
	./sim/vcs/run_m00.sh

m01-checker-selftest:
	@$(MAKE) -C sim/verilator/m01 NEGATIVE_STUB=1 \
		TESTCASE=release_and_dependency SIM_BUILD=sim_build_negative
	@if grep -q '<failure' sim/verilator/m01/results.xml; then \
		echo "M01_CHECKER_SELFTEST_PASS"; \
	else \
		echo "错误：故意错误的 M01 Stub 未被 Checker 检出"; \
		exit 1; \
	fi

m01-lint:
	verilator --lint-only -Wall -Wno-fatal --top-module pcie_clk_reset_ctrl \
		rtl/common/pcie_reset_sync.sv \
		rtl/common/pcie_bit_sync.sv \
		rtl/common/pcie_clk_reset_ctrl.sv

m01-verilator:
	./sim/verilator/m01/run_m01.sh

m01-vcs:
	./sim/vcs/run_m01.sh

m01-vivado:
	./fpga/ku060/run_m01_checks.sh

m01: m01-checker-selftest m01-lint m01-verilator m01-vcs m01-vivado

m02-checker-selftest:
	@$(MAKE) -C sim/verilator/m02 NEGATIVE_STUB=1 LGFIFO=4 \
		TESTCASE=incomplete_packet_hidden SIM_BUILD=sim_build_negative
	@if grep -q '<failure' sim/verilator/m02/results.xml; then \
		echo "M02_CHECKER_SELFTEST_PASS"; \
	else \
		echo "错误：故意提前输出半包的 M02 Stub 未被 Checker 检出"; \
		exit 1; \
	fi

m02-lint:
	verilator --lint-only -Wall -Wno-fatal -Wno-TIMESCALEMOD \
		--top-module pcie_async_pkt_fifo \
		-G"LGFIFO=9" \
		/home/wx/Documents/AXI/prj_wb2axip_master/wb2axip-master/rtl/afifo.v \
		rtl/common/pcie_reset_sync.sv \
		rtl/common/pcie_gray_sync.sv \
		rtl/common/pcie_async_pkt_fifo.sv

m02-afifo-check:
	./sim/common/check_afifo_dependency.sh

m02-verilator: m02-afifo-check
	./sim/verilator/m02/run_m02.sh

m02-verilator-signoff: m02-afifo-check
	./sim/verilator/m02_native/run_m02_native.sh

m02-vcs: m02-afifo-check
	./sim/vcs/run_m02.sh

m02-vivado: m02-afifo-check
	./fpga/ku060/run_m02_checks.sh

m02: m02-checker-selftest m02-lint m02-verilator \
	m02-verilator-signoff m02-vcs m02-vivado

clean:
	$(MAKE) -C sim/verilator clean
	$(RM) sim/verilator/results.xml
	./sim/verilator/m01/clean.sh
	./sim/verilator/m02/clean.sh
	$(RM) -r sim/verilator/m02_native/build
	./sim/vcs/clean.sh
	$(RM) -r fpga/ku060/build_m01
	$(RM) -r fpga/ku060/build_m02
