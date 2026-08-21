import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer

from k13_gen3_golden_checker import assert_training_prefix


COM, PAD, TS1, TS2, IDL = 0xBC, 0xF7, 0x4A, 0x45, 0x00
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
PHY_POWERUP = 15
RECOVERY_SPEED = 18
partner_lfsr = 0xFFFF


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
        elif not (is_k and symbol == 0x1C):
            state = scrambler_advance_byte(state)
    return state, result


async def tick(dut, count=1):
    for _ in range(count):
        await RisingEdge(dut.phy_pclk)
    await ReadOnly()


async def writable():
    await Timer(1, units="ps")


async def wait_state(dut, expected, timeout=12000):
    for _ in range(timeout):
        await tick(dut)
        if int(dut.ltssm_state.value) == expected:
            await writable()
            return
        await writable()
    raise AssertionError(
        f"等待 LTSSM={expected} 超时，当前={int(dut.ltssm_state.value)} "
        f"speed={int(dut.speed_state.value)} rate={int(dut.phy_rate.value)}"
    )


async def pulse_phystatus(dut, status=0):
    dut.phy_rxstatus.value = status
    dut.phy_phystatus.value = 1
    await tick(dut)
    await writable()
    dut.phy_phystatus.value = 0


def ts_symbols(kind, link=PAD, lane=PAD, rate=0x02):
    ident = TS1 if kind == 1 else TS2
    return (
        [COM, link, lane, 0xFF, rate, 0] + [ident] * 10,
        [1, int(link == PAD), int(lane == PAD), 0, 0, 0] + [0] * 10,
    )


async def drive_symbols(dut, symbols, isk, scramble_disable=True):
    global partner_lfsr
    for pos in range(0, len(symbols), 2):
        plain = symbols[pos] | (symbols[pos + 1] << 8)
        datak = isk[pos] | (isk[pos + 1] << 1)
        partner_lfsr, encoded = scrambler_word(
            partner_lfsr, plain, datak, scramble_disable
        )
        dut.phy_rxdata.value = encoded
        dut.phy_rxdatak.value = datak
        dut.phy_rxdata_valid.value = 1
        dut.phy_rxvalid.value = 1
        dut.phy_rxelecidle.value = 0
        await tick(dut)
        await writable()
    dut.phy_rxdata.value = 0
    dut.phy_rxdatak.value = 0
    dut.phy_rxdata_valid.value = 0
    dut.phy_rxvalid.value = 0


async def send_ts(dut, kind, count, link=PAD, lane=PAD, rate=0x02):
    for _ in range(count):
        symbols, isk = ts_symbols(kind, link, lane, rate)
        await drive_symbols(dut, symbols, isk)


async def send_idle(dut, cycles=8):
    global partner_lfsr
    for _ in range(cycles):
        partner_lfsr, encoded = scrambler_word(partner_lfsr, 0, 0, False)
        dut.phy_rxdata.value = encoded
        dut.phy_rxdatak.value = 0
        dut.phy_rxdata_valid.value = 1
        dut.phy_rxvalid.value = 1
        dut.phy_rxelecidle.value = 0
        await tick(dut)
        await writable()
    dut.phy_rxdata_valid.value = 0
    dut.phy_rxvalid.value = 0


async def train_gen1_to_l0(dut):
    await wait_state(dut, DETECT_ACTIVE)
    await pulse_phystatus(dut, 0b011)
    await wait_state(dut, PHY_POWERUP)
    await pulse_phystatus(dut, 0)
    await wait_state(dut, POLLING_ACTIVE)
    await send_ts(dut, 1, 1024)
    await wait_state(dut, POLLING_CONFIG)
    await send_ts(dut, 2, 8)
    await wait_state(dut, CFG_LINKWIDTH_START)
    await send_ts(dut, 1, 1, link=0, lane=PAD)
    await wait_state(dut, CFG_LINKWIDTH_ACCEPT)
    await send_ts(dut, 1, 2, link=0, lane=PAD)
    await send_ts(dut, 1, 1, link=0, lane=0)
    await wait_state(dut, CFG_LANENUM_WAIT)
    await send_ts(dut, 1, 1, link=0, lane=0)
    await wait_state(dut, CFG_LANENUM_ACCEPT)
    await send_ts(dut, 1, 2, link=0, lane=0)
    await send_ts(dut, 2, 1, link=0, lane=0)
    await wait_state(dut, CFG_COMPLETE)
    await send_ts(dut, 2, 8, link=0, lane=0)
    await wait_state(dut, CFG_IDLE)
    await send_idle(dut, 8)
    await wait_state(dut, L0)


async def phy_command_responder(dut):
    previous_rate = int(dut.phy_rate.value)
    phystatus_hold = 0
    txeq_seen = False
    rxeq_seen = False
    while True:
        await RisingEdge(dut.phy_pclk)
        await ReadOnly()
        rate = int(dut.phy_rate.value)
        txeq = int(dut.phy_txeq_ctrl.value)
        rxeq = int(dut.phy_rxeq_ctrl.value)
        await writable()
        if rate != previous_rate:
            phystatus_hold = 2
        dut.phy_phystatus.value = int(phystatus_hold > 0)
        if phystatus_hold:
            phystatus_hold -= 1
        previous_rate = rate
        dut.phy_txeq_done.value = int(txeq != 0 and not txeq_seen)
        dut.phy_rxeq_done.value = int(rxeq == 2 and not rxeq_seen)
        dut.phy_rxeq_adapt_done.value = int(rxeq == 2 and not rxeq_seen)
        txeq_seen = txeq != 0
        rxeq_seen = rxeq != 0


async def phy_command_responder_with_one_rxeq_failure(dut):
    """Respond to two Gen3 attempts; inject done-only RXEQ on the first."""
    previous_rate = int(dut.phy_rate.value)
    phystatus_hold = 0
    attempt = 0
    txeq_seen = False
    rxeq_seen = False
    while True:
        await RisingEdge(dut.phy_pclk)
        await ReadOnly()
        rate = int(dut.phy_rate.value)
        txeq = int(dut.phy_txeq_ctrl.value)
        rxeq = int(dut.phy_rxeq_ctrl.value)
        await writable()
        if rate != previous_rate:
            phystatus_hold = 2
            txeq_seen = False
            rxeq_seen = False
            if rate == 2:
                attempt += 1
        dut.phy_phystatus.value = int(phystatus_hold > 0)
        if phystatus_hold:
            phystatus_hold -= 1
        dut.phy_txeq_done.value = int(txeq != 0 and not txeq_seen)
        if rxeq == 2 and not rxeq_seen:
            dut.phy_rxeq_done.value = 1
            # First Gen3 attempt deliberately omits AdaptDone.  The second
            # attempt supplies both completion indications.
            dut.phy_rxeq_adapt_done.value = int(attempt >= 2)
        else:
            dut.phy_rxeq_done.value = 0
            dut.phy_rxeq_adapt_done.value = 0
        txeq_seen = txeq != 0
        rxeq_seen = rxeq != 0
        previous_rate = rate


async def drive_fallback_gen1_partner(dut):
    """Independent Gen1 Partner FSM used only for fallback/retry coverage."""
    while True:
        await tick(dut)
        if int(dut.fallback_sticky.value) and int(dut.phy_rate.value) == 0:
            break
    await wait_state(dut, RECOVERY_RCVRLOCK)
    await send_ts(dut, 1, 16, link=0, lane=0, rate=0x02)
    await wait_state(dut, RECOVERY_RCVRCFG)
    await send_ts(dut, 2, 16, link=0, lane=0, rate=0x02)
    await wait_state(dut, RECOVERY_IDLE)
    await send_idle(dut, 8)


async def capture_gen3_training_prefix(dut, words=8):
    """Capture the first valid Gen3 PIPE words independently of the partner RX."""
    captured = []
    while len(captured) < words:
        await RisingEdge(dut.phy_pclk)
        await ReadOnly()
        if int(dut.phy_rate.value) == 2 and int(dut.phy_txdata_valid.value):
            captured.append((
                int(dut.phy_txdata.value),
                int(dut.phy_txstart_block.value),
                int(dut.phy_txsync_header.value),
            ))
    return captured


@cocotb.test()
async def production_ltssm_gen1_to_gen3_eq_closed_loop(dut):
    global partner_lfsr
    partner_lfsr = 0xFFFF
    cocotb.start_soon(Clock(dut.phy_pclk, 8, units="ns").start())
    cocotb.start_soon(Clock(dut.core_clk, 10, units="ns").start())
    for name in (
        "pipe_rst_n", "core_rst_n", "phy_rxdata", "phy_rxdatak",
        "phy_rxdata_valid", "phy_rxstart_block", "phy_rxsync_header",
        "phy_rxvalid", "phy_phystatus", "phy_rxelecidle", "phy_rxstatus",
        "phy_cdr_lost", "phy_txeq_done", "phy_rxeq_adapt_done",
        "phy_rxeq_done",
        "retrain_pulse", "gen3_partner_enable",
    ):
        getattr(dut, name).value = 0
    dut.phy_rxelecidle.value = 1
    dut.target_speed.value = 2
    await tick(dut, 3)
    await writable()
    dut.pipe_rst_n.value = 1
    dut.core_rst_n.value = 1

    await train_gen1_to_l0(dut)
    assert int(dut.link_up.value) == 1
    dut.gen3_partner_enable.value = 1
    cocotb.start_soon(phy_command_responder(dut))
    prefix_task = cocotb.start_soon(capture_gen3_training_prefix(dut))

    dut.retrain_pulse.value = 1
    await RisingEdge(dut.core_clk)
    await writable()
    dut.retrain_pulse.value = 0

    await wait_state(dut, RECOVERY_RCVRLOCK)
    await send_ts(dut, 1, 8, link=0, lane=0, rate=0x8E)
    await wait_state(dut, RECOVERY_RCVRCFG)
    await send_ts(dut, 2, 8, link=0, lane=0, rate=0x8E)
    await wait_state(dut, RECOVERY_SPEED)
    assert int(dut.as_cdr_hold_req.value) == 1

    phases = []
    saw_ts1 = saw_ts2 = False
    saw_eq_done = False
    saw_recovery_idle = False
    for _ in range(4000):
        await tick(dut)
        phase = int(dut.eq_phase.value)
        if phase <= 4 and phase not in phases:
            phases.append(phase)
        saw_ts1 |= bool(int(dut.os_ts1_valid.value))
        saw_ts2 |= bool(int(dut.os_ts2_valid.value))
        saw_eq_done |= bool(int(dut.eq_done.value))
        saw_recovery_idle |= int(dut.ltssm_state.value) == RECOVERY_IDLE
        if saw_eq_done and saw_ts2 and saw_recovery_idle:
            break
        await writable()

    assert int(dut.phy_rate.value) == 2
    assert saw_ts1 and saw_ts2, (
        f"Gen3 TS不完整: ts1={saw_ts1} ts2={saw_ts2} "
        f"ltssm={int(dut.ltssm_state.value)} speed={int(dut.speed_state.value)} "
        f"cmd={int(dut.phy_rate_cmd.value)} active={int(dut.active_rate.value)} "
        f"reinit={int(dut.reinitialize_gen1.value)} done={int(dut.recovery_speed_done.value)} "
        f"contract={int(dut.rate_contract_state.value)}"
        f" partner={int(dut.partner_source_active.value)}"
    )
    assert saw_recovery_idle
    assert int(dut.as_cdr_hold_req.value) == 0
    assert int(dut.ts_reject.value) == 0
    assert int(dut.fallback_sticky.value) == 0, (
        f"fallback sticky speed={int(dut.speed_state.value)} "
        f"active={int(dut.active_rate.value)} ts_accept={int(dut.ts_accept.value)} "
        f"ts_reject={int(dut.ts_reject.value)} "
        f"partner={int(dut.partner_source_active.value)} "
        f"ltssm={int(dut.ltssm_state.value)}"
    )
    assert int(dut.eq_failed.value) == 0
    assert saw_eq_done
    assert phases == [0, 1, 2, 3, 4]
    assert int(dut.negotiated_speed.value) == 2
    prefix = await prefix_task
    # Independent checker: no TX/RX partner signal is used for this verdict.
    assert_training_prefix(prefix)


@cocotb.test()
async def partner_initiated_speed_change_closes_recovery_and_eq(dut):
    """Root Port的TS1 Speed Change必须直接启动生产K13控制器。"""
    global partner_lfsr
    partner_lfsr = 0xFFFF
    cocotb.start_soon(Clock(dut.phy_pclk, 8, units="ns").start())
    cocotb.start_soon(Clock(dut.core_clk, 10, units="ns").start())
    for name in (
        "pipe_rst_n", "core_rst_n", "phy_rxdata", "phy_rxdatak",
        "phy_rxdata_valid", "phy_rxstart_block", "phy_rxsync_header",
        "phy_rxvalid", "phy_phystatus", "phy_rxelecidle", "phy_rxstatus",
        "phy_cdr_lost", "phy_txeq_done", "phy_rxeq_adapt_done",
        "phy_rxeq_done",
        "retrain_pulse", "gen3_partner_enable",
    ):
        getattr(dut, name).value = 0
    dut.phy_rxelecidle.value = 1
    dut.target_speed.value = 2
    await tick(dut, 3)
    await writable()
    dut.pipe_rst_n.value = 1
    dut.core_rst_n.value = 1

    await train_gen1_to_l0(dut)
    assert int(dut.link_up.value) == 1
    dut.gen3_partner_enable.value = 1
    cocotb.start_soon(phy_command_responder(dut))

    # 0x8e与实板Root Port取证一致：Gen1/2/3能力位加Speed Change位。
    await send_ts(dut, 1, 1, link=0, lane=0, rate=0x8E)
    await wait_state(dut, RECOVERY_RCVRLOCK)
    assert int(dut.recovery_active.value) == 1
    await send_ts(dut, 1, 8, link=0, lane=0, rate=0x8E)
    await wait_state(dut, RECOVERY_RCVRCFG)
    await send_ts(dut, 2, 8, link=0, lane=0, rate=0x8E)
    await wait_state(dut, RECOVERY_SPEED)
    assert int(dut.as_cdr_hold_req.value) == 1

    phases = []
    saw_ts1 = saw_ts2 = saw_eq_done = saw_recovery_idle = False
    for _ in range(4000):
        await tick(dut)
        phase = int(dut.eq_phase.value)
        if phase <= 4 and phase not in phases:
            phases.append(phase)
        saw_ts1 |= bool(int(dut.os_ts1_valid.value))
        saw_ts2 |= bool(int(dut.os_ts2_valid.value))
        saw_eq_done |= bool(int(dut.eq_done.value))
        saw_recovery_idle |= int(dut.ltssm_state.value) == RECOVERY_IDLE
        if saw_eq_done and saw_ts2 and saw_recovery_idle:
            break
        await writable()

    assert int(dut.phy_rate.value) == 2
    assert saw_ts1 and saw_ts2
    assert saw_recovery_idle and saw_eq_done
    assert int(dut.as_cdr_hold_req.value) == 0
    assert phases == [0, 1, 2, 3, 4]
    assert int(dut.ts_reject.value) == 0
    assert int(dut.fallback_sticky.value) == 0
    assert int(dut.eq_failed.value) == 0
    assert int(dut.negotiated_speed.value) == 2


@cocotb.test()
async def production_gen3_failure_fallback_then_retry(dut):
    """Gate C: first Gen3 RXEQ failure must recover to Gen1, then retry Gen3."""
    global partner_lfsr
    partner_lfsr = 0xFFFF
    cocotb.start_soon(Clock(dut.phy_pclk, 8, units="ns").start())
    cocotb.start_soon(Clock(dut.core_clk, 10, units="ns").start())
    for name in (
        "pipe_rst_n", "core_rst_n", "phy_rxdata", "phy_rxdatak",
        "phy_rxdata_valid", "phy_rxstart_block", "phy_rxsync_header",
        "phy_rxvalid", "phy_phystatus", "phy_rxelecidle", "phy_rxstatus",
        "phy_cdr_lost", "phy_txeq_done", "phy_rxeq_adapt_done",
        "phy_rxeq_done", "retrain_pulse", "gen3_partner_enable",
    ):
        getattr(dut, name).value = 0
    dut.phy_rxelecidle.value = 1
    dut.target_speed.value = 2
    await tick(dut, 3)
    await writable()
    dut.pipe_rst_n.value = 1
    dut.core_rst_n.value = 1

    await train_gen1_to_l0(dut)
    assert int(dut.link_up.value) == 1
    cocotb.start_soon(phy_command_responder_with_one_rxeq_failure(dut))
    cocotb.start_soon(drive_fallback_gen1_partner(dut))
    dut.gen3_partner_enable.value = 1

    dut.retrain_pulse.value = 1
    await RisingEdge(dut.core_clk)
    await writable()
    dut.retrain_pulse.value = 0

    await wait_state(dut, RECOVERY_RCVRLOCK)
    await send_ts(dut, 1, 8, link=0, lane=0, rate=0x8E)
    await wait_state(dut, RECOVERY_RCVRCFG)
    await send_ts(dut, 2, 8, link=0, lane=0, rate=0x8E)
    await wait_state(dut, RECOVERY_SPEED)

    # The independent Gen1 Partner FSM takes over after the controller's
    # first RXEQ done-only failure and closes the fallback Recovery exchange.
    await wait_state(dut, L0, timeout=20000)
    assert int(dut.fallback_sticky.value) == 1
    assert int(dut.phy_rate.value) == 0
    assert int(dut.active_rate.value) == 0
    assert int(dut.negotiated_speed.value) == 0

    # A fresh directed retrain is now issued from a real Gen1 L0 boundary.
    dut.retrain_pulse.value = 1
    await RisingEdge(dut.core_clk)
    await writable()
    dut.retrain_pulse.value = 0
    await wait_state(dut, RECOVERY_RCVRLOCK)
    await send_ts(dut, 1, 8, link=0, lane=0, rate=0x8E)
    await wait_state(dut, RECOVERY_RCVRCFG)
    await send_ts(dut, 2, 8, link=0, lane=0, rate=0x8E)
    await wait_state(dut, RECOVERY_SPEED)

    # The current production LTSSM's Gen3 Recovery.Idle boundary is the
    # completed Gate-C target here; Gen3 L0 data-stream/SDS is the subsequent
    # protocol-freeze gate and is intentionally not claimed by this test.
    for _ in range(8000):
        await tick(dut)
        if (int(dut.eq_done.value) and
                int(dut.ltssm_state.value) == RECOVERY_IDLE and
                int(dut.phy_rate.value) == 2):
            break
    assert int(dut.phy_rate.value) == 2
    assert int(dut.active_rate.value) == 2
    assert int(dut.negotiated_speed.value) == 2
    assert int(dut.ltssm_state.value) == RECOVERY_IDLE
    assert int(dut.eq_done.value) == 1
    assert int(dut.eq_failed.value) == 0
