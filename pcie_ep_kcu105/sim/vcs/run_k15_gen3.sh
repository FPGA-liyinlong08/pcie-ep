#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
xdma_rp_imports="${project_dir}/../xdma_x1_demo/build/example/xdma_x1_ex/imports"
legacy_rp_imports="${project_dir}/../pcie3_ultrascale_0_ex/imports"
if [[ -f "${xdma_rp_imports}/pci_exp_usrapp_tx.v" ]]; then
    default_rp_imports="${xdma_rp_imports}"
else
    default_rp_imports="${legacy_rp_imports}"
fi
workspace_simlib="$(cd "${project_dir}/../../vcs_compile_simlib" 2>/dev/null && pwd || true)"

K15_VCS=1 \
K11B_SKIP_SELFTEST=1 \
K11B_SIM_TIMEOUT="${K15_SIM_TIMEOUT:-900}" \
K11B_RP_IMPORTS="${K11B_RP_IMPORTS:-${default_rp_imports}}" \
XILINX_VCS_SIMLIB="${XILINX_VCS_SIMLIB:-${workspace_simlib}}" \
exec "${script_dir}/run_k11b_serial.sh"
