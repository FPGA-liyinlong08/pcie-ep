#!/usr/bin/env bash
# Step-2 probe 1 (2026-09-03): sweep the L0 gap-grid phase against the SVT
# VIP with the 64/65 duty-cycle gap ENABLED.  For each phase the run is a
# PASS if the log contains the pass marker; FAIL otherwise (link_timeout is
# the expected failure).  Logs are archived per phase under build/.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

out_dir=build/phase_sweep
mkdir -p "${out_dir}"
: > "${out_dir}/sweep_summary.txt"

for phase in 0 1 2 3 4 5 6 7; do
    echo "=== phase ${phase} start $(date +%H:%M:%S) ==="
    if K15_SVT_L0_GAP_OFF=0 K15_L0_GAP_PHASE=${phase} ./run_k15_svt_x1.sh \
        > "${out_dir}/phase_${phase}.console" 2>&1; then
        verdict=PASS
    else
        verdict=FAIL
    fi
    cp build/simulate.log "${out_dir}/phase_${phase}.log"
    reason=$(grep -m1 'K15_SVT_X1_FAIL' "${out_dir}/phase_${phase}.log" || true)
    vip_fail=$(grep -c 'register_fail' "${out_dir}/phase_${phase}.log" || true)
    echo "phase=${phase} verdict=${verdict} reason='${reason}' register_fails=${vip_fail}" \
        >> "${out_dir}/sweep_summary.txt"
    echo "=== phase ${phase} ${verdict} $(date +%H:%M:%S) ==="
done

echo "SWEEP DONE"
cat "${out_dir}/sweep_summary.txt"
