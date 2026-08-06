#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rm -rf "${script_dir}/sim_build" "${script_dir}/sim_build_negative" \
       "${script_dir}/sim_build_arb" "${script_dir}/sim_build_smoke"
rm -f "${script_dir}/results.xml" "${script_dir}/results_negative.xml" \
      "${script_dir}/results_core.xml" "${script_dir}/results_arbiter.xml"
