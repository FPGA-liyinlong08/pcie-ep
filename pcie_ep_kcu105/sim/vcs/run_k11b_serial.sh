#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
vcs_home="${VCS_HOME:-/home/synopsys/vcs-mx/O-2018.09-SP2}"
vivado_home="${VIVADO_HOME:-/home/Xilinx/Vivado/2021.2}"
if [[ -n "${XILINX_VCS_SIMLIB:-}" ]]; then
    simlib_dir="${XILINX_VCS_SIMLIB}"
elif [[ -n "${VIVADO_SIMLIB:-}" ]]; then
    simlib_dir="${VIVADO_SIMLIB}"
elif [[ -f "${project_dir}/../../vcs_compile_simlib/synopsys_sim.setup" ]]; then
    simlib_dir="$(cd "${project_dir}/../../vcs_compile_simlib" && pwd)"
elif [[ -f /home/wx/Documents/vcs_compile_simlib/synopsys_sim.setup ]]; then
    simlib_dir=/home/wx/Documents/vcs_compile_simlib
else
    echo "错误：找不到 Vivado VCS simlib；请设置 XILINX_VCS_SIMLIB 或 VIVADO_SIMLIB" >&2
    exit 66
fi
if [[ -n "${K11B_RP_IMPORTS:-}" ]]; then
    rp_dir="${K11B_RP_IMPORTS}"
elif [[ -f /home/ICer/Vivado_prj/xdma_0_ex/imports/pcie3_uscale_rp_top.v ]]; then
    rp_dir=/home/ICer/Vivado_prj/xdma_0_ex/imports
elif [[ -f /home/ICer/pcie-ep/pcie3_ultrascale_0_ex/imports/pcie3_uscale_rp_top.v ]]; then
    rp_dir=/home/ICer/pcie-ep/pcie3_ultrascale_0_ex/imports
else
    echo "错误：找不到 Xilinx RP imports；请设置 K11B_RP_IMPORTS" >&2
    exit 66
fi
if [[ -n "${K11B_RP_APP_IMPORTS:-}" ]]; then
    rp_app_dir="${K11B_RP_APP_IMPORTS}"
else
    rp_app_dir="${rp_dir}"
fi
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
k14_reboot_mode="${K14_REBOOT_VCS:-0}"
k14_rate_ab_mode="${K14_RATE_AB_VCS:-0}"
k15_mode="${K15_VCS:-0}"
k15_phase2_only="${K15_PHASE2_ONLY:-0}"
k15_header_held_ab="${K15_HEADER_HELD_AB:-0}"
k15_xilinx_pattern_ab="${K15_XILINX_PATTERN_AB:-0}"
k15_local_phy_loopback="${K15_LOCAL_PHY_LOOPBACK:-0}"
k15_gt_loopback="${K15_GT_LOOPBACK:-0}"
k15_continue_after_fallback="${K15_CONTINUE_AFTER_FALLBACK:-0}"
k15_ab_cdr_hold="${K15_AB_CDR_HOLD:-0}"
k15_ab_prerate_txeq="${K15_AB_PRERATE_TXEQ:-1}"
k15_ab_prerate_query="${K15_AB_PRERATE_QUERY:-1}"
k15_ab_prerate_dwell="${K15_AB_PRERATE_DWELL_CYCLES:-0}"
k15_ab_prerate_preset="${K15_AB_PRERATE_PRESET:-4}"
k14_ep_tx_rate_id="${K14_EP_TX_RATE_ID:-02}"
k14_reboot_tx_rate_id="${K14_REBOOT_TX_RATE_ID:-02}"
k13_enable="${K13_ENABLE:-0}"
k13_retrain="${K13_VCS_RETRAIN:-0}"
k13_rxeq_bootstrap="${K13_RXEQ_BOOTSTRAP:-1}"
k13_rxeq_two_pass="${K13_RXEQ_TWO_PASS:-0}"
k13_fallback_wait="${K13_FALLBACK_WAIT:-20000}"
k13_waveform="${K13_WAVEFORM:-0}"
k13_trace="${K13_TRACE:-0}"
k13_pipe_compare="${K13_PIPE_COMPARE:-0}"
k13_retrain_source="${K13_RETRAIN_SOURCE:-dual}"
k13_local_loopback="${K13_LOCAL_LOOPBACK:-0}"
k13_gen3_cold_phy="${K13_GEN3_COLD_PHY:-0}"
case "${k13_retrain_source}" in
    dual|rp|ep) ;;
    *)
        echo "错误：K13_RETRAIN_SOURCE必须为dual、rp或ep" >&2
        exit 64
        ;;
esac
afifo="${AFIFO_RTL:-${project_dir}/rtl/vendor/wb2axip/afifo.v}"
tb_defines=()
tb_defines+=(+define+K13_RXEQ_BOOTSTRAP_VALUE=${k13_rxeq_bootstrap})
tb_defines+=(+define+K13_RXEQ_TWO_PASS_VALUE=${k13_rxeq_two_pass})
if [[ "${b2_mode}" == "1" || "${k14_reboot_mode}" == "1" ||
      "${k15_mode}" == "1" ||
      "${k14_rate_ab_mode}" == "1" ]]; then
    tb_defines+=(+define+K11B2_DUT)
fi
if [[ "${k14_reboot_mode}" == "1" || "${k14_rate_ab_mode}" == "1" ||
      "${k15_mode}" == "1" ]]; then
    tb_defines+=(+define+K14_REBOOT_VCS)
fi
if [[ "${k15_mode}" == "1" ]]; then
    tb_defines+=(+define+K15_VCS)
    tb_defines+=("+define+K14_EP_TX_RATE_ID_VALUE=8'h0e")
    tb_defines+=("+define+K15_AB_CDR_HOLD_VALUE=${k15_ab_cdr_hold}")
    tb_defines+=("+define+K15_AB_PRERATE_TXEQ_VALUE=${k15_ab_prerate_txeq}")
    tb_defines+=("+define+K15_AB_PRERATE_QUERY_VALUE=${k15_ab_prerate_query}")
    tb_defines+=("+define+K15_AB_PRERATE_DWELL_VALUE=${k15_ab_prerate_dwell}")
    tb_defines+=("+define+K15_AB_PRERATE_PRESET_VALUE=${k15_ab_prerate_preset}")
    if [[ "${k15_header_held_ab}" == "1" ||
          "${k15_xilinx_pattern_ab}" == "1" ]]; then
        tb_defines+=(+define+K15_AB_HEADER_HELD)
    fi
    if [[ "${k15_xilinx_pattern_ab}" == "1" ]]; then
        tb_defines+=(+define+K15_AB_XILINX_PATTERN)
    fi
    # Must live in the tb_defines build section: it gates a localparam in
    # pcie_gen3_idle_tx.sv, which is compiled by vlogan below (line ~263).
    if [[ "${K15_L0_SKP_DENSE:-0}" == "1" ]]; then
        tb_defines+=(+define+K15_L0_SKP_DENSE)
    fi
    if [[ "${K15_L0_SKP_OFF:-0}" == "1" ]]; then
        tb_defines+=(+define+K15_L0_SKP_OFF)
    fi
    # Gap-grid phase scan (0..15 blocks of offset after each SDS); default 0
    # gives the corrected 65-beat gap period (16 blocks x 4 + 1 gap).
    if [[ -n "${K15_L0_GAP_PHASE:-}" ]]; then
        tb_defines+=("+define+K15_L0_GAP_PHASE=${K15_L0_GAP_PHASE}")
    fi
fi
if [[ "${k14_rate_ab_mode}" == "1" ]]; then
    case "${k14_ep_tx_rate_id}" in
        02|0e) ;;
        *)
            echo "错误：K14_EP_TX_RATE_ID必须为02或0e" >&2
            exit 64
            ;;
    esac
    tb_defines+=("+define+K14_EP_TX_RATE_ID_VALUE=8'h${k14_ep_tx_rate_id}")
elif [[ "${k14_reboot_mode}" == "1" ]]; then
    case "${k14_reboot_tx_rate_id}" in
        02|0e) ;;
        *)
            echo "错误：K14_REBOOT_TX_RATE_ID必须为02或0e" >&2
            exit 64
            ;;
    esac
    tb_defines+=("+define+K14_EP_TX_RATE_ID_VALUE=8'h${k14_reboot_tx_rate_id}")
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
test -s "${rp_app_dir}/pci_exp_usrapp_cfg.v"
test -s "${rp_app_dir}/pci_exp_usrapp_com.v"
test -s "${rp_app_dir}/pci_exp_usrapp_rx.v"
test -s "${rp_app_dir}/pci_exp_usrapp_tx.v"
test -s "${afifo}"

run_dir="$(mktemp -d "${TMPDIR:-/tmp}/pcie_k11b_vcs.XXXXXX")"
setup_file="${run_dir}/synopsys_sim.setup"
rp_usrapp_tx="${run_dir}/pci_exp_usrapp_tx_k11b.v"
mkdir -p build "${run_dir}/work" "${run_dir}/xil_defaultlib"
python3 "${script_dir}/prepare_k11b_rp_usrapp.py" \
    "${rp_app_dir}/pci_exp_usrapp_tx.v" "${rp_usrapp_tx}"
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

extra_source_args=()
if [[ -n "${K11B_EXTRA_SOURCES:-}" ]]; then
    for extra_src in ${K11B_EXTRA_SOURCES}; do
        extra_source_args+=("${extra_src}")
    done
fi
if [[ "${#extra_source_args[@]}" -gt 0 ]]; then
    # Compile the unisim GTHE3_CHANNEL shell into xil_defaultlib so `bind`
    # probes in the extra sources attach to the GT instances (the precompiled
    # simlib copy cannot be bound into).
    "${vcs_home}/bin/vlogan" -full64 -sverilog -work xil_defaultlib \
        "${extra_source_args[@]}" \
        "${vivado_home}/data/verilog/src/unisims/GTHE3_CHANNEL.v" \
        -l build/k11b_extra_vlogan.log
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
    +incdir+"${rp_app_dir}" \
    "${rp_app_dir}/pci_exp_usrapp_cfg.v" \
    "${rp_app_dir}/pci_exp_usrapp_com.v" \
    "${rp_app_dir}/pci_exp_usrapp_rx.v" \
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
    "${project_dir}/rtl/common/pcie_retrain_cdc_mailbox.sv" \
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
    "${project_dir}/rtl/phy/pcie_gen3_idle_tx.sv" \
    "${project_dir}/rtl/phy/pcie_gen3_equalization_ctrl.sv" \
    "${project_dir}/rtl/phy/pcie_gen1_framer.sv" \
    "${project_dir}/rtl/phy/pcie_phy_command_ctrl.sv" \
    "${project_dir}/rtl/phy/pcie_recovery_speed_ctrl.sv" \
    "${project_dir}/rtl/phy/pcie_partner_retrain_pending.sv" \
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

if [[ "${k14_rate_ab_mode}" == "1" ]]; then
    set +e
    timeout --foreground "${simulation_timeout}" \
        "${run_dir}/k11b_simv" +K14_RATE_AB -licqueue \
        -l "build/k14_rate_id_${k14_ep_tx_rate_id}_simulate.log"
    k14_rate_ab_status=$?
    set -e
    if [[ ${k14_rate_ab_status} -eq 124 ]]; then
        echo "错误：K14 Rate ID ${k14_ep_tx_rate_id} A/B仿真超过 ${simulation_timeout} 秒" >&2
        exit 124
    elif [[ ${k14_rate_ab_status} -ne 0 ]]; then
        exit "${k14_rate_ab_status}"
    fi
    grep -q 'K14_RATE_ID_CAPTURE_PASS' \
        "build/k14_rate_id_${k14_ep_tx_rate_id}_simulate.log"
    echo "K14_RATE_ID_CAPTURE_VCS_PASS rate_id=${k14_ep_tx_rate_id} run_dir=${run_dir}"
    exit 0
fi

if [[ "${k14_reboot_mode}" == "1" ]]; then
    set +e
    timeout --foreground "${simulation_timeout}" \
        "${run_dir}/k11b_simv" +K14_REBOOT -licqueue \
        -l build/k14_reboot_simulate.log
    k14_reboot_status=$?
    set -e
    if [[ ${k14_reboot_status} -eq 124 ]]; then
        echo "错误：K14 reboot真实串行仿真超过 ${simulation_timeout} 秒" >&2
        exit 124
    elif [[ ${k14_reboot_status} -ne 0 ]]; then
        exit "${k14_reboot_status}"
    fi
    grep -q 'K14_REBOOT_VCS_PASS epochs=2' build/k14_reboot_simulate.log
    echo "K14_REBOOT_VCS_REAL_RP_PASS run_dir=${run_dir}"
    exit 0
fi

if [[ "${k15_mode}" == "1" ]]; then
    k15_plusargs=(+K15_GEN3)
    if [[ "${K15_RP_CFG_SCAN:-0}" == "1" ]]; then
        k15_plusargs+=(+K15_RP_CFG_SCAN)
    fi
    if [[ "${K15_RP_ENABLE_EQ:-0}" == "1" ]]; then
        k15_plusargs+=(+K15_RP_ENABLE_EQ)
    fi
    if [[ "${K15_RP_L0_EXIT_DUMP:-0}" == "1" ]]; then
        k15_plusargs+=(+K15_RP_L0_EXIT_DUMP)
    fi
    if [[ "${K15_BUF_TRACE:-0}" == "1" ]]; then
        k15_plusargs+=(+K15_BUF_TRACE)
    fi
    if [[ "${K15_GT_CHG:-0}" == "1" ]]; then
        k15_plusargs+=(+K15_GT_CHG)
    fi
    if [[ "${K15_L0FIX:-0}" == "1" ]]; then
        k15_plusargs+=(+K15_L0FIX)
    fi
    if [[ "${k15_phase2_only}" == "1" ]]; then
        k15_plusargs+=(+K15_PHASE2_ONLY)
    fi
    if [[ "${k15_local_phy_loopback}" == "1" ]]; then
        k15_plusargs+=(+K15_LOCAL_PHY_LOOPBACK)
        if [[ "${k15_gt_loopback}" == "1" ]]; then
            k15_plusargs+=(+K15_GT_LOOPBACK)
        fi
    fi
    if [[ "${k15_local_phy_loopback}" == "1" ]]; then
        k15_plusargs+=(+K15_CONTINUE_AFTER_FALLBACK)
    elif [[ "${k15_continue_after_fallback}" == "1" ]]; then
        k15_plusargs+=(+K15_CONTINUE_AFTER_FALLBACK)
    fi
    if [[ "${k13_trace}" == "1" ]]; then
        k15_plusargs+=(+K13_TRACE)
    fi
    set +e
    timeout --foreground "${simulation_timeout}" \
        "${run_dir}/k11b_simv" "${k15_plusargs[@]}" -licqueue \
        -l build/k15_gen3_simulate.log
    k15_status=$?
    set -e
    if [[ ${k15_status} -eq 124 ]]; then
        echo "错误：K15 Gen3真实串行仿真超过 ${simulation_timeout} 秒" >&2
        exit 124
    elif [[ ${k15_status} -ne 0 ]]; then
        exit "${k15_status}"
    fi
    if [[ "${k15_phase2_only}" == "1" ]]; then
        grep -q 'K15_XILINX_RP_PHASE2_PASS' build/k15_gen3_simulate.log
        echo "K15_XILINX_RP_PHASE2_VCS_PASS run_dir=${run_dir}"
    elif [[ "${k15_local_phy_loopback}" == "1" ]]; then
        grep -q 'K15_LOCAL_PHY_LOOPBACK_PASS' \
            build/k15_gen3_simulate.log
        echo "K15_LOCAL_PHY_LOOPBACK_PASS run_dir=${run_dir}"
    elif [[ "${k15_continue_after_fallback}" == "1" ]]; then
        grep -q 'K15_GEN1_RECOVERY_PASS_AFTER_FALLBACK' \
            build/k15_gen3_simulate.log
        echo "K15_GEN1_RECOVERY_DIAGNOSTIC_PASS run_dir=${run_dir}"
    else
        grep -q 'K15_VCS_PASS epochs=2' \
            build/k15_gen3_simulate.log
        echo "K15_VCS_REAL_RP_PASS run_dir=${run_dir}"
    fi
    exit 0
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
    if [[ "${k13_local_loopback}" == "1" ]]; then
        b2_plusargs+=(+K13_LOCAL_LOOPBACK)
    fi
    if [[ "${k13_gen3_cold_phy}" == "1" ]]; then
        b2_plusargs+=(+K13_GEN3_COLD_PHY)
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
