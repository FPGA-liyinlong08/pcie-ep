#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../../.." && pwd)"
build_dir="${script_dir}/build"
event_count="${K05_NATIVE_EVENTS:-1000000}"
seed="${K05_RANDOM_SEED:-20260806}"

export CCACHE_DISABLE=1
mkdir -p "${build_dir}"

verilator --cc --exe --build -j 0 -Wall -Wno-fatal -Wno-TIMESCALEMOD \
    --top-module k05_fc_manager_native_top \
    --Mdir "${build_dir}" -CFLAGS "-O3" \
    "${project_dir}/rtl/dll/pcie_fc_local_credit_pool.sv" \
    "${project_dir}/rtl/dll/pcie_dllp_fc_manager.sv" \
    "${script_dir}/k05_fc_manager_native_top.sv" \
    "${script_dir}/k05_fc_native.cpp"

K05_NATIVE_EVENTS="${event_count}" K05_RANDOM_SEED="${seed}" \
    "${build_dir}/Vk05_fc_manager_native_top" | tee "${script_dir}/summary.txt"
grep -q "K05_NATIVE_PASS events=${event_count}" "${script_dir}/summary.txt"
