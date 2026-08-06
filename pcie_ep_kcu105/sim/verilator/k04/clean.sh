#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${script_dir}"
rm -rf sim_build sim_build_negative
rm -f results.xml results_behavioral.xml results_negative.xml
