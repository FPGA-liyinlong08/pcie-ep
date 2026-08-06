#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
build_dir="${script_dir}/build_k04"
vivado_bin="${VIVADO_BIN:-/home/Xilinx/Vivado/2021.2/bin/vivado}"

export XILINX_LOCAL_USER_DATA=no
mkdir -p "${build_dir}"
cd "${project_dir}"

if [[ "${K04_REUSE_BUILD:-0}" != "1" ]]; then
    "${vivado_bin}" -mode batch -source "${script_dir}/run_k04_crc_ooc.tcl" \
        -nojournal -log "${build_dir}/vivado.log"
fi

if grep -q '^ERROR:' "${build_dir}/vivado.log"; then
    echo "错误：K04 Vivado 日志存在 Error" >&2
    exit 1
fi
if grep -q '^CRITICAL WARNING:' "${build_dir}/vivado.log"; then
    echo "错误：K04 Vivado 日志存在 Critical Warning" >&2
    exit 1
fi
if grep -Eq '\|[[:space:]]*(Critical Warning|Error)[[:space:]]*\|' "${build_dir}/drc.rpt"; then
    echo "错误：K04 DRC 存在 Critical Warning 或 Error" >&2
    exit 1
fi

actual_drc_warning_ids="$(awk -F'|' '$3 ~ /Warning/ {gsub(/[[:space:]]/, "", $2); print $2}' \
    "${build_dir}/drc.rpt" | sort -u)"
if [[ "${actual_drc_warning_ids}" != "CFGBVS-1" ]]; then
    echo "错误：K04 DRC Warning ID 集合与固定 allowlist 不一致：${actual_drc_warning_ids}" >&2
    exit 1
fi
if ! grep -Eq '^\| CFGBVS-1 +\| Warning +\|.*\| 1 +\|$' "${build_dir}/drc.rpt"; then
    echo "错误：K04 CFGBVS-1 数量不是固定值 1" >&2
    exit 1
fi
if grep -Eq 'CDC-[0-9]+[[:space:]]+(Critical|Warning)' "${build_dir}/cdc.rpt"; then
    echo "错误：K04 CDC 存在 Warning/Critical" >&2
    exit 1
fi
cdc9_count="$(awk '$1 == "CDC-9" && $2 == "Info" {print $3}' "${build_dir}/cdc.rpt")"
if [[ "${cdc9_count}" != "1" ]]; then
    echo "错误：K04 CDC-9 组数为 ${cdc9_count:-0}，期望 1" >&2
    exit 1
fi

actual_warning_ids="$({ grep -oE 'WARNING: \[[^]]+\]' "${build_dir}/vivado.log" || true; } \
    | sed -E 's/^WARNING: \[([^]]+)\]$/\1/' | sort -u)"
expected_warning_ids=$'Synth 8-7080\nTiming 38-242'
if [[ "${actual_warning_ids}" != "${expected_warning_ids}" ]]; then
    echo "错误：K04 Vivado Warning ID 集合与固定 allowlist 不一致" >&2
    printf '实际：\n%s\n期望：\n%s\n' "${actual_warning_ids}" "${expected_warning_ids}" >&2
    exit 1
fi

grep -q '^1\. checking no_clock (0)$' "${build_dir}/check_timing.rpt"
grep -q '^4\. checking unconstrained_internal_endpoints (0)$' "${build_dir}/check_timing.rpt"
grep -q '^K04_VIVADO_PASS$' "${build_dir}/summary.txt"
cat "${build_dir}/summary.txt"
