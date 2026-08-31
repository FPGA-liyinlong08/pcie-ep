#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../../.." && pwd)"
vivado="${VIVADO:-/home/Xilinx/Vivado/2021.2/bin/vivado}"

cd "${project_dir}"
"${vivado}" -mode batch -nojournal -nolog \
    -source fpga/kcu105/xdma_x1_demo/create_xdma_x1_demo.tcl \
    -log fpga/kcu105/xdma_x1_demo/create.log
"${vivado}" -mode batch -nojournal -nolog \
    -source fpga/kcu105/xdma_x1_demo/build_xdma_x1_demo.tcl \
    -log fpga/kcu105/xdma_x1_demo/build.log

grep -q '^XDMA_X1_IMPL_PASS$' fpga/kcu105/xdma_x1_demo/build/summary.txt
grep -q '^width=X1$' fpga/kcu105/xdma_x1_demo/build/summary.txt
grep -q '^speed=8.0_GT/s$' fpga/kcu105/xdma_x1_demo/build/summary.txt
grep -q '^quad=GTH_Quad_225$' fpga/kcu105/xdma_x1_demo/build/summary.txt
test -s fpga/kcu105/xdma_x1_demo/build/xdma_x1_demo.bit
echo "XDMA_X1_DEMO_PASS"
