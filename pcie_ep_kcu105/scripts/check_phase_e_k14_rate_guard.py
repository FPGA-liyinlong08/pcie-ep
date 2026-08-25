#!/usr/bin/env python3
import hashlib
import pathlib
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
FROZEN = {
    "rtl/phy/pcie_phy_command_ctrl.sv":
        "f16097555901f94c1ec04880d8c27c14cfecf874a8445c13b2fc879d4ed40c42",
    "rtl/phy/pcie_recovery_speed_ctrl.sv":
        "105ca877c0dafd4d380c93b1dd10323837938efb98d3469a14125f60c4e11b84",
}


def main():
    errors = []
    for relative, expected in FROZEN.items():
        actual = hashlib.sha256((ROOT / relative).read_bytes()).hexdigest()
        if actual != expected:
            errors.append(f"{relative}: expected={expected} actual={actual}")
    production_top = (ROOT / "rtl/ep/kcu105_pcie_ep_gen1_top.sv").read_text()
    if ".peer_speed_reject(gen3_rcvrlock_failed)" not in production_top:
        errors.append("E2 failure is not connected to semantic peer reject")
    if "? gen3_rcvrlock_complete" not in production_top:
        errors.append("Gen3 peer success bypasses E2 RcvrLock completion")
    if "assign speed_recovery_done = rate_op_success;" not in production_top:
        errors.append("K14 rate-success to LTSSM completion boundary changed")
    if errors:
        print("PHASE_E_K14_RATE_GUARD_FAIL", *errors, sep="\n",
              file=sys.stderr)
        return 1
    print("PHASE_E_K14_RATE_GUARD_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
