#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for build_name in sim_build sim_build_negative sim_build_16 sim_build_16ns sim_build_8ns sim_build_4ns; do
    build_dir="${SCRIPT_DIR}/${build_name}"
    if [[ -d "${build_dir}" ]]; then
        rm -rf -- "${build_dir}"
    fi
done

if [[ -f "${SCRIPT_DIR}/results.xml" ]]; then
    rm -f -- "${SCRIPT_DIR}/results.xml"
fi

