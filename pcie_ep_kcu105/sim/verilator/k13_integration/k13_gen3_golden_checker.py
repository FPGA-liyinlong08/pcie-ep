"""Independent checks for the first Gen3 training blocks.

This module intentionally knows nothing about the DUT internals.  It checks
the PIPE observation tuple (data, start_block, sync_header) captured at the
Endpoint boundary, so a TX/RX pair cannot pass by sharing the same mistake.
"""


def check_training_prefix(words):
    """Validate the Gen3 EIEOS, SDS, then TS1 startup sequence.

    Each ordered set occupies four 32-bit PIPE transfers.  SDS is required to
    establish 128b/130b block alignment before the first scrambled TS1.
    """
    if len(words) < 9:
        raise AssertionError(f"Gen3 prefix too short: {len(words)}")

    eieos = words[:4]
    if [word[0] for word in eieos] != [0xFF00FF00] * 4:
        raise AssertionError(f"invalid EIEOS data: {[word[0] for word in eieos]}")
    if [word[1] for word in eieos] != [1, 0, 0, 0]:
        raise AssertionError(f"invalid EIEOS start markers: {[word[1] for word in eieos]}")
    if eieos[0][2] != 0b01:
        raise AssertionError(f"invalid EIEOS sync header: {eieos[0][2]:02b}")

    sds = words[4:8]
    if [word[0] for word in sds] != [
            0xAAAAAAAA, 0xAAAAAAAA, 0xAAAAAAAA, 0xBCBF9DE1]:
        raise AssertionError(f"invalid SDS data: {[word[0] for word in sds]}")
    if [word[1] for word in sds] != [1, 0, 0, 0]:
        raise AssertionError(f"invalid SDS start markers: {[word[1] for word in sds]}")
    if sds[0][2] != 0b01:
        raise AssertionError(f"invalid SDS sync header: {sds[0][2]:02b}")

    first_ts = words[8]
    if first_ts[1:] != (1, 0b01):
        raise AssertionError(f"invalid TS1 block boundary/header: {first_ts[1:]}")
    if first_ts[0] & 0xFF != 0x1E:
        raise AssertionError(f"invalid TS1 marker: 0x{first_ts[0] & 0xFF:02x}")


def assert_training_prefix(words):
    """Pytest/cocotb-friendly wrapper returning the original capture."""
    check_training_prefix(words)
    return words
