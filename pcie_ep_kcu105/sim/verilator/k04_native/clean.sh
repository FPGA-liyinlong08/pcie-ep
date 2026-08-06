#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rm -rf "${script_dir}/build"
rm -f "${script_dir}/summary.txt"
