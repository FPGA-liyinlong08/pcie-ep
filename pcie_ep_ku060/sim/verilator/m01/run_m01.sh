#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RANDOM_RESETS="${M01_RANDOM_RESETS:-1000}"
RANDOM_STATUS_EVENTS="${M01_RANDOM_STATUS_EVENTS:-100}"
RANDOM_SEED="${M01_RANDOM_SEED:-20260806}"

for pipe_period in 16 8 4; do
    make -C "${SCRIPT_DIR}" \
        PIPE_PERIOD_NS="${pipe_period}" \
        M01_RANDOM_RESETS="${RANDOM_RESETS}" \
        M01_RANDOM_STATUS_EVENTS="${RANDOM_STATUS_EVENTS}" \
        M01_RANDOM_SEED="${RANDOM_SEED}" \
        SIM_BUILD="sim_build_${pipe_period}ns"

    if grep -q '<failure' "${SCRIPT_DIR}/results.xml"; then
        echo "错误：M01 Verilator 回归失败，PIPE 周期 ${pipe_period} ns" >&2
        exit 1
    fi
done

echo "M01_VERILATOR_PASS periods_ns=16,8,4 resets_per_period=${RANDOM_RESETS} status_events_per_period=${RANDOM_STATUS_EVENTS} seed=${RANDOM_SEED}"
