#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VCS_HOME="${VCS_HOME:-/home/synopsys/vcs-mx/O-2018.09-SP2}"

export VCS_HOME
export VCS_ARCH_OVERRIDE=linux

cd "${SCRIPT_DIR}"
./check_env.sh

mkdir -p build/work build/xil_defaultlib

"${VCS_HOME}/bin/vlogan" -full64 -sverilog -work xil_defaultlib \
    "${PROJECT_DIR}/rtl/common/pcie_reset_sync.sv" \
    "${PROJECT_DIR}/rtl/common/pcie_bit_sync.sv" \
    "${PROJECT_DIR}/rtl/common/pcie_clk_reset_ctrl.sv" \
    "${PROJECT_DIR}/rtl/phy/pcie_clk_reset.sv" \
    "/home/Xilinx/Vivado/2021.2/data/verilog/src/glbl.v" \
    "${SCRIPT_DIR}/m01_clk_reset_tb.sv" \
    -l build/m01_vlogan.log

"${VCS_HOME}/bin/vcs" -full64 \
    xil_defaultlib.m01_clk_reset_tb xil_defaultlib.glbl \
    -Lunisims_ver \
    -LDFLAGS "-Wl,--no-as-needed" \
    -Mdir=build/csrc_m01 \
    -o build/m01_simv \
    -l build/m01_elaborate.log

"${SCRIPT_DIR}/build/m01_simv" -l build/m01_simulate.log
grep -q 'M01_VCS_PASS' build/m01_simulate.log

