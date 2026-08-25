.PHONY: k00 k00-baseline k00-verilator k00-pcie-model k00-vcs \
	k00-m02-checker-selftest k00-m02-afifo-check k00-m02-lint \
	k00-m02-verilator k00-m02-verilator-signoff k00-m02-vcs \
	k00-m02-vivado k00-m02 \
	k01-checker-selftest k01-lint k01-verilator k01-vcs k01-vivado k01 \
	k02-checker-selftest k02-lint k02-verilator k02-ip k02-vcs k02-gen3-vcs k02-vivado \
	k02-hw-probe k02-hw-program k02 phy-command-ctrl-test phy-command-ownership \
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
	k11b-vcs-serial k11b2-lint k11b2-vcs-serial k11b2-vcs-stress k11b2-vivado \
	k11b2-hw-probe k11b2-hw-program k11b2-hw-acceptance k11b2-hw-program-debug \
	k14-recovery-speed-vivado k14-recovery-speed-hw-program-arm \
	k14-recovery-speed-hw-capture-wait k14-recovery-speed-hw-upload \
	k14-recovery-speed-hw-repeat k14-recovery-speed-test \
	g2-gen1-vcs-serial g2-gen1-vivado g2-gen1-hw-program \
	k11b2-debug-finalize k11b2-ila-lint k11b2-ila-vivado \
	k11b2-ila-hw-program-arm k11b2-ila-hw-capture-wait \
	k11b2-ila-hw-capture-cfg-wait k11b2-ila-hw-capture-tx-wait \
	k11b2-ila-hw-capture-cfg-complete-wait \
	k11b2-ila-hw-program-arm-cfg-complete k11b2-ila-hw-program-arm-detect-active \
	k11b2-ila-hw-arm-detect-active \
	k11b2-ila-hw-program-arm-perst k11b2-ila-hw-program-arm-perst-release k11b2-ila-hw-program-arm-phy-reset-release \
	k11b2-ila-hw-program-arm-linkdown k11b2-ila-hw-capture-linkdown-wait \
	k11b2-ila-hw-program-arm-rxidle-conflict k11b2-ila-hw-capture-rxidle-conflict-wait \
	k11b2-ila-hw-capture-now k11b2-ila-hw-upload \
	k11b3-trigger-sim k11b3-cdc-sim k11b3-diagnostic-sim \
	k12a-cdc-lint k12a-cdc k12a-checker-selftest k12a \
	k12b-speed-lint k12b-speed k12b-checker-selftest k12b \
	k12c-eq-lint k12c-eq k12c-checker-selftest k12c \
	k12-integration-lint k12-integration-sim k12-integration-checker-selftest k12-integration \
	k12de-vcs-serial k12de \
	k13-rate-contract k13-ctrl-lint k13-ctrl-sim \
	ku040-hw-probe ku040-hw-program \
	remote-check remote-reboot remote-wait remote-lspci remote-cycle remote-retrain-gen3 \
	xdma-x1-demo xdma-x1-hw-program clean

PYTHON ?= python3
VIVADO ?= /home/Xilinx/Vivado/2021.2/bin/vivado
KU040_SERVER ?= localhost:3122
KU040_BIT ?= fpga/kcu105/build_k11_gen1_release/impl/k11b2_gen1_endpoint.bit

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

# K02 lint：K02 顶层实例化 Golden `phy_ctrl.v` + `phy_bringup_seq`，
# 需 +incdir+rtl/phy（phy_ctrl_pat_gen_lane.v:62 引用 `phy_ctrl_defines.vh`），
# 需 --timing 容忍 phy_ctrl.v 的 `#(TCQ)` 非阻塞延迟。
# 实板 ILA PASS: seq_state 走到 S_DONE、debug_state==8'h04、QPLL1LOCK 1->0->1。
k02-lint:
	verilator --lint-only --timing -Wall -Wno-fatal -Wno-TIMESCALEMOD -Wno-DECLFILENAME \
		-Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-INITIALDLY -Wno-CASEINCOMPLETE -Wno-WIDTH \
		+incdir+rtl/phy \
		--top-module kcu105_pcie_phy_bringup_top \
		sim/verilator/k02/xilinx_primitive_stubs.sv \
		sim/verilator/k02/pcie_phy_x1_gen3_behavioral_stub.sv \
		rtl/common/pcie_reset_sync.sv \
		rtl/phy/kcu105_reset_ctrl.sv \
		rtl/phy/kcu105_refclk_reset.sv \
		rtl/phy/kcu105_pcie_phy_wrapper.sv \
		rtl/phy/phy_ctrl.v \
		rtl/phy/phy_ctrl_pat_gen.v \
		rtl/phy/phy_ctrl_pat_gen_lane.v \
		rtl/phy/phy_bringup_seq.sv \
		rtl/phy/k02_phy_event_recorder.sv \
		rtl/phy/kcu105_pcie_phy_bringup_top.sv

k02-verilator:
	./sim/verilator/k02/run_k02.sh

k02-ip:
	./fpga/kcu105/run_k02_ip_generation.sh

k02-vcs:
	./sim/vcs/run_k02.sh

k02-query-vcs:
	K02_VCS_DYNAMIC_TXEQ=1 K02_VCS_QUERY=1 ./sim/vcs/run_k02.sh

k02-gen3-vcs:
	K02_VCS_GEN3_STEADY=1 ./sim/vcs/run_k02.sh

# K02 顶层直接实例化 Golden 控制器（commit 7d39d60 起的 K02_USE_PHY_CTRL=1 路径
# 升级为唯一路径）。bit/probe 落到 fpga/kcu105/build_k02/。
k02-vivado:
	./fpga/kcu105/run_k02_impl.sh

k02-hw-probe:
	$(VIVADO) -mode batch \
		-source fpga/kcu105/run_k02_hw.tcl -nojournal \
		-log fpga/kcu105/build_k02/hw_probe.log \
		-tclargs localhost:3122 probe

k02-hw-program:
	$(VIVADO) -mode batch \
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
		rtl/phy/pcie_gen3_scrambler32.sv \
		rtl/phy/pcie_gen3_os_rx.sv \
		rtl/phy/pcie_gen3_os_tx.sv \
		rtl/phy/pcie_gen1_framer.sv \
		rtl/phy/pcie_phy_command_ctrl.sv \
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
		rtl/phy/pcie_gen3_scrambler32.sv \
		rtl/phy/pcie_gen3_os_rx.sv \
		rtl/phy/pcie_gen3_os_tx.sv \
		rtl/phy/pcie_gen1_framer.sv \
		rtl/phy/pcie_phy_command_ctrl.sv \
		rtl/phy/pcie_ltssm_mac_gen1.sv \
		rtl/phy/kcu105_pcie_gen1_top.sv

k03-verilator:
	./sim/verilator/k03/run_k03.sh

phy-command-ctrl-test:
	verilator --cc --exe --build -Wall -Wno-fatal -Wno-TIMESCALEMOD \
		--top-module pcie_phy_command_ctrl \
		-GGOLDEN_RELEASE_GAP_CYCLES=4 -GRATE_TIMEOUT_CYCLES=8 \
		-GGEN3_TX_SETTLE_CYCLES=2 \
		$(CURDIR)/rtl/phy/pcie_phy_command_ctrl.sv \
		$(CURDIR)/sim/verilator/phy_command_ctrl/pcie_phy_command_ctrl_test.cpp \
		-Mdir sim/verilator/phy_command_ctrl/sim_build
	./sim/verilator/phy_command_ctrl/sim_build/Vpcie_phy_command_ctrl

phy-command-ownership:
	python3 scripts/check_phy_command_ownership.py

k14-recovery-speed-test:
	verilator --cc --exe --build -Wall -Wno-fatal -Wno-TIMESCALEMOD \
		--top-module k14_recovery_speed_test_top \
		$(CURDIR)/rtl/phy/pcie_phy_command_ctrl.sv \
		$(CURDIR)/rtl/phy/pcie_recovery_speed_ctrl.sv \
		$(CURDIR)/sim/verilator/k14_recovery_speed/k14_recovery_speed_test_top.sv \
		$(CURDIR)/sim/verilator/k14_recovery_speed/k14_recovery_speed_test.cpp \
		-Mdir sim/verilator/k14_recovery_speed/sim_build
	./sim/verilator/k14_recovery_speed/sim_build/Vk14_recovery_speed_test_top

k03-vivado:
	./fpga/kcu105/run_k03_checks.sh

k03: k03-checker-selftest k03-scrambler-checker-selftest k03-scrambler \
	k03-lint k03-verilator k03-vivado

k11b-vcs-serial:
	./sim/vcs/run_k11b_serial.sh

k11b2-lint:
	verilator $(K11B2_LINT_DEFINES) --lint-only -Wall -Wno-fatal -Wno-TIMESCALEMOD \
		-Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
		--top-module kcu105_pcie_ep_gen1_top \
		/home/wx/Documents/AXI/prj_wb2axip_master/wb2axip-master/rtl/afifo.v \
		sim/verilator/k02/xilinx_primitive_stubs.sv \
		sim/verilator/k02/pcie_phy_x1_gen3_behavioral_stub.sv \
		rtl/common/pcie_reset_sync.sv rtl/common/pcie_gray_sync.sv \
		rtl/common/pcie_async_pkt_fifo.sv rtl/common/pcie_async_event_fifo.sv \
		rtl/common/pcie_tlp_async_bridge.sv rtl/common/pcie_cdc_snapshot.sv \
		rtl/common/pcie_cdc_pulse.sv rtl/common/pcie_link_loss_trigger.sv \
		rtl/phy/kcu105_reset_ctrl.sv \
		rtl/phy/kcu105_refclk_reset.sv rtl/phy/kcu105_pcie_phy_wrapper.sv \
		rtl/phy/pcie_gen12_scrambler.sv rtl/phy/pcie_gen1_rx_symbol_aligner.sv \
		rtl/phy/pcie_gen1_os_rx.sv rtl/phy/pcie_gen1_os_tx.sv \
		rtl/phy/pcie_gen3_scrambler32.sv rtl/phy/pcie_gen3_os_rx.sv rtl/phy/pcie_gen3_os_tx.sv \
		rtl/phy/pcie_gen1_framer.sv rtl/phy/pcie_phy_command_ctrl.sv \
		rtl/phy/pcie_ltssm_mac_gen1.sv \
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
	./fpga/kcu105/run_k11_gen1_release.sh

k14-recovery-speed-vivado:
	./fpga/kcu105/run_k14_recovery_speed_impl.sh

k12a-cdc-lint:
	verilator --lint-only -Wall -Wno-fatal -Wno-TIMESCALEMOD \
		--top-module pcie_retrain_cdc_mailbox \
		rtl/common/pcie_retrain_cdc_mailbox.sv

k12a-cdc:
	@rm -f sim/verilator/k12a_cdc/results.xml
	$(MAKE) -C sim/verilator/k12a_cdc \
		COCOTB_RESULTS_FILE=results.xml results.xml
	@if grep -Eq '<failure|<error|<skipped' sim/verilator/k12a_cdc/results.xml; then \
		echo "错误：K12-A CDC mailbox回归失败"; exit 1; \
	fi
	@grep -q 'valid_must_hold_until_accept' sim/verilator/k12a_cdc/results.xml
	@grep -q 'payload_is_atomic_and_busy_command_is_reported' sim/verilator/k12a_cdc/results.xml
	@grep -q 'illegal_speed_is_transferred_for_controller_rejection' sim/verilator/k12a_cdc/results.xml
	@echo "K12A_CDC_MAILBOX_PASS"

k12a-checker-selftest:
	$(MAKE) -C sim/verilator/k12a_cdc checker-selftest

k12a: k12a-checker-selftest k12a-cdc-lint k12a-cdc
	@echo "K12A_PASS"

k12b-speed-lint:
	verilator --lint-only -Wall -Wno-fatal -Wno-TIMESCALEMOD \
		--top-module pcie_recovery_speed_ctrl \
		rtl/phy/pcie_recovery_speed_ctrl.sv

k12b-speed:
	@rm -f sim/verilator/k12b_speed/results.xml
	$(MAKE) -C sim/verilator/k12b_speed SIM_BUILD=sim_build_k12b COCOTB_RESULTS_FILE=results.xml results.xml
	@if grep -Eq '<failure|<error|<skipped' sim/verilator/k12b_speed/results.xml; then \
		echo "错误：K12-B Recovery.Speed回归失败"; exit 1; \
	fi
	@grep -q 'normal_gen1_to_gen3_speed_handshake' sim/verilator/k12b_speed/results.xml
	@grep -q 'internal_speed_timeout_falls_back_to_gen1' sim/verilator/k12b_speed/results.xml
	@grep -q 'peer_reject_falls_back_to_gen1' sim/verilator/k12b_speed/results.xml
	@grep -q 'illegal_target_is_rejected_at_l0' sim/verilator/k12b_speed/results.xml
	@echo "K12B_RECOVERY_SPEED_PASS"

k12b-checker-selftest:
	$(MAKE) -C sim/verilator/k12b_speed checker-selftest

k12b: k12b-checker-selftest k12b-speed-lint k12b-speed
	@echo "K12B_PASS"

k13-rate-contract:
	$(MAKE) -C sim/verilator/k13_rate_contract \
		SIM_BUILD=sim_build_k13_rate_contract \
		COCOTB_RESULTS_FILE=results.xml results.xml
	@if grep -Eq '<failure|<error|<skipped' sim/verilator/k13_rate_contract/results.xml; then \
		echo "错误：K13 PHY Rate Contract回归失败"; exit 1; \
	fi
	@echo "K13_RATE_CONTRACT_PASS"

k12c-eq-lint:
	verilator --lint-only -Wall -Wno-fatal -Wno-TIMESCALEMOD \
		--top-module pcie_equalization_ctrl \
		rtl/phy/pcie_equalization_ctrl.sv

k12c-eq:
	@rm -f sim/verilator/k12c_eq/results.xml
	$(MAKE) -C sim/verilator/k12c_eq SIM_BUILD=sim_build_k12c COCOTB_RESULTS_FILE=results.xml results.xml
	@if grep -Eq '<failure|<error|<skipped' sim/verilator/k12c_eq/results.xml; then \
		echo "错误：K12-C Equalization回归失败"; exit 1; \
	fi
	@grep -q 'normal_phase_0_to_3' sim/verilator/k12c_eq/results.xml
	@grep -q 'illegal_preset_or_coefficient_is_rejected' sim/verilator/k12c_eq/results.xml
	@grep -q 'tx_done_timeout_fails_and_clears_commands' sim/verilator/k12c_eq/results.xml
	@grep -q 'rx_done_timeout_fails_and_clears_commands' sim/verilator/k12c_eq/results.xml
	@echo "K12C_EQ_PHASES_PASS"

k12c-checker-selftest:
	$(MAKE) -C sim/verilator/k12c_eq checker-selftest

k12c: k12c-checker-selftest k12c-eq-lint k12c-eq
	@echo "K12C_PASS"

k12-integration-lint:
	verilator --lint-only -Wall -Wno-fatal -Wno-TIMESCALEMOD \
		--top-module k12_behavioral_partner_top \
		rtl/common/pcie_retrain_cdc_mailbox.sv \
		rtl/phy/pcie_phy_rate_contract.sv \
		rtl/phy/pcie_recovery_speed_ctrl.sv \
		rtl/phy/pcie_equalization_ctrl.sv \
		rtl/phy/pcie_recovery_ts_guard.sv \
		sim/verilator/k12_integration/k12_behavioral_partner_top.sv

k12-integration-sim:
	@rm -f sim/verilator/k12_integration/results.xml
	$(MAKE) -C sim/verilator/k12_integration SIM_BUILD=sim_build_k12_integration COCOTB_RESULTS_FILE=results.xml results.xml
	@if grep -Eq '<failure|<error|<skipped' sim/verilator/k12_integration/results.xml; then \
		echo "错误：K12-A/B/C行为PHY Partner集成回归失败"; exit 1; \
	fi
	@grep -q 'integrated_rate_and_eq_handshake_respects_boundaries' sim/verilator/k12_integration/results.xml
	@grep -q 'peer_reject_falls_back_in_integrated_partner' sim/verilator/k12_integration/results.xml
	@grep -q 'eq_timeout_is_reported_by_integrated_partner' sim/verilator/k12_integration/results.xml
	@echo "K12_INTEGRATION_PASS"

k12-integration-checker-selftest:
	$(MAKE) -C sim/verilator/k12_integration checker-selftest

k12-integration: k12-integration-checker-selftest k12-integration-lint k12-integration-sim
	@echo "K12_INTEGRATION_GATE_PASS"

k12de-vcs-serial:
	./sim/vcs/run_k12e_vcs_serial.sh

k12de: k12-integration k12de-vcs-serial
	@echo "K12DE_PASS"

k12: k12a k12b k12c k12de
	@echo "K12_A_TO_E_PASS"

k13-ctrl-lint:
	verilator --lint-only -Wall -Wno-fatal -Wno-TIMESCALEMOD \
		--top-module pcie_k13_production_ctrl \
		-GK13_ENABLE=1 \
		rtl/common/pcie_retrain_cdc_mailbox.sv \
		rtl/phy/pcie_phy_rate_contract.sv \
		rtl/phy/pcie_recovery_speed_ctrl.sv \
		rtl/phy/pcie_equalization_ctrl.sv \
		rtl/phy/pcie_recovery_ts_guard.sv \
		rtl/phy/pcie_k13_production_ctrl.sv

k13-ctrl-sim:
	@rm -f sim/verilator/k13_ctrl/results.xml
	$(MAKE) -C sim/verilator/k13_ctrl \
		SIM_BUILD=sim_build_k13_ctrl COCOTB_RESULTS_FILE=results.xml results.xml
	@if grep -Eq '<failure|<error|<skipped' sim/verilator/k13_ctrl/results.xml; then \
		echo "错误：K13生产控制器回归失败"; exit 1; \
	fi
	@grep -q 'production_gen3_speed_eq_path' sim/verilator/k13_ctrl/results.xml
	@grep -q 'production_cdr_loss_fallback' sim/verilator/k13_ctrl/results.xml
	@grep -q 'production_bad_ts_rejects' sim/verilator/k13_ctrl/results.xml
	@grep -q 'production_rxeq_done_without_adapt_falls_back' sim/verilator/k13_ctrl/results.xml
	@echo "K13_CTRL_SIM_PASS"

# K13 full-top/LTSSM integration is intentionally reference-only after the
# Gen1 command-boundary split.  Its RTL, tests and reports remain in-tree but
# are not production Make entry points.  Independent rate-contract/controller
# unit targets above remain available for later Phase D work.

g2-gen1-vcs-serial:
	G2_GEN1_ONLY=1 K11B2_MODE=1 K11B_SKIP_SELFTEST=1 ./sim/vcs/run_k11b_serial.sh

g2-gen1-vivado:
	./fpga/kcu105/run_g2_gen1_impl.sh

k11b2-debug-finalize:
	$(VIVADO) -mode batch -nojournal -nolog \
		-source fpga/kcu105/finalize_k11b2_debug.tcl

k11b2-ila-lint:
	$(MAKE) k11b2-lint K11B2_LINT_DEFINES=-GK11B2_ILA_DEBUG=1

k11b2-ila-vivado:
	./fpga/kcu105/run_k11b2_ila_impl.sh

k11b2-ila-hw-program-arm:
	$(VIVADO) -mode batch -nojournal -nolog \
		-source fpga/kcu105/run_k11b2_ila_hw.tcl \
		-tclargs localhost:3122 program-arm

k11b2-ila-hw-program-arm-linkdown:
	$(VIVADO) -mode batch -nojournal -nolog \
		-source fpga/kcu105/run_k11b2_ila_hw.tcl \
		-tclargs localhost:3122 program-arm-linkdown

k11b2-ila-hw-program-arm-rxidle-conflict:
	$(VIVADO) -mode batch -nojournal -nolog \
		-source fpga/kcu105/run_k11b2_ila_hw.tcl \
		-tclargs localhost:3122 program-arm-rxidle-conflict

k11b2-ila-hw-capture-wait:
	$(VIVADO) -mode batch -nojournal -nolog \
		-source fpga/kcu105/run_k11b2_ila_hw.tcl \
		-tclargs localhost:3122 capture-wait

k11b2-ila-hw-capture-cfg-wait:
	$(VIVADO) -mode batch -nojournal -nolog \
		-source fpga/kcu105/run_k11b2_ila_hw.tcl \
		-tclargs localhost:3122 capture-cfg-wait

k11b2-ila-hw-capture-cfg-complete-wait:
	$(VIVADO) -mode batch -nojournal -nolog \
		-source fpga/kcu105/run_k11b2_ila_hw.tcl \
		-tclargs localhost:3122 capture-cfg-complete-wait

k11b2-ila-hw-program-arm-cfg-complete:
	$(VIVADO) -mode batch -nojournal -nolog \
		-source fpga/kcu105/run_k11b2_ila_hw.tcl \
		-tclargs localhost:3122 program-arm-cfg-complete

k11b2-ila-hw-program-arm-detect-active:
	$(VIVADO) -mode batch -nojournal -nolog \
		-source fpga/kcu105/run_k11b2_ila_hw.tcl \
		-tclargs localhost:3122 program-arm-detect-active

k11b2-ila-hw-arm-detect-active:
	$(VIVADO) -mode batch -nojournal -nolog \
		-source fpga/kcu105/run_k11b2_ila_hw.tcl \
		-tclargs localhost:3122 arm-detect-active

k11b2-ila-hw-program-arm-perst:
	$(VIVADO) -mode batch -nojournal -nolog \
		-source fpga/kcu105/run_k11b2_ila_hw.tcl \
		-tclargs localhost:3122 program-arm-perst

k11b2-ila-hw-program-arm-perst-release:
	$(VIVADO) -mode batch -nojournal -nolog \
		-source fpga/kcu105/run_k11b2_ila_hw.tcl \
		-tclargs localhost:3122 program-arm-perst-release

k11b2-ila-hw-program-arm-phy-reset-release:
	$(VIVADO) -mode batch -nojournal -nolog \
		-source fpga/kcu105/run_k11b2_ila_hw.tcl \
		-tclargs localhost:3122 program-arm-phy-reset-release

k11b2-ila-hw-capture-tx-wait:
	$(VIVADO) -mode batch -nojournal -nolog \
		-source fpga/kcu105/run_k11b2_ila_hw.tcl \
		-tclargs localhost:3122 capture-tx-wait

k11b2-ila-hw-capture-linkdown-wait:
	$(VIVADO) -mode batch -nojournal -nolog \
		-source fpga/kcu105/run_k11b2_ila_hw.tcl \
		-tclargs localhost:3122 capture-linkdown-wait

k11b2-ila-hw-capture-rxidle-conflict-wait:
	$(VIVADO) -mode batch -nojournal -nolog \
		-source fpga/kcu105/run_k11b2_ila_hw.tcl \
		-tclargs localhost:3122 capture-rxidle-conflict-wait

k11b2-ila-hw-capture-now:
	$(VIVADO) -mode batch -nojournal -nolog \
		-source fpga/kcu105/run_k11b2_ila_hw.tcl \
		-tclargs localhost:3122 capture-now

k11b2-ila-hw-upload:
	$(VIVADO) -mode batch -nojournal -nolog \
		-source fpga/kcu105/run_k11b2_ila_hw.tcl \
		-tclargs localhost:3122 upload

k11b3-trigger-sim:
	rm -f sim/verilator/k11b3/results.xml
	$(MAKE) -C sim/verilator/k11b3 results.xml
	! grep -q '<failure' sim/verilator/k11b3/results.xml
	@echo "K11B3_TRIGGER_SIM_PASS"

k11b3-cdc-sim:
	rm -f sim/verilator/k11b3/results.xml
	$(MAKE) -C sim/verilator/k11b3 -f Makefile.cdc results.xml
	! grep -q '<failure' sim/verilator/k11b3/results.xml
	@echo "K11B3_CDC_SIM_PASS"

k11b3-diagnostic-sim: k11b3-trigger-sim k11b3-cdc-sim
	@echo "K11B3_DIAGNOSTIC_SIM_PASS"

k11b2-hw-probe:
	$(VIVADO) -mode batch -nojournal -nolog \
		-source fpga/kcu105/run_k11b2_hw.tcl -tclargs localhost:3122 probe

k11b2-hw-program:
	$(VIVADO) -mode batch -nojournal -nolog \
		-source fpga/kcu105/run_k11b2_hw.tcl -tclargs localhost:3122 program

k11b2-hw-acceptance:
	./fpga/kcu105/run_k11_gen1_release_acceptance_hw.sh 3 5

k11b2-hw-program-debug:
	$(VIVADO) -mode batch -nojournal -nolog \
		-source fpga/kcu105/run_k11b2_hw.tcl \
		-tclargs localhost:3122 program-debug

k14-recovery-speed-hw-program-arm:
	$(VIVADO) -mode batch -nojournal -nolog \
		-source fpga/kcu105/run_k14_recovery_speed_ila_hw.tcl \
		-tclargs $(KU040_SERVER) program-arm

k14-recovery-speed-hw-capture-wait:
	$(VIVADO) -mode batch -nojournal -nolog \
		-source fpga/kcu105/run_k14_recovery_speed_ila_hw.tcl \
		-tclargs $(KU040_SERVER) capture-wait

k14-recovery-speed-hw-upload:
	$(VIVADO) -mode batch -nojournal -nolog \
		-source fpga/kcu105/run_k14_recovery_speed_ila_hw.tcl \
		-tclargs $(KU040_SERVER) upload

k14-recovery-speed-hw-repeat:
	./fpga/kcu105/run_k14_recovery_speed_repeated_hw.sh \
		$(or $(K14_REPEAT_CYCLES),10)

g2-gen1-hw-program:
	$(VIVADO) -mode batch -nojournal -nolog \
		-source fpga/kcu105/run_k11b2_hw.tcl \
		-tclargs localhost:3122 program-g2-gen1

xdma-x1-demo:
	./fpga/kcu105/xdma_x1_demo/run_xdma_x1_demo.sh

xdma-x1-hw-program:
	$(VIVADO) -mode batch -nojournal -nolog \
		-source fpga/kcu105/xdma_x1_demo/program_xdma_x1_demo.tcl \
		-tclargs localhost:3122

ku040-hw-probe:
	$(VIVADO) -mode batch -nojournal -nolog \
		-source scripts/program_ku040.tcl \
		-tclargs $(KU040_SERVER) - probe

ku040-hw-program:
	$(VIVADO) -mode batch -nojournal -nolog \
		-source scripts/program_ku040.tcl \
		-tclargs $(KU040_SERVER) $(KU040_BIT) program

remote-check:
	./scripts/remote_pcie_host.sh check

remote-reboot:
	./scripts/remote_pcie_host.sh reboot

remote-wait:
	./scripts/remote_pcie_host.sh wait

remote-lspci:
	./scripts/remote_pcie_host.sh lspci

remote-cycle:
	./scripts/remote_pcie_host.sh cycle

remote-retrain-gen3:
	./scripts/remote_pcie_host.sh retrain-gen3

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
