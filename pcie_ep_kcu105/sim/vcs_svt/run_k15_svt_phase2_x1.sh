#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

K15_SVT_PHASE2_ONLY=1 \
K15_SVT_BUILD_DIR="${K15_SVT_PHASE2_BUILD_DIR:-${script_dir}/build_phase2}" \
K15_SVT_SIM_TIMEOUT="${K15_SVT_PHASE2_SIM_TIMEOUT:-900}" \
SVT_PROCESS_EPOCHS=1 \
SVT_TESTCASE=k15_svt_x1_test \
SVT_PASS_MARKER=K15_SVT_PHASE2_PASS \
SVT_FAIL_MARKER=K15_SVT_PHASE2_FAIL \
SVT_RUN_LABEL=K15_SVT_PHASE2 \
exec "${script_dir}/run_k15_svt_x1.sh"
