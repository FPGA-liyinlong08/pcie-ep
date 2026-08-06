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
    +define+XILINX_SIM \
    "${PROJECT_DIR}/sim/common/m00_smoke.sv" \
    "${SCRIPT_DIR}/m00_smoke_tb.sv" \
    -l build/vlogan.log

"${VCS_HOME}/bin/vcs" -full64 \
    xil_defaultlib.m00_smoke_tb \
    -Lunisims_ver \
    -LDFLAGS "-Wl,--no-as-needed" \
    -Mdir=build/csrc \
    -o build/m00_simv \
    -l build/elaborate.log

"${SCRIPT_DIR}/build/m00_simv" -l build/simulate.log
grep -q 'M00_VCS_PASS' build/simulate.log
