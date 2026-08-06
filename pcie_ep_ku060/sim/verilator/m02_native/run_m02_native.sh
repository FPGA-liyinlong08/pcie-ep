#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../../.." && pwd)"
afifo_rtl="${AFIFO_RTL:-/home/wx/Documents/AXI/prj_wb2axip_master/wb2axip-master/rtl/afifo.v}"
build_dir="${script_dir}/build"
packets="${M02_SIGNOFF_PACKETS:-1000000}"
seed="${M02_RANDOM_SEED:-20260806}"

export CCACHE_DISABLE=1

mkdir -p "${build_dir}"

verilator --cc --exe --build -O3 -Wall -Wno-fatal -Wno-TIMESCALEMOD \
    --top-module pcie_async_pkt_fifo \
    -GLGFIFO=9 \
    --timescale 1ns/1ps \
    --Mdir "${build_dir}" \
    "${afifo_rtl}" \
    "${project_dir}/rtl/common/pcie_reset_sync.sv" \
    "${project_dir}/rtl/common/pcie_gray_sync.sv" \
    "${project_dir}/rtl/common/pcie_async_pkt_fifo.sv" \
    "${script_dir}/m02_stress.cpp"

combinations=(
    "rx_gen1:80:20:0"
    "rx_gen2:40:20:0"
    "rx_gen3:20:20:4"
    "tx_gen1:20:80:0"
    "tx_gen2:20:40:0"
    "tx_gen3:20:20:8"
)

: >"${build_dir}/summary.txt"
for combination in "${combinations[@]}"; do
    IFS=: read -r name s_period m_period m_phase <<<"${combination}"
    "${build_dir}/Vpcie_async_pkt_fifo" \
        --name "${name}" \
        --packets "${packets}" \
        --seed "${seed}" \
        --s-period "${s_period}" \
        --m-period "${m_period}" \
        --m-phase "${m_phase}" | tee -a "${build_dir}/summary.txt"
done

pass_count="$(grep -c '^M02_NATIVE_PASS' "${build_dir}/summary.txt")"
if [[ "${pass_count}" != 6 ]]; then
    echo "错误：M02 Native 百万 Packet 回归仅 ${pass_count}/6 通过" >&2
    exit 1
fi

echo "M02_NATIVE_ALL_PASS combinations=6 packets_per_combination=${packets} seed=${seed}"
