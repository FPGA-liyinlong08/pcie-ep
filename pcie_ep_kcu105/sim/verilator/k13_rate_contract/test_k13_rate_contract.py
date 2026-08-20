"""
K13 Rate Contract 单元仿真 - Gate A 测试矩阵

覆盖 k13_phy_rate_contract_architecture_20260819.md 第 15 节 Gate A
列出的 6 个 case + fast-fallback 路径：

  1. Gen1 -> Gen3  PASS
  2. Gen3 -> Gen1  PASS
  3. same-rate request (no-op)
  4. PHY_PHYSTATUS delayed
  5. PHY_PHYSTATUS timeout
  6. 非法 target (2'b11) -> sticky error
  7. fast-fallback (Gen3->Gen1 跳过 10us gap)
  8. no fallback_req 时仍走 normal 10us gap (回归保护)

不变量断言 (Doc 第 15 节 Gate A)：
  - active_rate 只能在 completion 时改变
  - raw phy_rate_cmd 可以在 active_rate 不变时先行
  - rate_done 是 1 周期 pulse
  - 单一 raw PHY_RATE owner (由架构保证，本测试无法在模块级证)
  - fallback_req=1 必须直接进 RC_FALLBACK_WAIT，跳过 RDY0_GAP
  - fallback_req=0 必须走 RDY0_GAP 路径

设计文档对齐：
  状态编码与 pcie_phy_rate_contract.sv 中 localparam 一一对应
  仿真参数：RATE_TIMEOUT_CYCLES=200, GEN1_RELEASE_GAP_CYCLES=10
"""
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


# ----------------------------------------------------------------------
# 状态编码 (必须与 pcie_phy_rate_contract.sv 一致)
# ----------------------------------------------------------------------
RC_DISABLED       = 0x0
RC_RDY2_STABLE    = 0x4
RC_RELEASE_RDY3   = 0x5
RC_RDY0_GAP       = 0x2
RC_APPLY_RDY1     = 0x3
RC_WAIT_PHYSTATUS = 0xA
RC_COMMIT_RDY2    = 0xB
RC_FALLBACK_WAIT  = 0xC
RC_NOOP_DONE      = 0xD
RC_ERROR          = 0xF

# 速率编码
RATE_GEN1     = 0x0
RATE_GEN2     = 0x1
RATE_GEN3     = 0x2
RATE_RESERVED = 0x3


# ----------------------------------------------------------------------
# Helper
# ----------------------------------------------------------------------
async def reset_dut(dut):
    """应用复位，link_up 后等待 FSM 同步到 RC_RDY2_STABLE。"""
    dut.rst_n.value = 0
    dut.link_ready.value = 0
    dut.reinitialize_gen1.value = 0
    dut.rate_req_valid.value = 0
    dut.rate_req_target.value = 0
    dut.fallback_req.value = 0   # 默认走 normal path
    dut.phy_phystatus.value = 0
    await Timer(5, units="ns")
    dut.rst_n.value = 1
    dut.link_ready.value = 1
    # 等 4 拍让 FSM 从 RC_DISABLED 走到 RC_RDY2_STABLE
    for _ in range(4):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
    state = int(dut.dbg_state.value)
    assert state == RC_RDY2_STABLE, (
        f"reset 后期望 RC_RDY2_STABLE(0x4)，实测 0x{state:x}"
    )
    assert int(dut.active_rate.value) == RATE_GEN1
    assert int(dut.phy_rate_cmd.value) == RATE_GEN1
    assert int(dut.rate_req_ready.value) == 1


async def issue_rate_request(dut, target, fallback=0):
    """发起 semantic rate-change 请求。valid 拉高 1 拍。"""
    dut.rate_req_target.value = target
    dut.fallback_req.value = fallback
    dut.rate_req_valid.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    dut.rate_req_valid.value = 0
    dut.fallback_req.value = 0


async def pulse_phystatus(dut, cycles=2):
    """拉高 phy_phystatus `cycles` 拍（仅置位，不验证 FSM 行为）。"""
    dut.phy_phystatus.value = 1
    for _ in range(cycles):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
    dut.phy_phystatus.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")


async def trigger_phystatus_and_complete(dut, expected_new_rate):
    """在 WAIT_PHYSTATUS 注入 phystatus 上升沿，并显式断言 rate_done 1-cycle pulse。

    时序（与 RTL 对应）：
      Edge A: phystatus_rising=1 被采样，state_r <= COMMIT_RDY2
              （此时 rate_done 仍 = 0）
      Edge B: active_rate_r <= target, rate_done_pulse_r <= 1,
              state_r <= RDY2_STABLE
              （此拍之后 rate_done = 1, 1 周期 pulse）
      Edge C: rate_done_pulse_r <= 0 (default 复位)

    Pre:  state == RC_WAIT_PHYSTATUS, phy_phystatus == 0
    Post: state == RC_RDY2_STABLE, phy_phystatus == 0,
          active_rate == expected_new_rate
    """
    assert int(dut.dbg_state.value) == RC_WAIT_PHYSTATUS, (
        f"pre: 应在 RC_WAIT_PHYSTATUS，实测 0x{int(dut.dbg_state.value):x}"
    )
    dut.phy_phystatus.value = 1
    # Edge A：phystatus_rising 触发，state -> COMMIT_RDY2
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert int(dut.dbg_state.value) == RC_COMMIT_RDY2, (
        f"phystatus 上升沿后应进入 COMMIT_RDY2，实测 0x{int(dut.dbg_state.value):x}"
    )
    assert int(dut.rate_done.value) == 0, "COMMIT_RDY2 拍 rate_done 必须仍为 0"
    # Edge B：state -> RDY2_STABLE, rate_done <= 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert int(dut.rate_done.value) == 1, (
        "rate_done 必须在 COMMIT_RDY2 -> RDY2_STABLE 跳转变高"
    )
    assert int(dut.dbg_state.value) == RC_RDY2_STABLE
    assert int(dut.active_rate.value) == expected_new_rate, (
        f"active_rate 未更新为 0x{expected_new_rate:x}"
    )
    # Edge C：rate_done <= 0 (default)
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert int(dut.rate_done.value) == 0, "rate_done 必须是 1 周期 pulse"
    # 清理
    dut.phy_phystatus.value = 0
    await Timer(1, units="ns")


async def wait_state(dut, expected, max_cycles=200):
    """等到 dbg_state == expected。超时则 fail。"""
    for _ in range(max_cycles):
        if int(dut.dbg_state.value) == expected:
            return
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
    state = int(dut.dbg_state.value)
    raise AssertionError(
        f"等待状态 0x{expected:x} 超时，当前 0x{state:x}"
    )


async def assert_active_rate_unchanged(dut, expected, cycles, msg=""):
    """连续 `cycles` 拍断言 active_rate 不变。"""
    for i in range(cycles):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        actual = int(dut.active_rate.value)
        assert actual == expected, (
            f"active_rate 在 transition 中变化 [{msg}]  cycle={i} "
            f"expected=0x{expected:x} actual=0x{actual:x}"
        )


# ----------------------------------------------------------------------
# Test 1: Gen1 -> Gen3 正常握手
# ----------------------------------------------------------------------
@cocotb.test()
async def gen1_to_gen3_normal_flow(dut):
    """Doc Gate A case 1：Gen1->Gen3 完整 7 态路径。"""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    # 起始不变量
    assert int(dut.force_txelecidle.value) == 0
    assert int(dut.rate_busy.value) == 0
    assert int(dut.rate_failed.value) == 0

    await issue_rate_request(dut, RATE_GEN3)

    # 走完 RELEASE_RDY3 -> RDY0_GAP
    await wait_state(dut, RC_RDY0_GAP)
    assert int(dut.force_txelecidle.value) == 1, "GAP 状态必须 force TXEI"
    assert int(dut.active_rate.value) == RATE_GEN1, "GAP 中 active_rate 不应变"

    # 等到 APPLY_RDY1 (GAP 计数 +1 拍后跳转)
    await wait_state(dut, RC_APPLY_RDY1)
    assert int(dut.phy_rate_cmd.value) == RATE_GEN3, (
        "APPLY_RDY1 必须已驱动 phy_rate_cmd=Gen3"
    )
    assert int(dut.active_rate.value) == RATE_GEN1, (
        "APPLY_RDY1 阶段 active_rate 仍必须为旧值"
    )

    # APPLY_RDY1 是 1 拍 settle，下一拍进入 WAIT_PHYSTATUS
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert int(dut.dbg_state.value) == RC_WAIT_PHYSTATUS

    # 注入 phystatus 上升沿，并显式断言 rate_done 1-cycle pulse
    await trigger_phystatus_and_complete(dut, RATE_GEN3)

    # 最终稳态不变量
    assert int(dut.dbg_state.value) == RC_RDY2_STABLE
    assert int(dut.active_rate.value) == RATE_GEN3
    assert int(dut.phy_rate_cmd.value) == RATE_GEN3
    assert int(dut.force_txelecidle.value) == 0
    assert int(dut.rate_busy.value) == 0
    assert int(dut.rate_failed.value) == 0
    assert int(dut.timeout_sticky.value) == 0


# ----------------------------------------------------------------------
# Test 2: Gen3 -> Gen1 正常握手
# ----------------------------------------------------------------------
@cocotb.test()
async def gen3_to_gen1_normal_flow(dut):
    """Doc Gate A case 2：Gen3->Gen1 与 Gen1->Gen3 路径对称。"""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    # 先把 active_rate 推到 Gen3
    await issue_rate_request(dut, RATE_GEN3)
    await wait_state(dut, RC_APPLY_RDY1)
    await RisingEdge(dut.clk)  # APPLY 1 拍 settle -> WAIT_PHYSTATUS
    await Timer(1, units="ns")
    await trigger_phystatus_and_complete(dut, RATE_GEN3)
    assert int(dut.active_rate.value) == RATE_GEN3

    # 再发 Gen1 请求
    await issue_rate_request(dut, RATE_GEN1)
    await wait_state(dut, RC_APPLY_RDY1)
    assert int(dut.phy_rate_cmd.value) == RATE_GEN1, (
        "APPLY 阶段 phy_rate_cmd 必须已切到 Gen1"
    )
    assert int(dut.active_rate.value) == RATE_GEN3, (
        "APPLY 阶段 active_rate 不能变"
    )
    await RisingEdge(dut.clk)  # APPLY 1 拍 settle -> WAIT_PHYSTATUS
    await Timer(1, units="ns")
    await trigger_phystatus_and_complete(dut, RATE_GEN1)
    assert int(dut.active_rate.value) == RATE_GEN1
    assert int(dut.phy_rate_cmd.value) == RATE_GEN1
    assert int(dut.rate_failed.value) == 0


# ----------------------------------------------------------------------
# Test 3: same-rate 请求是 no-op
# ----------------------------------------------------------------------
@cocotb.test()
async def same_rate_request_is_noop(dut):
    """Doc Gate A case 3：target == active 必须不触发 transition。"""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    assert int(dut.active_rate.value) == RATE_GEN1
    assert int(dut.rate_req_ready.value) == 1

    await issue_rate_request(dut, RATE_GEN1)
    await Timer(50, units="ns")  # 等 5 拍

    assert int(dut.dbg_state.value) == RC_RDY2_STABLE, (
        "same-rate 必须停留在 RDY2_STABLE"
    )
    assert int(dut.active_rate.value) == RATE_GEN1
    assert int(dut.phy_rate_cmd.value) == RATE_GEN1
    assert int(dut.rate_busy.value) == 0
    assert int(dut.rate_failed.value) == 0
    # phystatus 没有触发，所以 phystatus_seen 应该不会 latch
    # (Phystatus_seen 是 phystatus_seen_pulse OR phystatus_rising；
    #  这里 phystatus_rising = 0 & ~0 = 0，pulse 也没产生)


# ----------------------------------------------------------------------
# Test 4: PHY_PHYSTATUS 延迟到位
# ----------------------------------------------------------------------
@cocotb.test()
async def phystatus_delayed_completes_correctly(dut):
    """Doc Gate A case 4：phystatus 延迟到来，active_rate 必须保持旧值。"""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    await issue_rate_request(dut, RATE_GEN3)
    await wait_state(dut, RC_APPLY_RDY1)
    await RisingEdge(dut.clk)  # 进 WAIT_PHYSTATUS
    await Timer(1, units="ns")
    assert int(dut.dbg_state.value) == RC_WAIT_PHYSTATUS

    # 在 WAIT_PHYSTATUS 滞留 50 拍（远小于 RATE_TIMEOUT_CYCLES=200）
    for i in range(50):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        # active_rate 必须仍为 Gen1
        assert int(dut.active_rate.value) == RATE_GEN1, (
            f"cycle {i}: active_rate 提前变化"
        )
        # phy_rate_cmd 必须仍为 Gen3 (raw command owner 已驱动)
        assert int(dut.phy_rate_cmd.value) == RATE_GEN3, (
            f"cycle {i}: phy_rate_cmd 错误"
        )
        # force TXEI 仍在生效
        assert int(dut.force_txelecidle.value) == 1

    # 现在才注入 phystatus，并验证 completion
    await trigger_phystatus_and_complete(dut, RATE_GEN3)
    assert int(dut.active_rate.value) == RATE_GEN3


# ----------------------------------------------------------------------
# Test 5: PHY_PHYSTATUS timeout -> sticky error
# ----------------------------------------------------------------------
@cocotb.test()
async def phystatus_timeout_triggers_error(dut):
    """Doc Gate A case 5：phystatus 永不到来，RATE_TIMEOUT_CYCLES 触发 RC_ERROR。"""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    await issue_rate_request(dut, RATE_GEN3)
    await wait_state(dut, RC_WAIT_PHYSTATUS)

    # 等 250 拍 (> RATE_TIMEOUT_CYCLES=200)
    for _ in range(250):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.dbg_state.value) == RC_ERROR:
            break

    assert int(dut.dbg_state.value) == RC_ERROR
    assert int(dut.rate_failed.value) == 1
    assert int(dut.timeout_sticky.value) == 1
    # active_rate 仍为旧值——timeout 不允许更新
    assert int(dut.active_rate.value) == RATE_GEN1
    # contract 保持失败目标与 TXEI，等待 semantic Gen1 fallback；active_rate
    # 仍然保持旧值，不能把错误命令误当作已提交速率。
    assert int(dut.phy_rate_cmd.value) == RATE_GEN3


# ----------------------------------------------------------------------
# Test 6: 非法 target (2'b11) -> sticky error
# ----------------------------------------------------------------------
@cocotb.test()
async def illegal_target_triggers_error(dut):
    """Doc Gate A case 6：target=RATE_RESERVED 直接走 RC_ERROR。"""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    await issue_rate_request(dut, RATE_RESERVED)
    await wait_state(dut, RC_ERROR, max_cycles=5)
    assert int(dut.rate_failed.value) == 1
    # 非法 target 不属于 timeout 路径
    assert int(dut.timeout_sticky.value) == 0
    # active_rate 仍为 Gen1——未发生真实切速
    assert int(dut.active_rate.value) == RATE_GEN1


@cocotb.test()
async def timeout_can_accept_gen1_fallback(dut):
    """失败操作之后仍可接受唯一的 Gen1 fallback 请求。"""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    await issue_rate_request(dut, RATE_GEN3)
    await wait_state(dut, RC_WAIT_PHYSTATUS)
    await wait_state(dut, RC_ERROR, max_cycles=250)
    assert int(dut.active_rate.value) == RATE_GEN1
    await issue_rate_request(dut, RATE_GEN1, fallback=1)
    await wait_state(dut, RC_FALLBACK_WAIT, max_cycles=5)
    dut.phy_phystatus.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert int(dut.dbg_state.value) == RC_RDY2_STABLE
    assert int(dut.rate_done.value) == 1
    assert int(dut.active_rate.value) == RATE_GEN1
    dut.phy_phystatus.value = 0
    assert int(dut.active_rate.value) == RATE_GEN1


@cocotb.test()
async def initialized_contract_ready_across_recovery(dut):
    """link_ready掉低不能让Recovery中的semantic request失去ready。"""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    dut.link_ready.value = 0
    await Timer(1, units="ns")
    assert int(dut.rate_req_ready.value) == 1


# ----------------------------------------------------------------------
# Test 7: fast-fallback (Gen3→Gen1 跳过 10us gap)
# ----------------------------------------------------------------------
@cocotb.test()
async def fast_fallback_skips_gen1_release_gap(dut):
    """Doc Section 7.3：fallback_req=1 时 contract 直接进 RC_FALLBACK_WAIT，
    跳过 RC_RDY0_GAP (10us) 但仍走 phystatus 上升沿检测。
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    # 先把 active_rate 推到 Gen3
    await issue_rate_request(dut, RATE_GEN3)
    await wait_state(dut, RC_APPLY_RDY1)
    await RisingEdge(dut.clk)  # APPLY 1 拍 settle -> WAIT_PHYSTATUS
    await Timer(1, units="ns")
    await trigger_phystatus_and_complete(dut, RATE_GEN3)
    assert int(dut.active_rate.value) == RATE_GEN3

    # 现在发 fallback request: Gen3 -> Gen1, fallback_req=1
    await issue_rate_request(dut, RATE_GEN1, fallback=1)
    # 关键不变量：FSM 必须 **直接** 进 RC_FALLBACK_WAIT，
    # 不经过 RC_RELEASE_RDY3 / RC_RDY0_GAP
    await wait_state(dut, RC_FALLBACK_WAIT, max_cycles=4)
    # phystatus_seen 2-cycle 延迟线需要清零（之前 trigger_phystatus_and_complete
    # 留下的 seen=1, prev=1；issue_rate_request edge 后 seen=0, prev=1）
    # 再等 1 拍让 prev=0, seen=0，才能正确检测新的 phystatus 上升沿
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert int(dut.dbg_state.value) == RC_FALLBACK_WAIT
    # 进一步确认：在 FALLBACK_WAIT 期间 force_txelecidle=1
    assert int(dut.force_txelecidle.value) == 1, (
        "FALLBACK_WAIT 期间必须 force TXEI"
    )
    # phy_rate_cmd 已切到 Gen1 (RC_FALLBACK_WAIT 走 target 路径)
    assert int(dut.phy_rate_cmd.value) == RATE_GEN1, (
        "FALLBACK_WAIT 期间 phy_rate_cmd 必须 = target (Gen1)"
    )
    # active_rate 仍为 Gen3 (在 phystatus 之前不能变)
    assert int(dut.active_rate.value) == RATE_GEN3

    # FALLBACK_WAIT 状态下 phystatus 上升沿直接进 RDY2_STABLE 并 pulse rate_done
    # （不经过独立的 COMMIT_RDY2 状态——这是 fast-fallback 的关键节省）
    assert int(dut.dbg_state.value) == RC_FALLBACK_WAIT
    dut.phy_phystatus.value = 1
    # Edge A: phystatus_rising -> active_rate <= target, rate_done <= 1
    #         state <= RDY2_STABLE
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert int(dut.active_rate.value) == RATE_GEN1, (
        "fast-fallback: phystatus 后 active_rate 必须立即为 Gen1"
    )
    assert int(dut.rate_done.value) == 1, (
        "fast-fallback: phystatus 后 rate_done 必须 pulse 1 拍"
    )
    assert int(dut.dbg_state.value) == RC_RDY2_STABLE
    # Edge B: rate_done <= 0
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert int(dut.rate_done.value) == 0
    # 清理
    dut.phy_phystatus.value = 0
    await Timer(1, units="ns")

    # 回归保护：fast-fallback 路径不触发 sticky 失败
    assert int(dut.rate_failed.value) == 0
    assert int(dut.timeout_sticky.value) == 0


# ----------------------------------------------------------------------
# Test 8: fallback_req=0 时走 normal 路径 (回归保护)
# ----------------------------------------------------------------------
@cocotb.test()
async def no_fallback_req_uses_normal_gap(dut):
    """fallback_req=0 时即使 target=Gen1 (active=Gen3)，仍走 normal 路径。"""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    # 推到 Gen3
    await issue_rate_request(dut, RATE_GEN3)
    await wait_state(dut, RC_APPLY_RDY1)
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    await trigger_phystatus_and_complete(dut, RATE_GEN3)

    # target=Gen1, fallback_req=0: 应当走 normal 路径
    await issue_rate_request(dut, RATE_GEN1, fallback=0)
    # 1 拍后应进 RC_RDY0_GAP, NOT RC_FALLBACK_WAIT
    await wait_state(dut, RC_RDY0_GAP, max_cycles=2)
    assert int(dut.dbg_state.value) == RC_RDY0_GAP
    assert int(dut.dbg_state.value) != RC_FALLBACK_WAIT
