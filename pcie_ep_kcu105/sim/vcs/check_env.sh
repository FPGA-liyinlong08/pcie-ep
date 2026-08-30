#!/usr/bin/env bash
set -euo pipefail

VCS_HOME="${VCS_HOME:-/home/synopsys/vcs-mx/O-2018.09-SP2}"
if [[ -n "${XILINX_VCS_SIMLIB:-}" ]]; then
    SIMLIB_DIR="${XILINX_VCS_SIMLIB}"
elif [[ -n "${VIVADO_SIMLIB:-}" ]]; then
    SIMLIB_DIR="${VIVADO_SIMLIB}"
elif [[ -f /home/ICer/Vivado_prj/xdma_0_ex/xdma_0_ex.cache/compile_simlib/vcs/synopsys_sim.setup ]]; then
    SIMLIB_DIR=/home/ICer/Vivado_prj/xdma_0_ex/xdma_0_ex.cache/compile_simlib/vcs
else
    echo "错误：找不到 Vivado VCS simlib；请设置 XILINX_VCS_SIMLIB 或 VIVADO_SIMLIB" >&2
    exit 66
fi

export VCS_HOME
export VCS_ARCH_OVERRIDE=linux

test -x "${VCS_HOME}/bin/vcs"
test -x "${VCS_HOME}/bin/vlogan"
test -f "${SIMLIB_DIR}/synopsys_sim.setup"
test -d "${SIMLIB_DIR}/unisims_ver"
test -d "${SIMLIB_DIR}/secureip"

VCS_ID="$(${VCS_HOME}/bin/vcs -full64 -ID 2>&1)"
printf '%s\n' "${VCS_ID}"
printf '%s\n' "${VCS_ID}" | grep -q 'machine type = linux64'
printf '%s\n' "${VCS_ID}" | grep -q 'VCS-MX O-2018.09-SP2_Full64'

printf '%s\n' "M00_VCS_ENV_PASS simlib=${SIMLIB_DIR}"

