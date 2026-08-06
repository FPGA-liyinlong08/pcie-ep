#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
build_dir="${script_dir}/build_k06"
warning_allowlist="${script_dir}/k06_vivado_warning_allowlist.txt"
vivado_bin="${VIVADO_BIN:-/home/Xilinx/Vivado/2021.2/bin/vivado}"

export XILINX_LOCAL_USER_DATA=no
mkdir -p "${build_dir}"
cd "${project_dir}"

if [[ "${K06_REUSE_BUILD:-0}" != "1" ]]; then
    "${vivado_bin}" -mode batch -source "${script_dir}/run_k06_dll_ooc.tcl" \
        -nojournal -log "${build_dir}/vivado.log"
fi

if grep -q '^ERROR:' "${build_dir}/vivado.log"; then
    echo "错误：K06 Vivado日志存在Error" >&2
    exit 1
fi
if grep -q '^CRITICAL WARNING:' "${build_dir}/vivado.log"; then
    echo "错误：K06 Vivado日志存在Critical Warning" >&2
    exit 1
fi

grep '^WARNING:' "${build_dir}/vivado.log" \
    | sed -n 's/^WARNING: \[\([^]]*\)\].*/\1/p' \
    | sort | uniq -c \
    | awk '{$1=$1; print $2 " " $3 " " $1}' \
    > "${build_dir}/warnings_actual.txt"
if ! diff -u "${warning_allowlist}" "${build_dir}/warnings_actual.txt"; then
    echo "错误：K06 Vivado普通Warning不符合固定Allowlist" >&2
    exit 1
fi

if grep -Eq '\|[[:space:]]*(Critical Warning|Error)[[:space:]]*\|' "${build_dir}/drc.rpt"; then
    echo "错误：K06 DRC存在Critical Warning或Error" >&2
    exit 1
fi
grep -Eq '^\|[[:space:]]*CFGBVS-1[[:space:]]*\|[[:space:]]*Warning[[:space:]]*\|.*\|[[:space:]]*1[[:space:]]*\|' \
    "${build_dir}/drc.rpt"
if awk -F'|' '/^\|/ && $3 ~ /(Warning|Critical Warning|Error)/ && $2 !~ /CFGBVS-1/ {exit 1}' \
    "${build_dir}/drc.rpt"; then
    true
else
    echo "错误：K06 DRC存在Allowlist之外的违例" >&2
    exit 1
fi
if grep -Eq 'CDC-[0-9]+[[:space:]]+(Critical|Warning)' "${build_dir}/cdc.rpt"; then
    echo "错误：K06 CDC存在Warning/Critical" >&2
    exit 1
fi
grep -q '^1\. checking no_clock (0)$' "${build_dir}/check_timing.rpt"
grep -q '^4\. checking unconstrained_internal_endpoints (0)$' "${build_dir}/check_timing.rpt"
grep -q '^K06_VIVADO_PASS$' "${build_dir}/summary.txt"
cat "${build_dir}/summary.txt"
