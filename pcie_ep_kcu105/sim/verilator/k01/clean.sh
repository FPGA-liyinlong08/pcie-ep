#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rm -rf \
    "${script_dir}/sim_build_negative" \
    "${script_dir}/sim_build_gen1" \
    "${script_dir}/sim_build_gen2" \
    "${script_dir}/sim_build_gen3"
rm -f "${script_dir}"/results*.xml
