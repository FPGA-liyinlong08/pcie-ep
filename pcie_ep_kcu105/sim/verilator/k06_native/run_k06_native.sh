#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../../.." && pwd)"
build_dir="${script_dir}/build"

export CCACHE_DISABLE=1
mkdir -p "${build_dir}"
verilator --cc --exe --build -Wall -Wno-fatal -Wno-TIMESCALEMOD \
    --top-module k06_dll_replay_native_top \
    --Mdir "${build_dir}" \
    "${project_dir}/rtl/common/pcie_reset_sync.sv" \
    "${project_dir}/rtl/dll/pcie_crc_stream.sv" \
    "${project_dir}/rtl/dll/pcie_crc32_lcrc.sv" \
    "${project_dir}/rtl/dll/pcie_dll_replay.sv" \
    "${script_dir}/k06_dll_replay_native_top.sv" \
    "${script_dir}/k06_dll_replay_native.cpp"

"${build_dir}/Vk06_dll_replay_native_top" | tee "${script_dir}/summary.txt"
grep -q '^K06_NATIVE_PASS ' "${script_dir}/summary.txt"
