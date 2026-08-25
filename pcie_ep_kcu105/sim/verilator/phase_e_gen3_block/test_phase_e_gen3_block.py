import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


LANE0_SEED = 0x1DBFBC
EIEOS_WORDS = [0xFF00FF00] * 4
SH_ORDERED_SET = 0b01
OS_TS1 = 0x1E
OS_TS2 = 0x2D
D_TS1 = 0x4A
D_TS2 = 0x45


async def tick(dut):
    await RisingEdge(dut.clk)
    await ReadOnly()
    await Timer(1, units="ps")


async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
    dut.rst_n.value = 0
    dut.rx_enable.value = 0
    dut.rx_in_valid.value = 0
    dut.rx_start_block.value = 0
    dut.rx_sync_header.value = 0
    dut.rx_data.value = 0
    dut.tx_enable.value = 0
    dut.tx_mode.value = 0
    dut.tx_link_number.value = 0
    dut.tx_link_is_pad.value = 0
    dut.tx_lane_number.value = 0
    dut.tx_lane_is_pad.value = 0
    dut.tx_n_fts.value = 0xFF
    dut.tx_rate_id.value = 0x0E
    dut.tx_training_control.value = 0
    dut.tx_eq_control.value = 0
    dut.tx_eq_data.value = 0
    for _ in range(4):
        await tick(dut)
    dut.rst_n.value = 1
    await tick(dut)


def scramble_word(state, data, bypass_byte=0):
    """Independent bit-serial model of the frozen Gen3 lane scrambler."""
    result = data
    for bit_index in range(32):
        feedback = (state >> 22) & 1
        if not ((bypass_byte >> (bit_index // 8)) & 1):
            result ^= feedback << bit_index

        state = ((state << 1) & 0x7FFFFF) | feedback
        for tap in (21, 16, 8, 5, 2):
            state ^= feedback << tap
    return state, result & 0xFFFFFFFF


def make_ts(mode, link, lane, n_fts, rate_id, training_control,
            eq_control, eq_data, state=LANE0_SEED):
    os_id = OS_TS1 if mode == 1 else OS_TS2
    symbol = D_TS1 if mode == 1 else D_TS2
    plain = [
        (n_fts << 24) | (lane << 16) | (link << 8) | os_id,
        ((eq_data & 0xFF) << 24) | (eq_control << 16) |
        (training_control << 8) | rate_id,
        (symbol << 24) | (symbol << 16) | ((eq_data >> 8) & 0xFFFF),
        (symbol << 24) | (symbol << 16) | (symbol << 8) | symbol,
    ]
    encoded = []
    for index, word in enumerate(plain):
        state, value = scramble_word(
            state, word, bypass_byte=0b0001 if index == 0 else 0
        )
        encoded.append(value)
    return state, encoded


async def rx_idle(dut, cycles=1):
    dut.rx_in_valid.value = 0
    dut.rx_start_block.value = 0
    dut.rx_sync_header.value = 0
    dut.rx_data.value = 0
    for _ in range(cycles):
        await tick(dut)


async def drive_word(dut, data, start=False, header=0, bubbles=0):
    if bubbles:
        await rx_idle(dut, bubbles)
    dut.rx_in_valid.value = 1
    dut.rx_start_block.value = int(start)
    dut.rx_sync_header.value = header
    dut.rx_data.value = data
    await tick(dut)


async def drive_block(dut, words, header=SH_ORDERED_SET, rng=None):
    for index, word in enumerate(words):
        bubbles = rng.randrange(3) if rng is not None else 0
        await drive_word(
            dut, word, start=(index == 0),
            header=header if index == 0 else rng.randrange(4) if rng else 0,
            bubbles=bubbles,
        )
    await rx_idle(dut)


async def collect_tx_words(dut, count):
    words = []
    while len(words) < count:
        await Timer(1, units="ps")
        if int(dut.tx_valid.value):
            words.append((
                int(dut.tx_data.value),
                int(dut.tx_start_block.value),
                int(dut.tx_sync_header.value),
            ))
        await RisingEdge(dut.clk)
    return words


@cocotb.test()
async def tx_recovery_stream_is_eieos_then_32_ts(dut):
    await reset(dut)
    dut.tx_link_number.value = 3
    dut.tx_lane_number.value = 0
    dut.tx_n_fts.value = 0xFF
    dut.tx_rate_id.value = 0x0E
    dut.tx_training_control.value = 0x80
    dut.tx_eq_control.value = 0x12
    dut.tx_eq_data.value = 0x345678
    dut.tx_mode.value = 1
    dut.tx_enable.value = 1

    words = await collect_tx_words(dut, 4 + 32 * 4 + 4)
    assert [item[0] for item in words[:4]] == EIEOS_WORDS
    assert [item[1] for item in words[:4]] == [1, 0, 0, 0]
    assert words[0][2] == SH_ORDERED_SET

    _, expected_ts = make_ts(
        1, 3, 0, 0xFF, 0x0E, 0x80, 0x12, 0x345678
    )
    assert [item[0] for item in words[4:8]] == expected_ts
    assert [item[1] for item in words[4:8]] == [1, 0, 0, 0]
    assert [item[0] for item in words[-4:]] == EIEOS_WORDS
    assert [item[1] for item in words[-4:]] == [1, 0, 0, 0]


@cocotb.test()
async def rx_requires_eieos_and_tolerates_valid_bubbles(dut):
    await reset(dut)
    dut.rx_enable.value = 1
    rng = random.Random(0xE100)

    # Random PIPE words before a StartBlock represent an arbitrary word slip.
    for _ in range(11):
        await drive_word(dut, rng.getrandbits(32))
    assert int(dut.rx_block_locked.value) == 0

    _, ts_words = make_ts(1, 7, 0, 0xA5, 0x0E, 0x80, 0x22, 0x123456)
    await drive_block(dut, ts_words, rng=rng)
    assert int(dut.rx_ts1_valid.value) == 0
    assert int(dut.rx_block_locked.value) == 0

    await drive_block(dut, EIEOS_WORDS, rng=rng)
    assert int(dut.rx_eieos_valid.value) == 1
    assert int(dut.rx_lock_acquired.value) == 1
    assert int(dut.rx_block_locked.value) == 1

    await drive_block(dut, ts_words, rng=rng)
    assert int(dut.rx_ts1_valid.value) == 1
    assert int(dut.rx_malformed.value) == 0
    assert int(dut.rx_link_number.value) == 7
    assert int(dut.rx_lane_number.value) == 0
    assert int(dut.rx_n_fts.value) == 0xA5
    assert int(dut.rx_rate_id.value) == 0x0E
    assert int(dut.rx_training_control.value) == 0x80
    assert int(dut.rx_eq_control.value) == 0x22
    assert int(dut.rx_eq_data.value) == 0x123456


@cocotb.test()
async def invalid_header_and_early_start_force_reacquisition(dut):
    await reset(dut)
    dut.rx_enable.value = 1
    await drive_block(dut, EIEOS_WORDS)
    assert int(dut.rx_block_locked.value) == 1

    # An illegal Sync Header destroys semantic lock.
    await drive_block(dut, EIEOS_WORDS, header=0b11)
    assert int(dut.rx_malformed.value) == 1
    assert int(dut.rx_lock_lost.value) == 1
    assert int(dut.rx_block_locked.value) == 0

    # Reacquire, then inject a StartBlock before the previous block ends.
    await drive_block(dut, EIEOS_WORDS)
    assert int(dut.rx_block_locked.value) == 1
    await drive_word(dut, 0x11111111, start=True, header=SH_ORDERED_SET)
    await drive_word(dut, 0x22222222)
    await drive_word(dut, EIEOS_WORDS[0], start=True,
                     header=SH_ORDERED_SET)
    await rx_idle(dut)
    assert int(dut.rx_malformed.value) == 1
    assert int(dut.rx_lock_lost.value) == 1
    assert int(dut.rx_block_locked.value) == 0
    for word in EIEOS_WORDS[1:]:
        await drive_word(dut, word)
    await rx_idle(dut)
    assert int(dut.rx_eieos_valid.value) == 1
    assert int(dut.rx_block_locked.value) == 1


@cocotb.test()
async def one_thousand_random_rate_change_relocks(dut):
    await reset(dut)
    rng = random.Random(0x20260825)

    for iteration in range(1000):
        dut.rx_enable.value = 0
        await rx_idle(dut, 1)
        dut.rx_enable.value = 1

        # Random word alignment at the instant the Gen3 transaction commits.
        for _ in range(rng.randrange(4)):
            await drive_word(dut, rng.getrandbits(32))

        # Inject a bad candidate periodically; it must never produce TS valid.
        if iteration % 17 == 0:
            bad = list(EIEOS_WORDS)
            bad[rng.randrange(4)] ^= 1 << rng.randrange(32)
            await drive_block(dut, bad, rng=rng)
            assert int(dut.rx_block_locked.value) == 0

        await drive_block(dut, EIEOS_WORDS, rng=rng)
        assert int(dut.rx_block_locked.value) == 1

        mode = 1 if rng.getrandbits(1) == 0 else 2
        link = rng.randrange(32)
        lane = 0
        n_fts = rng.randrange(256)
        rate_id = rng.randrange(256)
        training = rng.randrange(256)
        eq_control = rng.randrange(256)
        eq_data = rng.randrange(1 << 24)
        _, ts_words = make_ts(
            mode, link, lane, n_fts, rate_id,
            training, eq_control, eq_data
        )
        await drive_block(dut, ts_words, rng=rng)
        assert int(dut.rx_ts1_valid.value) == (mode == 1)
        assert int(dut.rx_ts2_valid.value) == (mode == 2)
        assert int(dut.rx_malformed.value) == 0
        assert int(dut.rx_link_number.value) == link
        assert int(dut.rx_lane_number.value) == lane
        assert int(dut.rx_n_fts.value) == n_fts
        assert int(dut.rx_rate_id.value) == rate_id
        assert int(dut.rx_training_control.value) == training
        assert int(dut.rx_eq_control.value) == eq_control
        assert int(dut.rx_eq_data.value) == eq_data
