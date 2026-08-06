import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


SEED = int(os.getenv("K03_RANDOM_SEED", "20260806"))
RANDOM_TRAININGS = int(os.getenv("K03_RANDOM_TRAININGS", "100"))
RANDOM_PACKETS = int(os.getenv("K03_RANDOM_PACKETS", "2000"))

COM, PAD, TS1, TS2, IDL = 0xBC, 0xF7, 0x4A, 0x45, 0x7C
STP, SDP, END, EDB = 0xFB, 0x5C, 0xFD, 0xFE
SKP = 0x1C

DETECT_QUIET = 0
DETECT_ACTIVE = 1
POLLING_ACTIVE = 2
POLLING_CONFIG = 3
CFG_LINKWIDTH_START = 4
CFG_LINKWIDTH_ACCEPT = 5
CFG_LANENUM_WAIT = 6
CFG_LANENUM_ACCEPT = 7
CFG_COMPLETE = 8
CFG_IDLE = 9
L0 = 10
RECOVERY_RCVRLOCK = 11
RECOVERY_RCVRCFG = 12
RECOVERY_IDLE = 13
HOT_RESET = 14


def drive_defaults(dut):
    dut.pipe_rst_n.value = 0
    dut.phy_rxdata.value = 0
    dut.phy_rxdatak.value = 0
    dut.phy_rxdata_valid.value = 0
    dut.phy_rxvalid.value = 0
    dut.phy_phystatus.value = 0
    dut.phy_rxelecidle.value = 1
    dut.phy_rxstatus.value = 0
    dut.tx_pkt_valid.value = 0
    dut.tx_pkt_data.value = 0
    dut.tx_pkt_keep.value = 0
    dut.tx_pkt_sop.value = 0
    dut.tx_pkt_eop.value = 0
    dut.tx_pkt_is_dllp.value = 0
    dut.tx_pkt_bad.value = 0
    dut.link_disable.value = 0
    dut.hot_reset_req.value = 0
    dut.force_recovery.value = 0


async def tick(dut, count=1):
    for _ in range(count):
        await RisingEdge(dut.phy_pclk)
    await ReadOnly()


async def writable_phase():
    await Timer(1, units="ps")


async def initialize(dut):
    drive_defaults(dut)
    cocotb.start_soon(Clock(dut.phy_pclk, 8, units="ns").start())
    await tick(dut, 3)
    assert int(dut.ltssm_state.value) == DETECT_QUIET
    assert int(dut.phy_powerdown.value) == 2
    assert int(dut.phy_txelecidle.value) == 1
    assert int(dut.phy_rate.value) == 0
    assert int(dut.phy_txdata.value) >> 16 == 0
    await writable_phase()
    dut.pipe_rst_n.value = 1


async def wait_state(dut, expected, timeout=800):
    for _ in range(timeout):
        await tick(dut)
        if int(dut.ltssm_state.value) == expected:
            await writable_phase()
            return
        await writable_phase()
    raise AssertionError(
        f"等待 LTSSM state={expected} 超时，当前={int(dut.ltssm_state.value)}"
    )


async def pulse_phystatus(dut, status):
    dut.phy_rxstatus.value = status
    dut.phy_phystatus.value = 1
    await tick(dut)
    await writable_phase()
    dut.phy_phystatus.value = 0


def ts_symbols(kind, link=PAD, lane=PAD, nfts=0xFF, rate=0x07, control=0):
    ident = TS1 if kind == 1 else TS2
    link_k = 1 if link == PAD else 0
    lane_k = 1 if lane == PAD else 0
    symbols = [COM, link, lane, nfts, rate, control] + [ident] * 10
    isk = [1, link_k, lane_k, 0, 0, 0] + [0] * 10
    return symbols, isk


async def drive_symbols(dut, symbols, isk):
    assert len(symbols) == len(isk) and len(symbols) % 2 == 0
    for pos in range(0, len(symbols), 2):
        dut.phy_rxdata.value = symbols[pos] | (symbols[pos + 1] << 8)
        dut.phy_rxdatak.value = isk[pos] | (isk[pos + 1] << 1)
        dut.phy_rxdata_valid.value = 1
        dut.phy_rxvalid.value = 1
        dut.phy_rxelecidle.value = 0
        await tick(dut)
        await writable_phase()
    dut.phy_rxdata_valid.value = 0
    dut.phy_rxvalid.value = 0
    dut.phy_rxdata.value = 0
    dut.phy_rxdatak.value = 0


async def send_ts(dut, kind, count, link=PAD, lane=PAD, corrupt_index=None):
    for packet_index in range(count):
        symbols, isk = ts_symbols(kind, link=link, lane=lane)
        if corrupt_index is not None and packet_index == 0:
            symbols[corrupt_index] ^= 1
        await drive_symbols(dut, symbols, isk)


async def send_idle(dut, cycles=8):
    for _ in range(cycles):
        dut.phy_rxdata.value = IDL | (IDL << 8)
        dut.phy_rxdatak.value = 0b11
        dut.phy_rxdata_valid.value = 1
        dut.phy_rxvalid.value = 1
        dut.phy_rxelecidle.value = 0
        await tick(dut)
        await writable_phase()
    dut.phy_rxdata_valid.value = 0
    dut.phy_rxvalid.value = 0


async def capture_tx_ts(dut, kind, link=PAD, lane=PAD, timeout=64):
    expected, expected_k = ts_symbols(kind, link=link, lane=lane)
    for _ in range(timeout):
        await tick(dut)
        data = int(dut.phy_txdata.value)
        datak = int(dut.phy_txdatak.value)
        assert data >> 16 == 0, "Gen1 高 16 bit 必须为 0"
        if (data & 0xFF) == COM and (datak & 1):
            got, got_k = [], []
            for index in range(8):
                if index:
                    await writable_phase()
                    await tick(dut)
                    data = int(dut.phy_txdata.value)
                    datak = int(dut.phy_txdatak.value)
                got += [data & 0xFF, (data >> 8) & 0xFF]
                got_k += [datak & 1, (datak >> 1) & 1]
            assert got == expected, f"TX TS{kind} Symbol 错误: {got}"
            assert got_k == expected_k, f"TX TS{kind} K 属性错误: {got_k}"
            await writable_phase()
            return
        await writable_phase()
    raise AssertionError(f"未观察到 TS{kind}")


async def train_to_l0(
    dut,
    validate_tx=True,
    partner_delay=0,
    inject_bad=False,
    inject_bad_fields=False,
):
    await wait_state(dut, DETECT_ACTIVE)
    assert int(dut.phy_txdetectrx.value) == 1
    await writable_phase()
    await pulse_phystatus(dut, 0b011)
    await wait_state(dut, POLLING_ACTIVE)
    if partner_delay:
        await tick(dut, partner_delay)
        await writable_phase()
    if validate_tx:
        await capture_tx_ts(dut, 1)
    if inject_bad:
        before = int(dut.training_error_count.value)
        await send_ts(dut, 1, 1, corrupt_index=7)
        await tick(dut)
        await writable_phase()
        assert int(dut.ltssm_state.value) == POLLING_ACTIVE
        assert int(dut.training_error_count.value) > before
    await send_ts(dut, 1, 8)
    await wait_state(dut, POLLING_CONFIG)
    if validate_tx:
        await capture_tx_ts(dut, 2)
    await send_ts(dut, 2, 8)
    await wait_state(dut, CFG_LINKWIDTH_START)
    if inject_bad_fields:
        before = int(dut.training_error_count.value)
        await send_ts(dut, 1, 1, link=0, lane=1)
        await tick(dut)
        await writable_phase()
        assert int(dut.ltssm_state.value) == CFG_LINKWIDTH_START
        assert int(dut.training_error_count.value) > before
    await send_ts(dut, 1, 1, link=0, lane=PAD)
    await wait_state(dut, CFG_LINKWIDTH_ACCEPT)
    if validate_tx:
        await capture_tx_ts(dut, 1, link=0, lane=PAD)
    if inject_bad_fields:
        await send_ts(dut, 1, 1, link=1, lane=PAD)
        await tick(dut)
        await writable_phase()
        assert int(dut.ltssm_state.value) == CFG_LINKWIDTH_ACCEPT
    await send_ts(dut, 1, 2, link=0, lane=PAD)
    await wait_state(dut, CFG_LANENUM_WAIT)
    if inject_bad_fields:
        await send_ts(dut, 1, 1, link=0, lane=1)
        await tick(dut)
        await writable_phase()
        assert int(dut.ltssm_state.value) == CFG_LANENUM_WAIT
    await send_ts(dut, 1, 1, link=0, lane=0)
    await wait_state(dut, CFG_LANENUM_ACCEPT)
    if validate_tx:
        await capture_tx_ts(dut, 1, link=0, lane=0)
    await send_ts(dut, 1, 2, link=0, lane=0)
    await wait_state(dut, CFG_COMPLETE)
    if validate_tx:
        await capture_tx_ts(dut, 2, link=0, lane=0)
    if inject_bad_fields:
        await send_ts(dut, 2, 1, link=1, lane=0)
        await tick(dut)
        await writable_phase()
        assert int(dut.ltssm_state.value) == CFG_COMPLETE
    await send_ts(dut, 2, 8, link=0, lane=0)
    await wait_state(dut, CFG_IDLE)
    await send_idle(dut, 8)
    await wait_state(dut, L0)
    assert int(dut.link_up.value) == 1
    assert int(dut.negotiated_width.value) == 1
    assert int(dut.negotiated_speed.value) == 0


async def reset_for_next_training(dut):
    await writable_phase()
    dut.pipe_rst_n.value = 0
    await tick(dut, 2)
    await writable_phase()
    dut.pipe_rst_n.value = 1


@cocotb.test()
async def normal_training(dut):
    """错误 Stub 必须因跳过 Polling/Configuration 而被本用例检出。"""
    await initialize(dut)
    await train_to_l0(dut, validate_tx=True)


@cocotb.test()
async def detect_errors_recovery_and_hot_reset(dut):
    await initialize(dut)
    await wait_state(dut, DETECT_ACTIVE)
    await tick(dut, 70)
    assert int(dut.timeout_count.value) >= 1

    await reset_for_next_training(dut)
    await wait_state(dut, DETECT_ACTIVE)
    await pulse_phystatus(dut, 0b000)
    await wait_state(dut, DETECT_QUIET)
    assert int(dut.training_error_count.value) >= 1

    await wait_state(dut, DETECT_ACTIVE)
    await pulse_phystatus(dut, 0b011)
    await wait_state(dut, POLLING_ACTIVE)
    await send_ts(dut, 1, 1, corrupt_index=9)
    await tick(dut, 520)
    assert int(dut.timeout_count.value) >= 1
    await wait_state(dut, DETECT_QUIET)

    await reset_for_next_training(dut)
    await train_to_l0(dut, validate_tx=False)
    await writable_phase()
    dut.force_recovery.value = 1
    await tick(dut)
    await writable_phase()
    dut.force_recovery.value = 0
    await wait_state(dut, RECOVERY_RCVRLOCK)
    await send_ts(dut, 1, 8, link=0, lane=0)
    await wait_state(dut, RECOVERY_RCVRCFG)
    await send_ts(dut, 2, 8, link=0, lane=0)
    await wait_state(dut, RECOVERY_IDLE)
    await send_idle(dut, 8)
    await wait_state(dut, L0)

    dut.hot_reset_req.value = 1
    await tick(dut)
    assert int(dut.ltssm_state.value) == HOT_RESET
    assert int(dut.hot_reset_seen.value) == 1
    await writable_phase()
    dut.hot_reset_req.value = 0
    await wait_state(dut, DETECT_QUIET)


async def send_tx_packet(dut, payload, is_dllp, bad, rng):
    offset = 0
    while offset < len(payload):
        count = min(2, len(payload) - offset)
        word = payload[offset] | ((payload[offset + 1] if count == 2 else 0) << 8)
        dut.tx_pkt_data.value = word
        dut.tx_pkt_keep.value = 3 if count == 2 else 1
        dut.tx_pkt_sop.value = int(offset == 0)
        dut.tx_pkt_eop.value = int(offset + count == len(payload))
        dut.tx_pkt_is_dllp.value = int(is_dllp)
        dut.tx_pkt_bad.value = int(bad and offset + count == len(payload))
        dut.tx_pkt_valid.value = 1
        while True:
            await ReadOnly()
            ready = int(dut.tx_pkt_ready.value)
            await writable_phase()
            await RisingEdge(dut.phy_pclk)
            if ready:
                break
        await writable_phase()
        dut.tx_pkt_valid.value = 0
        offset += count
        if offset < len(payload):
            for _ in range(rng.randrange(3)):
                await tick(dut)
                await writable_phase()


async def collect_wire_packet(dut, timeout=400):
    started = False
    data_bytes = []
    is_dllp = False
    bad = False
    for _ in range(timeout):
        await ReadOnly()
        data = int(dut.phy_txdata.value)
        datak = int(dut.phy_txdatak.value)
        for lane in range(2):
            byte = (data >> (lane * 8)) & 0xFF
            is_k = (datak >> lane) & 1
            if not started:
                if is_k and byte in (STP, SDP):
                    started = True
                    is_dllp = byte == SDP
            elif is_k and byte in (END, EDB):
                bad = byte == EDB
                await writable_phase()
                return bytes(data_bytes), is_dllp, bad
            elif is_k:
                raise AssertionError(f"Packet 内非法 K-code {byte:02x}")
            else:
                data_bytes.append(byte)
        await writable_phase()
        await RisingEdge(dut.phy_pclk)
    raise AssertionError("等待线上 Packet 结束超时")


async def drive_rx_wire_packet(dut, payload, is_dllp, bad, start_on_high=False):
    symbols = []
    if start_on_high:
        symbols.append((IDL, 1))
    symbols.append((SDP if is_dllp else STP, 1))
    symbols += [(value, 0) for value in payload]
    symbols += [(EDB if bad else END, 1)]
    if len(symbols) & 1:
        symbols.append((IDL, 1))

    observed = []
    saw_sop = False
    saw_eop = False
    observed_bad = False
    for pos in range(0, len(symbols), 2):
        dut.phy_rxdata.value = symbols[pos][0] | (symbols[pos + 1][0] << 8)
        dut.phy_rxdatak.value = symbols[pos][1] | (symbols[pos + 1][1] << 1)
        dut.phy_rxdata_valid.value = 1
        dut.phy_rxvalid.value = 1
        dut.phy_rxelecidle.value = 0
        await tick(dut)
        if int(dut.rx_pkt_valid.value):
            keep = int(dut.rx_pkt_keep.value)
            word = int(dut.rx_pkt_data.value)
            if keep & 1:
                observed.append(word & 0xFF)
            if keep & 2:
                observed.append((word >> 8) & 0xFF)
            saw_sop |= bool(int(dut.rx_pkt_sop.value))
            saw_eop |= bool(int(dut.rx_pkt_eop.value))
            observed_bad |= bool(int(dut.rx_pkt_error.value) & 1)
            assert int(dut.rx_pkt_is_dllp.value) == int(is_dllp)
        await writable_phase()
    dut.phy_rxdata_valid.value = 0
    dut.phy_rxvalid.value = 0
    return bytes(observed), saw_sop, saw_eop, observed_bad


@cocotb.test()
async def packet_framing_randomized(dut):
    await initialize(dut)
    await train_to_l0(dut, validate_tx=False)
    rng = random.Random(SEED)

    for iteration in range(RANDOM_PACKETS):
        length = rng.randint(1, 160)
        payload = bytes(rng.getrandbits(8) for _ in range(length))
        is_dllp = bool(rng.getrandbits(1))
        bad = bool(rng.getrandbits(1))
        start_on_high = bool(rng.getrandbits(1))
        await send_tx_packet(dut, payload, is_dllp, bad, rng)
        got, got_dllp, got_bad = await collect_wire_packet(dut)
        assert got == payload, f"TX Packet 数据错误 iteration={iteration}"
        assert got_dllp == is_dllp
        assert got_bad == bad

        got, sop, eop, got_bad = await drive_rx_wire_packet(
            dut, payload, is_dllp, bad, start_on_high=start_on_high
        )
        assert got == payload, f"RX Packet 数据错误 iteration={iteration}"
        assert sop and eop and got_bad == bad


@cocotb.test()
async def packet_protocol_errors(dut):
    """嵌套 Start、非法 K、非法 keep 和超长 TX 必须丢弃并计数。"""
    await initialize(dut)
    await train_to_l0(dut, validate_tx=False)
    before = int(dut.frame_error_count.value)

    await drive_symbols(dut, [STP, SDP], [1, 1])
    await tick(dut, 2)
    await writable_phase()
    assert int(dut.frame_error_count.value) > before
    before = int(dut.frame_error_count.value)

    await drive_symbols(dut, [STP, 0x12, SKP, IDL], [1, 0, 1, 1])
    await tick(dut, 2)
    await writable_phase()
    assert int(dut.frame_error_count.value) > before
    before = int(dut.frame_error_count.value)

    dut.tx_pkt_valid.value = 1
    dut.tx_pkt_sop.value = 1
    dut.tx_pkt_eop.value = 1
    dut.tx_pkt_keep.value = 0
    await RisingEdge(dut.phy_pclk)
    await writable_phase()
    dut.tx_pkt_valid.value = 0
    dut.tx_pkt_sop.value = 0
    dut.tx_pkt_eop.value = 0
    await tick(dut, 2)
    await writable_phase()
    assert int(dut.frame_error_count.value) > before
    before = int(dut.frame_error_count.value)

    rng = random.Random(SEED ^ 0xBAD)
    await send_tx_packet(dut, bytes(range(162)), False, False, rng)
    await tick(dut, 2)
    await writable_phase()
    assert int(dut.frame_error_count.value) > before
    assert int(dut.tx_pkt_ready.value) == 1


@cocotb.test()
async def one_hundred_random_trainings(dut):
    await initialize(dut)
    rng = random.Random(SEED ^ 0x4B3033)
    for iteration in range(RANDOM_TRAININGS):
        if iteration:
            await reset_for_next_training(dut)
        await train_to_l0(
            dut,
            validate_tx=(iteration == 0),
            partner_delay=rng.randrange(8),
            inject_bad=bool(rng.getrandbits(1)),
            inject_bad_fields=bool(rng.getrandbits(1)),
        )
        assert int(dut.phy_rate.value) == 0
        assert int(dut.phy_txstart_block.value) == 0
        assert int(dut.phy_txsync_header.value) == 0
