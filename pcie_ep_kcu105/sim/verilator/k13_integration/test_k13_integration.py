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
    dbg_first = True
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
        # 调试: 每次 send_ts 第一个 TS 第一个 symbol pair 都打一行, 不管是否有 TS 检出
        if dbg_first and scramble_disable and pos == 0:
            dbg_first = False
            print(f"  [DBG-send] pos=0 sym0=0x{symbols[0]:02x} "
                  f"ltssm={int(dut.ltssm_state.value)} "
                  f"phy_rxvalid={int(dut.phy_rxvalid.value)} "
                  f"phy_rxdata=0x{int(dut.phy_rxdata.value):08x} "
                  f"os_dbg_act={int(dut.os_dbg_active.value)} "
                  f"dbg_active_gen3={int(dut.dut_dbg_active_gen3.value) if hasattr(dut, 'dut_dbg_active_gen3') else '?'}")
        # Probe: 诊断 os_rx 是否处理数据 (仅在 rate change 期间)
        if scramble_disable:
            ts1 = int(dut.os_ts1_valid.value)
            ts2 = int(dut.os_ts2_valid.value)
            mal = int(dut.os_malformed.value)
            if ts1 or ts2 or mal:
                # os_link_is_pad inferred: link_number==K_PAD(0xF7) => pad
                os_link = int(dut.os_link_number.value)
                os_lane = int(dut.os_lane_number.value)
                print(f"  [OSPROBE] pos={pos} sym0=0x{symbols[pos]:02x} "
                      f"sym1=0x{symbols[pos+1]:02x} datak={datak:#x} "
                      f"ltssm={int(dut.ltssm_state.value)} "
                      f"ts1={ts1} ts2={ts2} mal={mal} "
                      f"os_link={os_link}({'PAD' if os_link==0xF7 else 'NUM'}) "
                      f"os_lane={os_lane}({'PAD' if os_lane==0xF7 else 'NUM'}) "
                      f"dbg_act={int(dut.os_dbg_active.value)} "
                      f"dbg_wi={int(dut.os_dbg_word_index.value)}")
    dut.phy_rxdata.value = 0
    dut.phy_rxdatak.value = 0
    dut.phy_rxdata_valid.value = 0
    dut.phy_rxvalid.value = 0


async def send_ts(dut, kind, count, link=PAD, lane=PAD, rate=0x02):
    for _ in range(count):
        symbols, isk = ts_symbols(kind, link, lane, rate)
        await drive_symbols(dut, symbols, isk)


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
    # 注意：responder 必须监听 phy_rate_cmd (raw) 而非 phy_rate (LTSSM 视图)
    # 在新 contract 架构下, phy_rate = active_rate 仅在 completion 后变,
    # 若用它当触发源, contract 永远等不到 phystatus -> 死锁
    # phystatus 脉冲必须 ≥3 cycle: contract 用 2-stage 延迟线检测上升沿
    # (phystatus_rising = phy_phystatus & ~phystatus_seen_prev_r)
    # 1 cycle 脉冲会被延迟线"漏掉"——上升沿检测需要至少 2 cycle 持续高
    previous_rate_cmd = int(dut.phy_rate_cmd.value)
    phystatus_cycles_left = 0
    txeq_seen = False
    rxeq_seen = False
    while True:
        await RisingEdge(dut.phy_pclk)
        await ReadOnly()
        rate_cmd = int(dut.phy_rate_cmd.value)
        txeq = int(dut.phy_txeq_ctrl.value)
        rxeq = int(dut.phy_rxeq_ctrl.value)
        if rate_cmd != previous_rate_cmd:
            phystatus_cycles_left = 4   # 4 cycle 脉冲, 覆盖 2-stage 延迟线
        else:
            phystatus_cycles_left = max(0, phystatus_cycles_left - 1)
        previous_rate_cmd = rate_cmd
        await writable()
        dut.phy_phystatus.value = int(phystatus_cycles_left > 0)
        dut.phy_txeq_done.value = int(txeq != 0 and not txeq_seen)
        dut.phy_rxeq_done.value = int(rxeq == 2 and not rxeq_seen)
        dut.phy_rxeq_adapt_done.value = int(rxeq == 2 and not rxeq_seen)
        txeq_seen = txeq != 0
        rxeq_seen = rxeq != 0


async def capture_gen3_training_prefix(dut, words=8):
    """Capture the first valid Gen3 PIPE words independently of the partner RX.
    使用 phy_rate_cmd (raw) 而非 phy_rate (LTSSM 视图) — 早一拍捕获以观察
    contract 在 completion 前就开始驱动 raw 命令的不变量。
    """
    captured = []
    while len(captured) < words:
        await RisingEdge(dut.phy_pclk)
        await ReadOnly()
        if int(dut.phy_rate_cmd.value) == 2 and int(dut.phy_txdata_valid.value):
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
    # 诊断：retrain 是否通过 CDC 传到 speed_ctrl
    for _ in range(40):
        await tick(dut)
        s = int(dut.speed_state.value)
        if s != 0:
            print(f"  [DBG] speed_state={s} recovery_active={int(dut.recovery_active.value)} "
                  f"ltssm={int(dut.ltssm_state.value)} "
                  f"txeq_ctrl={int(dut.phy_txeq_ctrl.value):#x} "
                  f"txeq_done={int(dut.phy_txeq_done.value)} "
                  f"fallback_sticky={int(dut.fallback_sticky.value)}")
            if s == 1:  # QUIESCE
                prev_cs = -1
                for j in range(500):
                    await tick(dut)
                    s2 = int(dut.speed_state.value)
                    cs = int(dut.rate_contract_state.value)
                    rc = int(dut.phy_rate_cmd.value)
                    ps = int(dut.phy_phystatus.value)
                    cd = int(dut.rate_contract_done.value)
                    cf = int(dut.rate_contract_failed.value)
                    if cs != prev_cs or j % 20 == 0 or cd or cf:
                        print(f"  [DBG2] j={j} speed_state={s2} "
                              f"contract_state=0x{cs:x} rate_cmd={rc} phystatus={ps} "
                              f"contract_done={cd} contract_failed={cf} "
                              f"recovery_active={int(dut.recovery_active.value)} "
                              f"ltssm={int(dut.ltssm_state.value)} "
                              f"ltssm_speed_ready={int(dut.recovery_speed_ready.value)} "
                              f"txeq_ctrl={int(dut.phy_txeq_ctrl.value):#x} "
                              f"txeq_done={int(dut.phy_txeq_done.value)} "
                              f"fallback_sticky={int(dut.fallback_sticky.value)}")
                        prev_cs = cs
                    if cs == 0xF or s2 == 0:  # ERROR or back to L0
                        break
                break

    await wait_state(dut, RECOVERY_RCVRLOCK)
    # 关键: 在发 rate change TS1s 之前, 强制 phy_rxvalid=0 多拍,
    # 让 Gen1 os_rx 的 stuck active=1 (从 initial training 残留) 走
    # !in_valid 路径 → malformed=1, active=0, 否则新 TS1 会被当作
    # 旧 TS 的延续处理 → 全 malformed → os_ts1_valid 永不置位
    for _ in range(8):
        dut.phy_rxdata.value = 0
        dut.phy_rxdatak.value = 0
        dut.phy_rxdata_valid.value = 0
        dut.phy_rxvalid.value = 0
        dut.phy_rxelecidle.value = 0
        await tick(dut)
        await writable()
    print(f"  [DBG3] LTSSM in RCVRLOCK, sending 8 TS1s with rate=0x8E")
    print(f"  [DBG3-pre] link_number={int(dut.dut_link_number.value)} "
          f"os_link={int(dut.os_link_number.value)} "
          f"phy_rxvalid={int(dut.phy_rxvalid.value)} "
          f"phy_rxdata_valid={int(dut.phy_rxdata_valid.value)} "
          f"rxelecidle={int(dut.phy_rxelecidle.value)} "
          f"rxstatus={int(dut.phy_rxstatus.value)}")
    await send_ts(dut, 1, 8, link=0, lane=0, rate=0x8E)
    print(f"  [DBG3-post] phy_rxvalid={int(dut.phy_rxvalid.value)} "
          f"phy_rxdata_valid={int(dut.phy_rxdata_valid.value)} "
          f"rxelecidle={int(dut.phy_rxelecidle.value)}")
    for _ in range(20):
        await tick(dut)
        print(f"  [DBG3-loop] ltssm={int(dut.ltssm_state.value)} "
              f"ts1={int(dut.os_ts1_valid.value)} ts2={int(dut.os_ts2_valid.value)} "
              f"malformed={int(dut.os_malformed.value)} "
              f"rx_ts_count={int(dut.rx_ts_count.value)} "
              f"ts_reject={int(dut.ts_reject.value)} "
              f"phy_rxvalid={int(dut.phy_rxvalid.value)}")
    await wait_state(dut, RECOVERY_RCVRCFG)
    await send_ts(dut, 2, 8, link=0, lane=0, rate=0x8E)
    # 诊断: RCVRCFG 收 TS2 时 LTSSM 内部状态——查 rx_ts_count / recovery_speed_changed / speed_retrain_active
    # 同时检测 as_cdr_hold_req 在 RECOVERY_SPEED 期间是否被拉高
    saw_cdr_hold = False
    saw_recovery_speed = False
    for _ in range(60):
        await tick(dut)
        ls = int(dut.ltssm_state.value)
        if ls == RECOVERY_SPEED:
            saw_recovery_speed = True
            if int(dut.as_cdr_hold_req.value) == 1:
                saw_cdr_hold = True
        print(f"  [DBG3-ts2] ltssm={ls} "
              f"ts2={int(dut.os_ts2_valid.value)} "
              f"rx_ts_count={int(dut.rx_ts_count.value)} "
              f"recovery_speed_changed={int(dut.recovery_speed_changed.value)} "
              f"speed_retrain_active={int(dut.speed_retrain_active.value)} "
              f"as_cdr_hold_req={int(dut.as_cdr_hold_req.value)} "
              f"link_number={int(dut.dut_link_number.value)} "
              f"os_link={int(dut.os_link_number.value)} os_lane={int(dut.os_lane_number.value)}")
    assert saw_recovery_speed, (
        f"LTSSM 根本没进 RECOVERY_SPEED; 最终 ltssm={int(dut.ltssm_state.value)} "
        f"recovery_speed_changed={int(dut.recovery_speed_changed.value)}"
    )
    assert saw_cdr_hold, "as_cdr_hold_req 在 RECOVERY_SPEED 期间未被拉高"

    # RECOVERY_SPEED 完成后, LTSSM 退出到 RCVRLOCK (11).
    # RCVRLOCK/RCVRCFG 期间 partner_enable=0, 必须由 test 侧用 phy_rxdata 发 TS1/TS2
    # 驱动 LTSSM 经过 RCVRCFG (12) -> RECOVERY_IDLE (13) -> L0 (10).
    # 这是 PCIe spec 规定的 Gen3 速率切换第二步 (RCVRLOCK->RCVRCFG->Recovery.Idle).
    # partner 只在 RCVLOCK 期间补 IDL/EIEOS, 不发 TS——所以 test 主导 TS 流.
    await wait_state(dut, RECOVERY_RCVRLOCK)
    # 关键: 强制 phy_rxvalid=0 多拍, 让 Gen1 os_rx 从 RECOVERY_SPEED 期间
    # 被 partner_data 喂过的残留状态走 !in_valid -> active=0 复位,
    # 否则新 TS1 会被当作旧 TS 的延续处理 -> 全 malformed
    for _ in range(8):
        dut.phy_rxdata.value = 0
        dut.phy_rxdatak.value = 0
        dut.phy_rxdata_valid.value = 0
        dut.phy_rxvalid.value = 0
        dut.phy_rxelecidle.value = 0
        await tick(dut)
        await writable()
    print(f"  [DBG4-pre] os_dbg_active={int(dut.os_dbg_active.value)} "
          f"os_dbg_wi={int(dut.os_dbg_word_index.value)} "
          f"phy_rxvalid={int(dut.phy_rxvalid.value)}")
    await send_ts(dut, 1, 8, link=0, lane=0, rate=0x8E)
    # 诊断: 确认 Gen1 os_rx 是否在 RCVRLOCK 期间收到 TS1
    for _ in range(20):
        await tick(dut)
        print(f"  [DBG4-loop] ltssm={int(dut.ltssm_state.value)} "
              f"ts1={int(dut.os_ts1_valid.value)} mal={int(dut.os_malformed.value)} "
              f"rx_ts_count={int(dut.rx_ts_count.value)} "
              f"os_dbg_act={int(dut.os_dbg_active.value)} "
              f"os_dbg_wi={int(dut.os_dbg_word_index.value)}")
    await wait_state(dut, RECOVERY_RCVRCFG)
    await send_ts(dut, 2, 8, link=0, lane=0, rate=0x8E)
    await wait_state(dut, RECOVERY_IDLE)

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

    assert int(dut.phy_rate.value) == 2, (
        f"phy_rate stuck at {int(dut.phy_rate.value)}; "
        f"active_rate={int(dut.k13_active_rate.value)} "
        f"rate_cmd={int(dut.phy_rate_cmd.value)} "
        f"contract_state=0x{int(dut.rate_contract_state.value):x} "
        f"contract_done={int(dut.rate_contract_done.value)} "
        f"contract_failed={int(dut.rate_contract_failed.value)} "
        f"speed_state={int(dut.speed_state.value)} "
        f"ltssm={int(dut.ltssm_state.value)}"
    )
    assert saw_ts1 and saw_ts2, (
        f"Gen3 TS不完整: ts1={saw_ts1} ts2={saw_ts2} "
        f"ltssm={int(dut.ltssm_state.value)} speed={int(dut.speed_state.value)}"
    )
    assert saw_recovery_idle
    assert int(dut.as_cdr_hold_req.value) == 0
    assert int(dut.ts_reject.value) == 0
    assert int(dut.fallback_sticky.value) == 0
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
    # 快速过场的 RECOVERY_SPEED 必须用窗口检测——等固定状态会 timeout
    saw_cdr_hold = False
    saw_recovery_speed = False
    for _ in range(60):
        await tick(dut)
        ls = int(dut.ltssm_state.value)
        if ls == RECOVERY_SPEED:
            saw_recovery_speed = True
            if int(dut.as_cdr_hold_req.value) == 1:
                saw_cdr_hold = True
    assert saw_recovery_speed, f"LTSSM 根本没进 RECOVERY_SPEED; 最终 ltssm={int(dut.ltssm_state.value)}"
    assert saw_cdr_hold, "as_cdr_hold_req 在 RECOVERY_SPEED 期间未被拉高"

    # RECOVERY_SPEED 退出后: RCVRLOCK -> RCVRCFG -> RECOVERY_IDLE
    # RCVRLOCK/RCVRCFG 期间 partner_enable=0, 必须由 test 侧发 TS1/TS2
    await wait_state(dut, RECOVERY_RCVRLOCK)
    await send_ts(dut, 1, 8, link=0, lane=0, rate=0x8E)
    await wait_state(dut, RECOVERY_RCVRCFG)
    await send_ts(dut, 2, 8, link=0, lane=0, rate=0x8E)
    await wait_state(dut, RECOVERY_IDLE)

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
