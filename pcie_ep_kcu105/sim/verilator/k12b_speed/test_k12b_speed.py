"""
K12b Recovery.Speed 控制器单元仿真 - 新接口

对应 pcie_recovery_speed_ctrl.sv 重构后的 8 态 FSM：
  0 L0                稳态
  1 QUIESCE           等 ltssm_speed_ready
  2 RATE_REQUEST      驱动 rate_req_valid/target，等 rate_req_ready
  3 RATE_WAIT         已被 contract 接受，等 rate_op_done/failed
  4 RECOVERY_IDLE     物理切速完成，等 peer TS
  5 FALLBACK_REQUEST  fallback 路径：发 Gen1 请求
  6 FALLBACK_WAIT     等 Gen1 物理完成
  7 FALLBACK_IDLE     等对端接受 Gen1

接口变化（vs 旧版）：
  - 移除：phy_phystatus 输入、phy_rate 输出、phy_txelecidle 输出
  - 新增：rate_req_valid/target 输出、rate_req_ready/rate_op_done/rate_op_failed 输入
  - raw phy_rate/phy_txelecidle 现在由 pcie_phy_rate_contract 拥有
    (本测试只覆盖 speed ctrl 语义层，contract 行为见 k13_rate_contract)
"""
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


# 新状态编码（必须与 pcie_recovery_speed_ctrl.sv 一致）
ST_L0               = 0
ST_QUIESCE          = 1
ST_RATE_REQUEST     = 2
ST_RATE_WAIT        = 3
ST_RECOVERY_IDLE    = 4
ST_FALLBACK_REQUEST = 5
ST_FALLBACK_WAIT    = 6
ST_FALLBACK_IDLE    = 7


async def reset_dut(dut):
    """应用复位；新接口下 rate_req_ready/op_done/op_failed 由 contract 驱动。"""
    dut.rst_n.value = 0
    dut.link_up.value = 0
    dut.retrain_valid.value = 0
    dut.retrain_target_speed.value = 0
    dut.ltssm_speed_ready.value = 1
    dut.phy_cdr_lost.value = 0
    dut.peer_speed_ok.value = 0
    dut.peer_speed_reject.value = 0
    # contract back-pressure：稳态高（contract 在 RC_RDY2_STABLE 时拉高）
    dut.rate_req_ready.value = 1
    dut.rate_op_done.value = 0
    dut.rate_op_failed.value = 0
    dut.active_rate.value = 0
    await Timer(3, units="ns")
    dut.rst_n.value = 1
    dut.link_up.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk)


async def issue_retrain(dut, speed):
    dut.retrain_target_speed.value = speed
    dut.retrain_valid.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    dut.retrain_valid.value = 0


async def advance(dut, count=1):
    for _ in range(count):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")


async def wait_state(dut, expected, max_cycles=200):
    for _ in range(max_cycles):
        if int(dut.state.value) == expected:
            return
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
    raise AssertionError(
        f"等待状态 {expected} 超时，当前 {int(dut.state.value)}"
    )


# ----------------------------------------------------------------------
# Test 1: Gen1 → Gen3 正常握手
# ----------------------------------------------------------------------
@cocotb.test()
async def normal_gen1_to_gen3_speed_handshake(dut):
    """语义层: retrain(Gen3) → quiesce → rate_req → contract ack → done → peer ok"""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    await issue_retrain(dut, 2)
    assert int(dut.retrain_accept.value) == 1
    assert int(dut.state.value) == ST_QUIESCE
    assert int(dut.traffic_quiesce.value) == 1
    # ltssm_speed_ready=1，1 拍后进 RATE_REQUEST
    await advance(dut)
    assert int(dut.state.value) == ST_RATE_REQUEST
    # RATE_REQUEST 期间 rate_req_valid 拉高、target=Gen3
    assert int(dut.rate_req_valid.value) == 1
    assert int(dut.rate_req_target.value) == 2
    # contract 接受（rate_req_ready=1，1 拍后进 RATE_WAIT）
    await advance(dut)
    assert int(dut.state.value) == ST_RATE_WAIT
    # 完成后 contract 拉高 rate_op_done，1 拍后进 RECOVERY_IDLE
    dut.rate_op_done.value = 1
    await advance(dut)
    dut.rate_op_done.value = 0
    assert int(dut.state.value) == ST_RECOVERY_IDLE
    # Contract has committed the physical rate; expose that semantic result
    # before the partner TS is accepted.
    dut.active_rate.value = 2
    dut.peer_speed_ok.value = 1
    await advance(dut)
    dut.peer_speed_ok.value = 0
    assert int(dut.state.value) == ST_L0
    assert int(dut.negotiated_speed.value) == 2
    assert int(dut.traffic_quiesce.value) == 0


# ----------------------------------------------------------------------
# Test 2: rate 请求必须等 ltssm_speed_ready
# ----------------------------------------------------------------------
@cocotb.test()
async def rate_waits_for_ltssm_speed_ready(dut):
    """ltssm_speed_ready=0 时 speed ctrl 不能发 rate request。"""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    dut.ltssm_speed_ready.value = 0
    await issue_retrain(dut, 2)
    assert int(dut.state.value) == ST_QUIESCE
    await advance(dut, 2)
    assert int(dut.state.value) == ST_QUIESCE
    # 关键不变量: rate_req_valid 必须仍为 0
    assert int(dut.rate_req_valid.value) == 0
    assert int(dut.traffic_quiesce.value) == 1
    # ltssm 准备好，1 拍后进 RATE_REQUEST
    dut.ltssm_speed_ready.value = 1
    await advance(dut)
    assert int(dut.state.value) == ST_RATE_REQUEST
    assert int(dut.rate_req_valid.value) == 1
    assert int(dut.rate_req_target.value) == 2


# ----------------------------------------------------------------------
# Test 3: contract back-pressure (rate_req_ready=0) → 停在 RATE_REQUEST
# ----------------------------------------------------------------------
@cocotb.test()
async def contract_back_pressure_holds_at_rate_request(dut):
    """contract 未拉高 rate_req_ready 时, speed ctrl 在 RATE_REQUEST 等待
    (在 SPEED_TIMEOUT_CYCLES 内)。"""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    dut.rate_req_ready.value = 0  # contract busy
    await issue_retrain(dut, 2)
    assert int(dut.state.value) == ST_QUIESCE
    await advance(dut)
    assert int(dut.state.value) == ST_RATE_REQUEST
    # rate_req_valid 应当已拉高
    assert int(dut.rate_req_valid.value) == 1
    assert int(dut.rate_req_target.value) == 2
    # 保持 back-pressure 2 拍（< TIMEOUT_LIMIT=4）—— 仍在 RATE_REQUEST
    await advance(dut, 2)
    assert int(dut.state.value) == ST_RATE_REQUEST
    assert int(dut.rate_req_valid.value) == 1
    # contract 释放 back-pressure
    dut.rate_req_ready.value = 1
    await advance(dut)
    assert int(dut.state.value) == ST_RATE_WAIT


# ----------------------------------------------------------------------
# Test 4: contract rate_op_failed → sticky + fallback
# ----------------------------------------------------------------------
@cocotb.test()
async def contract_failure_falls_back_to_gen1(dut):
    """rate_op_failed 触发 speed_timeout_sticky + fallback_taken_sticky。"""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    await issue_retrain(dut, 2)
    await advance(dut, 2)
    assert int(dut.state.value) == ST_RATE_WAIT
    # contract 报告失败
    dut.rate_op_failed.value = 1
    await advance(dut)
    dut.rate_op_failed.value = 0
    # 1 拍后进入 FALLBACK_REQUEST
    assert int(dut.state.value) == ST_FALLBACK_REQUEST
    # FALLBACK_REQUEST 期间 rate_req_valid 拉高、target=Gen1 (2'b00)
    assert int(dut.rate_req_valid.value) == 1
    assert int(dut.rate_req_target.value) == 0
    await advance(dut)
    assert int(dut.state.value) == ST_FALLBACK_WAIT
    # contract 接受 fallback，1 拍后进 FALLBACK_WAIT
    dut.rate_op_done.value = 1
    await advance(dut)
    dut.rate_op_done.value = 0
    assert int(dut.state.value) == ST_FALLBACK_IDLE
    assert int(dut.speed_timeout_sticky.value) == 1
    assert int(dut.fallback_taken_sticky.value) == 1
    # 等 peer_speed_ok，回 L0
    dut.peer_speed_ok.value = 1
    await advance(dut)
    dut.peer_speed_ok.value = 0
    assert int(dut.state.value) == ST_L0
    assert int(dut.negotiated_speed.value) == 0


# ----------------------------------------------------------------------
# Test 5: 内部 timeout (SPEED_TIMEOUT_CYCLES=4) → sticky + fallback
# ----------------------------------------------------------------------
@cocotb.test()
async def internal_speed_timeout_falls_back_to_gen1(dut):
    """RATE_REQUEST 内部 4-cycle timeout → FALLBACK_REQUEST。"""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    # Makefile 编译时 -GSPEED_TIMEOUT_CYCLES=4
    await issue_retrain(dut, 2)
    # issue_retrain 后 state=QUIESCE (L0 + accept → QUIESCE 1 cycle)
    assert int(dut.state.value) == ST_QUIESCE
    # cycle 1: QUIESCE → RATE_REQUEST (ltssm_speed_ready=1)
    await advance(dut)
    assert int(dut.state.value) == ST_RATE_REQUEST
    # rate_req_valid 应当为 1 但 contract 还没 back-pressure ack
    assert int(dut.rate_req_valid.value) == 1
    # rate_req_ready=1 (reset_dut 默认)，1 拍后 → RATE_WAIT
    # cycle 2: RATE_REQUEST → RATE_WAIT (timeout_count reset)
    # cycle 3-5: RATE_WAIT 计数 timeout (4 cycles)
    # cycle 6: RATE_WAIT → FALLBACK_REQUEST
    await advance(dut, 5)
    assert int(dut.state.value) == ST_FALLBACK_REQUEST
    assert int(dut.speed_timeout_sticky.value) == 1
    assert int(dut.fallback_taken_sticky.value) == 1
    # FALLBACK_REQUEST 看 rate_req_ready=1 → FALLBACK_WAIT
    await advance(dut)
    assert int(dut.state.value) == ST_FALLBACK_WAIT
    # FALLBACK_WAIT 看 rate_op_done=1 → FALLBACK_IDLE
    dut.rate_op_done.value = 1
    await advance(dut)
    dut.rate_op_done.value = 0
    assert int(dut.state.value) == ST_FALLBACK_IDLE
    dut.peer_speed_ok.value = 1
    await advance(dut)
    dut.peer_speed_ok.value = 0
    assert int(dut.state.value) == ST_L0
    assert int(dut.negotiated_speed.value) == 0


# ----------------------------------------------------------------------
# Test 6: peer_speed_reject 在 RECOVERY_IDLE → fallback
# ----------------------------------------------------------------------
@cocotb.test()
async def peer_reject_falls_back_to_gen1(dut):
    """对端在 TS 处 reject → fallback。"""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    await issue_retrain(dut, 2)
    await advance(dut, 2)
    assert int(dut.state.value) == ST_RATE_WAIT
    dut.rate_op_done.value = 1
    await advance(dut)
    dut.rate_op_done.value = 0
    assert int(dut.state.value) == ST_RECOVERY_IDLE
    dut.peer_speed_reject.value = 1
    await advance(dut)
    dut.peer_speed_reject.value = 0
    assert int(dut.state.value) == ST_FALLBACK_REQUEST
    assert int(dut.peer_reject_sticky.value) == 1
    assert int(dut.fallback_taken_sticky.value) == 1
    await advance(dut)
    dut.rate_op_done.value = 1
    await advance(dut)
    dut.rate_op_done.value = 0
    assert int(dut.state.value) == ST_FALLBACK_IDLE
    dut.peer_speed_ok.value = 1
    await advance(dut)
    dut.peer_speed_ok.value = 0
    assert int(dut.state.value) == ST_L0
    assert int(dut.negotiated_speed.value) == 0


# ----------------------------------------------------------------------
# Test 7: 非法 target (2'b11) → illegal_speed_sticky，停在 L0
# ----------------------------------------------------------------------
@cocotb.test()
async def illegal_target_is_rejected_at_l0(dut):
    """retrain_target=2'b11 直接触发 illegal_speed_sticky，不进 transition。"""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    await issue_retrain(dut, 3)
    assert int(dut.retrain_accept.value) == 1
    assert int(dut.state.value) == ST_L0
    assert int(dut.illegal_speed_sticky.value) == 1
    assert int(dut.rate_req_valid.value) == 0
    assert int(dut.traffic_quiesce.value) == 0


# ----------------------------------------------------------------------
# Test 8: 非法 target + non-zero negotiated → 不进 transition (新要求)
# ----------------------------------------------------------------------
# 旧测试 illegal_target_is_accepted_without_phy_action 已合并到 test 7
# 区别: 旧版非法 target 也保留 negotiated_speed，新版语义不变

# ----------------------------------------------------------------------
# Test 9: same-rate retrain → no-op
# ----------------------------------------------------------------------
@cocotb.test()
async def same_rate_retrain_is_noop(dut):
    """retrain_target==negotiated_speed 时不应发 rate request。"""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    # negotiated_speed 初始=0；retrain target=0 应当 no-op
    await issue_retrain(dut, 0)
    assert int(dut.retrain_accept.value) == 1
    assert int(dut.state.value) == ST_L0
    assert int(dut.rate_req_valid.value) == 0
    assert int(dut.traffic_quiesce.value) == 0


# ----------------------------------------------------------------------
# Test 10: phy_cdr_lost 在 QUIESCE → 立即走 fallback
# ----------------------------------------------------------------------
@cocotb.test()
async def cdr_lost_in_quiesce_triggers_fallback(dut):
    """QUIESCE 期间 phy_cdr_lost 立即转 FALLBACK_REQUEST。"""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    dut.ltssm_speed_ready.value = 0
    await issue_retrain(dut, 2)
    assert int(dut.state.value) == ST_QUIESCE
    dut.phy_cdr_lost.value = 1
    await advance(dut)
    assert int(dut.state.value) == ST_FALLBACK_REQUEST
    assert int(dut.cdr_loss_sticky.value) == 1
    assert int(dut.fallback_taken_sticky.value) == 1
    assert int(dut.rate_req_valid.value) == 1
    assert int(dut.rate_req_target.value) == 0  # fallback → Gen1


@cocotb.test()
async def checker_detects_early_phy_done(dut):
    """Negative checker: a bad stub must not enter Recovery.Idle early."""
    if os.environ.get("K12B_NEGATIVE_STUB") != "1":
        return
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    await issue_retrain(dut, 2)
    await advance(dut)
    if int(dut.state.value) == ST_RECOVERY_IDLE:
        with open("k12b_negative_checker_observed.txt", "w", encoding="utf-8") as marker:
            marker.write("K12B_NEGATIVE_CHECKER_OBSERVED phy_done_order\n")
        assert False, "bad stub entered Recovery.Idle before rate_op_done"
    assert False, "negative stub violation was not observed"
