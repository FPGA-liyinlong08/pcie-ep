#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
build_dir="${script_dir}/build_k11_gen1_release/impl"
vivado_bin="${VIVADO_BIN:-/home/Xilinx/Vivado/2021.2/bin/vivado}"
bit_path="${build_dir}/k11b2_gen1_endpoint.bit"

export XILINX_LOCAL_USER_DATA=no
mkdir -p "${build_dir}"
cd "${project_dir}"
if [[ "${K11B2_REUSE_BUILD:-0}" != "1" ]]; then
  "${script_dir}/run_k02_ip_generation.sh"
  "${vivado_bin}" -mode batch -source "${script_dir}/run_k11_gen1_release.tcl" \
    -nojournal -log "${build_dir}/vivado.log"
fi

grep -q '^K11_GEN1_COMMAND_BOUNDARY_IMPL_PASS$' "${build_dir}/summary.txt"
grep -q 'All user specified timing constraints are met\.' \
  "${build_dir}/timing_summary.rpt"
if grep -q '^ERROR:' "${build_dir}/vivado.log"; then
  echo "错误：Gen1 release Vivado日志存在Error" >&2
  exit 1
fi
# Route 35-39 may be emitted before the post-route physical optimization
# closes timing.  All other critical warnings remain fatal.
if grep '^CRITICAL WARNING:' "${build_dir}/vivado.log" \
    | grep -Ev '\[Route 35-39\]' | grep -q .; then
  echo "错误：Gen1 release Vivado日志存在未允许的Critical Warning" >&2
  exit 1
fi
sha256sum "${bit_path}" | tee "${build_dir}/bitstream.sha256"
{
  printf 'G9_WAIT_REMOTE_DETECT=1\n'
  printf 'G9_WAIT_REMOTE_DETECT_CYCLES=%s\n' \
    "${G9_WAIT_REMOTE_DETECT_CYCLES:-6250000}"
  printf 'ILA_DEBUG=0\n'
  printf 'GEN3_RATE_CHANGE=0\n'
  printf 'EQ_ENABLE=0\n'
} > "${build_dir}/build_parameters.txt"
cat "${build_dir}/summary.txt"
