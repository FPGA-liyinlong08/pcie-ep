#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../../.." && pwd)"
demo_dir="${K13_OFFICIAL_PHY_DEMO:-/home/wx/Documents/KCU105/pcie_phy_0_ex}"
vcs_home="${VCS_HOME:-/home/synopsys/vcs-mx/O-2018.09-SP2}"
simlib_dir="${XILINX_VCS_SIMLIB:-/home/wx/Documents/vcs_compile_simlib}"
result_dir="${K13_PHY_RESULT_DIR:-${demo_dir}/vcs_results/k13_phy_rate_change}"
license_server="${VCS_LICENSE_SERVER:-27000@wx-linux}"
license_timeout="${VCS_LICENSE_TIMEOUT:-300}"
simulation_timeout="${K13_PHY_SIM_TIMEOUT:-300}"
ip_root="${demo_dir}/pcie_phy_0_ex.gen/sources_1/ip/pcie_phy_0"

test -s "${ip_root}/sim/pcie_phy_0.v"
test -s "${ip_root}/source/pcie_phy_0_core_top.v"
test -s "${simlib_dir}/synopsys_sim.setup"

export VCS_HOME="${vcs_home}"
export VCS_ARCH_OVERRIDE=linux
export SNPSLMD_LICENSE_FILE="${SNPSLMD_LICENSE_FILE:-${license_server}}"
if [[ ":${LM_LICENSE_FILE:-}:" != *":${license_server}:"* ]]; then
    export LM_LICENSE_FILE="${license_server}${LM_LICENSE_FILE:+:${LM_LICENSE_FILE}}"
fi

mkdir -p "${result_dir}"
run_dir="$(mktemp -d /tmp/pcie_k13_phy_rate_change.XXXXXX)"
setup_file="${run_dir}/synopsys_sim.setup"
mkdir -p "${run_dir}/work" "${run_dir}/xil_defaultlib"
printf 'WORK > DEFAULT\nDEFAULT : %s\nxil_defaultlib : %s\nOTHERS=%s/synopsys_sim.setup\n' \
    "${run_dir}/work" "${run_dir}/xil_defaultlib" "${simlib_dir}" > "${setup_file}"
export SYNOPSYS_SIM_SETUP="${setup_file}"

cd "${script_dir}"
"${vcs_home}/bin/vlogan" -full64 +v2k -work xil_defaultlib \
    "${ip_root}/ip_0/sim/gtwizard_ultrascale_v1_7_gthe3_channel.v" \
    "${ip_root}/ip_0/sim/pcie_phy_0_gt_gthe3_channel_wrapper.v" \
    "${ip_root}/ip_0/sim/gtwizard_ultrascale_v1_7_gthe3_common.v" \
    "${ip_root}/ip_0/sim/pcie_phy_0_gt_gthe3_common_wrapper.v" \
    "${ip_root}/ip_0/sim/pcie_phy_0_gt_gtwizard_gthe3.v" \
    "${ip_root}/ip_0/sim/pcie_phy_0_gt_gtwizard_top.v" \
    "${ip_root}/ip_0/sim/pcie_phy_0_gt.v" \
    "${ip_root}/source/pcie_phy_0_sync_cell.v" \
    "${ip_root}/source/pcie_phy_0_sync.v" \
    "${ip_root}/source/pcie_phy_0_phy_ff_chain.v" \
    "${ip_root}/source/pcie_phy_0_phy_pipeline.v" \
    "${ip_root}/source/pcie_phy_0_us_gt_phy_wrapper.v" \
    "${ip_root}/source/pcie_phy_0_us_gt_phy_clk.v" \
    "${ip_root}/source/pcie_phy_0_us_gt_phy_rst.v" \
    "${ip_root}/source/pcie_phy_0_us_gt_phy_txeq.v" \
    "${ip_root}/source/pcie_phy_0_us_gt_phy_rxeq.v" \
    "${ip_root}/source/pcie_phy_0_gtwizard_top.v" \
    "${ip_root}/source/pcie_phy_0_core_top.v" \
    "${ip_root}/sim/pcie_phy_0.v" \
    -l "${result_dir}/k13_phy_rate_change_phy_vlogan.log"

"${vcs_home}/bin/vlogan" -full64 -sverilog -work xil_defaultlib \
    "${project_dir}/rtl/common/pcie_retrain_cdc_mailbox.sv" \
    "${project_dir}/rtl/phy/pcie_phy_rate_contract.sv" \
    "${project_dir}/rtl/phy/pcie_recovery_speed_ctrl.sv" \
    "${project_dir}/rtl/phy/pcie_recovery_ts_guard.sv" \
    "${project_dir}/rtl/phy/pcie_equalization_ctrl.sv" \
    "${project_dir}/rtl/phy/pcie_k13_production_ctrl.sv" \
    "${script_dir}/k13_phy_rate_change_tb.sv" \
    "/home/Xilinx/Vivado/2021.2/data/verilog/src/glbl.v" \
    -l "${result_dir}/k13_phy_rate_change_tb_vlogan.log"

set +e
timeout --foreground "${license_timeout}" "${vcs_home}/bin/vcs" -full64 \
    xil_defaultlib.k13_phy_rate_change_tb xil_defaultlib.glbl \
    -Lgtwizard_ultrascale_v1_7_12 -Lsecureip -Lunisims_ver -Lxpm \
    -debug_access+pp+dmptf -t ps -licqueue \
    -LDFLAGS "-Wl,--no-as-needed" \
    -Mdir="${run_dir}/csrc" -o "${run_dir}/k13_phy_rate_change_simv" \
    -l "${result_dir}/k13_phy_rate_change_elaboration.log"
elaborate_status=$?
set -e
if [[ ${elaborate_status} -eq 124 ]]; then
    echo "K13 narrow VCS elaboration license timeout" >&2
    exit 124
elif [[ ${elaborate_status} -ne 0 ]]; then
    exit "${elaborate_status}"
fi

cd "${result_dir}"
set +e
timeout --foreground "${simulation_timeout}" \
    "${run_dir}/k13_phy_rate_change_simv" -licqueue \
    -l "${result_dir}/k13_phy_rate_change_simulation.log"
simulation_status=$?
set -e
if [[ ${simulation_status} -eq 124 ]]; then
    echo "K13 narrow VCS simulation timeout" >&2
    exit 124
elif [[ ${simulation_status} -ne 0 ]]; then
    exit "${simulation_status}"
fi

grep -q 'K13_PRODUCTION_PHY_RATE_CHANGE_VCS_PASS' \
    "${result_dir}/k13_phy_rate_change_simulation.log"
echo "K13_PRODUCTION_PHY_RATE_CHANGE_VCS_PASS result_dir=${result_dir}"
