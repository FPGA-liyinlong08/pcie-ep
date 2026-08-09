#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rm -rf "${script_dir}/sim_build" "${script_dir}/sim_build_negative"
rm -f "${script_dir}"/results*.xml "${script_dir}"/k10_*_marker.txt \
    "${script_dir}"/k10_random_evidence.txt
