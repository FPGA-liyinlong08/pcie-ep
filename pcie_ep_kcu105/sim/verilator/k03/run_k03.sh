#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

make -C "${script_dir}" SIM_BUILD=sim_build
cp "${script_dir}/results.xml" "${script_dir}/results_behavioral.xml"

if grep -q '<failure' "${script_dir}/results.xml"; then
    echo "错误：K03 Verilator/cocotb 回归失败" >&2
    exit 1
fi

echo "K03_VERILATOR_PASS trainings=${K03_RANDOM_TRAININGS:-100} packets=${K03_RANDOM_PACKETS:-2000} seed=${K03_RANDOM_SEED:-20260806}"
