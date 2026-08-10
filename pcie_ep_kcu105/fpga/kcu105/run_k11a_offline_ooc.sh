#!/usr/bin/env bash
set -euo pipefail
root_dir="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root_dir"
vivado_bin="${VIVADO_BIN:-/home/Xilinx/Vivado/2021.2/bin/vivado}"
mkdir -p fpga/kcu105/build_k11a
"$vivado_bin" -mode batch -source fpga/kcu105/run_k11a_offline_ooc.tcl \
  -nojournal -log fpga/kcu105/build_k11a/vivado.log
grep -q 'K11A_VIVADO_PASS' fpga/kcu105/build_k11a/vivado.log
echo K11A_VIVADO_PASS
