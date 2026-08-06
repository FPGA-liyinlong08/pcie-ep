#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
build_dir="${script_dir}/build_k02"
vivado_bin="${VIVADO_BIN:-/home/Xilinx/Vivado/2021.2/bin/vivado}"

export XILINX_LOCAL_USER_DATA=no
mkdir -p "${build_dir}"
cd "${project_dir}"

"${script_dir}/run_k02_ip_generation.sh"

"${vivado_bin}" -mode batch \
    -source "${script_dir}/run_k02_impl.tcl" \
    -nojournal \
    -log "${build_dir}/impl.log"

if grep -q '^ERROR:' "${build_dir}/impl.log"; then
    echo "错误：K02 Vivado 实现日志存在 Error" >&2
    exit 1
fi
if grep -q '^CRITICAL WARNING:' "${build_dir}/impl.log"; then
    echo "错误：K02 Vivado 实现日志存在 Critical Warning" >&2
    exit 1
fi


# Xilinx pcie_phy/GT Wizard 生成 RTL 在未启用调试、外部 PLL 和保留接口时会
# 产生下列固定综合 Warning。只允许精确集合；新增或减少都要求人工复核。
actual_warning_ids="$(grep '^WARNING: \[' "${build_dir}/impl.log" \
    | sed -E 's/^WARNING: \[([^]]+)\].*/\1/' \
    | sort -u)"
expected_warning_ids="$(printf '%s\n' \
    'Synth 8-3848' \
    'Synth 8-6014' \
    'Synth 8-7023' \
    'Synth 8-7071' \
    'Synth 8-7080' \
    'Synth 8-7129')"
if [[ "${actual_warning_ids}" != "${expected_warning_ids}" ]]; then
    echo "错误：K02 Vivado Warning ID 集合与固定 allowlist 不一致" >&2
    echo "实际：" >&2
    printf '%s\n' "${actual_warning_ids}" >&2
    echo "期望：" >&2
    printf '%s\n' "${expected_warning_ids}" >&2
    exit 1
fi

if grep -Eq '\|[[:space:]]*(Critical Warning|Error)[[:space:]]*\|' "${build_dir}/drc.rpt"; then
    echo "错误：K02 report_drc 存在 Critical Warning 或 Error" >&2
    exit 1
fi
if grep -Eq 'CDC-[0-9]+[[:space:]]+Critical' "${build_dir}/cdc_routed.rpt"; then
    echo "错误：K02 report_cdc 存在 Critical CDC" >&2
    exit 1
fi

grep -q '^K02_IMPL_PASS$' "${build_dir}/impl_summary.txt"
cat "${build_dir}/impl_summary.txt"
