#!/usr/bin/env python3
"""解析K11-B3两级ILA CSV，并输出配置枚举数据路径摘要。"""

import csv
import sys
from pathlib import Path


def bits(value, lsb, width=1):
    return (value >> lsb) & ((1 << width) - 1)


def read_capture(path):
    with path.open(newline="") as handle:
        reader = csv.reader(handle)
        header = next(reader)
        next(reader)  # radix line
        rows = [row for row in reader if row]
    probe_columns = {name: index for index, name in enumerate(header)}
    return probe_columns, rows


def find_column(columns, suffix):
    matches = [index for name, index in columns.items() if suffix in name]
    if len(matches) != 1:
        raise RuntimeError(f"探针{suffix}匹配数量为{len(matches)}")
    return matches[0]


def decode_pipe(path):
    columns, rows = read_capture(path)
    trigger_col = find_column(columns, "dbg_pipe_tlp_trigger")
    top_col = find_column(columns, "dbg_pipe_top[")
    dll_col = find_column(columns, "dbg_pipe_dll[")
    decoded = []
    for row in rows:
        top = int(row[top_col], 16)
        dll = int(row[dll_col], 16)
        decoded.append({
            "sample": int(row[0]), "trigger": int(row[trigger_col], 16),
            "ltssm": bits(top, 27, 6), "link_up": bits(top, 36),
            "dll_active": bits(top, 35), "fc_state": bits(top, 33, 2),
            "mac_rx_valid": bits(top, 16), "mac_rx_sop": bits(top, 15),
            "mac_rx_eop": bits(top, 14), "mac_rx_dllp": bits(top, 13),
            "mac_rx_error": bits(top, 9, 4),
            "mac_tx_valid": bits(top, 8), "mac_tx_ready": bits(top, 7),
            "mac_tx_sop": bits(top, 6), "mac_tx_eop": bits(top, 5),
            "mac_tx_dllp": bits(top, 4), "mac_tx_bad": bits(top, 3),
            "training_error": bits(top, 19), "timeout_error": bits(top, 18),
            "frame_error": bits(top, 17),
            "dll_rx_valid": bits(dll, 17), "dll_rx_ready": bits(dll, 16),
            "dll_rx_sop": bits(dll, 15), "dll_rx_eop": bits(dll, 14),
            "dll_rx_error": bits(dll, 10, 4),
            "dll_tx_valid": bits(dll, 9), "dll_tx_ready": bits(dll, 8),
            "dll_tx_sop": bits(dll, 7), "dll_tx_eop": bits(dll, 6),
            "next_tx_seq": bits(dll, 61, 12), "next_rx_seq": bits(dll, 49, 12),
            "last_acked_seq": bits(dll, 37, 12),
            "replay_occupancy": bits(dll, 32, 5),
            "ack_count": bits(dll, 77, 4), "nak_count": bits(dll, 73, 4),
            "dll_rx_count": bits(dll, 101, 4), "dll_tx_count": bits(dll, 97, 4),
            "lcrc_count": bits(dll, 93, 4), "sequence_count": bits(dll, 89, 4),
            "duplicate_count": bits(dll, 85, 4), "buffer_count": bits(dll, 81, 4),
            "lcrc_nonzero": bits(dll, 109), "sequence_nonzero": bits(dll, 108),
            "fc_error_nonzero": bits(dll, 110), "bad_dllp_crc": bits(dll, 111),
            "malformed_dllp": bits(dll, 112),
        })
    return decoded


def decode_core(path):
    columns, rows = read_capture(path)
    trigger_col = find_column(columns, "dbg_core_tlp_trigger")
    stream_col = find_column(columns, "dbg_core_stream[")
    detail_col = find_column(columns, "dbg_core_detail[")
    decoded = []
    for row in rows:
        stream = int(row[stream_col], 16)
        detail = int(row[detail_col], 16)
        decoded.append({
            "sample": int(row[0]), "trigger": int(row[trigger_col], 16),
            "rx_valid": bits(stream, 113), "rx_ready": bits(stream, 112),
            "rx_sop": bits(stream, 111), "rx_eop": bits(stream, 110),
            "rx_error": bits(stream, 106, 4),
            "tx_valid": bits(stream, 105), "tx_ready": bits(stream, 104),
            "tx_sop": bits(stream, 103), "tx_eop": bits(stream, 102),
            "tx_error": bits(stream, 98, 4), "tx_type": bits(stream, 96, 2),
            "captured_bdf": bits(stream, 78, 16), "bdf_valid": bits(stream, 77),
            "mse": bits(stream, 56), "cfg_count": bits(stream, 48, 8),
            "mem_count": bits(stream, 40, 8), "cpl_count": bits(stream, 32, 8),
            "ur_count": bits(stream, 24, 8), "malformed_count": bits(stream, 16, 8),
            "unsupported_count": bits(stream, 8, 8), "cdc_errors": bits(stream, 0, 8),
            "raw_data": bits(detail, 0, 128), "raw_keep": bits(detail, 128, 16),
            "detail_error": bits(detail, 144, 4),
            "detail_eop": bits(detail, 148), "detail_sop": bits(detail, 149),
            "detail_ready": bits(detail, 150), "detail_valid": bits(detail, 151),
            "cfg_req_write": bits(detail, 152), "cfg_req_ready": bits(detail, 153),
            "cfg_req_valid": bits(detail, 154),
            "cfg_rsp_status": bits(detail, 155, 3), "cfg_rsp_ready": bits(detail, 158),
            "cfg_rsp_valid": bits(detail, 159),
            "detail_cfg_count": bits(detail, 160, 8),
            "detail_unsupported": bits(detail, 168, 8),
            "detail_malformed": bits(detail, 176, 8),
        })
    return decoded


def count(rows, predicate):
    return sum(1 for row in rows if predicate(row))


def main():
    if len(sys.argv) != 3:
        raise SystemExit("用法：decode_k11b3_ila.py PIPE.csv CORE.csv")
    pipe = decode_pipe(Path(sys.argv[1]))
    core = decode_core(Path(sys.argv[2]))
    pipe_trigger = [r["sample"] for r in pipe if r["trigger"]]
    core_trigger = [r["sample"] for r in core if r["trigger"]]
    print(f"PIPE samples={len(pipe)} trigger={pipe_trigger}")
    print(
        "PIPE final "
        f"ltssm=0x{pipe[-1]['ltssm']:02x} link={pipe[-1]['link_up']} "
        f"dll_active={pipe[-1]['dll_active']} fc={pipe[-1]['fc_state']} "
        f"rx_tlp={pipe[-1]['dll_rx_count']} tx_tlp={pipe[-1]['dll_tx_count']} "
        f"next_rx_seq={pipe[-1]['next_rx_seq']} next_tx_seq={pipe[-1]['next_tx_seq']} "
        f"last_acked=0x{pipe[-1]['last_acked_seq']:03x} "
        f"replay_occ={pipe[-1]['replay_occupancy']} ack_tx={pipe[-1]['ack_count']} "
        f"nak_tx={pipe[-1]['nak_count']}"
    )
    print(
        "PIPE events "
        f"mac_rx_tlp_sop={count(pipe, lambda r: r['mac_rx_valid'] and r['mac_rx_sop'] and not r['mac_rx_dllp'])} "
        f"dll_rx_sop={count(pipe, lambda r: r['dll_rx_valid'] and r['dll_rx_ready'] and r['dll_rx_sop'])} "
        f"dll_tx_sop={count(pipe, lambda r: r['dll_tx_valid'] and r['dll_tx_ready'] and r['dll_tx_sop'])} "
        f"mac_tx_tlp_sop={count(pipe, lambda r: r['mac_tx_valid'] and r['mac_tx_ready'] and r['mac_tx_sop'] and not r['mac_tx_dllp'])}"
    )
    print(
        "PIPE errors "
        f"lcrc={pipe[-1]['lcrc_count']} sequence={pipe[-1]['sequence_count']} "
        f"duplicate={pipe[-1]['duplicate_count']} buffer={pipe[-1]['buffer_count']} "
        f"fc={pipe[-1]['fc_error_nonzero']} bad_dllp_crc={pipe[-1]['bad_dllp_crc']} "
        f"malformed_dllp={pipe[-1]['malformed_dllp']}"
    )
    print(f"CORE samples={len(core)} trigger={core_trigger}")
    print(
        "CORE final "
        f"cfg_count={core[-1]['cfg_count']} cpl_count={core[-1]['cpl_count']} "
        f"malformed={core[-1]['malformed_count']} unsupported={core[-1]['unsupported_count']} "
        f"cdc_errors=0x{core[-1]['cdc_errors']:02x} bdf_valid={core[-1]['bdf_valid']} "
        f"bdf={core[-1]['captured_bdf']:04x}"
    )
    reqs = [r for r in core if r["cfg_req_valid"] and r["cfg_req_ready"]]
    rsps = [r for r in core if r["cfg_rsp_valid"] and r["cfg_rsp_ready"]]
    print(f"CORE cfg_req_handshakes={len(reqs)} cfg_rsp_handshakes={len(rsps)}")
    print(
        "CORE stream "
        f"rx_sop={count(core, lambda r: r['rx_valid'] and r['rx_ready'] and r['rx_sop'])} "
        f"tx_sop={count(core, lambda r: r['tx_valid'] and r['tx_ready'] and r['tx_sop'])} "
        f"tx_eop={count(core, lambda r: r['tx_valid'] and r['tx_ready'] and r['tx_eop'])}"
    )
    raw_beats = [r for r in core if r["detail_valid"] and r["detail_ready"]]
    for row in raw_beats[:16]:
        print(
            f"DETAIL_BEAT sample={row['sample']} sop={row['detail_sop']} "
            f"eop={row['detail_eop']} keep=0x{row['raw_keep']:04x} "
            f"error=0x{row['detail_error']:x} data=0x{row['raw_data']:032x}"
        )
    for row in rsps[:16]:
        print(
            f"CFG_RSP sample={row['sample']} status={row['cfg_rsp_status']}"
        )


if __name__ == "__main__":
    main()
