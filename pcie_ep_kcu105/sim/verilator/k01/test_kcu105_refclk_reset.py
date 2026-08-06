import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Combine, FallingEdge, ReadOnly, RisingEdge, Timer


RESET_STAGES = 4
PCLK_PERIOD_NS = float(os.getenv("PCLK_PERIOD_NS", "16"))
PCLK_PHASE_NS = float(os.getenv("PCLK_PHASE_NS", "0"))
RANDOM_RESETS = int(os.getenv("K01_RANDOM_RESETS", "1000"))
RANDOM_PHY_RESETS = int(os.getenv("K01_RANDOM_PHY_RESETS", "250"))
RANDOM_SEED = int(os.getenv("K01_RANDOM_SEED", "20260806"))


async def start_clocks(dut):
    core_clock_task = cocotb.start_soon(
        Clock(dut.phy_coreclk, 4, units="ns").start()
    )
    if PCLK_PHASE_NS:
        await Timer(PCLK_PHASE_NS, units="ns")
    pipe_clock_task = cocotb.start_soon(
        Clock(dut.phy_pclk, PCLK_PERIOD_NS, units="ns").start()
    )
    await Timer(1, units="ps")
    return core_clock_task, pipe_clock_task


def drive_reset(dut):
    dut.pcie_perst_n.value = 0
    dut.phy_phystatus_rst.value = 0


async def sampled(signal):
    await ReadOnly()
    return int(signal.value)


async def expect_sync_release(clock, reset_n, name, iteration=None):
    suffix = "" if iteration is None else f" iteration={iteration}"
    for cycle in range(1, RESET_STAGES):
        await RisingEdge(clock)
        assert await sampled(reset_n) == 0, f"{name} released early cycle={cycle}{suffix}"
    await RisingEdge(clock)
    assert await sampled(reset_n) == 1, f"{name} did not release cycle={RESET_STAGES}{suffix}"


async def release_both_domains(dut, iteration=None):
    core_task = cocotb.start_soon(
        expect_sync_release(dut.phy_coreclk, dut.core_rst_n, "core_rst_n", iteration)
    )
    pipe_task = cocotb.start_soon(
        expect_sync_release(dut.phy_pclk, dut.pipe_rst_n, "pipe_rst_n", iteration)
    )
    await Combine(core_task, pipe_task)


@cocotb.test()
async def release_and_dependency(dut):
    """冻结 PERST#、PHY Status 的依赖关系和精确同步释放拍数。"""
    drive_reset(dut)
    dut.phy_phystatus_rst.value = 1
    await start_clocks(dut)

    assert int(dut.phy_rst_n.value) == 0
    assert int(dut.core_rst_n.value) == 0
    assert int(dut.pipe_rst_n.value) == 0

    await FallingEdge(dut.phy_coreclk)
    dut.pcie_perst_n.value = 1
    await Timer(1, units="ps")
    assert int(dut.phy_rst_n.value) == 1, "phy_rst_n must directly follow PERST#"
    await expect_sync_release(dut.phy_coreclk, dut.core_rst_n, "core_rst_n")
    assert int(dut.pipe_rst_n.value) == 0, "PIPE reset released while PHY Status reset is active"

    await FallingEdge(dut.phy_pclk)
    dut.phy_phystatus_rst.value = 0
    await expect_sync_release(dut.phy_pclk, dut.pipe_rst_n, "pipe_rst_n")

    await Timer(1300, units="ps")
    dut.phy_phystatus_rst.value = 1
    await Timer(1, units="ps")
    assert int(dut.pipe_rst_n.value) == 0, "PIPE missed asynchronous PHY Status reset"
    assert int(dut.core_rst_n.value) == 1, "Core reset followed PHY Status reset"
    assert int(dut.phy_rst_n.value) == 1, "PHY reset followed PHY Status reset"

    await Timer(217, units="ps")
    dut.phy_phystatus_rst.value = 0
    await expect_sync_release(dut.phy_pclk, dut.pipe_rst_n, "pipe_rst_n")

    await Timer(911, units="ps")
    dut.pcie_perst_n.value = 0
    await Timer(1, units="ps")
    assert int(dut.phy_rst_n.value) == 0
    assert int(dut.core_rst_n.value) == 0
    assert int(dut.pipe_rst_n.value) == 0


@cocotb.test()
async def randomized_perst_stress(dut):
    """每种 PIPE 速率执行 1,000 次随机相位、随机宽度 PERST#。"""
    rng = random.Random(RANDOM_SEED + int(PCLK_PERIOD_NS * 100) + 1)
    drive_reset(dut)
    await start_clocks(dut)

    await Timer(731, units="ps")
    dut.pcie_perst_n.value = 1
    await release_both_domains(dut)

    for iteration in range(RANDOM_RESETS):
        await Timer(rng.randint(1, max(2, int(PCLK_PERIOD_NS * 1000) - 1)), units="ps")
        dut.pcie_perst_n.value = 0
        await Timer(1, units="ps")

        assert int(dut.phy_rst_n.value) == 0, f"PHY missed PERST# iteration={iteration}"
        assert int(dut.core_rst_n.value) == 0, f"Core missed PERST# iteration={iteration}"
        assert int(dut.pipe_rst_n.value) == 0, f"PIPE missed PERST# iteration={iteration}"

        await Timer(rng.randint(10, 3000), units="ps")
        dut.pcie_perst_n.value = 1
        await Timer(1, units="ps")
        assert int(dut.phy_rst_n.value) == 1, f"PHY reset did not release iteration={iteration}"
        await release_both_domains(dut, iteration)


@cocotb.test()
async def randomized_phystatus_stress(dut):
    """随机注入 PHY Status Reset，证明只重置 PIPE 域。"""
    rng = random.Random(RANDOM_SEED + int(PCLK_PERIOD_NS * 100) + 2)
    drive_reset(dut)
    await start_clocks(dut)

    await Timer(977, units="ps")
    dut.pcie_perst_n.value = 1
    await release_both_domains(dut)

    for iteration in range(RANDOM_PHY_RESETS):
        await Timer(rng.randint(1, max(2, int(PCLK_PERIOD_NS * 1000) - 1)), units="ps")
        dut.phy_phystatus_rst.value = 1
        await Timer(1, units="ps")

        assert int(dut.pipe_rst_n.value) == 0, f"PIPE missed PHY reset iteration={iteration}"
        assert int(dut.core_rst_n.value) == 1, f"Core followed PHY reset iteration={iteration}"
        assert int(dut.phy_rst_n.value) == 1, f"PHY reset output changed iteration={iteration}"

        await Timer(rng.randint(10, 3000), units="ps")
        dut.phy_phystatus_rst.value = 0
        await expect_sync_release(
            dut.phy_pclk, dut.pipe_rst_n, "pipe_rst_n", iteration
        )
        assert int(dut.core_rst_n.value) == 1
        assert int(dut.phy_rst_n.value) == 1


@cocotb.test()
async def held_reset_requires_clock_edges(dut):
    """确认异步条件释放后仍必须等待本域时钟，不允许组合释放。"""
    drive_reset(dut)
    core_clock_task, pipe_clock_task = await start_clocks(dut)
    await Timer(333, units="ps")

    dut.pcie_perst_n.value = 1
    await Timer(100, units="ps")
    assert int(dut.phy_rst_n.value) == 1
    assert int(dut.core_rst_n.value) == 0
    assert int(dut.pipe_rst_n.value) == 0

    await release_both_domains(dut)
    await ClockCycles(dut.phy_coreclk, 1)
    assert int(dut.core_rst_n.value) == 1
    assert int(dut.pipe_rst_n.value) == 1

    dut.pcie_perst_n.value = 0
    await Timer(1, units="ps")
    core_clock_task.kill()
    pipe_clock_task.kill()
    dut.phy_coreclk.value = 0
    dut.phy_pclk.value = 0

    dut.pcie_perst_n.value = 1
    await Timer(10 * max(4, PCLK_PERIOD_NS), units="ns")
    assert int(dut.phy_rst_n.value) == 1
    assert int(dut.core_rst_n.value) == 0, "Core reset released while clock stopped"
    assert int(dut.pipe_rst_n.value) == 0, "PIPE reset released while clock stopped"

    cocotb.start_soon(
        Clock(dut.phy_coreclk, 4, units="ns").start(start_high=False)
    )
    cocotb.start_soon(
        Clock(dut.phy_pclk, PCLK_PERIOD_NS, units="ns").start(start_high=False)
    )
    await release_both_domains(dut)
