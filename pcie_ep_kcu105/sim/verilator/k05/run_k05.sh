#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
random_seed="${K05_RANDOM_SEED:-20260806}"
random_events="${K05_RANDOM_EVENTS:-10000}"

cd "${script_dir}"
rm -f results.xml
K05_RANDOM_SEED="${random_seed}" K05_RANDOM_EVENTS="${random_events}" \
    make SIM_BUILD=sim_build
cp results.xml results_behavioral.xml
if grep -q '<failure' results.xml; then
    echo "错误：K05 cocotb 回归存在失败用例" >&2
    exit 1
fi
echo "K05_VERILATOR_PASS events=${random_events} seed=${random_seed}"
