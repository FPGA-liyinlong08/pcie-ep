#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
rtl_root="${SVT_RTL_ROOT:-${project_dir}}"
svt_tb_dir="${SVT_TB_DIR:-${script_dir}}"
svt_board_file="${SVT_BOARD_FILE:-${svt_tb_dir}/board_svt_pcie_x1.sv}"
svt_program_file="${SVT_PROGRAM_FILE:-${svt_tb_dir}/pcie_svt_k15_program.sv}"
svt_config_file="${SVT_CONFIG_FILE:-${svt_tb_dir}/pcie_svt_k15_config.v}"
build_dir="${K15_SVT_BUILD_DIR:-${script_dir}/build}"
vip_version="${SVT_PCIE_VIP_VERSION:-O-2018.09}"
if [[ -n "${DESIGNWARE_HOME:-}" ]]; then
    designware_home="${DESIGNWARE_HOME}"
elif [[ -x /home/wx/synopsys/designware/bin/dw_vip_setup ]]; then
    designware_home=/home/wx/synopsys/designware
else
    designware_home=/home/ICer/synopsys/designware
fi
vcs_home="${VCS_HOME:-/home/synopsys/vcs-mx/O-2018.09-SP2}"
vivado_home="${VIVADO_HOME:-/home/Xilinx/Vivado/2021.2}"
phy_name=pcie_phy_x1_gen3
ip_dir="${project_dir}/fpga/kcu105/ip/${phy_name}"
afifo="${project_dir}/rtl/vendor/wb2axip/afifo.v"
license_server="${VCS_LICENSE_SERVER:-27000@wx-linux}"
license_timeout="${VCS_LICENSE_TIMEOUT:-300}"
simulation_timeout="${K15_SVT_SIM_TIMEOUT:-900}"
process_epochs="${SVT_PROCESS_EPOCHS:-1}"
if ! [[ "${process_epochs}" =~ ^[1-9][0-9]*$ ]]; then
    echo "SVT_PROCESS_EPOCHS must be a positive integer" >&2
    exit 64
fi
license_lmutil="${VCS_LICENSE_LMUTIL:-/home/questasim/linux_x86_64/lmutil}"
svt_testcase="${SVT_TESTCASE:-k15_svt_x1_test}"
svt_pass_marker="${SVT_PASS_MARKER:-K15_SVT_X1_PASS epochs=2}"
svt_fail_marker="${SVT_FAIL_MARKER:-K15_SVT_X1_FAIL}"
svt_run_label="${SVT_RUN_LABEL:-K15_SVT_X1}"
phase2_only="${K15_SVT_PHASE2_ONLY:-0}"
header_held_ab="${K15_SVT_HEADER_HELD_AB:-0}"

if [[ -n "${XILINX_VCS_SIMLIB:-}" ]]; then
    simlib_dir="${XILINX_VCS_SIMLIB}"
elif [[ -n "${VIVADO_SIMLIB:-}" ]]; then
    simlib_dir="${VIVADO_SIMLIB}"
elif [[ -f "${project_dir}/../../vcs_compile_simlib/synopsys_sim.setup" ]]; then
    simlib_dir="$(cd "${project_dir}/../../vcs_compile_simlib" && pwd)"
elif [[ -f /home/wx/Documents/vcs_compile_simlib/synopsys_sim.setup ]]; then
    simlib_dir=/home/wx/Documents/vcs_compile_simlib
else
    echo "missing Vivado VCS simlib; set XILINX_VCS_SIMLIB or VIVADO_SIMLIB" >&2
    exit 66
fi

for required in "${vcs_home}/bin/vcs" "${vcs_home}/bin/vlogan" \
                "${designware_home}/bin/dw_vip_setup"; do
    test -x "${required}" || { echo "missing executable: ${required}" >&2; exit 66; }
done
test -f "${simlib_dir}/synopsys_sim.setup" || {
    echo "missing Vivado VCS simlib setup: ${simlib_dir}/synopsys_sim.setup" >&2; exit 66;
}
test -d "${simlib_dir}/secureip" || { echo "missing secureip library" >&2; exit 66; }
test -s "${afifo}" || { echo "missing vendored AFIFO: ${afifo}" >&2; exit 66; }

if [[ ! -s "${ip_dir}/sim/${phy_name}.v" ]]; then
    echo "[K15-SVT] generating standalone PCIe PHY output products"
    "${project_dir}/fpga/kcu105/run_k02_ip_generation.sh"
else
    echo "[K15-SVT] reusing generated PHY under ${ip_dir}"
fi

export DESIGNWARE_HOME="${designware_home}"
export VCS_HOME="${vcs_home}"
export VCS_ARCH_OVERRIDE=linux
export SNPSLMD_LICENSE_FILE="${SNPSLMD_LICENSE_FILE:-${license_server}}"
if [[ ":${LM_LICENSE_FILE:-}:" != *":${license_server}:"* ]]; then
    export LM_LICENSE_FILE="${license_server}${LM_LICENSE_FILE:+:${LM_LICENSE_FILE}}"
fi

mkdir -p "${build_dir}"
if [[ "${VCS_LICENSE_PREFLIGHT:-1}" == "1" && -x "${license_lmutil}" ]]; then
    set +e
    timeout --foreground 10 "${license_lmutil}" lmstat \
        -f VCSCompiler_Net -c "${license_server}" \
        > "${build_dir}/license_preflight.log" 2>&1
    preflight_status=$?
    set -e
    if [[ ${preflight_status} -ne 0 ]]; then
        cat "${build_dir}/license_preflight.log" >&2
        echo "K15 SVT license preflight failed for ${license_server}" >&2
        exit 69
    fi
fi

vip_design_dir="${build_dir}/vendor"
if [[ ! -f "${vip_design_dir}/src/sverilog/vcs/svt_pcie_device_group_serdes_x4_8g_hdl.sv" ]]; then
    "${designware_home}/bin/dw_vip_setup" -path "${vip_design_dir}" \
        -example pcie_svt/tb_pcie_svt_vmm_8lane_sys -version "${vip_version}"
fi
vip_inc="${vip_design_dir}/include/sverilog"
vip_sv="${vip_design_dir}/src/sverilog/vcs"
vip_v="${vip_design_dir}/src/verilog/vcs"
shadow_file="${vip_sv}/pciesvc_global_shadow.sv"
device_wrapper="${vip_sv}/svt_pcie_device_group_serdes_x4_8g_hdl.sv"
model_file="${vip_v}/pciesvc_device_serdes_x4_model_8g.v"
for required in "${vip_inc}/svt.vmm.pkg" "${shadow_file}" \
                "${device_wrapper}" "${model_file}"; do
    test -s "${required}" || { echo "SVT setup missing ${required}" >&2; exit 66; }
done

run_dir="$(mktemp -d "${TMPDIR:-/tmp}/pcie_k15_svt_x1.XXXXXX")"
setup_file="${run_dir}/synopsys_sim.setup"
mkdir -p "${run_dir}/work" "${run_dir}/xil_defaultlib"
printf 'WORK > DEFAULT\nDEFAULT : %s\nxil_defaultlib : %s\nOTHERS=%s/synopsys_sim.setup\n' \
    "${run_dir}/work" "${run_dir}/xil_defaultlib" "${simlib_dir}" > "${setup_file}"
export SYNOPSYS_SIM_SETUP="${setup_file}"

log_file="${build_dir}/build.log"
: > "${log_file}"
run_logged() { "$@" 2>&1 | tee -a "${log_file}"; }

pcie_svt_latest="${designware_home}/vip/svt/pcie_svt/latest"
"${pcie_svt_latest}/bin/param2def.sh" < "${vip_v}/svc_util_parms.v" \
    > "${run_dir}/svc_util_parms.h"
"${CC:-cc}" -c -I"${run_dir}" -I"${vcs_home}/include" \
    -I"${pcie_svt_latest}/C/include" -DVCS_VERILOG -DUSE_VPI=1 -DPLI_64_BIT \
    "${pcie_svt_latest}/C/src/msglog.c" -o "${run_dir}/msglog.o"
"${vcs_home}/bin/veriuser_to_pli_tab" -include "${vcs_home}/include" \
    "${pcie_svt_latest}/C/src/veriuser.c" > "${run_dir}/pli.tab"

run_logged "${vcs_home}/bin/vlogan" -full64 +v2k -work xil_defaultlib \
    "${ip_dir}/ip_0/sim/gtwizard_ultrascale_v1_7_gthe3_channel.v" \
    "${ip_dir}/ip_0/sim/${phy_name}_gt_gthe3_channel_wrapper.v" \
    "${ip_dir}/ip_0/sim/gtwizard_ultrascale_v1_7_gthe3_common.v" \
    "${ip_dir}/ip_0/sim/${phy_name}_gt_gthe3_common_wrapper.v" \
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
    "${ip_dir}/sim/${phy_name}.v"

run_logged "${vcs_home}/bin/vlogan" -full64 +v2k -work xil_defaultlib "${afifo}"

rtl_sources=(
    rtl/common/pcie_reset_sync.sv rtl/common/pcie_gray_sync.sv
    rtl/common/pcie_async_pkt_fifo.sv rtl/common/pcie_async_event_fifo.sv
    rtl/common/pcie_tlp_async_bridge.sv rtl/common/pcie_cdc_snapshot.sv
    rtl/common/pcie_cdc_pulse.sv rtl/common/pcie_retrain_cdc_mailbox.sv
    rtl/phy/kcu105_reset_ctrl.sv rtl/phy/kcu105_refclk_reset.sv
    rtl/phy/kcu105_pcie_phy_wrapper.sv rtl/phy/pcie_gen12_scrambler.sv
    rtl/phy/pcie_gen1_rx_symbol_aligner.sv rtl/phy/pcie_gen1_os_rx.sv
    rtl/phy/pcie_gen1_os_tx.sv rtl/phy/pcie_gen3_scrambler32.sv
    rtl/phy/pcie_gen3_os_rx.sv rtl/phy/pcie_gen3_os_tx.sv
    rtl/phy/pcie_gen3_idle_tx.sv rtl/phy/pcie_gen3_equalization_ctrl.sv
    rtl/phy/pcie_gen1_framer.sv rtl/phy/pcie_phy_command_ctrl.sv
    rtl/phy/pcie_recovery_speed_ctrl.sv rtl/phy/pcie_partner_retrain_pending.sv
    rtl/phy/pcie_ltssm_mac_gen1.sv rtl/phy/kcu105_pcie_gen1_top.sv
    rtl/dll/pcie_crc_stream.sv rtl/dll/pcie_crc16_dllp.sv
    rtl/dll/pcie_crc32_lcrc.sv rtl/dll/pcie_fc_local_credit_pool.sv
    rtl/dll/pcie_dllp_codec.sv rtl/dll/pcie_dllp_fc_manager.sv
    rtl/dll/pcie_dllp_tx_arbiter.sv rtl/dll/pcie_dll_mac_tx_arbiter.sv
    rtl/dll/pcie_dll_replay.sv rtl/dll/pcie_dll.sv
    rtl/tl/pcie_tlp_codec.sv rtl/tl/pcie_cfg_space.sv
    rtl/tl/pcie_bar_axil_master.sv rtl/tl/demo_axil_slave.sv
    sim/verilator/k09_integration/k09_tlp_test_top.sv
    rtl/ep/k11a_offline_top.sv rtl/ep/kcu105_pcie_ep_gen1_top.sv
)
rtl_paths=()
for source in "${rtl_sources[@]}"; do
    if [[ -f "${rtl_root}/${source}" ]]; then
        rtl_paths+=("${rtl_root}/${source}")
    fi
done
rtl_defines=()
if [[ "${header_held_ab}" == "1" ]]; then
    rtl_defines+=(+define+K15_AB_HEADER_HELD)
fi
run_logged "${vcs_home}/bin/vlogan" -full64 -sverilog -work xil_defaultlib \
    "${rtl_defines[@]}" \
    "${rtl_paths[@]}" "${vivado_home}/data/verilog/src/glbl.v"

vlog_common=(
    -full64 -sverilog +v2k -lca -ntb_opts rvm +libext+.v+.sv
    -y "${vip_v}" -y "${vip_sv}"
    "+incdir+${svt_tb_dir}" "+incdir+${vip_inc}"
    "+incdir+${vip_design_dir}/include/verilog"
    "+incdir+${vip_sv}" "+incdir+${vip_v}"
    +define+PCIESVC_SVT_NAMING +define+PCIESVC_FLAT_INCLUDES
    +define+SVT_PCIE_ENABLE_GEN3 +define+EXPERTIO_PCIESVC_INCLUDE_8G
    +define+PCIESVC_MEM_PATH=test_top.global_shadow0.shadow_mem0
    +define+EXPERTIO_PCIESVC_GLOBAL_SHADOW_PATH=test_top.global_shadow0
    +define+SVT_VMM_TECHNOLOGY +define+SVT_PCIE_PKG=svt_pcie_vmm_pkg
    +define+SYNOPSYS_SV
)
if [[ "${WAVES:-0}" == "1" ]]; then vlog_common+=(+define+WAVES); fi
run_logged "${vcs_home}/bin/vlogan" "${vlog_common[@]}" -work xil_defaultlib \
    "${svt_board_file}" "${svt_program_file}" "${svt_config_file}" \
    "${shadow_file}" "${device_wrapper}"

set +e
timeout --foreground "${license_timeout}" "${vcs_home}/bin/vcs" -full64 -lca \
    xil_defaultlib.test_top xil_defaultlib.glbl \
    -Lgtwizard_ultrascale_v1_7_12 -Lsecureip -Lunisims_ver -Lxpm \
    -debug_access+pp+dmptf -t ps -licqueue -LDFLAGS "-Wl,--no-as-needed" \
    -P "${run_dir}/pli.tab" "${run_dir}/msglog.o" \
    -Mdir="${run_dir}/csrc" -o "${run_dir}/k15_svt_x1_simv" \
    -l "${build_dir}/elaborate.log"
elaborate_status=$?
set -e
if [[ ${elaborate_status} -eq 124 ]]; then
    echo "K15 SVT elaboration license timeout after ${license_timeout}s" >&2; exit 124
elif [[ ${elaborate_status} -ne 0 ]]; then
    exit "${elaborate_status}"
fi

simulation_plusargs=()
if [[ "${phase2_only}" == "1" ]]; then
    simulation_plusargs+=(+K15_PHASE2_ONLY)
fi

for ((process_epoch = 0; process_epoch < process_epochs; process_epoch++)); do
    if [[ ${process_epochs} -eq 1 ]]; then
        process_log="${build_dir}/simulate.log"
    else
        process_log="${build_dir}/simulate.process_${process_epoch}.log"
    fi
    set +e
    timeout --foreground "${simulation_timeout}" "${run_dir}/k15_svt_x1_simv" \
        -licqueue "+vmm_test=${svt_testcase}" +vmm_log_nowarn_at_200 \
        "${simulation_plusargs[@]}" run \
        -l "${process_log}"
    simulation_status=$?
    set -e
    if [[ ${simulation_status} -eq 124 ]]; then
        echo "K15 SVT simulation timeout after ${simulation_timeout}s" >&2; exit 124
    elif [[ ${simulation_status} -ne 0 ]]; then
        exit "${simulation_status}"
    fi
    grep -Fq "${svt_pass_marker}" "${process_log}"
    if grep -Fq "${svt_fail_marker}" "${process_log}"; then
        echo "${svt_run_label} gate reported failure in process ${process_epoch}" >&2
        exit 1
    fi
    if [[ "${phase2_only}" == "1" ]] &&
       grep -Eq "phy_recovery_speed_electrical_idle_with_no_eios|phy_data_block_before_sds|phy_max_rx_skp_interval" "${process_log}"; then
        echo "${svt_run_label} protocol monitor reported a pre-Phase2 failure" >&2
        exit 1
    fi
    echo "${svt_run_label}_PROCESS_PASS process=${process_epoch} log=${process_log}"
done
echo "${svt_run_label}_VCS_PASS processes=${process_epochs} run_dir=${run_dir} simlib=${simlib_dir}"
