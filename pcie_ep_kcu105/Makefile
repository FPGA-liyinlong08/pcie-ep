.PHONY: k00 k00-baseline k00-verilator k00-pcie-model k00-vcs \
	k00-m02-checker-selftest k00-m02-afifo-check k00-m02-lint \
	k00-m02-verilator k00-m02-verilator-signoff k00-m02-vcs \
	k00-m02-vivado k00-m02 \
	k01-checker-selftest k01-lint k01-verilator k01-vcs k01-vivado k01 \
	k02-checker-selftest k02-lint k02-verilator k02-ip k02-vcs k02-vivado \
	k02-hw-probe k02-hw-program k02 \
	k03-checker-selftest k03-scrambler-checker-selftest k03-scrambler \
	k03-lint k03-verilator k03-vivado k03 \
	k04-checker-selftest k04-lint k04-verilator k04-verilator-signoff \
	k04-vivado k04 \
	k05-checker-selftest k05-lint k05-verilator k05-verilator-signoff \
	k05-vivado k05 \
	k06-checker-selftest k06-lint k06-verilator k06-verilator-signoff \
	k06-vivado k06 \
	k07-checker-selftest k07-lint k07-verilator k07-vivado k07 \
	k08-checker-selftest k08-lint k08-verilator k08-vivado k08 \
	k09-checker-selftest k09-lint k09-verilator k09-integration \
	k09-vivado k09 \
	k10-checker-selftest k10-lint k10-verilator k10-integration \
	k10-vivado k10 \
	k11a-checker-selftest k11a-lint k11a-bridge k11a-offline \
	k11a-regression k11a-vivado k11a \
	k11b-vcs-serial k11b2-lint k11b2-vcs-serial k11b2-vcs-stress k11b2-vivado clean

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

k02-checker-selftest:
	@$(MAKE) -C sim/verilator/k02 NEGATIVE_STUB=1 \
		TESTCASE=reset_detect_and_rate SIM_BUILD=sim_build_negative
	@cp sim/verilator/k02/results.xml sim/verilator/k02/results_negative.xml
	@if grep -q '<failure' sim/verilator/k02/results.xml; then \
		echo "K02_CHECKER_SELFTEST_PASS"; \
	else \
		echo "错误：故意释放复位的 K02 Stub 未被 Checker 检出"; \
		exit 1; \
	fi

k02-lint:
	verilator --lint-only -Wall -Wno-fatal -Wno-TIMESCALEMOD -Wno-DECLFILENAME \
		-Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
		--top-module kcu105_pcie_phy_bringup_top \
		sim/verilator/k02/xilinx_primitive_stubs.sv \
		sim/verilator/k02/pcie_phy_x1_gen3_behavioral_stub.sv \
		rtl/common/pcie_reset_sync.sv \
		rtl/phy/kcu105_reset_ctrl.sv \
		rtl/phy/kcu105_refclk_reset.sv \
		rtl/phy/kcu105_pcie_phy_wrapper.sv \
		rtl/phy/kcu105_pcie_phy_bringup_top.sv

k02-verilator:
	./sim/verilator/k02/run_k02.sh

k02-ip:
	./fpga/kcu105/run_k02_ip_generation.sh

k02-vcs:
	./sim/vcs/run_k02.sh

k02-vivado:
	./fpga/kcu105/run_k02_impl.sh

k02-hw-probe:
	/home/Xilinx/Vivado/2021.2/bin/vivado -mode batch \
		-source fpga/kcu105/run_k02_hw.tcl -nojournal \
		-log fpga/kcu105/build_k02/hw_probe.log \
		-tclargs localhost:3122 probe

k02-hw-program:
	/home/Xilinx/Vivado/2021.2/bin/vivado -mode batch \
		-source fpga/kcu105/run_k02_hw.tcl -nojournal \
		-log fpga/kcu105/build_k02/hw_program.log \
		-tclargs localhost:3122 program

k02: k02-checker-selftest k02-lint k02-verilator k02-ip k02-vcs k02-vivado

k03-checker-selftest:
	@$(MAKE) -C sim/verilator/k03 NEGATIVE_STUB=1 \
		TESTCASE=normal_training SIM_BUILD=sim_build_negative
	@cp sim/verilator/k03/results.xml sim/verilator/k03/results_negative.xml
	@if grep -q '<failure' sim/verilator/k03/results.xml; then \
		echo "K03_CHECKER_SELFTEST_PASS"; \
	else \
		echo "错误：非法跳过训练状态的 K03 Stub 未被 Checker 检出"; \
		exit 1; \
	fi

k03-scrambler-checker-selftest:
	@$(MAKE) -C sim/verilator/k03_scrambler NEGATIVE_STUB=1 \
		TESTCASE=known_vectors_com_skp_and_bypass SIM_BUILD=sim_build_negative
	@if grep -q '<failure' sim/verilator/k03_scrambler/results.xml; then \
		echo "K03_SCRAMBLER_CHECKER_SELFTEST_PASS"; \
	else \
		echo "错误：旁路扰码的K03 Stub未被已知向量检出"; exit 1; \
	fi

k03-scrambler:
	$(MAKE) -C sim/verilator/k03_scrambler

k03-lint:
	verilator --lint-only -Wall -Wno-fatal -Wno-TIMESCALEMOD \
		--top-module pcie_ltssm_mac_gen1 \
		rtl/phy/pcie_gen12_scrambler.sv \
		rtl/phy/pcie_gen1_rx_symbol_aligner.sv \
		rtl/phy/pcie_gen1_os_rx.sv \
		rtl/phy/pcie_gen1_os_tx.sv \
		rtl/phy/pcie_gen1_framer.sv \
		rtl/phy/pcie_ltssm_mac_gen1.sv
	verilator --lint-only -Wall -Wno-fatal -Wno-TIMESCALEMOD -Wno-DECLFILENAME \
		-Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM --top-module kcu105_pcie_gen1_top \
		sim/verilator/k02/xilinx_primitive_stubs.sv \
		sim/verilator/k02/pcie_phy_x1_gen3_behavioral_stub.sv \
		rtl/common/pcie_reset_sync.sv \
		rtl/phy/kcu105_reset_ctrl.sv \
		rtl/phy/kcu105_refclk_reset.sv \
		rtl/phy/kcu105_pcie_phy_wrapper.sv \
		rtl/phy/pcie_gen12_scrambler.sv \
		rtl/phy/pcie_gen1_rx_symbol_aligner.sv \
		rtl/phy/pcie_gen1_os_rx.sv \
		rtl/phy/pcie_gen1_os_tx.sv \
		rtl/phy/pcie_gen1_framer.sv \
		rtl/phy/pcie_ltssm_mac_gen1.sv \
		rtl/phy/kcu105_pcie_gen1_top.sv

k03-verilator:
	./sim/verilator/k03/run_k03.sh

k03-vivado:
	./fpga/kcu105/run_k03_checks.sh

k03: k03-checker-selftest k03-scrambler-checker-selftest k03-scrambler \
	k03-lint k03-verilator k03-vivado

k11b-vcs-serial:
	./sim/vcs/run_k11b_serial.sh

k11b2-lint:
	verilator --lint-only -Wall -Wno-fatal -Wno-TIMESCALEMOD \
		-Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
		--top-module kcu105_pcie_ep_gen1_top \
		/home/wx/Documents/AXI/prj_wb2axip_master/wb2axip-master/rtl/afifo.v \
		sim/verilator/k02/xilinx_primitive_stubs.sv \
		sim/verilator/k02/pcie_phy_x1_gen3_behavioral_stub.sv \
		rtl/common/pcie_reset_sync.sv rtl/common/pcie_gray_sync.sv \
		rtl/common/pcie_async_pkt_fifo.sv rtl/common/pcie_async_event_fifo.sv \
		rtl/common/pcie_tlp_async_bridge.sv rtl/common/pcie_cdc_snapshot.sv \
		rtl/common/pcie_cdc_pulse.sv rtl/phy/kcu105_reset_ctrl.sv \
		rtl/phy/kcu105_refclk_reset.sv rtl/phy/kcu105_pcie_phy_wrapper.sv \
		rtl/phy/pcie_gen12_scrambler.sv rtl/phy/pcie_gen1_rx_symbol_aligner.sv \
		rtl/phy/pcie_gen1_os_rx.sv rtl/phy/pcie_gen1_os_tx.sv \
		rtl/phy/pcie_gen1_framer.sv rtl/phy/pcie_ltssm_mac_gen1.sv \
		rtl/dll/pcie_crc_stream.sv rtl/dll/pcie_crc16_dllp.sv \
		rtl/dll/pcie_crc32_lcrc.sv rtl/dll/pcie_fc_local_credit_pool.sv \
		rtl/dll/pcie_dllp_codec.sv rtl/dll/pcie_dllp_fc_manager.sv \
		rtl/dll/pcie_dllp_tx_arbiter.sv rtl/dll/pcie_dll_mac_tx_arbiter.sv \
		rtl/dll/pcie_dll_replay.sv rtl/dll/pcie_dll.sv \
		rtl/tl/pcie_tlp_codec.sv rtl/tl/pcie_cfg_space.sv \
		rtl/tl/pcie_bar_axil_master.sv rtl/tl/demo_axil_slave.sv \
		sim/verilator/k09_integration/k09_tlp_test_top.sv \
		rtl/ep/k11a_offline_top.sv rtl/ep/kcu105_pcie_ep_gen1_top.sv

k11b2-vcs-serial:
	./sim/vcs/run_k11b2_serial.sh

k11b2-vcs-stress:
	./sim/vcs/run_k11b2_stress.sh

k11b2-vivado:
	./fpga/kcu105/run_k11b2_impl.sh

k04-checker-selftest:
	@$(MAKE) -C sim/verilator/k04 NEGATIVE_STUB=1 \
		TESTCASE=known_vectors SIM_BUILD=sim_build_negative
	@cp sim/verilator/k04/results.xml sim/verilator/k04/results_negative.xml
	@if grep -q '<failure' sim/verilator/k04/results.xml; then \
		echo "K04_CHECKER_SELFTEST_PASS"; \
	else \
		echo "错误：固定返回零的 K04 CRC Stub 未被 Checker 检出"; \
		exit 1; \
	fi

k04-lint:
	verilator --lint-only -Wall -Wno-fatal -Wno-TIMESCALEMOD \
		--top-module k04_crc_test_top \
		rtl/dll/pcie_crc_stream.sv \
		rtl/dll/pcie_crc16_dllp.sv \
		rtl/dll/pcie_crc32_lcrc.sv \
		sim/verilator/k04/k04_crc_test_top.sv

k04-verilator:
	./sim/verilator/k04/run_k04.sh

k04-verilator-signoff:
	./sim/verilator/k04_native/run_k04_native.sh

k04-vivado:
	./fpga/kcu105/run_k04_crc_ooc.sh

k04: k04-checker-selftest k04-lint k04-verilator \
	k04-verilator-signoff k04-vivado

k05-checker-selftest:
	@$(MAKE) -C sim/verilator/k05 NEGATIVE_STUB=1 \
		TESTCASE=initialization_and_credit_gating SIM_BUILD=sim_build_negative
	@cp sim/verilator/k05/results.xml sim/verilator/k05/results_negative.xml
	@if grep -q '<failure' sim/verilator/k05/results.xml; then \
		echo "K05_CHECKER_SELFTEST_PASS"; \
	else \
		echo "错误：跳过InitFC的K05 Stub未被Checker检出"; \
		exit 1; \
	fi

k05-lint:
	verilator --lint-only -Wall -Wno-fatal -Wno-TIMESCALEMOD \
		--top-module k05_dllp_fc_test_top \
		rtl/common/pcie_reset_sync.sv \
		rtl/dll/pcie_crc_stream.sv \
		rtl/dll/pcie_crc16_dllp.sv \
		rtl/dll/pcie_fc_local_credit_pool.sv \
		rtl/dll/pcie_dllp_codec.sv \
		rtl/dll/pcie_dllp_fc_manager.sv \
		rtl/dll/pcie_dllp_fc.sv \
		sim/verilator/k05/k05_dllp_fc_test_top.sv

k05-verilator:
	./sim/verilator/k05/run_k05.sh

k05-verilator-signoff:
	./sim/verilator/k05_native/run_k05_native.sh

k05-vivado:
	./fpga/kcu105/run_k05_dllp_fc_ooc.sh

k05: k05-checker-selftest k05-lint k05-verilator \
	k05-verilator-signoff k05-vivado

k06-checker-selftest:
	@$(MAKE) -C sim/verilator/k06 NEGATIVE_STUB=1 \
		TESTCASE=tx_sequence_lcrc_and_credit SIM_BUILD=sim_build_negative
	@cp sim/verilator/k06/results.xml sim/verilator/k06/results_negative.xml
	@if grep -q '<failure' sim/verilator/k06/results.xml; then \
		echo "K06_CHECKER_SELFTEST_PASS"; \
	else \
		echo "错误：不发送Sequence/LCRC的K06 Stub未被Checker检出"; \
		exit 1; \
	fi

k06-lint:
	verilator --lint-only -Wall -Wno-fatal -Wno-TIMESCALEMOD \
		--top-module pcie_dll_replay \
		rtl/common/pcie_reset_sync.sv \
		rtl/dll/pcie_crc_stream.sv \
		rtl/dll/pcie_crc32_lcrc.sv \
		rtl/dll/pcie_dll_replay.sv
	verilator --lint-only -Wall -Wno-fatal -Wno-TIMESCALEMOD \
		--top-module pcie_dll \
		rtl/common/pcie_reset_sync.sv \
		rtl/dll/pcie_crc_stream.sv \
		rtl/dll/pcie_crc16_dllp.sv \
		rtl/dll/pcie_crc32_lcrc.sv \
		rtl/dll/pcie_dllp_codec.sv \
		rtl/dll/pcie_fc_local_credit_pool.sv \
		rtl/dll/pcie_dllp_fc_manager.sv \
		rtl/dll/pcie_dll_replay.sv \
		rtl/dll/pcie_dllp_tx_arbiter.sv \
		rtl/dll/pcie_dll_mac_tx_arbiter.sv \
		rtl/dll/pcie_dll.sv

k06-verilator:
	./sim/verilator/k06/run_k06.sh
	cp sim/verilator/k06/results.xml sim/verilator/k06/results_core.xml
	$(MAKE) -C sim/verilator/k06 ARB_TEST=1 SIM_BUILD=sim_build_arb
	@cp sim/verilator/k06/results.xml sim/verilator/k06/results_arbiter.xml
	@if grep -q '<failure' sim/verilator/k06/results.xml; then \
		echo "错误：K06仲裁器回归存在失败"; exit 1; \
	fi

k06-verilator-signoff:
	./sim/verilator/k06_native/run_k06_native.sh

k06-vivado:
	./fpga/kcu105/run_k06_dll_ooc.sh

k06: k06-checker-selftest k06-lint k06-verilator \
	k06-verilator-signoff k06-vivado

k07-checker-selftest:
	@$(MAKE) -C sim/verilator/k07 NEGATIVE_STUB=1 \
		TESTCASE=whole_packet_commit_guard SIM_BUILD=sim_build_negative \
		COCOTB_RESULTS_FILE=results_negative.xml
	@if grep -q '<failure' sim/verilator/k07/results_negative.xml; then \
		echo "K07_CHECKER_SELFTEST_PASS"; \
	else \
		echo "错误：提前分派Cfg请求的K07 Stub未被Checker检出"; \
		exit 1; \
	fi

k07-lint:
	verilator --lint-only -Wall -Wno-TIMESCALEMOD \
		--top-module pcie_tlp_codec \
		rtl/tl/pcie_tlp_codec.sv
	verilator --lint-only -Wall -Wno-TIMESCALEMOD \
		--top-module k07_tlp_codec_ooc_top \
		rtl/common/pcie_reset_sync.sv \
		rtl/tl/pcie_tlp_codec.sv \
		rtl/tl/k07_tlp_codec_ooc_top.sv
	./sim/verilator/k07/check_counter_saturation.py

k07-verilator:
	./sim/verilator/k07/run_k07.sh

k07-vivado:
	./fpga/kcu105/run_k07_tlp_codec_ooc.sh

k07:
	$(MAKE) k07-checker-selftest
	$(MAKE) k07-lint
	$(MAKE) k07-verilator
	$(MAKE) k07-vivado

k08-checker-selftest:
	@$(RM) sim/verilator/k08/negative_checker_observed.txt \
		sim/verilator/k08/results_negative.xml
	@$(MAKE) -C sim/verilator/k08 NEGATIVE_STUB=1 \
		TESTCASE=identity_and_bar_probe_guard SIM_BUILD=sim_build_negative \
		COCOTB_RESULTS_FILE=results_negative.xml
	@if grep -q '<failure' sim/verilator/k08/results_negative.xml && \
		grep -qx 'K08_NEGATIVE_CHECKER_OBSERVED identity bar be' \
			sim/verilator/k08/negative_checker_observed.txt; then \
		echo "K08_CHECKER_SELFTEST_PASS identity=1 bar=1 be=1"; \
	else \
		echo "错误：K08错误Stub未被三个值守卫完整检出"; exit 1; \
	fi

k08-lint:
	verilator --lint-only -Wall -Wno-TIMESCALEMOD \
		--top-module pcie_cfg_space \
		rtl/tl/pcie_cfg_space.sv
	verilator --lint-only -Wall -Wno-TIMESCALEMOD \
		--top-module k08_cfg_space_ooc_top \
		rtl/common/pcie_reset_sync.sv \
		rtl/tl/pcie_cfg_space.sv \
		rtl/tl/k08_cfg_space_ooc_top.sv
	verilator --lint-only -Wall -Wno-TIMESCALEMOD \
		--top-module k08_cfg_tlp_test_top \
		rtl/tl/pcie_tlp_codec.sv \
		rtl/tl/pcie_cfg_space.sv \
		sim/verilator/k08/k08_cfg_tlp_test_top.sv

k08-verilator:
	./sim/verilator/k08/run_k08.sh

k08-vivado:
	./fpga/kcu105/run_k08_cfg_space_ooc.sh

k08:
	$(MAKE) k08-checker-selftest
	$(MAKE) k08-lint
	$(MAKE) k08-verilator
	$(MAKE) k08-vivado

k09-checker-selftest:
	@$(RM) sim/verilator/k09/k09_negative_marker.txt \
		sim/verilator/k09/results_negative.xml
	@K09_NEGATIVE_STUB=1 \
		K09_NEGATIVE_MARKER=$(CURDIR)/sim/verilator/k09/k09_negative_marker.txt \
		COCOTB_RESULTS_FILE=results_negative.xml TESTCASE=checker_guard \
		$(MAKE) -C sim/verilator/k09 K09_NEGATIVE_STUB=1
	@if grep -q '<failure' sim/verilator/k09/results_negative.xml && \
		grep -qx 'K09_NEGATIVE_CHECKER_OBSERVED address be posted' \
			sim/verilator/k09/k09_negative_marker.txt; then \
		echo "K09_CHECKER_SELFTEST_PASS address=1 be=1 posted=1"; \
	else \
		echo "错误：K09错误Stub未被address/be/posted三个守卫完整检出"; exit 1; \
	fi

k09-lint:
	verilator --lint-only -Wall -Wno-TIMESCALEMOD \
		--top-module pcie_bar_axil_master \
		rtl/tl/pcie_bar_axil_master.sv
	verilator --lint-only -Wall -Wno-TIMESCALEMOD \
		--top-module k09_tlp_test_top \
		rtl/tl/pcie_tlp_codec.sv \
		rtl/tl/pcie_cfg_space.sv \
		rtl/tl/pcie_bar_axil_master.sv \
		sim/verilator/k09_integration/k09_tlp_test_top.sv
	$(PYTHON) -m py_compile \
		sim/verilator/k09/k09_model.py \
		sim/verilator/k09/test_pcie_bar_axil_master.py \
		sim/verilator/k09/check_counter_saturation.py \
		sim/verilator/k09_integration/k09_simport_adapter.py \
		sim/verilator/k09_integration/test_k09_tlp_integration.py
	$(PYTHON) sim/verilator/k09/check_counter_saturation.py

k09-verilator:
	@$(RM) sim/verilator/k09/k09_negative_marker.txt \
		sim/verilator/k09/k09_random_evidence.txt \
		sim/verilator/k09/results.xml
	@K09_NEGATIVE_STUB=0 K09_RANDOM_REQUESTS=100000 \
		K09_RANDOM_EVIDENCE=$(CURDIR)/sim/verilator/k09/k09_random_evidence.txt \
		COCOTB_RESULTS_FILE=results.xml TESTCASE= \
		$(MAKE) -C sim/verilator/k09
	@if test ! -s sim/verilator/k09/results.xml || \
		grep -Eq '<failure|<error' sim/verilator/k09/results.xml || \
		test "$$(grep -c '<testcase ' sim/verilator/k09/results.xml)" != 9 || \
		! grep -q 'name="randomized_100k_reference"' \
			sim/verilator/k09/results.xml || \
		! grep -q '^K09_RANDOM_SIGNOFF seed=20260807 requests=100000 random_ready=1 max_delay=3 ' \
			sim/verilator/k09/k09_random_evidence.txt; then \
		echo "错误：K09单模块JUnit缺失、失败或测试集合不完整"; exit 1; \
	fi
	@echo "K09_VERILATOR_PASS requests=100000"

k09-integration:
	./sim/verilator/k09_integration/run_k09_integration.sh

k09-vivado:
	./fpga/kcu105/run_k09_bar_axil_ooc.sh

k09:
	$(MAKE) k09-checker-selftest
	$(MAKE) k09-lint
	$(MAKE) k09-verilator
	$(MAKE) k09-integration
	$(MAKE) k09-vivado

k10-checker-selftest:
	@$(RM) sim/verilator/k10/k10_negative_marker.txt \
		sim/verilator/k10/results_negative.xml
	@K10_NEGATIVE_STUB=1 \
		K10_NEGATIVE_MARKER=$(CURDIR)/sim/verilator/k10/k10_negative_marker.txt \
		COCOTB_RESULTS_FILE=results_negative.xml TESTCASE=checker_guard \
		$(MAKE) -C sim/verilator/k10 K10_NEGATIVE_STUB=1
	@if grep -q '<failure' sim/verilator/k10/results_negative.xml && \
		grep -qx 'K10_NEGATIVE_CHECKER_OBSERVED signature strobe decerr' \
			sim/verilator/k10/k10_negative_marker.txt; then \
		echo "K10_CHECKER_SELFTEST_PASS signature=1 strobe=1 decerr=1"; \
	else \
		echo "错误：K10错误Stub未被三个守卫完整检出"; exit 1; \
	fi

k10-lint:
	verilator --lint-only -Wall -Wno-TIMESCALEMOD \
		--top-module demo_axil_slave rtl/tl/demo_axil_slave.sv
	verilator --lint-only -Wall -Wno-TIMESCALEMOD \
		--top-module k10_bar_demo_top \
		rtl/tl/pcie_bar_axil_master.sv \
		rtl/tl/demo_axil_slave.sv \
		sim/verilator/k10_integration/k10_bar_demo_top.sv
	$(PYTHON) -m py_compile sim/verilator/k10/test_demo_axil_slave.py \
		sim/verilator/k10_integration/test_k10_bar_demo_integration.py

k10-verilator:
	@$(RM) sim/verilator/k10/k10_negative_marker.txt \
		sim/verilator/k10/k10_random_evidence.txt \
		sim/verilator/k10/results.xml
	@K10_NEGATIVE_STUB=0 K10_RANDOM_REQUESTS=100000 \
		K10_RANDOM_EVIDENCE=$(CURDIR)/sim/verilator/k10/k10_random_evidence.txt \
		COCOTB_RESULTS_FILE=results.xml TESTCASE= \
		$(MAKE) -C sim/verilator/k10
	@if test ! -s sim/verilator/k10/results.xml || \
		grep -Eq '<failure|<error' sim/verilator/k10/results.xml || \
		test "$$(grep -c '<testcase ' sim/verilator/k10/results.xml)" != 7 || \
		! grep -q 'name="randomized_100k_reference"' \
			sim/verilator/k10/results.xml || \
		! grep -q '^K10_RANDOM_SIGNOFF seed=20260810 requests=100000 ' \
			sim/verilator/k10/k10_random_evidence.txt; then \
		echo "错误：K10单模块JUnit或100k证据不完整"; exit 1; \
	fi
	@echo "K10_VERILATOR_PASS requests=100000"

k10-integration:
	$(MAKE) -C sim/verilator/k10_integration

k10-vivado:
	./fpga/kcu105/run_k10_demo_axil_ooc.sh

k10:
	$(MAKE) k10-checker-selftest
	$(MAKE) k10-lint
	$(MAKE) k10-verilator
	$(MAKE) k10-integration
	$(MAKE) k10-vivado

k11a-checker-selftest:
	@$(RM) sim/verilator/k11a/k11a_negative_marker.txt \
		sim/verilator/k11a/results_negative.xml
	@cd sim/verilator/k11a && \
		CCACHE_DISABLE=1 \
		K11A_NEGATIVE_MARKER=$$(pwd)/k11a_negative_marker.txt \
		COCOTB_RESULTS_FILE=results_negative.xml TESTCASE=tx_metadata_checker \
		$(MAKE) NEGATIVE_STUB=1 SIM_BUILD=sim_build_negative || true
	@if grep -q '<failure' sim/verilator/k11a/results_negative.xml && \
		grep -qx 'K11A_NEGATIVE_CHECKER_OBSERVED metadata' \
			sim/verilator/k11a/k11a_negative_marker.txt; then \
		echo 'K11A_CHECKER_SELFTEST_PASS metadata=1'; \
	else echo '错误：K11-A错误Stub未被元数据守卫检出'; exit 1; fi

k11a-lint:
	verilator --lint-only -Wall -Wno-fatal -Wno-TIMESCALEMOD \
		--top-module k11a_offline_top \
		/home/wx/Documents/AXI/prj_wb2axip_master/wb2axip-master/rtl/afifo.v \
		rtl/common/pcie_reset_sync.sv rtl/common/pcie_gray_sync.sv \
		rtl/common/pcie_async_pkt_fifo.sv rtl/common/pcie_async_event_fifo.sv \
		rtl/common/pcie_tlp_async_bridge.sv rtl/common/pcie_cdc_snapshot.sv \
		rtl/common/pcie_cdc_pulse.sv \
		rtl/dll/pcie_crc_stream.sv rtl/dll/pcie_crc16_dllp.sv \
		rtl/dll/pcie_crc32_lcrc.sv rtl/dll/pcie_fc_local_credit_pool.sv \
		rtl/dll/pcie_dllp_codec.sv rtl/dll/pcie_dllp_fc_manager.sv \
		rtl/dll/pcie_dllp_tx_arbiter.sv rtl/dll/pcie_dll_mac_tx_arbiter.sv \
		rtl/dll/pcie_dll_replay.sv rtl/dll/pcie_dll.sv \
		rtl/tl/pcie_tlp_codec.sv rtl/tl/pcie_cfg_space.sv \
		rtl/tl/pcie_bar_axil_master.sv rtl/tl/demo_axil_slave.sv \
		sim/verilator/k09_integration/k09_tlp_test_top.sv \
		rtl/ep/k11a_offline_top.sv

k11a-bridge:
	cd sim/verilator/k11a && CCACHE_DISABLE=1 \
		COCOTB_RESULTS_FILE=results.xml $(MAKE) SIM_BUILD=sim_build

k11a-offline:
	cd sim/verilator/k11a && CCACHE_DISABLE=1 \
		COCOTB_RESULTS_FILE=offline_results.xml \
		$(MAKE) -f Makefile.offline SIM_BUILD=sim_build_offline

k11a-regression: k09-integration k10-integration

k11a-vivado:
	./fpga/kcu105/run_k11a_offline_ooc.sh

k11a: k11a-checker-selftest k11a-lint k11a-bridge k11a-offline \
	k11a-regression k11a-vivado

clean:
	$(MAKE) -C sim/verilator clean
	$(RM) sim/verilator/results.xml
	./sim/verilator/m02/clean.sh
	./sim/verilator/k01/clean.sh
	./sim/verilator/k02/clean.sh
	./sim/verilator/k03/clean.sh
	./sim/verilator/k04/clean.sh
	./sim/verilator/k04_native/clean.sh
	./sim/verilator/k05/clean.sh
	./sim/verilator/k06/clean.sh
	./sim/verilator/k06_native/clean.sh
	./sim/verilator/k07/clean.sh
	./sim/verilator/k08/clean.sh
	./sim/verilator/k09/clean.sh
	./sim/verilator/k09_integration/clean.sh
	./sim/verilator/k10/clean.sh
	./sim/verilator/k10_integration/clean.sh
	$(RM) -r sim/verilator/k11a/sim_build \
		sim/verilator/k11a/sim_build_negative \
		sim/verilator/k11a/sim_build_offline
	$(RM) sim/verilator/k11a/*.xml \
		sim/verilator/k11a/k11a_negative_marker.txt
	$(RM) -r fpga/kcu105/build_k06
	$(RM) -r fpga/kcu105/build_k07
	$(RM) -r fpga/kcu105/build_k08
	$(RM) -r fpga/kcu105/build_k09
	$(RM) -r fpga/kcu105/build_k10
	$(RM) -r fpga/kcu105/build_k11a
	./sim/verilator/k05_native/clean.sh
	$(RM) -r sim/verilator/m02_native/build
	./sim/vcs/clean.sh
	$(RM) -r fpga/kcu105/build_k00_m02
	$(RM) -r fpga/kcu105/build_k01
	$(RM) -r fpga/kcu105/build_k03
	$(RM) -r fpga/kcu105/build_k04
	$(RM) -r fpga/kcu105/build_k05
