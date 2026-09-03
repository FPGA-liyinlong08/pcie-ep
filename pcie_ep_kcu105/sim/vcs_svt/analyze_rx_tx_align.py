#!/usr/bin/env python3
"""Align the K15 EP TX stream (K15_SVT_EP_TX_PIPE, MAC-side post-scrambler)
against the VIP RX stream (K15_SVT_RP_PIPE_RX, pre-descrambler) and report
every divergence event, classified as tx_skip (bytes the MAC sent but the
wire lost) or rx_ins (bytes the wire carries that the MAC never sent).

Both probes carry the same logical stream, so any mismatch is a GT TX
data-path corruption (e.g. TX elastic-buffer overrun at 100% duty, or
gap-beat residue).  See docs/reports/k15-svt-debug-log-20260903.md section 8.

Usage: analyze_rx_tx_align.py <simulate.log> [--tx-end <records>]
"""
import re
import sys


def parse(path):
    tx, rx = [], []
    for line in open(path, errors='ignore'):
        if 'K15_SVT_EP_TX_PIPE' in line:
            t = int(re.search(r't_ps=(\d+)', line).group(1))
            d = int(re.search(r'data=([0-9a-f]{8})', line).group(1), 16)
            if re.search(r'valid=(\d)', line).group(1) == '1':
                tx.append((t, bytes([d & 0xff, (d >> 8) & 0xff,
                                     (d >> 16) & 0xff, (d >> 24) & 0xff])))
        elif 'K15_SVT_RP_PIPE_RX' in line:
            t = int(re.search(r't_ps=(\d+)', line).group(1))
            d = int(re.search(r'data=([0-9a-f]{8})', line).group(1), 16)
            if re.search(r'data_valid=(\d)', line).group(1) == '1':
                rx.append(d & 0xff)
    return tx, rx


def main():
    log = sys.argv[1]
    tx, rx = parse(log)
    TX = b''.join(b for _, b in tx)
    print('tx_records=%d tx_bytes=%d rx_bytes=%d' % (len(tx), len(TX), len(rx)))
    if not TX or not rx:
        print('no data to align')
        return
    # The first RX byte may fall in a TX capture hole (gap beat or probe
    # warm-up), so anchor on the first RX byte that also occurs in TX.
    k = None
    for j, b0 in enumerate(rx[:32]):
        anchors = [i for i in range(len(TX) - 4) if TX[i] == b0]
        if anchors:
            k = anchors[0]
            i = j
            print('anchor: rx[%d] -> tx byte %d' % (j, k))
            break
    if k is None:
        print('FATAL: no RX anchor byte found in TX stream')
        return
    events = []
    while i < len(rx) and k < len(TX):
        if rx[i] == TX[k]:
            i += 1
            k += 1
            continue
        found = None
        for back in range(1, 9):
            if TX[k + back:k + back + 4] == bytes(rx[i:i + 4]):
                found = ('tx_skip', back)
                break
        if not found:
            for ins in range(1, 5):
                if TX[k:k + 2] == bytes(rx[i + ins:i + ins + 2]):
                    found = ('rx_ins', ins)
                    break
        if found:
            events.append((i, k, found,
                           bytes(rx[max(0, i - 2):i + 6]).hex(),
                           TX[max(0, k - 2):k + 10].hex()))
            if found[0] == 'tx_skip':
                k += found[1]
            else:
                i += found[1]
            continue
        events.append((i, k, ('mismatch', 0),
                       bytes(rx[i:i + 6]).hex(), TX[k:k + 8].hex()))
        i += 1
        k += 1
    print('divergence events: %d' % len(events))
    for e in events[:20]:
        print(e)


if __name__ == '__main__':
    main()
