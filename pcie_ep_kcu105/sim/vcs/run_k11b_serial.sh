#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
vcs_home="${VCS_HOME:-/home/synopsys/vcs-mx/O-2018.09-SP2}"
vivado_home="${VIVADO_HOME:-/home/Xilinx/Vivado/2021.2}"
simlib_dir="${XILINX_VCS_SIMLIB:-/home/wx/Documents/vcs_compile_simlib}"
rp_dir="${K11B_RP_IMPORTS:-/home/wx/Documents/XDMA/xdma_dec_250922/imports}"
g2_gen1_only="${G2_GEN1_ONLY:-0}"
if [[ "${g2_gen1_only}" == "1" ]]; then
    phy_ip_root="ip_g2_gen1"
else
    phy_ip_root="ip"
fi
phy_name="pcie_phy_x1_gen3"
ip_dir="${project_dir}/fpga/kcu105/${phy_ip_root}/${phy_name}"
license_timeout="${VCS_LICENSE_TIMEOUT:-300}"
simulation_timeout="${K11B_SIM_TIMEOUT:-900}"
license_server="${VCS_LICENSE_SERVER:-27000@wx-linux}"
license_lmutil="${VCS_LICENSE_LMUTIL:-/home/questasim/linux_x86_64/lmutil}"
b2_mode="${K11B2_MODE:-0}"
b2_stress_mode="${K11B2_STRESS_MODE:-0}"
k12e_mode="${K12E_VCS:-0}"
k13_enable="${K13_ENABLE:-0}"
k13_retrain="${K13_VCS_RETRAIN:-0}"
k13_rxeq_bootstrap="${K13_RXEQ_BOOTSTRAP:-1}"
k13_fallback_wait="${K13_FALLBACK_WAIT:-20000}"
k13_waveform="${K13_WAVEFORM:-0}"
k13_trace="${K13_TRACE:-0}"
k13_pipe_compare="${K13_PIPE_COMPARE:-0}"
k13_retrain_source="${K13_RETRAIN_SOURCE:-dual}"
case "${k13_retrain_source}" in
    dual|rp|ep) ;;
    *)
        echo "错误：K13_RETRAIN_SOURCE必须为dual、rp或ep" >&2
        exit 64
        ;;
esac
afifo="/home/wx/Documents/AXI/prj_wb2axip_master/wb2axip-master/rtl/afifo.v"
tb_defines=()
tb_defines+=(+define+K13_RXEQ_BOOTSTRAP_VALUE=${k13_rxeq_bootstrap})
if [[ "${b2_mode}" == "1" ]]; then
    tb_defines+=(+define+K11B2_DUT)
fi
if [[ "${k12e_mode}" == "1" ]]; then
    tb_defines+=(+define+K12E_VCS)
fi
if [[ "${k13_enable}" == "1" ]]; then
    tb_defines+=(+define+K13_DUT)
fi

export VCS_HOME="${vcs_home}"
export VCS_ARCH_OVERRIDE=linux
export SNPSLMD_LICENSE_FILE="${SNPSLMD_LICENSE_FILE:-${license_server}}"
if [[ ":${LM_LICENSE_FILE:-}:" != *":${license_server}:"* ]]; then
    export LM_LICENSE_FILE="${license_server}${LM_LICENSE_FILE:+:${LM_LICENSE_FILE}}"
fi

cd "${script_dir}"
./check_env.sh
mkdir -p build
if [[ "${VCS_LICENSE_PREFLIGHT:-1}" == "1" && -x "${license_lmutil}" ]]; then
    set +e
    timeout --foreground 10 "${license_lmutil}" lmstat \
        -f VCSCompiler_Net -c "${license_server}" \
        > build/vcs_license_preflight.log 2>&1
    license_preflight_status=$?
    set -e
    if [[ ${license_preflight_status} -ne 0 ]]; then
        cat build/vcs_license_preflight.log >&2
        echo "错误：无法访问Synopsys许可证服务 ${license_server}；请在允许访问FlexNet端口的环境运行，不要盲目增加-licqueue等待时间" >&2
        exit 69
    fi
fi
test -s "${ip_dir}/${phy_name}.xci"
test -s "${ip_dir}/sim/${phy_name}.v"
test -s "${rp_dir}/pcie3_uscale_rp_core_top.v"
test -s "${rp_dir}/pcie3_uscale_rp_top.v"
test -s "${afifo}"

run_dir="$(mktemp -d "${TMPDIR:-/tmp}/pcie_k11b_vcs.XXXXXX")"
setup_file="${run_dir}/synopsys_sim.setup"
rp_usrapp_tx="${run_dir}/pci_exp_usrapp_tx_k11b.v"
mkdir -p build "${run_dir}/work" "${run_dir}/xil_defaultlib"
python3 "${script_dir}/prepare_k11b_rp_usrapp.py" \
    "${rp_dir}/pci_exp_usrapp_tx.v" "${rp_usrapp_tx}"
printf 'WORK > DEFAULT\nDEFAULT : %s\nxil_defaultlib : %s\nOTHERS=%s/synopsys_sim.setup\n' \
    "${run_dir}/work" "${run_dir}/xil_defaultlib" "${simlib_dir}" \
    > "${setup_file}"
export SYNOPSYS_SIM_SETUP="${setup_file}"

gt_common_files=()
if [[ "${g2_gen1_only}" != "1" ]]; then
    gt_common_files+=(
        "${ip_dir}/ip_0/sim/gtwizard_ultrascale_v1_7_gthe3_common.v"
        "${ip_dir}/ip_0/sim/${phy_name}_gt_gthe3_common_wrapper.v"
    )
fi

"${vcs_home}/bin/vlogan" -full64 +v2k -work xil_defaultlib \
    "${ip_dir}/ip_0/sim/gtwizard_ultrascale_v1_7_gthe3_channel.v" \
    "${ip_dir}/ip_0/sim/${phy_name}_gt_gthe3_channel_wrapper.v" \
    "${gt_common_files[@]}" \
    "${ip_dir}/ip_0/sim/${phy_name}_gt_gtwizard_gthe3.v" \
    "${ip_dir}/ip_0/sim/${phy_name}_gt_gtwizard_top.v" \
    "${ip_dir}/ip_0/sim/${phy_name}_gt.v" \
    "${ip_dir}/source/${phy_name}_sync_cell.v" \
    "${ip_dir}/source/${phy_name}_sync.v" \
    "${ip_dir}/source/${phy_name}_phy_ff_chain.v" \
    "${ip_dir}/source/${phy_name}_phy_pipeline.v" \
    "${ip_dir}/source/${phy_name}_us_gt_phy_wrapper.v" \
    "${ip_dir}/source/${phy_name}_us_gt_phy_clk.v" \
    "${ip_dir}/source/${phy_name}_us_gt_phy_rst.v" \
    "${ip_dir}/source/${phy_name}_us_gt_phy_txeq.v" \
    "${ip_dir}/source/${phy_name}_us_gt_phy_rxeq.v" \
    "${ip_dir}/source/${phy_name}_gtwizard_top.v" \
    "${ip_dir}/source/${phy_name}_core_top.v" \
    "${ip_dir}/sim/${phy_name}.v" \
    -l build/k11b_ep_phy_vlogan.log

"${vcs_home}/bin/vlogan" -full64 +v2k -work xil_defaultlib \
    +define+K11B_DISABLE_XILINX_AUTO_TEST \
    +incdir+"${rp_dir}" \
    "${rp_dir}/pci_exp_usrapp_cfg.v" \
    "${rp_dir}/pci_exp_usrapp_com.v" \
    "${rp_dir}/pci_exp_usrapp_rx.v" \
    "${rp_usrapp_tx}" \
    "${rp_dir}/pcie3_uscale_rp_core_top.v" \
    "${rp_dir}/pcie3_uscale_rp_top.v" \
    "${rp_dir}/xilinx_pcie_uscale_rp.v" \
    -l build/k11b_rp_vlogan.log

"${vcs_home}/bin/vlogan" -full64 +v2k -work xil_defaultlib \
    "${afifo}" -l build/k11b_afifo_vlogan.log

"${vcs_home}/bin/vlogan" -full64 -sverilog -work xil_defaultlib \
    "${tb_defines[@]}" \
    "${project_dir}/rtl/common/pcie_reset_sync.sv" \
    "${project_dir}/rtl/common/pcie_gray_sync.sv" \
    "${project_dir}/rtl/common/pcie_async_pkt_fifo.sv" \
    "${project_dir}/rtl/common/pcie_async_event_fifo.sv" \
    "${project_dir}/rtl/common/pcie_tlp_async_bridge.sv" \
    "${project_dir}/rtl/common/pcie_cdc_snapshot.sv" \
    "${project_dir}/rtl/common/pcie_cdc_pulse.sv" \
    "${project_dir}/rtl/phy/kcu105_reset_ctrl.sv" \
    "${project_dir}/rtl/phy/kcu105_refclk_reset.sv" \
    "${project_dir}/rtl/phy/kcu105_pcie_phy_wrapper.sv" \
    "${project_dir}/rtl/phy/pcie_gen12_scrambler.sv" \
    "${project_dir}/rtl/phy/pcie_gen1_rx_symbol_aligner.sv" \
    "${project_dir}/rtl/phy/pcie_gen1_os_rx.sv" \
    "${project_dir}/rtl/phy/pcie_gen1_os_tx.sv" \
    "${project_dir}/rtl/phy/pcie_gen3_scrambler32.sv" \
    "${project_dir}/rtl/phy/pcie_gen3_os_rx.sv" \
    "${project_dir}/rtl/phy/pcie_gen3_os_tx.sv" \
    "${project_dir}/rtl/phy/pcie_gen1_framer.sv" \
    "${project_dir}/rtl/phy/pcie_ltssm_mac_gen1.sv" \
    "${project_dir}/rtl/phy/kcu105_pcie_gen1_top.sv" \
    "${project_dir}/rtl/dll/pcie_crc_stream.sv" \
    "${project_dir}/rtl/dll/pcie_crc16_dllp.sv" \
    "${project_dir}/rtl/dll/pcie_crc32_lcrc.sv" \
    "${project_dir}/rtl/dll/pcie_fc_local_credit_pool.sv" \
    "${project_dir}/rtl/dll/pcie_dllp_codec.sv" \
    "${project_dir}/rtl/dll/pcie_dllp_fc_manager.sv" \
    "${project_dir}/rtl/dll/pcie_dllp_tx_arbiter.sv" \
    "${project_dir}/rtl/dll/pcie_dll_mac_tx_arbiter.sv" \
    "${project_dir}/rtl/dll/pcie_dll_replay.sv" \
    "${project_dir}/rtl/dll/pcie_dll.sv" \
    "${project_dir}/rtl/tl/pcie_tlp_codec.sv" \
    "${project_dir}/rtl/tl/pcie_cfg_space.sv" \
    "${project_dir}/rtl/tl/pcie_bar_axil_master.sv" \
    "${project_dir}/rtl/tl/demo_axil_slave.sv" \
    "${project_dir}/sim/verilator/k09_integration/k09_tlp_test_top.sv" \
    "${project_dir}/rtl/ep/k11a_offline_top.sv" \
    "${project_dir}/rtl/ep/kcu105_pcie_ep_gen1_top.sv" \
    "${project_dir}/rtl/common/pcie_retrain_cdc_mailbox.sv" \
    "${project_dir}/rtl/phy/pcie_phy_rate_contract.sv" \
    "${project_dir}/rtl/phy/pcie_recovery_speed_ctrl.sv" \
    "${project_dir}/rtl/phy/pcie_equalization_ctrl.sv" \
    "${project_dir}/rtl/phy/pcie_recovery_ts_guard.sv" \
    "${project_dir}/rtl/phy/pcie_k13_production_ctrl.sv" \
    $(if [[ "${k12e_mode}" == "1" ]]; then echo "${script_dir}/k12e_phy_monitor.sv"; fi) \
    "${vivado_home}/data/verilog/src/glbl.v" \
    "${script_dir}/k11b_serial_board.sv" \
    -l build/k11b_tb_vlogan.log

set +e
timeout --foreground "${license_timeout}" "${vcs_home}/bin/vcs" -full64 \
    xil_defaultlib.board xil_defaultlib.glbl \
    -Lgtwizard_ultrascale_v1_7_12 \
    -Lsecureip -Lunisims_ver -Lxpm \
    -debug_access+pp+dmptf -t ps -licqueue \
    -LDFLAGS "-Wl,--no-as-needed" \
    -Mdir="${run_dir}/csrc_k11b" \
    -o "${run_dir}/k11b_simv" \
    -l build/k11b_elaborate.log
elaborate_status=$?
set -e
if [[ ${elaborate_status} -eq 124 ]]; then
    echo "错误：K11-B VCS 展开等待许可证超过 ${license_timeout} 秒" >&2
    exit 124
elif [[ ${elaborate_status} -ne 0 ]]; then
    exit "${elaborate_status}"
fi

if [[ "${b2_mode}" == "1" ]]; then
    b2_plusargs=(+K11B2_RUN)
    if [[ "${b2_stress_mode}" == "1" ]]; then
        b2_plusargs+=(+K11B2_STRESS)
    fi
    if [[ "${k13_retrain}" == "1" ]]; then
        b2_plusargs+=(+K13_RETRAIN)
    fi
    b2_plusargs+=(+K13_FALLBACK_WAIT=${k13_fallback_wait})
    if [[ "${k13_waveform}" == "1" ]]; then
        b2_plusargs+=(+K13_DUMP_WAVEFORM)
    fi
    if [[ "${k13_trace}" == "1" ]]; then
        b2_plusargs+=(+K13_TRACE)
    fi
    if [[ "${k13_pipe_compare}" == "1" ]]; then
        b2_plusargs+=(+K13_PIPE_COMPARE)
    fi
    case "${k13_retrain_source}" in
        rp) b2_plusargs+=(+K13_RETRAIN_SOURCE_RP) ;;
        ep) b2_plusargs+=(+K13_RETRAIN_SOURCE_EP) ;;
    esac
    set +e
    timeout --foreground "${simulation_timeout}" \
        "${run_dir}/k11b_simv" "${b2_plusargs[@]}" -licqueue \
        -l build/k11b2_simulate.log
    b2_status=$?
    set -e
    if [[ ${b2_status} -eq 124 ]]; then
        echo "错误：K11-B2真实串行仿真超过 ${simulation_timeout} 秒" >&2
        exit 124
    elif [[ ${b2_status} -ne 0 ]]; then
        exit "${b2_status}"
    fi
    grep -q 'K11B2_DLL_ACTIVE_PASS' build/k11b2_simulate.log
    grep -q 'K11B2_ENUM_PASS' build/k11b2_simulate.log
    grep -q 'K11B2_BAR_PASS' build/k11b2_simulate.log
    if [[ "${b2_stress_mode}" == "1" ]]; then
        grep -q 'K11B2_RANDOM_MMIO_PASS' build/k11b2_simulate.log
        grep -q 'K11B2_BAD_LCRC_PASS' build/k11b2_simulate.log
        grep -q 'K11B2_ACK_LOSS_PASS' build/k11b2_simulate.log
        grep -q 'K11B2_PERST_RECOVERY_PASS' build/k11b2_simulate.log
        grep -q 'K11B2_STRESS_PASS' build/k11b2_simulate.log
    fi
    grep -q 'K11B2_VCS_PASS' build/k11b2_simulate.log
    if [[ "${k12e_mode}" == "1" ]]; then
        grep -q 'K12E_REAL_PHY_ADAPTER_PASS' build/k11b2_simulate.log
    fi
    if [[ "${k13_retrain}" == "1" ]]; then
        grep -q 'K13_VCS_GEN3_RETRAIN_PASS' build/k11b2_simulate.log
    fi
    echo "K11B2_VCS_REAL_PHY_PASS run_dir=${run_dir}"
    if [[ "${k12e_mode}" == "1" ]]; then
        echo "K12E_VCS_REAL_PHY_PASS"
    fi
    exit 0
fi

if [[ "${K11B_SKIP_SELFTEST:-0}" != "1" ]]; then
    set +e
    timeout --foreground "${simulation_timeout}" \
        "${run_dir}/k11b_simv" +K11B_DISCONNECT_LANE0 -licqueue \
        -l build/k11b_checker_selftest.log
    selftest_status=$?
    set -e
    if [[ ${selftest_status} -eq 124 ]]; then
        echo "错误：K11-B 断线 Stub 仿真超过 ${simulation_timeout} 秒" >&2
        exit 124
    elif [[ ${selftest_status} -ne 0 ]]; then
        exit "${selftest_status}"
    fi
    grep -q 'K11B_VCS_CHECKER_SELFTEST_PASS' build/k11b_checker_selftest.log

    set +e
    timeout --foreground "${simulation_timeout}" \
        "${run_dir}/k11b_simv" +K11B2_NEGATIVE_STUB -licqueue \
        -l build/k11b2_checker_selftest.log
    b2_selftest_status=$?
    set -e
    if [[ ${b2_selftest_status} -eq 124 ]]; then
        echo "错误：K11-B2 K03-only负向Stub仿真超过 ${simulation_timeout} 秒" >&2
        exit 124
    elif [[ ${b2_selftest_status} -ne 0 ]]; then
        exit "${b2_selftest_status}"
    fi
    grep -q 'K11B2_CHECKER_SELFTEST_PASS' build/k11b2_checker_selftest.log
else
    echo "K11B_VCS_CHECKER_SELFTEST_SKIPPED_FOR_DEBUG"
fi

set +e
normal_plusargs=()
if [[ "${k13_waveform}" == "1" ]]; then
    normal_plusargs+=(+K13_DUMP_WAVEFORM)
fi
if [[ "${k13_trace}" == "1" ]]; then
    normal_plusargs+=(+K13_TRACE)
fi
timeout --foreground "${simulation_timeout}" \
    "${run_dir}/k11b_simv" "${normal_plusargs[@]}" -licqueue -l build/k11b_simulate.log
simulate_status=$?
set -e
if [[ ${simulate_status} -eq 124 ]]; then
    echo "错误：K11-B 正常串行仿真超过 ${simulation_timeout} 秒" >&2
    exit 124
elif [[ ${simulate_status} -ne 0 ]]; then
    exit "${simulate_status}"
fi
grep -q 'K11B_VCS_GEN1_L0_PASS' build/k11b_simulate.log

echo "K11B_VCS_REAL_PHY_PASS run_dir=${run_dir}"
