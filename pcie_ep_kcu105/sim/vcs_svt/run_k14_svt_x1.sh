#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

K15_SVT_BUILD_DIR="${K14_SVT_BUILD_DIR:-${script_dir}/build_k14}" \
K15_SVT_SIM_TIMEOUT="${K14_SVT_SIM_TIMEOUT:-900}" \
SVT_TESTCASE=k14_svt_x1_test \
SVT_PASS_MARKER='K14_SVT_X1_PASS epochs=2' \
SVT_FAIL_MARKER=K14_SVT_X1_FAIL \
SVT_RUN_LABEL=K14_SVT_X1 \
exec "${script_dir}/run_k15_svt_x1.sh"
