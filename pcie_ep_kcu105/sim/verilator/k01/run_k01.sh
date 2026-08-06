#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
random_resets="${K01_RANDOM_RESETS:-1000}"
random_phy_resets="${K01_RANDOM_PHY_RESETS:-250}"
random_seed="${K01_RANDOM_SEED:-20260806}"

for config in "gen1:16:0" "gen2:8:0" "gen3:4:0.8"; do
    IFS=: read -r name period phase <<< "${config}"
    make -C "${script_dir}" \
        PCLK_PERIOD_NS="${period}" \
        PCLK_PHASE_NS="${phase}" \
        K01_RANDOM_RESETS="${random_resets}" \
        K01_RANDOM_PHY_RESETS="${random_phy_resets}" \
        K01_RANDOM_SEED="${random_seed}" \
        SIM_BUILD="sim_build_${name}"

    if grep -q '<failure' "${script_dir}/results.xml"; then
        echo "错误：K01 Verilator 回归失败：${name}" >&2
        exit 1
    fi
    cp "${script_dir}/results.xml" "${script_dir}/results_${name}.xml"
done

echo "K01_VERILATOR_PASS periods_ns=16,8,4 resets_per_period=${random_resets} phy_resets_per_period=${random_phy_resets} seed=${random_seed}"
