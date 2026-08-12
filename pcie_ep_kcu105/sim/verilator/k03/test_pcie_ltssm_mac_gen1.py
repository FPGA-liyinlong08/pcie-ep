import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


SEED = int(os.getenv("K03_RANDOM_SEED", "20260806"))
RANDOM_TRAININGS = int(os.getenv("K03_RANDOM_TRAININGS", "100"))
RANDOM_PACKETS = int(os.getenv("K03_RANDOM_PACKETS", "2000"))

COM, PAD, TS1, TS2, IDL = 0xBC, 0xF7, 0x4A, 0x45, 0x00
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
PHY_POWERUP = 15
WAIT_REMOTE_DETECT = 16
G9_DETECT_TIMEOUT = 17
G9_ENABLED = os.getenv("G9_WAIT_REMOTE_DETECT", "0") == "1"
partner_rx_lfsr = 0xFFFF


def scrambler_advance_byte(value):
    b = [(value >> i) & 1 for i in range(16)]
    n = [0] * 16
    n[0], n[1], n[2] = b[8], b[9], b[10]
    n[3] = b[11] ^ b[8]
    n[4] = b[12] ^ b[9] ^ b[8]
    n[5] = b[13] ^ b[10] ^ b[9] ^ b[8]
    n[6] = b[14] ^ b[11] ^ b[10] ^ b[9]
    n[7] = b[15] ^ b[12] ^ b[11] ^ b[10]
    n[8] = b[0] ^ b[13] ^ b[12] ^ b[11]
    n[9] = b[1] ^ b[14] ^ b[13] ^ b[12]
    n[10] = b[2] ^ b[15] ^ b[14] ^ b[13]
    n[11] = b[3] ^ b[15] ^ b[14]
    n[12] = b[4] ^ b[15]
    n[13], n[14], n[15] = b[5], b[6], b[7]
    return sum(bit << i for i, bit in enumerate(n))


def scrambler_word(state, data, datak, disabled):
    result = 0
    for lane in range(2):
        symbol = (data >> (8 * lane)) & 0xFF
        is_k = (datak >> lane) & 1
        mask = sum(((state >> (15 - i)) & 1) << i for i in range(8))
        result |= (symbol if disabled or is_k else symbol ^ mask) << (8 * lane)
        if is_k and symbol == COM:
            state = 0xFFFF
        elif not (is_k and symbol == SKP):
            state = scrambler_advance_byte(state)
    return state, result


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
    global partner_rx_lfsr
    partner_rx_lfsr = 0xFFFF
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


async def complete_receiver_detect(dut):
    """完成Receiver Detect以及随后独立的P1->P0 PHY握手。"""
    await pulse_phystatus(dut, 0b011)
    await wait_state(dut, PHY_POWERUP)
    assert int(dut.phy_txdetectrx.value) == 0
    assert int(dut.phy_powerdown.value) == 0b00
    assert int(dut.phy_txelecidle.value) == 1
    assert int(dut.phy_txdata_valid.value) == 0
    await pulse_phystatus(dut, 0b000)
    if G9_ENABLED:
        await wait_state(dut, WAIT_REMOTE_DETECT)
        assert int(dut.phy_powerdown.value) == 0b00
        assert int(dut.phy_txdetectrx.value) == 0
        assert int(dut.phy_txelecidle.value) == 1
        assert int(dut.phy_txdata_valid.value) == 0
        assert int(dut.as_mac_in_detect.value) == 1
        # 模拟Root Port开始发送活动；G9应只因RXELECIDLE下降而离开等待态。
        dut.phy_rxelecidle.value = 0
        await wait_state(dut, POLLING_ACTIVE)
    else:
        await wait_state(dut, POLLING_ACTIVE)


@cocotb.test()
async def g9_timeout_latches_result(dut):
    if not G9_ENABLED:
        return
    await initialize(dut)
    await wait_state(dut, DETECT_ACTIVE)
    await complete_receiver_detect_without_remote_activity(dut)


async def complete_receiver_detect_without_remote_activity(dut):
    """G9专用：完成本端Detect后保持RX Electrical Idle，验证超时锁存。"""
    await pulse_phystatus(dut, 0b011)
    await wait_state(dut, PHY_POWERUP)
    await pulse_phystatus(dut, 0b000)
    await wait_state(dut, WAIT_REMOTE_DETECT)
    await wait_state(dut, G9_DETECT_TIMEOUT, timeout=128)
    assert int(dut.timeout_count.value) >= 1


def ts_symbols(kind, link=PAD, lane=PAD, nfts=0xFF, rate=0x02, control=0):
    ident = TS1 if kind == 1 else TS2
    link_k = 1 if link == PAD else 0
    lane_k = 1 if lane == PAD else 0
    symbols = [COM, link, lane, nfts, rate, control] + [ident] * 10
    isk = [1, link_k, lane_k, 0, 0, 0] + [0] * 10
    return symbols, isk


async def drive_symbols(dut, symbols, isk, data_valid=1, scramble_disable=True):
    global partner_rx_lfsr
    assert len(symbols) == len(isk) and len(symbols) % 2 == 0
    for pos in range(0, len(symbols), 2):
        plain = symbols[pos] | (symbols[pos + 1] << 8)
        datak = isk[pos] | (isk[pos + 1] << 1)
        partner_rx_lfsr, encoded = scrambler_word(
            partner_rx_lfsr, plain, datak, scramble_disable)
        dut.phy_rxdata.value = encoded
        dut.phy_rxdatak.value = datak
        dut.phy_rxdata_valid.value = data_valid
        dut.phy_rxvalid.value = 1
        dut.phy_rxelecidle.value = 0
        await tick(dut)
        await writable_phase()
    dut.phy_rxdata_valid.value = 0
    dut.phy_rxvalid.value = 0
    dut.phy_rxdata.value = 0
    dut.phy_rxdatak.value = 0


async def send_ts(
    dut, kind, count, link=PAD, lane=PAD, corrupt_index=None, data_valid=1
):
    for packet_index in range(count):
        symbols, isk = ts_symbols(kind, link=link, lane=lane)
        if corrupt_index is not None and packet_index == 0:
            symbols[corrupt_index] ^= 1
        await drive_symbols(dut, symbols, isk, data_valid=data_valid)


async def send_ts_high_symbol_aligned(dut, kind, count, link=PAD, lane=PAD):
    """构造 COM 位于高 Symbol、其余 TS 跨拍连续的真实 PHY 布局。"""
    symbols = [IDL]
    isk = [0]
    for _ in range(count):
        one_symbols, one_isk = ts_symbols(kind, link=link, lane=lane)
        symbols += one_symbols
        isk += one_isk
    symbols.append(IDL)
    isk.append(0)
    await drive_symbols(dut, symbols, isk, data_valid=0)


async def send_idle(dut, cycles=8, symbol=IDL, isk=0):
    global partner_rx_lfsr
    for _ in range(cycles):
        plain = symbol | (symbol << 8)
        datak = isk | (isk << 1)
        partner_rx_lfsr, encoded = scrambler_word(
            partner_rx_lfsr, plain, datak, False)
        dut.phy_rxdata.value = encoded
        dut.phy_rxdatak.value = datak
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
                assert int(dut.phy_txdata_valid.value) == 1
                assert int(dut.phy_txelecidle.value) == 0
                assert int(dut.phy_powerdown.value) == 0b00
                assert data >> 16 == 0, "Gen1每拍高16 bit必须为0"
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
    await complete_receiver_detect(dut)
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
    # Polling.Active的RX条件先在8个TS1后满足，但TX仍必须完成1024个TS1。
    await send_ts(dut, 1, 1024)
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
    await tick(dut, 2)
    await writable_phase()
    assert int(dut.ltssm_state.value) == CFG_LINKWIDTH_ACCEPT, (
        "Linkwidth.Accept 不得仅因收到2个TS1而提前退出，必须先发送16个TS1"
    )
    await send_ts(dut, 1, 1, link=0, lane=0)
    assert int(dut.rx_ts_count.value) == 2, (
        "对端提前发送下一阶段 Link/Lane TS1 时不得清除已满足的接收条件"
    )
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
    await tick(dut, 2)
    await writable_phase()
    assert int(dut.ltssm_state.value) == CFG_LANENUM_ACCEPT, (
        "Lanenum.Accept 不得仅因收到2个TS1而提前退出，必须先发送16个TS1"
    )
    await send_ts(dut, 2, 1, link=0, lane=0)
    assert int(dut.rx_ts_count.value) == 2, (
        "对端提前发送TS2时不得清除 Lanenum.Accept 已满足的接收条件"
    )
    await wait_state(dut, CFG_COMPLETE)
    if validate_tx:
        await capture_tx_ts(dut, 2, link=0, lane=0)
    if inject_bad_fields:
        await send_ts(dut, 2, 1, link=1, lane=0)
        await tick(dut)
        await writable_phase()
        assert int(dut.ltssm_state.value) == CFG_COMPLETE
    await send_ts(dut, 2, 8, link=0, lane=0)
    await tick(dut, 2)
    await writable_phase()
    assert int(dut.ltssm_state.value) == CFG_COMPLETE, (
        "Configuration.Complete 必须发送至少16个TS2后才能进入Idle"
    )
    await wait_state(dut, CFG_IDLE)
    if validate_tx:
        await send_idle(dut, 8, symbol=0x7C, isk=1)
        assert int(dut.ltssm_state.value) == CFG_IDLE, (
            "K28.3 不得被误识别为 PCIe Logical Idle"
        )
    await send_idle(dut, 8)
    await wait_state(dut, L0)
    assert int(dut.link_up.value) == 1
    assert int(dut.negotiated_width.value) == 1
    assert int(dut.negotiated_speed.value) == 0


async def reset_for_next_training(dut):
    global partner_rx_lfsr
    await writable_phase()
    dut.pipe_rst_n.value = 0
    await tick(dut, 2)
    await writable_phase()
    dut.pipe_rst_n.value = 1
    partner_rx_lfsr = 0xFFFF


@cocotb.test()
async def normal_training(dut):
    """错误 Stub 必须因跳过 Polling/Configuration 而被本用例检出。"""
    await initialize(dut)
    await train_to_l0(dut, validate_tx=True)


@cocotb.test()
async def detect_waits_for_p0_phystatus_before_ts1(dut):
    """Receiver Detect完成后必须等待独立的P1->P0 PhyStatus，才可发送TS1。"""
    await initialize(dut)
    await wait_state(dut, DETECT_ACTIVE)
    assert int(dut.phy_powerdown.value) == 0b10
    assert int(dut.phy_txdetectrx.value) == 1
    assert int(dut.phy_txelecidle.value) == 1

    # 该脉冲只确认Receiver Detect完成，不能同时充当P1->P0完成通知。
    await pulse_phystatus(dut, 0b011)
    for _ in range(4):
        assert int(dut.phy_powerdown.value) == 0b00
        assert int(dut.phy_txdetectrx.value) == 0
        assert int(dut.phy_txelecidle.value) == 1
        assert int(dut.phy_txdata_valid.value) == 0
        await tick(dut)
        await writable_phase()

    # 新的PhyStatus脉冲确认P0已完成，此后才允许进入Polling.Active并发送TS1。
    await pulse_phystatus(dut, 0b000)
    await wait_state(dut, POLLING_ACTIVE)
    assert int(dut.phy_powerdown.value) == 0b00
    assert int(dut.phy_txelecidle.value) == 0
    assert int(dut.phy_txdata_valid.value) == 1


@cocotb.test()
async def gen1_ignores_gen3_rxdata_valid(dut):
    """Gen1 以 RxValid 采样 8b/10b Symbol，RxDataValid 允许保持 0。"""
    await initialize(dut)
    await wait_state(dut, DETECT_ACTIVE)
    await complete_receiver_detect(dut)
    await send_ts(dut, 1, 1024, data_valid=0)
    await wait_state(dut, POLLING_CONFIG)


@cocotb.test()
async def gen1_accepts_com_in_high_symbol(dut):
    """真实 GT 可能把 COM 放在高 Symbol，跨拍重组后仍应识别完整 TS。"""
    await initialize(dut)
    await wait_state(dut, DETECT_ACTIVE)
    await complete_receiver_detect(dut)
    await send_ts_high_symbol_aligned(dut, 1, 1024)
    await wait_state(dut, POLLING_CONFIG)


@cocotb.test()
async def polling_active_accepts_mixed_ts1_ts2_after_tx_threshold(dut):
    """Polling.Active的8个RX训练Ordered Set允许TS1/TS2混合，但仍需TX 1024 TS1。"""
    await initialize(dut)
    await wait_state(dut, DETECT_ACTIVE)
    await complete_receiver_detect(dut)

    for kind in (1, 2, 1, 2, 1, 2, 1, 2):
        await send_ts(dut, kind, 1)
    await tick(dut)
    await writable_phase()
    assert int(dut.ltssm_state.value) == POLLING_ACTIVE
    assert int(dut.rx_ts_count.value) >= 8
    assert int(dut.polling_tx_ts1_count.value) < 1024

    await send_ts(dut, 1, 1016)
    await wait_state(dut, POLLING_CONFIG)
    assert int(dut.polling_tx_ts1_count.value) == 1024


@cocotb.test()
async def l0_filters_rxelecidle_glitch_and_accepts_partner_recovery(dut):
    """L0过滤单周期Electrical Idle毛刺，并响应对端正常Recovery TS1。"""
    await initialize(dut)
    await train_to_l0(dut, validate_tx=False)

    await writable_phase()
    dut.phy_rxelecidle.value = 1
    await tick(dut)
    await writable_phase()
    dut.phy_rxelecidle.value = 0
    await tick(dut)
    assert int(dut.ltssm_state.value) == L0

    # 对端可以不依赖本地DLL请求，直接以带既有Link/Lane号的TS1发起Recovery。
    await writable_phase()
    await send_ts(dut, 1, 1, link=0, lane=0)
    await wait_state(dut, RECOVERY_RCVRLOCK)


@cocotb.test()
async def l0_enters_recovery_after_sustained_rxelecidle(dut):
    """锁定实板输入：RxValid重叠时不退出，真正Electrical Idle连续8拍才退出。"""
    await initialize(dut)
    await train_to_l0(dut, validate_tx=False)

    await writable_phase()
    # K11-B3实板窗口：PHY同时报告RxElecIdle和RxValid，且RxData仍变化。
    # 这不是有效Electrical Idle，不得触发Recovery。
    dut.phy_rxelecidle.value = 1
    dut.phy_rxvalid.value = 1
    dut.phy_rxdata.value = 0x000000BC
    await tick(dut, 8)
    assert int(dut.ltssm_state.value) == L0
    assert int(dut.rxelecidle_count.value) == 0

    # 真正Electrical Idle：RxValid撤销后，连续7拍只累积滤波计数。
    await writable_phase()
    dut.phy_rxvalid.value = 0
    await tick(dut, 7)
    assert int(dut.ltssm_state.value) == L0
    assert int(dut.rxelecidle_count.value) == 7
    # 第8拍观察到qualified，下一状态必须是Recovery.RcvrLock。
    await tick(dut)
    assert int(dut.ltssm_state.value) == RECOVERY_RCVRLOCK
    assert int(dut.hot_reset_seen.value) == 0
    await writable_phase()
    dut.phy_rxelecidle.value = 0


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
    await complete_receiver_detect(dut)
    await send_ts(dut, 1, 1, corrupt_index=9)
    await tick(dut, 10200)
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
    # Hot Reset保持期必须回送training_control.HotReset=1的TS1，不能立即静默。
    hot_reset_control_seen = False
    for _ in range(8):
        data = int(dut.phy_txdata.value)
        datak = int(dut.phy_txdatak.value)
        if (data & 0xFFFF) == 0x0102 and datak == 0:
            hot_reset_control_seen = True
        await writable_phase()
        await tick(dut)
    assert hot_reset_control_seen
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
        tx_state = int(dut.u_tx_scrambler.lfsr_state.value)
        _, data = scrambler_word(tx_state, data & 0xFFFF, datak, False)
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
    global partner_rx_lfsr
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
        plain = symbols[pos][0] | (symbols[pos + 1][0] << 8)
        datak = symbols[pos][1] | (symbols[pos + 1][1] << 1)
        partner_rx_lfsr, encoded = scrambler_word(
            partner_rx_lfsr, plain, datak, False)
        dut.phy_rxdata.value = encoded
        dut.phy_rxdatak.value = datak
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

    await drive_symbols(dut, [STP, SDP], [1, 1], scramble_disable=False)
    await tick(dut, 2)
    await writable_phase()
    assert int(dut.frame_error_count.value) > before
    before = int(dut.frame_error_count.value)

    await drive_symbols(
        dut, [STP, 0x12, SKP, IDL], [1, 0, 1, 1], scramble_disable=False
    )
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
