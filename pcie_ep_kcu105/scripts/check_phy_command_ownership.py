#!/usr/bin/env python3
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOP = ROOT / "rtl/ep/kcu105_pcie_ep_gen1_top.sv"
BOARD = ROOT / "rtl/ep/kcu105_pcie_ep_gen1_board_top.sv"
LTSSM = ROOT / "rtl/phy/pcie_ltssm_mac_gen1.sv"
NEGATIVE = ROOT / "sim/fixtures/phy_command_extra_driver.sv"

RAW = (
    "phy_powerdown", "phy_txdetectrx", "phy_txelecidle", "phy_rate",
    "phy_txeq_ctrl", "phy_txeq_preset", "phy_txeq_coeff",
    "phy_rxeq_ctrl", "phy_rxeq_txpreset", "as_mac_in_detect",
    "as_cdr_hold_req", "phy_txcompliance", "phy_rxpolarity",
    "phy_txmargin", "phy_txswing", "phy_txdeemph",
)


def violations(top_text: str, board_text: str, ltssm_text: str):
    errors = []
    instances = len(re.findall(r"\bpcie_phy_command_ctrl\s+u_[A-Za-z0-9_]+\s*\(", top_text))
    if instances != 1:
        errors.append(f"production controller instance count={instances}, expected=1")
    if re.search(r"\b[Kk]13[_A-Za-z0-9]*\b", top_text + "\n" + board_text):
        errors.append("production top contains a K13 identifier")
    for name in RAW:
        if re.search(rf"\bassign\s+{re.escape(name)}\b", top_text):
            errors.append(f"raw command has top-level assign driver: {name}")
        if re.search(rf"\b{name}\s*=\s*[^;]*\?", top_text):
            errors.append(f"raw command has top-level mux driver: {name}")
    header = ltssm_text.split(");", 1)[0]
    for name in RAW:
        if re.search(rf"\b{name}\b", header):
            errors.append(f"LTSSM exposes raw command port: {name}")
    if "phy_phystatus" in header:
        errors.append("LTSSM consumes raw PhyStatus completion")
    if "phy_rxstatus" in header:
        errors.append("LTSSM consumes raw Receiver Detect result")
    for required in ("phy_cmd_profile", "phy_cmd_valid", "phy_cmd_ready",
                     "phy_cmd_done", "phy_cmd_result"):
        if required not in header:
            errors.append(f"LTSSM semantic port missing: {required}")
    return errors


def main():
    top = TOP.read_text()
    board = BOARD.read_text()
    ltssm = LTSSM.read_text()
    errors = violations(top, board, ltssm)
    if errors:
        print("PHY_COMMAND_OWNERSHIP_FAIL", *errors, sep="\n", file=sys.stderr)
        return 1
    negative_errors = violations(top + "\n" + NEGATIVE.read_text(), board, ltssm)
    if not any("assign driver: phy_rate" in item for item in negative_errors):
        print("negative fixture was not rejected", file=sys.stderr)
        return 1
    print("PHY_COMMAND_OWNERSHIP_NEGATIVE_FIXTURE_PASS")
    print("PHY_COMMAND_OWNERSHIP_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
