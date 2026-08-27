#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export K14_DIRECT_VCS=1
export K02_SKIP_IP_GENERATION=1
exec "${script_dir}/run_k02.sh"
