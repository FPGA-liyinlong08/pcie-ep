#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
vcs_home="${VCS_HOME:-/home/synopsys/vcs-mx/O-2018.09-SP2}"
vivado_home="${VIVADO_HOME:-/home/Xilinx/Vivado/2021.2}"
ip_dir="${project_dir}/fpga/kcu105/ip/pcie_phy_x1_gen3"
simlib_dir="/home/wx/Documents/vcs_compile_simlib"
license_timeout="${VCS_LICENSE_TIMEOUT:-300}"
license_server="${VCS_LICENSE_SERVER:-27000@wx-linux}"
license_lmutil="${VCS_LICENSE_LMUTIL:-/home/questasim/linux_x86_64/lmutil}"

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
        echo "错误：无法访问 Synopsys 许可证服务 ${license_server}；请检查本地 license 环境" >&2
        exit 69
    fi
fi
extra_tb_sources=()
if [[ "${K14_DIRECT_VCS:-0}" == "1" ]]; then
    tb_name=k14_direct_vcs_tb
    tb_source="${script_dir}/k14_direct/k14_direct_vcs_tb.sv"
    sim_log=build/k14_direct_simulate.log
    elaborate_log=build/k14_direct_elaborate.log
    sim_exe_name=k14_direct_simv
    pass_marker=K14_DIRECT_VCS_PASS
    extra_tb_sources+=(
        "${project_dir}/rtl/phy/pcie_partner_retrain_pending.sv"
        "${project_dir}/rtl/phy/pcie_recovery_speed_ctrl.sv"
        "${project_dir}/rtl/phy/pcie_phy_command_ctrl.sv"
    )
elif [[ "${K02_VCS_DYNAMIC_TXEQ:-0}" == "1" ]]; then
    tb_name=k02_dynamic_txeq_tb
    tb_source="${script_dir}/k02_dynamic_txeq_tb.sv"
    sim_log=build/k02_dynamic_txeq_simulate.log
    elaborate_log=build/k02_dynamic_txeq_elaborate.log
    sim_exe_name=k02_dynamic_txeq_simv
    pass_marker=K02_VCS_DYNAMIC_TXEQ_PASS
elif [[ "${K02_VCS_GEN3_STEADY:-0}" == "1" ]]; then
    tb_name=k02_gen3_steady_tb
    tb_source="${script_dir}/k02_gen3_steady_tb.sv"
    sim_log=build/k02_gen3_steady_simulate.log
    elaborate_log=build/k02_gen3_steady_elaborate.log
    sim_exe_name=k02_gen3_steady_simv
    pass_marker=K02_VCS_GEN3_STEADY_PASS
else
    tb_name=k02_pcie_phy_tb
    tb_source="${script_dir}/k02_pcie_phy_tb.sv"
    sim_log=build/k02_simulate.log
    elaborate_log=build/k02_elaborate.log
    sim_exe_name=k02_simv
    pass_marker=K02_VCS_PHY_PASS
fi
if [[ "${K02_SKIP_IP_GENERATION:-0}" == "1" ]]; then
    test -s "${ip_dir}/pcie_phy_x1_gen3.xci"
    test -s "${ip_dir}/sim/pcie_phy_x1_gen3.v"
    echo "K02_VCS_REUSE_GENERATED_IP"
else
    "${project_dir}/fpga/kcu105/run_k02_ip_generation.sh"
fi

# VCS 的 AN.DB 会留下进程级数据库锁。K02 每次使用独立 work library，避免
# 被先前因许可证排队或 Ctrl-C 中止的进程污染；预编译 Xilinx 库仍通过 OTHERS
# 只读复用。
run_dir="$(mktemp -d "${TMPDIR:-/tmp}/pcie_k02_vcs.XXXXXX")"
setup_file="${run_dir}/synopsys_sim.setup"
mkdir -p build "${run_dir}/work" "${run_dir}/xil_defaultlib"
printf 'WORK > DEFAULT\nDEFAULT : %s\nxil_defaultlib : %s\nOTHERS=%s/synopsys_sim.setup\n' \
    "${run_dir}/work" "${run_dir}/xil_defaultlib" "${simlib_dir}" \
    > "${setup_file}"
export SYNOPSYS_SIM_SETUP="${setup_file}"

"${vcs_home}/bin/vlogan" -full64 +v2k -work xil_defaultlib \
    "${ip_dir}/ip_0/sim/gtwizard_ultrascale_v1_7_gthe3_channel.v" \
    "${ip_dir}/ip_0/sim/pcie_phy_x1_gen3_gt_gthe3_channel_wrapper.v" \
    "${ip_dir}/ip_0/sim/gtwizard_ultrascale_v1_7_gthe3_common.v" \
    "${ip_dir}/ip_0/sim/pcie_phy_x1_gen3_gt_gthe3_common_wrapper.v" \
    "${ip_dir}/ip_0/sim/pcie_phy_x1_gen3_gt_gtwizard_gthe3.v" \
    "${ip_dir}/ip_0/sim/pcie_phy_x1_gen3_gt_gtwizard_top.v" \
    "${ip_dir}/ip_0/sim/pcie_phy_x1_gen3_gt.v" \
    "${ip_dir}/source/pcie_phy_x1_gen3_sync_cell.v" \
    "${ip_dir}/source/pcie_phy_x1_gen3_sync.v" \
    "${ip_dir}/source/pcie_phy_x1_gen3_phy_ff_chain.v" \
    "${ip_dir}/source/pcie_phy_x1_gen3_phy_pipeline.v" \
    "${ip_dir}/source/pcie_phy_x1_gen3_us_gt_phy_wrapper.v" \
    "${ip_dir}/source/pcie_phy_x1_gen3_us_gt_phy_clk.v" \
    "${ip_dir}/source/pcie_phy_x1_gen3_us_gt_phy_rst.v" \
    "${ip_dir}/source/pcie_phy_x1_gen3_us_gt_phy_txeq.v" \
    "${ip_dir}/source/pcie_phy_x1_gen3_us_gt_phy_rxeq.v" \
    "${ip_dir}/source/pcie_phy_x1_gen3_gtwizard_top.v" \
    "${ip_dir}/source/pcie_phy_x1_gen3_core_top.v" \
    "${ip_dir}/sim/pcie_phy_x1_gen3.v" \
    -l build/k02_ip_vlogan.log

"${vcs_home}/bin/vlogan" -full64 -sverilog -work xil_defaultlib \
    "${project_dir}/rtl/common/pcie_reset_sync.sv" \
    "${project_dir}/rtl/phy/kcu105_reset_ctrl.sv" \
    "${project_dir}/rtl/phy/kcu105_refclk_reset.sv" \
    "${project_dir}/rtl/phy/kcu105_pcie_phy_wrapper.sv" \
    "${extra_tb_sources[@]}" \
    "${vivado_home}/data/verilog/src/glbl.v" \
    "${tb_source}" \
    -l build/k02_tb_vlogan.log

set +e
timeout --foreground "${license_timeout}" "${vcs_home}/bin/vcs" -full64 \
    "xil_defaultlib.${tb_name}" xil_defaultlib.glbl \
    -Lgtwizard_ultrascale_v1_7_12 \
    -Lsecureip -Lunisims_ver -Lxpm \
    -debug_access+pp+dmptf -t ps -licqueue \
    -LDFLAGS "-Wl,--no-as-needed" \
    -Mdir="${run_dir}/csrc_k02" \
    -o "${run_dir}/${sim_exe_name}" \
    -l "${elaborate_log}"
elaborate_status=$?
set -e
if [[ ${elaborate_status} -eq 124 ]]; then
    echo "错误：K02 VCS elaboration 等待 VCSCompiler_Net 许可证超过 ${license_timeout} 秒" >&2
    exit 124
elif [[ ${elaborate_status} -ne 0 ]]; then
    exit "${elaborate_status}"
fi

sim_plusargs=()
if [[ "${K02_VCS_QUERY:-0}" == "1" ]]; then
    sim_plusargs+=(+K02_QUERY=1)
fi

set +e
timeout --foreground "${license_timeout}" \
    "${run_dir}/${sim_exe_name}" -licqueue "${sim_plusargs[@]}" -l "${sim_log}"
simulate_status=$?
set -e
if [[ ${simulate_status} -eq 124 ]]; then
    echo "错误：K02 VCS 仿真等待许可证超过 ${license_timeout} 秒" >&2
    exit 124
elif [[ ${simulate_status} -ne 0 ]]; then
    exit "${simulate_status}"
fi
grep -q "${pass_marker}" "${sim_log}"

echo "K02_VCS_REAL_IP_PASS mode=${tb_name} run_dir=${run_dir}"
