#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
build_dir="${script_dir}/build_k11b2_ila/impl"
vivado_bin="${VIVADO_BIN:-/home/Xilinx/Vivado/2021.2/bin/vivado}"

export XILINX_LOCAL_USER_DATA=no
mkdir -p "${build_dir}"
cd "${project_dir}"

if [[ "${K11B2_REUSE_IP:-0}" != "1" ]]; then
  "${script_dir}/run_k02_ip_generation.sh"
fi
K11B2_ILA_DEBUG=1 "${vivado_bin}" -mode batch \
  -source "${script_dir}/run_k11b2_impl.tcl" -nojournal \
  -log "${build_dir}/vivado.log"

if grep -q '^ERROR:' "${build_dir}/vivado.log"; then
  echo "错误：K11-B3 ILA Vivado日志存在Error" >&2
  exit 1
fi
if grep -q '^CRITICAL WARNING:' "${build_dir}/vivado.log"; then
  echo "错误：K11-B3 ILA Vivado日志存在Critical Warning" >&2
  exit 1
fi
if grep -Eq '\|[[:space:]]*(Critical Warning|Error)[[:space:]]*\|' \
  "${build_dir}/drc.rpt"; then
  echo "错误：K11-B3 ILA DRC存在Critical Warning或Error" >&2
  exit 1
fi
grep -q '^K11B3_ILA_IMPL_PASS$' "${build_dir}/summary.txt"
grep -q '^TIMING_POLICY=DIAGNOSTIC_ONLY_NEGATIVE_ALLOWED$' \
  "${build_dir}/summary.txt"
test -s "${build_dir}/k11b2_gen1_endpoint_ila.bit"
test -s "${build_dir}/k11b2_gen1_endpoint_ila.ltx"
cat "${build_dir}/summary.txt"
