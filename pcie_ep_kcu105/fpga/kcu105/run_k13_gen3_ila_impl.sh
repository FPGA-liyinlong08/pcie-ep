#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
# The direct GT primitive probes are part of this diagnostic variant, so use
# the corresponding Vivado variant directory rather than mixing artifacts
# with the earlier non-primitive build.
build_dir="${script_dir}/build_k13_gen3_ila_gt_primitive/impl"
vivado_bin="${VIVADO_BIN:-/home/Xilinx/Vivado/2021.2/bin/vivado}"

export XILINX_LOCAL_USER_DATA=no
mkdir -p "${build_dir}"
cd "${project_dir}"

# K13 hardware differential build: keep only the PIPE ILA so the capture is
# focused on the Recovery.Speed -> Gen3 EIEOS -> RX-ready ordering.
K13_ENABLE=1 \
K13_GT_PRIMITIVE_DEBUG=1 \
K11B2_ILA_DEBUG=1 \
K11B2_ILA_PIPE_ONLY=1 \
"${vivado_bin}" -mode batch \
  -source "${script_dir}/run_k11b2_impl.tcl" -nojournal \
  -log "${build_dir}/vivado.log"

if grep -q '^ERROR:' "${build_dir}/vivado.log"; then
  echo "错误：K13 Gen3 ILA Vivado日志存在Error" >&2
  exit 1
fi
# This is an on-board diagnostic artifact.  The direct GT primitive source
# retargeting intentionally emits Vivado file-management critical warnings;
# timing status is reported in summary.txt and the real fatal criterion here
# is an ERROR or a missing implementation marker/artifact.
grep -q '^K13_ILA_IMPL_PASS$' "${build_dir}/summary.txt"
test -s "${build_dir}/k13_gen3_endpoint_ila.bit"
test -s "${build_dir}/k11b2_gen1_endpoint_ila.ltx"
sha256sum "${build_dir}/k13_gen3_endpoint_ila.bit" \
  "${build_dir}/k11b2_gen1_endpoint_ila.ltx" \
  > "${build_dir}/sha256sums.txt"
cat "${build_dir}/summary.txt"
cat "${build_dir}/sha256sums.txt"
