#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_dir="${K13_OFFICIAL_PHY_DEMO:-/home/wx/Documents/KCU105/pcie_phy_0_ex}"
vcs_home="${VCS_HOME:-/home/synopsys/vcs-mx/O-2018.09-SP2}"
simlib_dir="${XILINX_VCS_SIMLIB:-/home/wx/Documents/vcs_compile_simlib}"
result_dir="${K13_OFFICIAL_TRACE_RESULT_DIR:-${demo_dir}/vcs_results/official_trace}"
license_server="${VCS_LICENSE_SERVER:-27000@wx-linux}"
license_timeout="${VCS_LICENSE_TIMEOUT:-300}"
ip_root="${demo_dir}/pcie_phy_0_ex.gen/sources_1/ip/pcie_phy_0"

export VCS_HOME="${vcs_home}"
export VCS_ARCH_OVERRIDE=linux
export SNPSLMD_LICENSE_FILE="${SNPSLMD_LICENSE_FILE:-${license_server}}"
if [[ ":${LM_LICENSE_FILE:-}:" != *":${license_server}:"* ]]; then
    export LM_LICENSE_FILE="${license_server}${LM_LICENSE_FILE:+:${LM_LICENSE_FILE}}"
fi

test -s "${ip_root}/sim/pcie_phy_0.v"
mkdir -p "${result_dir}"
run_dir="$(mktemp -d /tmp/pcie_k13_official_trace.XXXXXX)"
setup_file="${run_dir}/synopsys_sim.setup"
mkdir -p "${run_dir}/work" "${run_dir}/xil_defaultlib"
printf 'WORK > DEFAULT\nDEFAULT : %s\nxil_defaultlib : %s\nOTHERS=%s/synopsys_sim.setup\n' \
    "${run_dir}/work" "${run_dir}/xil_defaultlib" "${simlib_dir}" > "${setup_file}"
export SYNOPSYS_SIM_SETUP="${setup_file}"

cd "${script_dir}"
"${vcs_home}/bin/vlogan" -full64 -sverilog -work xil_defaultlib \
    +incdir+"${demo_dir}/imports" \
    "/home/Xilinx/Vivado/2021.2/data/verilog/src/glbl.v" \
    "/home/Xilinx/Vivado/2021.2/data/verilog/src/unisims/BUFG_GT.v" \
    "/home/Xilinx/Vivado/2021.2/data/verilog/src/unisims/GTHE3_CHANNEL.v" \
    "/home/Xilinx/Vivado/2021.2/data/verilog/src/unisims/GTHE3_COMMON.v" \
    "/home/Xilinx/Vivado/2021.2/data/verilog/src/unisims/IBUF.v" \
    "/home/Xilinx/Vivado/2021.2/data/verilog/src/unisims/IBUFDS_GTE3.v" \
    "/home/Xilinx/Vivado/2021.2/data/verilog/src/unisims/OBUF.v" \
    "${demo_dir}/imports/board.v" \
    "${demo_dir}/imports/phy_ctrl.v" \
    "${demo_dir}/imports/phy_ctrl_pat_gen.v" \
    "${demo_dir}/imports/phy_ctrl_pat_gen_lane.v" \
    "${demo_dir}/imports/sys_clk_gen.v" \
    "${demo_dir}/imports/sys_clk_gen_ds.v" \
    "${demo_dir}/imports/xilinx_pcie_phy_model.v" \
    "${demo_dir}/imports/xilinx_pcie_phy_top.v" \
    "${ip_root}/ip_0/sim/gtwizard_ultrascale_v1_7_gthe3_channel.v" \
    "${ip_root}/ip_0/sim/gtwizard_ultrascale_v1_7_gthe3_common.v" \
    "${ip_root}/ip_0/sim/pcie_phy_0_gt.v" \
    "${ip_root}/ip_0/sim/pcie_phy_0_gt_gthe3_channel_wrapper.v" \
    "${ip_root}/ip_0/sim/pcie_phy_0_gt_gthe3_common_wrapper.v" \
    "${ip_root}/ip_0/sim/pcie_phy_0_gt_gtwizard_gthe3.v" \
    "${ip_root}/ip_0/sim/pcie_phy_0_gt_gtwizard_top.v" \
    "${ip_root}/sim/pcie_phy_0.v" \
    "${ip_root}/source/pcie_phy_0_core_top.v" \
    "${ip_root}/source/pcie_phy_0_gtwizard_top.v" \
    "${ip_root}/source/pcie_phy_0_phy_ff_chain.v" \
    "${ip_root}/source/pcie_phy_0_phy_pipeline.v" \
    "${ip_root}/source/pcie_phy_0_sync.v" \
    "${ip_root}/source/pcie_phy_0_sync_cell.v" \
    "${ip_root}/source/pcie_phy_0_us_gt_phy_clk.v" \
    "${ip_root}/source/pcie_phy_0_us_gt_phy_rst.v" \
    "${ip_root}/source/pcie_phy_0_us_gt_phy_rxeq.v" \
    "${ip_root}/source/pcie_phy_0_us_gt_phy_txeq.v" \
    "${ip_root}/source/pcie_phy_0_us_gt_phy_wrapper.v" \
    "${script_dir}/official_trace_bind.sv" \
    -l "${result_dir}/official_trace_vlogan.log"

set +e
timeout --foreground "${license_timeout}" "${vcs_home}/bin/vcs" -full64 \
    -top board -top glbl -Lsecureip -Lunisims_ver -Lunifast_ver \
    -Lunimacro_ver -debug_access+all -t ps -licqueue \
    -LDFLAGS "-Wl,--no-as-needed" \
    -Mdir="${run_dir}/csrc" -o "${run_dir}/official_trace_simv" \
    -l "${result_dir}/official_trace_elaboration.log"
elaborate_status=$?
set -e
if [[ ${elaborate_status} -eq 124 ]]; then
    echo "official trace elaboration license timeout" >&2
    exit 124
elif [[ ${elaborate_status} -ne 0 ]]; then
    exit "${elaborate_status}"
fi

cd "${result_dir}"
timeout --foreground "${K13_OFFICIAL_TRACE_SIM_TIMEOUT:-300}" \
    "${run_dir}/official_trace_simv" -licqueue \
    -l "${result_dir}/official_trace_simulation.log"
grep -q 'Test Completed Successfully' "${result_dir}/official_trace_simulation.log"
echo "K13_OFFICIAL_PHY_TRACE_PASS result_dir=${result_dir}"
