#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
C_SRC_DIR="${SCRIPT_DIR}/csrc"
UCLI_KEY="${SCRIPT_DIR}/ucli.key"

if [[ -d "${BUILD_DIR}" ]]; then
    rm -rf -- "${BUILD_DIR}"
fi

if [[ -d "${C_SRC_DIR}" ]]; then
    rm -rf -- "${C_SRC_DIR}"
fi

if [[ -f "${UCLI_KEY}" ]]; then
    rm -f -- "${UCLI_KEY}"
fi
