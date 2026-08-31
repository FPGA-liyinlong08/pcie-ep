#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../../.." && pwd)"
build_root="${script_dir}/k15_ab_build"
mkdir -p "${build_root}"

for variant in preset_only preset_query; do
    case "${variant}" in
        preset_only) query=0 ;;
        preset_query) query=1 ;;
    esac
    build_dir="${build_root}/${variant}"
    verilator --cc --exe --build -Wall -Wno-fatal -Wno-TIMESCALEMOD \
        -Wno-PINCONNECTEMPTY \
        --top-module k15_ab_test_top \
        -GK15_AB_CDR_HOLD=0 -GK15_AB_PRERATE_TXEQ=1 \
        -GK15_AB_PRERATE_QUERY="${query}" \
        -GK15_AB_PRERATE_DWELL_CYCLES=4 \
        -GK15_AB_PRERATE_PRESET=4 \
        "${project_dir}/rtl/phy/pcie_phy_command_ctrl.sv" \
        "${script_dir}/k15_ab_test_top.sv" \
        "${script_dir}/k15_ab_test.cpp" \
        -Mdir "${build_dir}"
    "${build_dir}/Vk15_ab_test_top"
done

echo "K15_PHY_AB_MATRIX_PASS variants=2 dwell=4"
