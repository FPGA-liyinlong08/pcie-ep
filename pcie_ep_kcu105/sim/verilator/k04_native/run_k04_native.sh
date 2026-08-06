#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../../.." && pwd)"
build_dir="${script_dir}/build"
base_packets="${K04_NATIVE_BASE_PACKETS:-500000}"
seed="${K04_RANDOM_SEED:-20260806}"

export CCACHE_DISABLE=1
mkdir -p "${build_dir}"

verilator --cc --exe --build -j 0 -Wall -Wno-fatal -Wno-TIMESCALEMOD \
    --top-module k04_crc_test_top \
    --Mdir "${build_dir}" \
    -CFLAGS "-O3" \
    "${project_dir}/rtl/dll/pcie_crc_stream.sv" \
    "${project_dir}/rtl/dll/pcie_crc16_dllp.sv" \
    "${project_dir}/rtl/dll/pcie_crc32_lcrc.sv" \
    "${project_dir}/sim/verilator/k04/k04_crc_test_top.sv" \
    "${script_dir}/k04_crc_native.cpp"

K04_NATIVE_BASE_PACKETS="${base_packets}" K04_RANDOM_SEED="${seed}" \
    "${build_dir}/Vk04_crc_test_top" | tee "${script_dir}/summary.txt"

grep -q "K04_NATIVE_PASS algorithm_vectors=$((base_packets * 2))" \
    "${script_dir}/summary.txt"
