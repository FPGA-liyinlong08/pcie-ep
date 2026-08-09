#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rm -rf "${script_dir}/sim_build"
rm -f "${script_dir}/results_k10_integration.xml"
