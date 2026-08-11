#!/usr/bin/env bash
set -euo pipefail
make -C "$(dirname "${BASH_SOURCE[0]}")" results.xml
grep -q 'failures="0"' "$(dirname "${BASH_SOURCE[0]}")/results.xml"
echo "K11B3_TRIGGER_VERILATOR_PASS"
