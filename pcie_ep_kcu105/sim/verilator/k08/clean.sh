#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rm -rf "${script_dir}/sim_build" "${script_dir}/sim_build_negative"
rm -rf "${script_dir}/sim_build_unit" "${script_dir}/sim_build_integration"
rm -rf "${script_dir}/sim_build_tlp_bad" "${script_dir}/__pycache__"
rm -f "${script_dir}/results.xml" "${script_dir}/results_negative.xml"
rm -f "${script_dir}/results_integration.xml" "${script_dir}/results_tlp_bad.xml"
rm -f "${script_dir}/results_guard.xml" "${script_dir}/results_reset_image.xml"
rm -f "${script_dir}/results_directed.xml" "${script_dir}/results_link_reset.xml"
rm -f "${script_dir}/results_random_short.xml" "${script_dir}/results_bits_short.xml"
rm -f "${script_dir}/negative_checker_observed.txt"
rm -f "${script_dir}"/*.fst "${script_dir}"/*.vcd
