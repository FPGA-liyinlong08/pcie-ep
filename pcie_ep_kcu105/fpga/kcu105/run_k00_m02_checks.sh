#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
build_dir="${script_dir}/build_k00_m02"
vivado_bin="${VIVADO_BIN:-/home/Xilinx/Vivado/2021.2/bin/vivado}"

# 批处理不依赖用户 Tcl Store，避免构建结果受 ~/.Xilinx 权限和内容影响。
export XILINX_LOCAL_USER_DATA=no

"${project_dir}/sim/common/check_afifo_dependency.sh"
mkdir -p "${build_dir}"
cd "${project_dir}"

"${vivado_bin}" -mode batch \
    -source "${script_dir}/run_k00_m02_checks.tcl" \
    -nojournal \
    -log "${build_dir}/vivado.log"

if grep -q '^CRITICAL WARNING:' "${build_dir}/vivado.log"; then
    echo "错误：K00 M02 Vivado 日志存在 Critical Warning" >&2
    exit 1
fi

if grep -Eq 'CDC-[0-9]+[[:space:]]+Critical' "${build_dir}/cdc.rpt"; then
    echo "错误：K00 M02 report_cdc 存在 Critical CDC" >&2
    exit 1
fi

if grep -Eq '\|[[:space:]]*(Critical Warning|Error)[[:space:]]*\|' "${build_dir}/drc.rpt"; then
    echo "错误：K00 M02 report_drc 存在 Critical Warning 或 Error" >&2
    exit 1
fi

# K00 的 Warning 必须与冻结 Allowlist 完全一致；新增类型立即失败。
actual_log_warning_ids="$({
    grep -oE 'WARNING: \[[^]]+\]' "${build_dir}/vivado.log" || true
} | sed -E 's/^WARNING: \[([^]]+)\]$/\1/' | sort -u)"
expected_log_warning_ids=$'Synth 8-7080\nTiming 38-242'
if [[ "${actual_log_warning_ids}" != "${expected_log_warning_ids}" ]]; then
    echo "错误：K00 M02 Vivado Warning 类型不在固定 Allowlist" >&2
    echo "实际：" >&2
    printf '%s\n' "${actual_log_warning_ids}" >&2
    exit 1
fi

actual_cdc_warning_ids="$(awk '$2 == "Warning" {print $1}' "${build_dir}/cdc.rpt" | sort -u)"
if [[ "${actual_cdc_warning_ids}" != "CDC-6" ]]; then
    echo "错误：K00 M02 CDC Warning 类型不在固定 Allowlist：${actual_cdc_warning_ids}" >&2
    exit 1
fi
cdc6_count="$(awk '$1 == "CDC-6" && $2 == "Warning" {print $3}' "${build_dir}/cdc.rpt")"
if [[ "${cdc6_count}" != "6" ]]; then
    echo "错误：K00 M02 CDC-6 路径组数量为 ${cdc6_count}，期望 6" >&2
    exit 1
fi

actual_drc_warning_ids="$(awk -F'|' '$3 ~ /Warning/ {gsub(/[[:space:]]/, "", $2); print $2}' \
    "${build_dir}/drc.rpt" | sort -u)"
if [[ "${actual_drc_warning_ids}" != "CFGBVS-1" ]]; then
    echo "错误：K00 M02 DRC Warning 类型不在固定 Allowlist：${actual_drc_warning_ids}" >&2
    exit 1
fi
if ! grep -Eq '^\| CFGBVS-1 +\| Warning +\|.*\| 1 +\|$' "${build_dir}/drc.rpt"; then
    echo "错误：K00 M02 CFGBVS-1 数量不是固定值 1" >&2
    exit 1
fi

grep -q '^K00_M02_VIVADO_PASS$' "${build_dir}/summary.txt"
cat "${build_dir}/summary.txt"
