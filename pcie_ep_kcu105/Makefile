.PHONY: k00 k00-baseline k00-verilator k00-pcie-model k00-vcs \
	k00-m02-checker-selftest k00-m02-afifo-check k00-m02-lint \
	k00-m02-verilator k00-m02-verilator-signoff k00-m02-vcs \
	k00-m02-vivado k00-m02 \
	k01-checker-selftest k01-lint k01-verilator k01-vcs k01-vivado k01 \
	clean

PYTHON ?= python3

k00: k00-baseline k00-m02

k00-baseline: k00-verilator k00-pcie-model k00-vcs

k00-verilator:
	$(MAKE) -C sim/verilator TESTCASE=reset_and_count

k00-pcie-model:
	$(MAKE) -C sim/verilator TESTCASE=pcie_model_objects
	$(PYTHON) sim/common/check_pcie_model.py

k00-vcs:
	./sim/vcs/run_m00.sh

k00-m02-checker-selftest:
	@$(MAKE) -C sim/verilator/m02 NEGATIVE_STUB=1 LGFIFO=4 \
		TESTCASE=incomplete_packet_hidden SIM_BUILD=sim_build_negative
	@if grep -q '<failure' sim/verilator/m02/results.xml; then \
		echo "K00_M02_CHECKER_SELFTEST_PASS"; \
	else \
		echo "错误：故意提前输出半包的 M02 Stub 未被 Checker 检出"; \
		exit 1; \
	fi

k00-m02-afifo-check:
	./sim/common/check_afifo_dependency.sh

k00-m02-lint:
	verilator --lint-only -Wall -Wno-fatal -Wno-TIMESCALEMOD \
		--top-module pcie_async_pkt_fifo \
		-G"LGFIFO=9" \
		/home/wx/Documents/AXI/prj_wb2axip_master/wb2axip-master/rtl/afifo.v \
		rtl/common/pcie_reset_sync.sv \
		rtl/common/pcie_gray_sync.sv \
		rtl/common/pcie_async_pkt_fifo.sv

k00-m02-verilator: k00-m02-afifo-check
	./sim/verilator/m02/run_m02.sh

k00-m02-verilator-signoff: k00-m02-afifo-check
	./sim/verilator/m02_native/run_m02_native.sh

k00-m02-vcs: k00-m02-afifo-check
	./sim/vcs/run_m02.sh

k00-m02-vivado: k00-m02-afifo-check
	./fpga/kcu105/run_k00_m02_checks.sh

k00-m02: k00-m02-checker-selftest k00-m02-lint \
	k00-m02-verilator k00-m02-verilator-signoff k00-m02-vcs \
	k00-m02-vivado

k01-checker-selftest:
	@$(MAKE) -C sim/verilator/k01 NEGATIVE_STUB=1 \
		TESTCASE=release_and_dependency SIM_BUILD=sim_build_negative
	@cp sim/verilator/k01/results.xml sim/verilator/k01/results_negative.xml
	@if grep -q '<failure' sim/verilator/k01/results.xml; then \
		echo "K01_CHECKER_SELFTEST_PASS"; \
	else \
		echo "错误：永久撤销复位的 K01 Stub 未被 Checker 检出"; \
		exit 1; \
	fi

k01-lint:
	verilator --lint-only -Wall -Wno-fatal -Wno-TIMESCALEMOD \
		--top-module kcu105_reset_ctrl \
		rtl/common/pcie_reset_sync.sv \
		rtl/phy/kcu105_reset_ctrl.sv

k01-verilator:
	./sim/verilator/k01/run_k01.sh

k01-vcs:
	./sim/vcs/run_k01.sh

k01-vivado:
	./fpga/kcu105/run_k01_checks.sh

k01: k01-checker-selftest k01-lint k01-verilator k01-vcs k01-vivado

clean:
	$(MAKE) -C sim/verilator clean
	$(RM) sim/verilator/results.xml
	./sim/verilator/m02/clean.sh
	./sim/verilator/k01/clean.sh
	$(RM) -r sim/verilator/m02_native/build
	./sim/vcs/clean.sh
	$(RM) -r fpga/kcu105/build_k00_m02
	$(RM) -r fpga/kcu105/build_k01
