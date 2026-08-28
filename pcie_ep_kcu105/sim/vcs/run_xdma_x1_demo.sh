#!/usr/bin/env bash
set -euo pipefail

# Compile/run the generated XDMA Gen3 x1 example shipped in this repository.
# This is intentionally independent of the K11-B soft endpoint testbench: it
# uses the demo's own board.v, RP imports, XDMA generated simulation model and
# GT Wizard model, so it is a useful A/B reference for the standalone PHY.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
demo_dir="${project_dir}/fpga/kcu105/xdma_x1_demo/build/example/xdma_x1_ex"
gen_dir="${demo_dir}/xdma_x1_ex.gen/sources_1/ip/xdma_x1"
gen_root="${demo_dir}/xdma_x1_ex.gen/sources_1/ip"
imports_dir="${demo_dir}/imports"
vcs_home="${VCS_HOME:-/home/synopsys/vcs-mx/O-2018.09-SP2}"
vivado_home="${VIVADO_HOME:-/home/Xilinx/Vivado/2021.2}"
simlib_dir="${XILINX_VCS_SIMLIB:-/home/wx/Documents/vcs_compile_simlib}"
license_server="${VCS_LICENSE_SERVER:-27000@wx-linux}"
license_timeout="${VCS_LICENSE_TIMEOUT:-300}"
simulation_timeout="${XDMA_X1_SIM_TIMEOUT:-300}"

for required in \
    "${imports_dir}/board.v" \
    "${imports_dir}/pcie3_uscale_rp_core_top.v" \
    "${gen_dir}/sim/xdma_x1.sv" \
    "${gen_dir}/ip_0/sim/xdma_x1_pcie3_ip.v"; do
    test -s "${required}" || { echo "missing demo simulation source: ${required}" >&2; exit 66; }
done

export VCS_HOME="${vcs_home}"
export VCS_ARCH_OVERRIDE=linux
export SNPSLMD_LICENSE_FILE="${SNPSLMD_LICENSE_FILE:-${license_server}}"
if [[ ":${LM_LICENSE_FILE:-}:" != *":${license_server}:"* ]]; then
    export LM_LICENSE_FILE="${license_server}${LM_LICENSE_FILE:+:${LM_LICENSE_FILE}}"
fi

cd "${script_dir}"
mkdir -p build
run_dir="$(mktemp -d "${TMPDIR:-/tmp}/xdma_x1_demo_vcs.XXXXXX")"
setup_file="${run_dir}/synopsys_sim.setup"
printf 'WORK > DEFAULT\nDEFAULT : %s\nxil_defaultlib : %s\nOTHERS=%s/synopsys_sim.setup\n' \
    "${run_dir}/work" "${run_dir}/xil_defaultlib" "${simlib_dir}" > "${setup_file}"
mkdir -p "${run_dir}/work" "${run_dir}/xil_defaultlib"
export SYNOPSYS_SIM_SETUP="${setup_file}"

if [[ "${VCS_LICENSE_PREFLIGHT:-1}" == "1" && -x "${VCS_LICENSE_LMUTIL:-/home/questasim/linux_x86_64/lmutil}" ]]; then
    set +e
    timeout --foreground 10 "${VCS_LICENSE_LMUTIL:-/home/questasim/linux_x86_64/lmutil}" lmstat \
        -f VCSCompiler_Net -c "${license_server}" > build/xdma_x1_demo_license.log 2>&1
    preflight_status=$?
    set -e
    if [[ ${preflight_status} -ne 0 ]]; then
        cat build/xdma_x1_demo_license.log >&2
        echo "VCS license preflight failed for ${license_server}" >&2
        exit 69
    fi
fi

# Generated XDMA simulation sources.  The wrapper and PCIe source are kept
# separate from the GT Wizard source because the latter supplies the secureip
# model through the standard VCS library.
mapfile -t gt_sim_files < <(find "${gen_dir}/ip_0/ip_0/sim" -maxdepth 1 -type f -name '*.v' | sort)
mapfile -t core_source_files < <(find "${gen_dir}/ip_0/source" -maxdepth 1 -type f -name '*.v' | sort)
mapfile -t xdma_hdl_files < <(find "${gen_dir}/xdma_v4_1/hdl/verilog" -maxdepth 1 -type f \( -name '*.sv' -o -name '*.v' \) | sort)

"${vcs_home}/bin/vlogan" -full64 -sverilog -work xil_defaultlib \
    +incdir+"${gen_dir}/hdl/verilog" \
    +incdir+"${gen_dir}/xdma_v4_1/hdl/verilog" \
    "${gt_sim_files[@]}" "${core_source_files[@]}" \
    "${xdma_hdl_files[@]}" \
    "${gen_dir}/hdl/xdma_v4_1_vl_rfs.sv" \
    "${gen_dir}/sim/xdma_x1.sv" \
    "${gen_dir}/ip_0/sim/xdma_x1_pcie3_ip.v" \
    "${gen_dir}/ip_1/sim/xdma_v4_1_14_blk_mem_64_reg_be.v" \
    "${gen_dir}/ip_2/sim/xdma_v4_1_14_blk_mem_64_noreg_be.v" \
    "${gen_root}/blk_mem_gen_1/sim/blk_mem_gen_1.v" \
    -l build/xdma_x1_demo_ep_vlogan.log

"${vcs_home}/bin/vlogan" -full64 +v2k -work xil_defaultlib \
    +incdir+"${imports_dir}" \
    "${imports_dir}/pci_exp_usrapp_cfg.v" \
    "${imports_dir}/pci_exp_usrapp_com.v" \
    "${imports_dir}/pci_exp_usrapp_rx.v" \
    "${imports_dir}/pci_exp_usrapp_tx.v" \
    "${imports_dir}/pci_exp_usrapp_pl.v" \
    "${imports_dir}/pcie3_uscale_rp_core_top.v" \
    "${imports_dir}/pcie3_uscale_rp_top.v" \
    "${imports_dir}/xilinx_pcie_uscale_rp.v" \
    "${imports_dir}/sys_clk_gen.v" \
    "${imports_dir}/sys_clk_gen_ds.v" \
    -l build/xdma_x1_demo_rp_vlogan.log

"${vcs_home}/bin/vlogan" -full64 -sverilog -work xil_defaultlib \
    +define+VCS \
    +incdir+"${imports_dir}" \
    "${imports_dir}/xdma_app.v" \
    "${imports_dir}/xilinx_dma_pcie_ep.sv" \
    "${vivado_home}/data/verilog/src/glbl.v" \
    "${imports_dir}/board.v" \
    -l build/xdma_x1_demo_tb_vlogan.log

set +e
timeout --foreground "${license_timeout}" "${vcs_home}/bin/vcs" -full64 \
    xil_defaultlib.board xil_defaultlib.glbl \
    -Lgtwizard_ultrascale_v1_7_12 -Lsecureip -Lunisims_ver -Lxpm \
    -debug_access+pp+dmptf -t ps -licqueue \
    -LDFLAGS "-Wl,--no-as-needed" \
    -Mdir="${run_dir}/csrc" -o "${run_dir}/xdma_x1_demo_simv" \
    -l build/xdma_x1_demo_elaborate.log
elab_status=$?
set -e
if [[ ${elab_status} -ne 0 ]]; then
    echo "XDMA x1 demo VCS elaboration failed/status=${elab_status}" >&2
    exit "${elab_status}"
fi

set +e
timeout --foreground "${simulation_timeout}" \
    "${run_dir}/xdma_x1_demo_simv" +dump_all -licqueue \
    -l build/xdma_x1_demo_simulate.log
sim_status=$?
set -e
if [[ ${sim_status} -ne 0 ]]; then
    echo "XDMA x1 demo VCS simulation failed/status=${sim_status}" >&2
    exit "${sim_status}"
fi

echo "XDMA_X1_DEMO_VCS_PASS run_dir=${run_dir}"
