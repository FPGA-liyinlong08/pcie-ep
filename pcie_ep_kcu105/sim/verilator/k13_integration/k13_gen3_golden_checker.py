"""Independent checks for the first Gen3 training blocks.

This module intentionally knows nothing about the DUT internals.  It checks
the PIPE observation tuple (data, start_block, sync_header) captured at the
Endpoint boundary, so a TX/RX pair cannot pass by sharing the same mistake.
"""


def check_training_prefix(words):
    """Validate EIEOS followed directly by a TS1 training block.

    The current Gen3 transmitter emits four EIEOS blocks before TS1.  The
    checker also rejects the old SDS placeholder and requires the TS1 marker
    in the first byte of the next block.
    """
    if len(words) < 5:
        raise AssertionError(f"Gen3 prefix too short: {len(words)}")

    eieos = words[:4]
    if [word[0] for word in eieos] != [0xFF00FF00] * 4:
        raise AssertionError(f"invalid EIEOS data: {[word[0] for word in eieos]}")
    if [word[1] for word in eieos] != [1, 0, 0, 0]:
        raise AssertionError(f"invalid EIEOS start markers: {[word[1] for word in eieos]}")
    if eieos[0][2] != 0b01:
        raise AssertionError(f"invalid EIEOS sync header: {eieos[0][2]:02b}")

    first_ts = words[4]
    if first_ts[1:] != (1, 0b01):
        raise AssertionError(f"invalid TS1 block boundary/header: {first_ts[1:]}")
    if first_ts[0] & 0xFF != 0x1E:
        raise AssertionError(f"invalid TS1 marker: 0x{first_ts[0] & 0xFF:02x}")
    if any(word[0] == 0xAAAAAAAA for word in words):
        raise AssertionError("SDS placeholder observed before TS1")


def assert_training_prefix(words):
    """Pytest/cocotb-friendly wrapper returning the original capture."""
    check_training_prefix(words)
    return words
