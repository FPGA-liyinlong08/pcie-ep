import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, Timer


async def tick(dut):
    await RisingEdge(dut.clk)
    await ReadOnly()


async def writable():
    await Timer(1, units="ps")


def clear_events(dut):
    dut.lock_lost.value = 0
    dut.ts1_valid.value = 0
    dut.ts1_fields_match.value = 1
    dut.ts2_valid.value = 0
    dut.malformed.value = 0


async def reset(dut):
    dut.rst_n.value = 0
    dut.enable.value = 0
    dut.block_locked.value = 0
    clear_events(dut)
    cocotb.start_soon(Clock(dut.clk, 8, units="ns").start())
    await tick(dut)
    await writable()
    dut.rst_n.value = 1
    dut.enable.value = 1
    await tick(dut)


async def pulse(dut, name, fields_match=True):
    await writable()
    clear_events(dut)
    getattr(dut, name).value = 1
    dut.ts1_fields_match.value = int(fields_match)
    await tick(dut)
    observed = (int(dut.complete.value), int(dut.failed.value),
                int(dut.ts1_count.value))
    await writable()
    clear_events(dut)
    return observed


async def restart(dut, locked=True):
    await writable()
    dut.enable.value = 0
    clear_events(dut)
    await tick(dut)
    await writable()
    dut.block_locked.value = int(locked)
    dut.enable.value = 1
    await tick(dut)


@cocotb.test()
async def requires_eieos_lock_before_consuming_ts1(dut):
    await reset(dut)
    complete, failed, count = await pulse(dut, "ts1_valid")
    assert (complete, failed, count) == (0, 0, 0)
    await writable()
    dut.block_locked.value = 1
    for expected in range(1, 8):
        complete, failed, count = await pulse(dut, "ts1_valid")
        assert (complete, failed, count) == (0, 0, expected)
    complete, failed, count = await pulse(dut, "ts1_valid")
    assert (complete, failed, count) == (1, 0, 0)


@cocotb.test()
async def eieos_gap_does_not_break_consecutive_ts1_run(dut):
    await reset(dut)
    await writable()
    dut.block_locked.value = 1
    for _ in range(4):
        await pulse(dut, "ts1_valid")
    await tick(dut)  # EIEOS is represented by lock staying asserted.
    assert int(dut.ts1_count.value) == 4
    for _ in range(3):
        await pulse(dut, "ts1_valid")
    complete, failed, _ = await pulse(dut, "ts1_valid")
    assert (complete, failed) == (1, 0)


@cocotb.test()
async def structural_or_protocol_error_requests_fallback(dut):
    await reset(dut)
    for event, fields_match in (("lock_lost", True),
                                ("malformed", True),
                                ("ts2_valid", True),
                                ("ts1_valid", False)):
        await restart(dut, locked=True)
        complete, failed, count = await pulse(
            dut, event, fields_match=fields_match)
        assert (complete, failed, count) == (0, 1, 0), event


@cocotb.test()
async def one_thousand_random_rcvrlock_contexts(dut):
    await reset(dut)
    rng = random.Random(0xE2_2026)
    for context in range(1000):
        await restart(dut, locked=False)
        for _ in range(rng.randrange(0, 4)):
            complete, failed, count = await pulse(dut, "ts1_valid")
            assert (complete, failed, count) == (0, 0, 0)
        await writable()
        dut.block_locked.value = 1

        inject_error = (context % 5) == 0
        error_after = rng.randrange(0, 8) if inject_error else -1
        terminated = False
        for index in range(8):
            if index == error_after:
                event = rng.choice(("lock_lost", "malformed", "ts2_valid"))
                complete, failed, count = await pulse(dut, event)
                assert (complete, failed, count) == (0, 1, 0)
                terminated = True
                break
            if rng.randrange(0, 3) == 0:
                await tick(dut)
                assert int(dut.complete.value) == 0
            complete, failed, count = await pulse(dut, "ts1_valid")
            if index == 7:
                assert (complete, failed, count) == (1, 0, 0)
                terminated = True
            else:
                assert (complete, failed, count) == (0, 0, index + 1)
        assert terminated
