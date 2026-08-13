#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
ila_debug="${K11B2_ILA_DEBUG:-0}"
build_variant="build_k11b2"
if [[ "${ila_debug}" == "1" ]]; then
  build_variant="build_k11b2_ila"
fi
if [[ "${G9_WAIT_REMOTE_DETECT:-0}" == "1" ]]; then
  if [[ "${ila_debug}" == "1" ]]; then
    build_variant="build_g9_wait_remote_detect_ila"
  else
    build_variant="build_g9_wait_remote_detect_release"
  fi
fi
if [[ "${G10_CFG_COMPLETE:-0}" == "1" ]]; then
  build_variant="build_g10_cfg_complete_ila"
fi
if [[ "${G11_RX_PARSER:-0}" == "1" ]]; then
  build_variant="build_g11_rx_parser_ila"
fi
if [[ "${G12_ORDERED_SET:-0}" == "1" ]]; then
  if [[ "${ila_debug}" == "1" ]]; then
    build_variant="build_g12_ordered_set_ila"
  else
    build_variant="build_g12_ordered_set_release"
  fi
fi
if [[ "${G8_FAST_DETECT:-0}" == "1" ]]; then
  build_variant="build_g8_fast_detect_ila"
fi
if [[ "${G7_RX_P0_QUIET:-0}" == "1" ]]; then
  build_variant="build_g7_rxp0_ila"
fi
if [[ "${G2_GEN1_ONLY:-0}" == "1" ]]; then
  build_variant="build_g2_gen1"
fi
build_dir="${script_dir}/${build_variant}/impl"
vivado_bin="${VIVADO_BIN:-/home/Xilinx/Vivado/2021.2/bin/vivado}"

export XILINX_LOCAL_USER_DATA=no
mkdir -p "${build_dir}"
cd "${project_dir}"

if [[ "${K11B2_REUSE_BUILD:-0}" != "1" ]]; then
  "${script_dir}/run_k02_ip_generation.sh"
  "${vivado_bin}" -mode batch -source "${script_dir}/run_k11b2_impl.tcl" \
    -nojournal -log "${build_dir}/vivado.log"
fi

if grep -q '^ERROR:' "${build_dir}/vivado.log"; then
  echo "错误：K11-B2 Vivado日志存在Error" >&2
  exit 1
fi
if grep -q '^CRITICAL WARNING:' "${build_dir}/vivado.log"; then
  echo "错误：K11-B2 Vivado日志存在Critical Warning" >&2
  exit 1
fi

warning_ids="$(grep '^WARNING: \[' "${build_dir}/vivado.log" \
  | sed -E 's/^WARNING: \[([^]]+)\].*/\1/' | sort -u)"
expected_warning_ids="$(printf '%s\n' \
  $([[ "${ila_debug}" == "1" ]] && printf '%s\n' \
    'DRC PDCN-1569' \
    'DRC RTSTAT-10' \
    'Route 35-328' || true) \
  'Synth 8-3848' \
  'Synth 8-3917' \
  'Synth 8-6014' \
  'Synth 8-6779' \
  'Synth 8-7023' \
  'Synth 8-7071' \
  'Synth 8-7080' \
  'Synth 8-7129' \
  $([[ "${ila_debug}" == "1" ]] && printf '%s\n' \
    'Timing 38-164' \
    'Timing 38-436' || true) \
  'Vivado 12-975')"
if [[ "${warning_ids}" != "${expected_warning_ids}" ]]; then
  echo "错误：K11-B2 Warning ID集合与固定allowlist不一致" >&2
  printf '实际：\n%s\n期望：\n%s\n' "${warning_ids}" "${expected_warning_ids}" >&2
  exit 1
fi

if grep -Eq '\|[[:space:]]*(Critical Warning|Error)[[:space:]]*\|' \
  "${build_dir}/drc.rpt"; then
  echo "错误：K11-B2 DRC报告存在Critical Warning或Error" >&2
  exit 1
fi
if grep -Eq '^CDC-[0-9]+[[:space:]]+Critical' "${build_dir}/cdc_routed.rpt"; then
  echo "错误：K11-B2 CDC报告存在Critical路径" >&2
  exit 1
fi
if [[ "${ila_debug}" != "1" ]]; then
  grep -q 'All user specified timing constraints are met.' \
    "${build_dir}/timing_summary.rpt"
  grep -q '^K11B2_IMPL_PASS$' "${build_dir}/summary.txt"
else
  grep -q '^K11B3_ILA_IMPL_PASS$' "${build_dir}/summary.txt"
fi
cat "${build_dir}/summary.txt"
