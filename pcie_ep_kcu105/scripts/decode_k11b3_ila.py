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


def find_optional_column(columns, suffix):
    matches = [index for name, index in columns.items() if suffix in name]
    if len(matches) > 1:
        raise RuntimeError(f"探针{suffix}匹配数量为{len(matches)}")
    return matches[0] if matches else None


def decode_pipe(path):
    columns, rows = read_capture(path)
    trigger_col = find_column(columns, "dbg_pipe_tlp_trigger")
    link_loss_col = find_column(columns, "dbg_pipe_link_loss_trigger")
    top_col = find_column(columns, "dbg_pipe_top[")
    dll_col = find_column(columns, "dbg_pipe_dll[")
    ltssm_col = find_column(columns, "dbg_ltssm_detail[")
    conflict_matches = [index for name, index in columns.items()
                        if "dbg_phy_rxidle_conflict" in name]
    conflict_col = conflict_matches[0] if len(conflict_matches) == 1 else None
    gt_rxresetdone_col = find_optional_column(columns, "rxresetdone_out[")
    gt_rxelecidle_col = find_optional_column(columns, "rxelecidle_out[")
    gt_rxvalid_col = find_optional_column(columns, "rxvalid_out[")
    gt_rxstatus_col = find_optional_column(columns, "rxstatus_out[")
    gt_rxdata_col = find_optional_column(columns, "rxdata_out[")
    gt_rxctrl0_col = find_optional_column(columns, "rxctrl0_out[")
    gt_gtrxreset_col = find_optional_column(columns, "gtrxreset_in[")
    gt_rxuserrdy_col = find_optional_column(columns, "rxuserrdy_in[")
    gt_rxcdrhold_col = find_optional_column(columns, "rxcdrhold_in[")
    gt_rxrate_col = find_optional_column(columns, "rxrate_in[")
    gt_rxpd_col = find_optional_column(columns, "rxpd_in[")
    gt_rxpolarity_col = find_optional_column(columns, "rxpolarity_in[")
    gt_rx8b10ben_col = find_optional_column(columns, "rx8b10ben_in[")
    decoded = []
    for row in rows:
        top = int(row[top_col], 16)
        dll = int(row[dll_col], 16)
        ltssm_detail = int(row[ltssm_col], 16)
        decoded.append({
            "sample": int(row[0]), "trigger": int(row[trigger_col], 16),
            "link_loss_trigger": int(row[link_loss_col], 16),
            "phy_rxidle_conflict": int(row[conflict_col], 16) if conflict_col is not None else 0,
            "ltssm": bits(top, 27, 6), "link_up": bits(top, 36),
            "k13_speed_state": bits(top, 61, 3),
            "k13_eq_phase": bits(top, 58, 3),
            "k13_recovery_active": bits(top, 57),
            "k13_eq_active": bits(top, 56),
            "k13_fallback": bits(top, 55),
            "k13_speed_timeout": bits(top, 54),
            "k13_ts_accept": bits(top, 53),
            "k13_ts_reject": bits(top, 52),
            "k13_cdr_loss": bits(top, 51),
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
            "ltssm_detail": ltssm_detail,
            "polling_tx_ts1_count": bits(ltssm_detail, 184, 11),
            "polling_tx_ts1_complete": bits(ltssm_detail, 183),
            "polling_tx_ts1_done": bits(ltssm_detail, 182),
            "polling_rx_ts_done": bits(ltssm_detail, 181),
            "link_disable": bits(ltssm_detail, 180),
            "hot_reset_req": bits(ltssm_detail, 179),
            "force_recovery": bits(ltssm_detail, 178),
            "os_ts1": bits(ltssm_detail, 122),
            "os_ts2": bits(ltssm_detail, 121),
            "os_malformed": bits(ltssm_detail, 120),
            "os_idle": bits(ltssm_detail, 119),
            "rxelecidle_qualified": bits(ltssm_detail, 123),
            "os_link": bits(ltssm_detail, 111, 8),
            "os_lane": bits(ltssm_detail, 102, 8),
            "os_training_control": bits(ltssm_detail, 77, 8),
            "phy_rxdata": bits(ltssm_detail, 45, 32),
            "phy_rxdatak": bits(ltssm_detail, 43, 2),
            "phy_rxvalid": bits(ltssm_detail, 42),
            "phy_rxdata_valid": bits(ltssm_detail, 41),
            "phy_rxelecidle": bits(ltssm_detail, 40),
            "phy_rxstatus": bits(ltssm_detail, 37, 3),
            "phy_phystatus": bits(ltssm_detail, 36),
            "phy_txdata": bits(ltssm_detail, 4, 32),
            "phy_txdatak": bits(ltssm_detail, 2, 2),
            "phy_txelecidle": bits(ltssm_detail, 0),
            "gt_rxresetdone": int(row[gt_rxresetdone_col], 16) if gt_rxresetdone_col is not None else None,
            "gt_rxelecidle": int(row[gt_rxelecidle_col], 16) if gt_rxelecidle_col is not None else None,
            "gt_rxvalid": int(row[gt_rxvalid_col], 16) if gt_rxvalid_col is not None else None,
            "gt_rxstatus": int(row[gt_rxstatus_col], 16) if gt_rxstatus_col is not None else None,
            "gt_rxdata": int(row[gt_rxdata_col], 16) if gt_rxdata_col is not None else None,
            "gt_rxctrl0": int(row[gt_rxctrl0_col], 16) if gt_rxctrl0_col is not None else None,
            "gt_gtrxreset": int(row[gt_gtrxreset_col], 16) if gt_gtrxreset_col is not None else None,
            "gt_rxuserrdy": int(row[gt_rxuserrdy_col], 16) if gt_rxuserrdy_col is not None else None,
            "gt_rxcdrhold": int(row[gt_rxcdrhold_col], 16) if gt_rxcdrhold_col is not None else None,
            "gt_rxrate": int(row[gt_rxrate_col], 16) if gt_rxrate_col is not None else None,
            "gt_rxpd": int(row[gt_rxpd_col], 16) if gt_rxpd_col is not None else None,
            "gt_rxpolarity": int(row[gt_rxpolarity_col], 16) if gt_rxpolarity_col is not None else None,
            "gt_rx8b10ben": int(row[gt_rx8b10ben_col], 16) if gt_rx8b10ben_col is not None else None,
        })
    return decoded


def decode_core(path):
    columns, rows = read_capture(path)
    trigger_col = find_column(columns, "dbg_core_tlp_trigger")
    link_loss_col = find_column(columns, "dbg_core_link_loss_trigger")
    stream_col = find_column(columns, "dbg_core_stream[")
    detail_col = find_column(columns, "dbg_core_detail[")
    decoded = []
    for row in rows:
        stream = int(row[stream_col], 16)
        detail = int(row[detail_col], 16)
        decoded.append({
            "sample": int(row[0]), "trigger": int(row[trigger_col], 16),
            "link_loss_trigger": int(row[link_loss_col], 16),
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
            "tx_raw_data": bits(detail, 0, 128),
            "rx_raw_data": bits(detail, 192, 128),
            "raw_keep": bits(detail, 128, 16),
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
    if len(sys.argv) not in (2, 3):
        raise SystemExit("用法：decode_k11b3_ila.py PIPE.csv [CORE.csv]")
    pipe = decode_pipe(Path(sys.argv[1]))
    core = decode_core(Path(sys.argv[2])) if len(sys.argv) == 3 else None
    pipe_trigger = [r["sample"] for r in pipe if r["trigger"]]
    pipe_loss = [r["sample"] for r in pipe if r["link_loss_trigger"]]
    pipe_conflict = [r["sample"] for r in pipe if r["phy_rxidle_conflict"]]
    print(f"PIPE samples={len(pipe)} trigger={pipe_trigger}")
    print(f"PIPE link_loss_trigger={pipe_loss}")
    print(f"PIPE phy_rxidle_conflict={pipe_conflict}")
    if pipe_loss:
        loss_sample = pipe_loss[0]
        transitions = [
            (pipe[index]["sample"], pipe[index - 1]["ltssm"], pipe[index]["ltssm"])
            for index in range(1, len(pipe))
            if pipe[index]["ltssm"] != pipe[index - 1]["ltssm"]
            and pipe[index]["sample"] <= loss_sample
        ]
        transition_sample, transition_before, transition_after = (
            transitions[-1] if transitions else (loss_sample, pipe[loss_sample]["ltssm"], pipe[loss_sample]["ltssm"])
        )
        after = pipe[min(len(pipe) - 1, loss_sample)]
        qualified = [
            row["sample"] for row in pipe[:loss_sample]
            if row["phy_rxelecidle"] and row["rxelecidle_qualified"]
        ]
        print(
            "PIPE link_loss_cause "
            f"sample={loss_sample} transition={transition_sample} "
            f"state_before=0x{transition_before:02x} state_at=0x{transition_after:02x} "
            f"rxelecidle_qualified_samples={qualified[-4:]} "
            f"hot_reset_req={after['hot_reset_req']} "
            f"force_recovery={after['force_recovery']} "
            f"ts1={after['os_ts1']} ts2={after['os_ts2']}"
        )
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
        "PIPE K13 "
        f"speed_states={sorted(set(r['k13_speed_state'] for r in pipe))} "
        f"eq_phases={sorted(set(r['k13_eq_phase'] for r in pipe))} "
        f"recovery_samples={count(pipe, lambda r: r['k13_recovery_active'])} "
        f"eq_active_samples={count(pipe, lambda r: r['k13_eq_active'])} "
        f"ts_accept={count(pipe, lambda r: r['k13_ts_accept'])} "
        f"ts_reject={count(pipe, lambda r: r['k13_ts_reject'])} "
        f"fallback={max(r['k13_fallback'] for r in pipe)} "
        f"speed_timeout={max(r['k13_speed_timeout'] for r in pipe)} "
        f"cdr_loss={max(r['k13_cdr_loss'] for r in pipe)}"
    )
    print(
        "PIPE events "
        f"mac_rx_tlp_sop={count(pipe, lambda r: r['mac_rx_valid'] and r['mac_rx_sop'] and not r['mac_rx_dllp'])} "
        f"dll_rx_sop={count(pipe, lambda r: r['dll_rx_valid'] and r['dll_rx_ready'] and r['dll_rx_sop'])} "
        f"dll_tx_sop={count(pipe, lambda r: r['dll_tx_valid'] and r['dll_tx_ready'] and r['dll_tx_sop'])} "
        f"mac_tx_tlp_sop={count(pipe, lambda r: r['mac_tx_valid'] and r['mac_tx_ready'] and r['mac_tx_sop'] and not r['mac_tx_dllp'])}"
    )
    print(
        "PIPE PHY RX "
        f"valid_samples={count(pipe, lambda r: r['phy_rxvalid'])} "
        f"data_valid_samples={count(pipe, lambda r: r['phy_rxdata_valid'])} "
        f"nonidle_samples={count(pipe, lambda r: not r['phy_rxelecidle'])} "
        f"nonzero_data_samples={count(pipe, lambda r: r['phy_rxdata'] != 0)}"
    )
    print(
        "PIPE PHY TX "
        f"active_samples={count(pipe, lambda r: not r['phy_txelecidle'])} "
        f"nonzero_data_samples={count(pipe, lambda r: r['phy_txdata'] != 0)} "
        f"datak_samples={count(pipe, lambda r: r['phy_txdatak'] != 0)}"
    )
    if pipe[0]["gt_rxresetdone"] is not None:
        optional_counts = []
        if pipe[0]["gt_rxdata"] is not None:
            optional_counts.append(
                f"nonzero_data_samples={count(pipe, lambda r: r['gt_rxdata'] != 0)}"
            )
        if pipe[0]["gt_rxctrl0"] is not None:
            optional_counts.append(
                f"nonzero_ctrl0_samples={count(pipe, lambda r: r['gt_rxctrl0'] != 0)}"
            )
        print(
            "PIPE GT RX "
            f"resetdone_samples={count(pipe, lambda r: r['gt_rxresetdone'])} "
            f"valid_samples={count(pipe, lambda r: r['gt_rxvalid'])} "
            f"nonidle_samples={count(pipe, lambda r: not r['gt_rxelecidle'])} "
            f"nonzero_status_samples={count(pipe, lambda r: r['gt_rxstatus'] != 0)}"
            f"{' ' if optional_counts else ''}{' '.join(optional_counts)}"
        )
    if pipe[0]["gt_rxcdrhold"] is not None:
        gtrxreset = (
            f"gtrxreset_high={count(pipe, lambda r: r['gt_gtrxreset'])} "
            if pipe[0]["gt_gtrxreset"] is not None else ""
        )
        rxuserrdy = (
            f"rxuserrdy_high={count(pipe, lambda r: r['gt_rxuserrdy'])} "
            if pipe[0]["gt_rxuserrdy"] is not None else ""
        )
        print(
            "PIPE GT RX control "
            f"{gtrxreset}{rxuserrdy}"
            f"rxcdrhold_high={count(pipe, lambda r: r['gt_rxcdrhold'])} "
            f"rxrate_values={sorted(set(r['gt_rxrate'] for r in pipe))} "
            f"rxpd_values={sorted(set(r['gt_rxpd'] for r in pipe))} "
            f"rxpolarity_values={sorted(set(r['gt_rxpolarity'] for r in pipe))} "
            f"rx8b10ben_values={sorted(set(r['gt_rx8b10ben'] for r in pipe))}"
        )
    print(
        "PIPE errors "
        f"lcrc={pipe[-1]['lcrc_count']} sequence={pipe[-1]['sequence_count']} "
        f"duplicate={pipe[-1]['duplicate_count']} buffer={pipe[-1]['buffer_count']} "
        f"fc={pipe[-1]['fc_error_nonzero']} bad_dllp_crc={pipe[-1]['bad_dllp_crc']} "
        f"malformed_dllp={pipe[-1]['malformed_dllp']}"
    )
    if core is None:
        return
    core_trigger = [r["sample"] for r in core if r["trigger"]]
    core_loss = [r["sample"] for r in core if r["link_loss_trigger"]]
    print(f"CORE samples={len(core)} trigger={core_trigger}")
    print(f"CORE link_loss_trigger={core_loss}")
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
            f"error=0x{row['detail_error']:x} "
            f"rx=0x{row['rx_raw_data']:032x} tx=0x{row['tx_raw_data']:032x}"
        )
    for row in rsps[:16]:
        print(
            f"CFG_RSP sample={row['sample']} status={row['cfg_rsp_status']}"
        )


if __name__ == "__main__":
    main()
