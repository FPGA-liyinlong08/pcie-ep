#!/usr/bin/env python3
"""Decode the packed K15 Phase-2 diagnostic buses in a Vivado ILA CSV."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


STICKY_NAMES = (
    "req_accept",
    "rxeq_done_rise",
    "proposal",
    "proposal_match",
    "phase_done",
    "phase_failed",
)


def find_column(fieldnames: list[str], needle: str) -> str:
    matches = [name for name in fieldnames if needle in name]
    if len(matches) != 1:
        raise SystemExit(
            f"expected one CSV column containing {needle!r}, found {len(matches)}"
        )
    return matches[0]


def parse_hex(value: str) -> int:
    text = value.strip().lower().replace("_", "")
    if text.startswith("0x"):
        text = text[2:]
    if not text or any(ch in text for ch in "xz"):
        raise ValueError(value)
    return int(text, 16)


def bit(value: int, index: int) -> int:
    return (value >> index) & 1


def field(value: int, high: int, low: int) -> int:
    return (value >> low) & ((1 << (high - low + 1)) - 1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("csv", type=Path, help="Vivado write_hw_ila_data CSV")
    args = parser.parse_args()

    with args.csv.open(newline="", encoding="utf-8-sig") as stream:
        reader = csv.DictReader(stream)
        if reader.fieldnames is None:
            raise SystemExit("CSV has no header")
        debug_column = find_column(reader.fieldnames, "k15_phase2_debug_w")
        detail_column = find_column(reader.fieldnames, "k15_phase2_detail_w")
        rows = list(reader)

    milestones: dict[str, int] = {}
    op_states: set[int] = set()
    rxeq_ctrls: set[int] = set()
    result_values: set[int] = set()
    ts1_samples = 0
    malformed_samples = 0
    valid_rows = 0
    max_elapsed = 0
    final_sticky = 0

    for row_number, row in enumerate(rows):
        try:
            debug = parse_hex(row[debug_column])
            detail = parse_hex(row[detail_column])
        except ValueError:
            continue
        valid_rows += 1
        elapsed = field(debug, 117, 95)
        sticky = field(debug, 94, 89)
        op_state = field(debug, 88, 86)
        eq_result = field(debug, 72, 70)
        rxeq_ctrl = field(debug, 69, 68)
        internal = field(detail, 37, 24)

        max_elapsed = max(max_elapsed, elapsed)
        final_sticky = sticky
        op_states.add(op_state)
        rxeq_ctrls.add(rxeq_ctrl)
        result_values.add(eq_result)
        ts1_samples += bit(debug, 42)
        malformed_samples += bit(debug, 41)

        events = {
            "req_accept": bit(debug, 79) and bit(debug, 78),
            "rxeq_done_level": bit(debug, 63),
            "proposal": bit(debug, 73) and eq_result == 2,
            "proposal_match": bit(internal, 0)
            and bit(internal, 3)
            and bit(internal, 4),
            "phase_done": bit(debug, 81),
            "phase_failed": bit(debug, 80),
        }
        for name, active in events.items():
            if active and name not in milestones:
                milestones[name] = row_number

    sticky_set = [name for index, name in enumerate(STICKY_NAMES)
                  if final_sticky & (1 << index)]
    print(f"file={args.csv}")
    print(f"samples={len(rows)} valid_packed_samples={valid_rows}")
    print(f"phase2_elapsed_max={max_elapsed} cycles ({max_elapsed * 4 / 1000:.3f} us)")
    print(f"sticky=0x{final_sticky:02x} set={','.join(sticky_set) or 'none'}")
    print(f"operation_states={','.join(map(str, sorted(op_states)))}")
    print(f"rxeq_ctrl_values={','.join(map(str, sorted(rxeq_ctrls)))}")
    print(f"eq_result_values={','.join(map(str, sorted(result_values)))}")
    print(f"ts1_samples={ts1_samples} malformed_samples={malformed_samples}")
    for name in (
        "req_accept",
        "rxeq_done_level",
        "proposal",
        "proposal_match",
        "phase_done",
        "phase_failed",
    ):
        print(f"first_{name}_sample={milestones.get(name, 'not_seen')}")


if __name__ == "__main__":
    main()
