#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

make -C "${script_dir}" SIM_BUILD=sim_build
cp "${script_dir}/results.xml" "${script_dir}/results_behavioral.xml"

if grep -q '<failure' "${script_dir}/results.xml"; then
    echo "错误：K02 Verilator 行为回归失败" >&2
    exit 1
fi

echo "K02_VERILATOR_PASS random_vectors=${K02_RANDOM_VECTORS:-10000} seed=${K02_RANDOM_SEED:-20260806}"
