#!/usr/bin/env bash
set -euo pipefail

# Run the Xilinx-generated XDMA x1 example endpoint against the Synopsys SVT
# PCIe Root Port.  The official endpoint/GT sources are treated as an opaque
# generated design; this script supplies only the SVT board and VMM test.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
demo_dir="${XDMA_X1_DEMO_DIR:-${project_dir}/fpga/kcu105/xdma_x1_demo/build/example/xdma_x1_ex}"
gen_dir="${demo_dir}/xdma_x1_ex.gen/sources_1/ip/xdma_x1"
gen_root="${demo_dir}/xdma_x1_ex.gen/sources_1/ip"
imports_dir="${demo_dir}/imports"
build_dir="${XDMA_X1_SVT_BUILD_DIR:-${script_dir}/build_xdma_x1}"
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
if [[ -n "${XILINX_VCS_SIMLIB:-}" ]]; then
    simlib_dir="${XILINX_VCS_SIMLIB}"
elif [[ -n "${VIVADO_SIMLIB:-}" ]]; then
    simlib_dir="${VIVADO_SIMLIB}"
elif [[ -f /home/wx/Documents/vcs_compile_simlib/synopsys_sim.setup ]]; then
    simlib_dir=/home/wx/Documents/vcs_compile_simlib
elif [[ -f /home/ICer/Vivado_prj/xdma_0_ex/xdma_0_ex.cache/compile_simlib/vcs/synopsys_sim.setup ]]; then
    simlib_dir=/home/ICer/Vivado_prj/xdma_0_ex/xdma_0_ex.cache/compile_simlib/vcs
else
    echo "missing Vivado VCS simlib; set XILINX_VCS_SIMLIB or VIVADO_SIMLIB" >&2
    exit 66
fi
license_server="${VCS_LICENSE_SERVER:-27000@wx-linux}"
license_timeout="${VCS_LICENSE_TIMEOUT:-300}"
simulation_timeout="${XDMA_X1_SVT_SIM_TIMEOUT:-900}"
forensics_enable="${XDMA_X1_SVT_FORENSICS:-1}"
license_lmutil="${VCS_LICENSE_LMUTIL:-/home/questasim/linux_x86_64/lmutil}"
svt_testcase="${SVT_TESTCASE:-xdma_x1_svt_test}"

for required in "${vcs_home}/bin/vcs" "${vcs_home}/bin/vlogan" \
                "${designware_home}/bin/dw_vip_setup" \
                "${demo_dir}/imports/xilinx_dma_pcie_ep.sv" \
                "${gen_dir}/sim/xdma_x1.sv" \
                "${gen_dir}/ip_0/sim/xdma_x1_pcie3_ip.v" \
                "${gen_dir}/ip_1/sim/xdma_v4_1_14_blk_mem_64_reg_be.v" \
                "${gen_dir}/ip_2/sim/xdma_v4_1_14_blk_mem_64_noreg_be.v" \
                "${gen_root}/blk_mem_gen_1/sim/blk_mem_gen_1.v"; do
    test -s "${required}" || { echo "missing XDMA/SVT source: ${required}" >&2; exit 66; }
done
test -f "${simlib_dir}/synopsys_sim.setup" || {
    echo "missing Vivado VCS simlib setup: ${simlib_dir}/synopsys_sim.setup" >&2
    exit 66
}
test -d "${simlib_dir}/secureip" || { echo "missing secureip library" >&2; exit 66; }

export DESIGNWARE_HOME="${designware_home}"
export VCS_HOME="${vcs_home}"
export VCS_ARCH_OVERRIDE=linux
export SNPSLMD_LICENSE_FILE="${SNPSLMD_LICENSE_FILE:-${license_server}}"
if [[ ":${LM_LICENSE_FILE:-}:" != *":${license_server}:"* ]]; then
    export LM_LICENSE_FILE="${license_server}${LM_LICENSE_FILE:+:${LM_LICENSE_FILE}}"
fi

mkdir -p "${build_dir}"
if [[ "${VCS_LICENSE_PREFLIGHT:-1}" == "1" && -x "${license_lmutil}" ]]; then
    : > "${build_dir}/license_preflight.log"
    for feature in VCSCompiler_Net VCSRuntime_Net; do
        set +e
        timeout --foreground 10 "${license_lmutil}" lmstat -f "${feature}" \
            -c "${license_server}" >> "${build_dir}/license_preflight.log" 2>&1
        preflight_status=$?
        set -e
        if [[ ${preflight_status} -ne 0 ]]; then
            cat "${build_dir}/license_preflight.log" >&2
            echo "XDMA x1 SVT license preflight failed for ${license_server} feature=${feature}" >&2
            exit 69
        fi
    done
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

run_dir="$(mktemp -d "${TMPDIR:-/tmp}/xdma_x1_svt.XXXXXX")"
setup_file="${run_dir}/synopsys_sim.setup"
mkdir -p "${run_dir}/work" "${run_dir}/xil_defaultlib"
printf 'WORK > DEFAULT\nDEFAULT : %s\nxil_defaultlib : %s\nOTHERS=%s/synopsys_sim.setup\n' \
    "${run_dir}/work" "${run_dir}/xil_defaultlib" "${simlib_dir}" > "${setup_file}"
export SYNOPSYS_SIM_SETUP="${setup_file}"
log_file="${build_dir}/build.log"
: > "${log_file}"
run_logged() { "$@" 2>&1 | tee -a "${log_file}"; }

pcie_svt_latest="${designware_home}/vip/svt/pcie_svt/latest"
"${pcie_svt_latest}/bin/param2def.sh" < "${vip_v}/svc_util_parms.v" > "${run_dir}/svc_util_parms.h"
"${CC:-cc}" -c -I"${run_dir}" -I"${vcs_home}/include" \
    -I"${pcie_svt_latest}/C/include" -DVCS_VERILOG -DUSE_VPI=1 -DPLI_64_BIT \
    "${pcie_svt_latest}/C/src/msglog.c" -o "${run_dir}/msglog.o"
"${vcs_home}/bin/veriuser_to_pli_tab" -include "${vcs_home}/include" \
    "${pcie_svt_latest}/C/src/veriuser.c" > "${run_dir}/pli.tab"

mapfile -t gt_sim_files < <(find "${gen_dir}/ip_0/ip_0/sim" -maxdepth 1 -type f -name '*.v' | sort)
mapfile -t core_source_files < <(find "${gen_dir}/ip_0/source" -maxdepth 1 -type f -name '*.v' | sort)
mapfile -t xdma_hdl_files < <(find "${gen_dir}/xdma_v4_1/hdl/verilog" -maxdepth 1 -type f \( -name '*.sv' -o -name '*.v' \) | sort)
run_logged "${vcs_home}/bin/vlogan" -full64 -v2k_generate -sverilog -work xil_defaultlib \
    +incdir+"${gen_dir}/hdl/verilog" +incdir+"${gen_dir}/xdma_v4_1/hdl/verilog" \
    "${gt_sim_files[@]}" "${core_source_files[@]}" "${xdma_hdl_files[@]}" \
    "${gen_dir}/hdl/xdma_v4_1_vl_rfs.sv" \
    "${gen_dir}/sim/xdma_x1.sv" "${gen_dir}/ip_0/sim/xdma_x1_pcie3_ip.v" \
    "${gen_dir}/ip_1/sim/xdma_v4_1_14_blk_mem_64_reg_be.v" \
    "${gen_dir}/ip_2/sim/xdma_v4_1_14_blk_mem_64_noreg_be.v" \
    "${gen_root}/blk_mem_gen_1/sim/blk_mem_gen_1.v" \
    -l "${build_dir}/xdma_ep_vlogan.log"

run_logged "${vcs_home}/bin/vlogan" -full64 -v2k_generate -sverilog -work xil_defaultlib \
    +incdir+"${imports_dir}" "${imports_dir}/xdma_app.v" \
    "${imports_dir}/xilinx_dma_pcie_ep.sv" "${vivado_home}/data/verilog/src/glbl.v"

vlog_common=(
    -full64 -sverilog +v2k -lca -ntb_opts rvm +libext+.v+.sv
    -y "${vip_v}" -y "${vip_sv}"
    "+incdir+${script_dir}" "+incdir+${vip_inc}"
    "+incdir+${vip_design_dir}/include/verilog"
    "+incdir+${vip_sv}" "+incdir+${vip_v}"
    +define+PCIESVC_SVT_NAMING +define+PCIESVC_FLAT_INCLUDES
    +define+SVT_PCIE_ENABLE_GEN3 +define+EXPERTIO_PCIESVC_INCLUDE_8G
    +define+PCIESVC_MEM_PATH=test_top.global_shadow0.shadow_mem0
    +define+EXPERTIO_PCIESVC_GLOBAL_SHADOW_PATH=test_top.global_shadow0
    +define+SVT_VMM_TECHNOLOGY +define+SVT_PCIE_PKG=svt_pcie_vmm_pkg
    +define+SYNOPSYS_SV
)
run_logged "${vcs_home}/bin/vlogan" -v2k_generate "${vlog_common[@]}" -work xil_defaultlib \
    "${script_dir}/xdma_x1_svt_board.sv" \
    "${script_dir}/xdma_x1_svt_program.sv" \
    "${script_dir}/xdma_x1_svt_config.v" \
    "${shadow_file}" "${device_wrapper}" \
    -l "${build_dir}/svt_vlogan.log"

set +e
timeout --foreground "${license_timeout}" "${vcs_home}/bin/vcs" -full64 -lca \
    xil_defaultlib.test_top xil_defaultlib.glbl \
    -Lgtwizard_ultrascale_v1_7_12 -Lsecureip -Lunisims_ver -Lxpm \
    -debug_access+pp+dmptf -t ps -licqueue -LDFLAGS "-Wl,--no-as-needed" \
    -P "${run_dir}/pli.tab" "${run_dir}/msglog.o" \
    -Mdir="${run_dir}/csrc" -o "${run_dir}/xdma_x1_svt_simv" \
    -l "${build_dir}/elaborate.log"
elaborate_status=$?
set -e
if [[ ${elaborate_status} -eq 124 ]]; then
    echo "XDMA x1 SVT elaboration license timeout after ${license_timeout}s" >&2
    exit 124
elif [[ ${elaborate_status} -ne 0 ]]; then
    exit "${elaborate_status}"
fi

sim_plusargs=(+vmm_log_nowarn_at_200)
if [[ "${forensics_enable}" == "1" ]]; then
    sim_plusargs+=(+PHY_FORENSICS)
fi
set +e
timeout --foreground "${simulation_timeout}" "${run_dir}/xdma_x1_svt_simv" \
    -licqueue "+vmm_test=${svt_testcase}" "${sim_plusargs[@]}" run \
    -l "${build_dir}/simulate.log"
simulation_status=$?
set -e
if [[ ${simulation_status} -eq 124 ]]; then
    echo "XDMA x1 SVT simulation timeout after ${simulation_timeout}s" >&2
    exit 124
elif [[ ${simulation_status} -ne 0 ]]; then
    exit "${simulation_status}"
fi
grep -Fq "XDMA_SVT_GEN3_L0_PASS" "${build_dir}/simulate.log"
grep -Fq "XDMA_SVT_L0_STABLE_PASS" "${build_dir}/simulate.log"
echo "XDMA_X1_SVT_VCS_PASS run_dir=${run_dir} simlib=${simlib_dir}"
