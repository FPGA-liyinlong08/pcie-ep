#!/usr/bin/env bash
# K15 EP TX / standalone PHY receiver isolation experiment.
#
# Official 2x standalone PHY testbench with ONE change at elaboration: the
# official phy_ctrl_pat_gen.v is replaced by k15_ep_pat_gen.sv (same module
# name and ports), which drives the Gen3 PIPE payload from K15's
# pcie_gen3_os_tx instead of the official EIEOS+beefcafe pattern.  The
# generated PHY, the official phy_ctrl reset/rate sequencer and the partner
# xilinx_pcie_phy_model receiver are untouched.
#
# Pass criteria (xilinx_pcie_phy_model receiving the K15 stream):
#   RXDATA_VALID occurs in Gen3 and the first valid block is a complete
#   EIEOS (start=1, header=01, ff00ff00 x4), as in the passing official
#   golden.  Complementary CSVs and serial edges reuse official_trace_bind.sv.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../../.." && pwd)"
demo_dir="${K13_OFFICIAL_PHY_DEMO:-${project_dir}/../pcie_phy_0_ex}"
vcs_home="${VCS_HOME:-/home/synopsys/vcs-mx/O-2018.09-SP2}"
vivado_home="${VIVADO_HOME:-/home/Xilinx/Vivado/2021.2}"
result_dir="${K15_ISO_RESULT_DIR:-${project_dir}/sim/vcs/build/k15_phy_isolation}"
license_server="${VCS_LICENSE_SERVER:-27000@wx-linux}"
license_timeout="${VCS_LICENSE_TIMEOUT:-300}"
ip_root="${K13_OFFICIAL_PHY_IP_ROOT:-${project_dir}/fpga/kcu105/ip/pcie_phy_x1_gen3}"
phy_name="${K13_OFFICIAL_PHY_MODULE:-pcie_phy_x1_gen3}"

if [[ -n "${XILINX_VCS_SIMLIB:-}" ]]; then
    simlib_dir="${XILINX_VCS_SIMLIB}"
elif [[ -n "${VIVADO_SIMLIB:-}" ]]; then
    simlib_dir="${VIVADO_SIMLIB}"
elif [[ -f /home/wx/Documents/vcs_compile_simlib/synopsys_sim.setup ]]; then
    simlib_dir=/home/wx/Documents/vcs_compile_simlib
else
    echo "missing Vivado VCS simlib; set XILINX_VCS_SIMLIB or VIVADO_SIMLIB" >&2
    exit 66
fi

export VCS_HOME="${vcs_home}"
export VCS_ARCH_OVERRIDE=linux
export SNPSLMD_LICENSE_FILE="${SNPSLMD_LICENSE_FILE:-${license_server}}"
if [[ ":${LM_LICENSE_FILE:-}:" != *":${license_server}:"* ]]; then
    export LM_LICENSE_FILE="${license_server}${LM_LICENSE_FILE:+:${LM_LICENSE_FILE}}"
fi

test -s "${demo_dir}/imports/board.v"
test -s "${ip_root}/sim/${phy_name}.v"
test -s "${simlib_dir}/synopsys_sim.setup"
test -s "${project_dir}/rtl/phy/pcie_gen3_os_tx.sv"
test -s "${project_dir}/rtl/phy/pcie_gen3_scrambler32.sv"
mkdir -p "${result_dir}"
run_dir="$(mktemp -d /tmp/pcie_k15_isolation.XXXXXX)"
setup_file="${run_dir}/synopsys_sim.setup"
mkdir -p "${run_dir}/work" "${run_dir}/xil_defaultlib"
printf 'WORK > DEFAULT\nDEFAULT : %s\nxil_defaultlib : %s\nOTHERS=%s/synopsys_sim.setup\n' \
    "${run_dir}/work" "${run_dir}/xil_defaultlib" "${simlib_dir}" > "${setup_file}"
export SYNOPSYS_SIM_SETUP="${setup_file}"

phy_top_source="${ip_root}/sim/${phy_name}.v"
if [[ "${phy_name}" != "pcie_phy_0" ]]; then
    phy_top_source="${run_dir}/pcie_phy_0_adapter.v"
    sed "s/^module ${phy_name} (/module pcie_phy_0 (/" \
        "${ip_root}/sim/${phy_name}.v" > "${phy_top_source}"
fi

# Optional diagnostic defines, e.g. K15_ISO_EXTRA_DEFINES=+define+K15_AB_XILINX_PATTERN
extra_defines=(${K15_ISO_EXTRA_DEFINES:-})

cd "${script_dir}"
"${vcs_home}/bin/vlogan" -full64 -sverilog -work xil_defaultlib \
    "${extra_defines[@]}" \
    +incdir+"${demo_dir}/imports" \
    "${vivado_home}/data/verilog/src/glbl.v" \
    "${vivado_home}/data/verilog/src/unisims/BUFG_GT.v" \
    "${vivado_home}/data/verilog/src/unisims/GTHE3_CHANNEL.v" \
    "${vivado_home}/data/verilog/src/unisims/GTHE3_COMMON.v" \
    "${vivado_home}/data/verilog/src/unisims/IBUF.v" \
    "${vivado_home}/data/verilog/src/unisims/IBUFDS_GTE3.v" \
    "${vivado_home}/data/verilog/src/unisims/OBUF.v" \
    "${demo_dir}/imports/board.v" \
    "${demo_dir}/imports/phy_ctrl.v" \
    "${demo_dir}/imports/phy_ctrl_pat_gen_lane.v" \
    "${demo_dir}/imports/sys_clk_gen.v" \
    "${demo_dir}/imports/sys_clk_gen_ds.v" \
    "${demo_dir}/imports/xilinx_pcie_phy_model.v" \
    "${demo_dir}/imports/xilinx_pcie_phy_top.v" \
    "${project_dir}/rtl/phy/pcie_gen3_os_tx.sv" \
    "${project_dir}/rtl/phy/pcie_gen3_scrambler32.sv" \
    "${ip_root}/ip_0/sim/gtwizard_ultrascale_v1_7_gthe3_channel.v" \
    "${ip_root}/ip_0/sim/gtwizard_ultrascale_v1_7_gthe3_common.v" \
    "${ip_root}/ip_0/sim/${phy_name}_gt.v" \
    "${ip_root}/ip_0/sim/${phy_name}_gt_gthe3_channel_wrapper.v" \
    "${ip_root}/ip_0/sim/${phy_name}_gt_gthe3_common_wrapper.v" \
    "${ip_root}/ip_0/sim/${phy_name}_gt_gtwizard_gthe3.v" \
    "${ip_root}/ip_0/sim/${phy_name}_gt_gtwizard_top.v" \
    "${phy_top_source}" \
    "${ip_root}/source/${phy_name}_core_top.v" \
    "${ip_root}/source/${phy_name}_gtwizard_top.v" \
    "${ip_root}/source/${phy_name}_phy_ff_chain.v" \
    "${ip_root}/source/${phy_name}_phy_pipeline.v" \
    "${ip_root}/source/${phy_name}_sync.v" \
    "${ip_root}/source/${phy_name}_sync_cell.v" \
    "${ip_root}/source/${phy_name}_us_gt_phy_clk.v" \
    "${ip_root}/source/${phy_name}_us_gt_phy_rst.v" \
    "${ip_root}/source/${phy_name}_us_gt_phy_rxeq.v" \
    "${ip_root}/source/${phy_name}_us_gt_phy_txeq.v" \
    "${ip_root}/source/${phy_name}_us_gt_phy_wrapper.v" \
    "${script_dir}/k15_ep_pat_gen.sv" \
    "${script_dir}/k15_isolation_trace.sv" \
    "${script_dir}/k15_iso_serial_trace.sv" \
    "${script_dir}/k15_iso_debug_trace.sv" \
    "${script_dir}/k15_iso_rxeq_trace.sv" \
    "${script_dir}/k15_iso_serial_long.sv" \
    "${script_dir}/k15_iso_gtrx_trace.sv" \
    "${script_dir}/k15_iso_gthe3_trace.sv" \
    "${script_dir}/k15_iso_gttx_trace.sv" \
    "${project_dir}/sim/vcs/k13_phy_rate_change/official_trace_bind.sv" \
    -l "${result_dir}/k15_isolation_vlogan.log"

set +e
timeout --foreground "${license_timeout}" "${vcs_home}/bin/vcs" -full64 \
    -top board -top glbl -Lsecureip -Lunisims_ver -Lunifast_ver \
    -Lunimacro_ver -debug_access+all -t ps -licqueue \
    -LDFLAGS "-Wl,--no-as-needed" \
    -Mdir="${run_dir}/csrc" -o "${run_dir}/k15_isolation_simv" \
    -l "${result_dir}/k15_isolation_elaboration.log"
elaborate_status=$?
set -e
if [[ ${elaborate_status} -eq 124 ]]; then
    echo "k15 isolation elaboration license timeout" >&2
    exit 124
elif [[ ${elaborate_status} -ne 0 ]]; then
    exit "${elaborate_status}"
fi

cd "${result_dir}"
timeout --foreground "${K15_ISO_SIM_TIMEOUT:-300}" \
    "${run_dir}/k15_isolation_simv" -licqueue \
    -l "${result_dir}/k15_isolation_simulation.log"
grep -q 'Test Completed Successfully' "${result_dir}/k15_isolation_simulation.log"
grep -q 'K15_ISO_RECEIVER_ACQ_PASS label=1' "${result_dir}/k15_isolation_simulation.log"
echo "K15_ISO_RECEIVER_ACQ experiment PASS result_dir=${result_dir}"
