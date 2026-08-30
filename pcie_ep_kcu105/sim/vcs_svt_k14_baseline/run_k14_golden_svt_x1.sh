#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
repo_dir="$(cd "${project_dir}/.." && pwd)"
baseline_commit=5095e7c4e8b23c356e11e1915c065f1ace88f92d
build_dir="${K14_GOLDEN_SVT_BUILD_DIR:-${project_dir}/sim/vcs_svt/build/k14_golden}"
snapshot_dir="${build_dir}/baseline_${baseline_commit}"
git_repo=(git --git-dir="${repo_dir}/.git")

actual_commit="$("${git_repo[@]}" rev-parse "${baseline_commit}")"
if [[ "${actual_commit}" != "${baseline_commit}" ]]; then
    echo "K14 Golden commit mismatch: ${actual_commit}" >&2
    exit 66
fi

if [[ ! -s "${snapshot_dir}/rtl/ep/kcu105_pcie_ep_gen1_top.sv" ]]; then
    mkdir -p "${snapshot_dir}"
    "${git_repo[@]}" archive "${baseline_commit}:pcie_ep_kcu105" -- \
        rtl sim/verilator/k09_integration | tar -x -C "${snapshot_dir}"
fi

SVT_RTL_ROOT="${snapshot_dir}" \
SVT_TB_DIR="${script_dir}" \
SVT_BOARD_FILE="${script_dir}/board_svt_k14_golden_x1.sv" \
SVT_PROGRAM_FILE="${script_dir}/pcie_svt_k14_golden_program.sv" \
SVT_CONFIG_FILE="${script_dir}/pcie_svt_k14_golden_config.v" \
K15_SVT_BUILD_DIR="${build_dir}" \
K15_SVT_SIM_TIMEOUT="${K14_GOLDEN_SVT_SIM_TIMEOUT:-900}" \
SVT_TESTCASE=k14_golden_svt_x1_test \
SVT_PASS_MARKER='K14_GOLDEN_SVT_X1_PASS epochs=2' \
SVT_FAIL_MARKER=K14_GOLDEN_SVT_X1_FAIL \
SVT_RUN_LABEL=K14_GOLDEN_SVT_X1 \
exec "${project_dir}/sim/vcs_svt/run_k15_svt_x1.sh"
