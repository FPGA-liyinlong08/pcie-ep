#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
vcs_home="${VCS_HOME:-/home/synopsys/vcs-mx/O-2018.09-SP2}"
afifo_rtl="${AFIFO_RTL:-/home/wx/Documents/AXI/prj_wb2axip_master/wb2axip-master/rtl/afifo.v}"

export VCS_HOME="${vcs_home}"
export VCS_ARCH_OVERRIDE=linux

cd "${script_dir}"
./check_env.sh
"${project_dir}/sim/common/check_afifo_dependency.sh"

mkdir -p build/work build/xil_defaultlib

"${vcs_home}/bin/vlogan" -full64 -sverilog -work xil_defaultlib \
    "${afifo_rtl}" \
    "${project_dir}/rtl/common/pcie_reset_sync.sv" \
    "${project_dir}/rtl/common/pcie_gray_sync.sv" \
    "${project_dir}/rtl/common/pcie_async_pkt_fifo.sv" \
    "${script_dir}/m02_async_pkt_fifo_tb.sv" \
    -l build/m02_vlogan.log

"${vcs_home}/bin/vcs" -full64 \
    xil_defaultlib.m02_async_pkt_fifo_tb \
    -LDFLAGS "-Wl,--no-as-needed" \
    -Mdir=build/csrc_m02 \
    -o build/m02_simv \
    -l build/m02_elaborate.log

"${script_dir}/build/m02_simv" -l build/m02_simulate.log
grep -q 'M02_VCS_PASS' build/m02_simulate.log

