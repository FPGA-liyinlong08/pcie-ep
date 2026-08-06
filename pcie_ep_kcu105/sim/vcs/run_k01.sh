#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
vcs_home="${VCS_HOME:-/home/synopsys/vcs-mx/O-2018.09-SP2}"
vivado_home="${VIVADO_HOME:-/home/Xilinx/Vivado/2021.2}"

export VCS_HOME="${vcs_home}"
export VCS_ARCH_OVERRIDE=linux

cd "${script_dir}"
./check_env.sh

mkdir -p build/work build/xil_defaultlib

"${vcs_home}/bin/vlogan" -full64 -sverilog -work xil_defaultlib \
    "${project_dir}/rtl/common/pcie_reset_sync.sv" \
    "${project_dir}/rtl/phy/kcu105_reset_ctrl.sv" \
    "${project_dir}/rtl/phy/kcu105_refclk_reset.sv" \
    "${vivado_home}/data/verilog/src/glbl.v" \
    "${script_dir}/k01_refclk_reset_tb.sv" \
    -l build/k01_vlogan.log

"${vcs_home}/bin/vcs" -full64 \
    xil_defaultlib.k01_refclk_reset_tb xil_defaultlib.glbl \
    -Lunisims_ver \
    -LDFLAGS "-Wl,--no-as-needed" \
    -Mdir=build/csrc_k01 \
    -o build/k01_simv \
    -l build/k01_elaborate.log

"${script_dir}/build/k01_simv" -l build/k01_simulate.log
grep -q 'K01_VCS_PASS' build/k01_simulate.log
