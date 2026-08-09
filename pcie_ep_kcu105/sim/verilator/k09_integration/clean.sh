#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
make -C "${SCRIPT_DIR}" clean
rm -f "${SCRIPT_DIR}"/results_k09_integration.xml
