#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
random_packets="${M02_COCOTB_PACKETS:-1000}"
random_seed="${M02_RANDOM_SEED:-20260806}"

combinations=(
    "rx_gen1:16:4:0"
    "rx_gen2:8:4:0"
    "rx_gen3:4:4:0.8"
    "tx_gen1:4:16:0"
    "tx_gen2:4:8:0"
    "tx_gen3:4:4:1.6"
)

for combination in "${combinations[@]}"; do
    IFS=: read -r name s_period m_period m_phase <<<"${combination}"
    make -C "${script_dir}" \
        S_PERIOD_NS="${s_period}" \
        M_PERIOD_NS="${m_period}" \
        M_PHASE_NS="${m_phase}" \
        M02_COCOTB_PACKETS="${random_packets}" \
        M02_RANDOM_SEED="${random_seed}" \
        SIM_BUILD="sim_build_${name}"

    if grep -q '<failure' "${script_dir}/results.xml"; then
        echo "错误：M02 cocotb 回归失败：${name}" >&2
        exit 1
    fi
    cp "${script_dir}/results.xml" "${script_dir}/results_${name}.xml"
done

echo "M02_VERILATOR_PASS combinations=6 packets_per_combination=${random_packets} seed=${random_seed}"

