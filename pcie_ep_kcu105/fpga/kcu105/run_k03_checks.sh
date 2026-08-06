#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
build_dir="${script_dir}/build_k03"
vivado_bin="${VIVADO_BIN:-/home/Xilinx/Vivado/2021.2/bin/vivado}"

export XILINX_LOCAL_USER_DATA=no
mkdir -p "${build_dir}/ooc" "${build_dir}/impl"
cd "${project_dir}"

if [[ "${K03_REUSE_BUILD:-0}" != "1" ]]; then
    "${vivado_bin}" -mode batch -source "${script_dir}/run_k03_ooc.tcl" \
        -nojournal -log "${build_dir}/ooc/vivado.log"

    "${script_dir}/run_k02_ip_generation.sh"
    "${vivado_bin}" -mode batch -source "${script_dir}/run_k03_impl.tcl" \
        -nojournal -log "${build_dir}/impl/vivado.log"
fi

for log_file in "${build_dir}/ooc/vivado.log" "${build_dir}/impl/vivado.log"; do
    if grep -q '^ERROR:' "${log_file}"; then
        echo "错误：K03 Vivado 日志存在 Error：${log_file}" >&2
        exit 1
    fi
    if grep -q '^CRITICAL WARNING:' "${log_file}"; then
        echo "错误：K03 Vivado 日志存在 Critical Warning：${log_file}" >&2
        exit 1
    fi
done

ooc_warning_ids="$(grep '^WARNING: \[' "${build_dir}/ooc/vivado.log" \
    | sed -E 's/^WARNING: \[([^]]+)\].*/\1/' | sort -u)"
expected_ooc_warning_ids="$(printf '%s\n' \
    'Synth 8-3917' \
    'Synth 8-7080' \
    'Synth 8-7129' \
    'Timing 38-242')"
if [[ "${ooc_warning_ids}" != "${expected_ooc_warning_ids}" ]]; then
    echo "错误：K03 OOC Warning ID 集合与固定 allowlist 不一致" >&2
    printf '实际：\n%s\n期望：\n%s\n' "${ooc_warning_ids}" "${expected_ooc_warning_ids}" >&2
    exit 1
fi

impl_warning_ids="$(grep '^WARNING: \[' "${build_dir}/impl/vivado.log" \
    | sed -E 's/^WARNING: \[([^]]+)\].*/\1/' | sort -u)"
expected_impl_warning_ids="$(printf '%s\n' \
    'Synth 8-3332' \
    'Synth 8-3848' \
    'Synth 8-6014' \
    'Synth 8-7023' \
    'Synth 8-7071' \
    'Synth 8-7080' \
    'Synth 8-7129')"
if [[ "${impl_warning_ids}" != "${expected_impl_warning_ids}" ]]; then
    echo "错误：K03 集成 Warning ID 集合与固定 allowlist 不一致" >&2
    printf '实际：\n%s\n期望：\n%s\n' "${impl_warning_ids}" "${expected_impl_warning_ids}" >&2
    exit 1
fi

for report in "${build_dir}/ooc/drc.rpt" "${build_dir}/impl/drc.rpt"; do
    if grep -Eq '\|[[:space:]]*(Critical Warning|Error)[[:space:]]*\|' "${report}"; then
        echo "错误：K03 DRC 报告失败：${report}" >&2
        exit 1
    fi
done

# OOC 顶层看不到 K01 的复位同步器，因此会把输入端口 pipe_rst_n 的异步置位
# 报告为 CDC-7。只允许这一来源；完整集成报告不允许任何 Critical。
if grep -E '^CDC-[0-9]+[[:space:]]+Critical' "${build_dir}/ooc/cdc.rpt" \
    | grep -qv '^CDC-7'; then
    echo "错误：K03 OOC CDC 出现非 CDC-7 Critical" >&2
    exit 1
fi
if ! awk '$2 ~ /^CDC-/ && $3 == "Critical" && $0 !~ /pipe_rst_n/ {bad=1} END {exit bad}' \
    "${build_dir}/ooc/cdc.rpt"; then
    echo "错误：K03 OOC CDC-7 存在非 pipe_rst_n 来源" >&2
    exit 1
fi
if grep -Eq 'CDC-[0-9]+[[:space:]]+Critical' "${build_dir}/impl/cdc_routed.rpt"; then
    echo "错误：K03 集成 CDC 报告存在 Critical" >&2
    exit 1
fi

grep -q '^K03_OOC_PASS$' "${build_dir}/ooc/summary.txt"
grep -q '^K03_IMPL_PASS$' "${build_dir}/impl/summary.txt"
cat "${build_dir}/ooc/summary.txt"
cat "${build_dir}/impl/summary.txt"
