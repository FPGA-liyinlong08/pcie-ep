import os
import random
from collections import deque

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge, Timer, with_timeout


S_PERIOD_NS = float(os.getenv("S_PERIOD_NS", "16"))
M_PERIOD_NS = float(os.getenv("M_PERIOD_NS", "4"))
M_PHASE_NS = float(os.getenv("M_PHASE_NS", "0"))
RANDOM_PACKETS = int(os.getenv("M02_COCOTB_PACKETS", "1000"))
RANDOM_SEED = int(os.getenv("M02_RANDOM_SEED", "20260806"))


def make_packet(rng, length):
    packet = []
    for index in range(length):
        last = index == length - 1
        valid_bytes = rng.randint(1, 16) if last else 16
        packet.append(
            {
                "data": rng.getrandbits(128),
                "keep": (1 << valid_bytes) - 1,
                "sop": int(index == 0),
                "eop": int(last),
                "error": rng.randrange(16),
            }
        )
    return packet


def drive_idle(dut):
    dut.s_valid.value = 0
    dut.s_data.value = 0
    dut.s_keep.value = 0
    dut.s_sop.value = 0
    dut.s_eop.value = 0
    dut.s_error.value = 0
    dut.m_ready.value = 0
    dut.flush.value = 0


async def start_clocks(dut):
    cocotb.start_soon(Clock(dut.s_clk, S_PERIOD_NS, units="ns").start())

    async def delayed_m_clock():
        if M_PHASE_NS:
            await Timer(int(round(M_PHASE_NS * 1000)), units="ps")
        await Clock(dut.m_clk, M_PERIOD_NS, units="ns").start()

    cocotb.start_soon(delayed_m_clock())
    await Timer(max(1000, int(round(M_PHASE_NS * 1000)) + 100), units="ps")


async def reset_dut(dut):
    drive_idle(dut)
    dut.s_rst_n.value = 0
    dut.m_rst_n.value = 0
    await ClockCycles(dut.s_clk, 3)
    await ClockCycles(dut.m_clk, 3)
    dut.s_rst_n.value = 1
    dut.m_rst_n.value = 1
    await ClockCycles(dut.s_clk, 4)
    await ClockCycles(dut.m_clk, 4)


def drive_beat(dut, beat):
    dut.s_valid.value = 1
    dut.s_data.value = beat["data"]
    dut.s_keep.value = beat["keep"]
    dut.s_sop.value = beat["sop"]
    dut.s_eop.value = beat["eop"]
    dut.s_error.value = beat["error"]


async def send_beat(dut, beat):
    await FallingEdge(dut.s_clk)
    drive_beat(dut, beat)
    while True:
        await RisingEdge(dut.s_clk)
        if int(dut.s_ready.value):
            break


async def end_source(dut):
    await FallingEdge(dut.s_clk)
    dut.s_valid.value = 0


async def send_packets(dut, packets, committed, rng, random_gaps=False):
    for packet in packets:
        for beat in packet:
            if random_gaps and rng.random() < 0.25:
                await FallingEdge(dut.s_clk)
                dut.s_valid.value = 0
                await ClockCycles(dut.s_clk, rng.randint(1, 3))
            await send_beat(dut, beat)
        committed.append(packet)
    await end_source(dut)


def sampled_beat(dut):
    return {
        "data": int(dut.m_data.value),
        "keep": int(dut.m_keep.value),
        "sop": int(dut.m_sop.value),
        "eop": int(dut.m_eop.value),
        "error": int(dut.m_error.value),
    }


async def receive_packets(dut, committed, packet_total, rng, random_backpressure=False):
    received_packets = 0
    active_packet = None
    beat_index = 0

    while received_packets < packet_total:
        await FallingEdge(dut.m_clk)
        dut.m_ready.value = int(not random_backpressure or rng.random() < 0.75)
        await RisingEdge(dut.m_clk)

        valid = int(dut.m_valid.value)
        ready = int(dut.m_ready.value)
        if valid and active_packet is None:
            assert committed, (
                "未完成 Packet 在 EOP Commit 前出现在读侧: "
                f"m_ready={ready} m_sop={int(dut.m_sop.value)} "
                f"m_eop={int(dut.m_eop.value)} "
                f"s_count={int(dut.s_packet_count.value)} "
                f"m_count={int(dut.m_packet_count.value)}"
            )
        if not (valid and ready):
            continue

        if active_packet is None:
            active_packet = committed.popleft()
            beat_index = 0

        actual = sampled_beat(dut)
        expected = active_packet[beat_index]
        assert actual == expected, (
            f"Packet {received_packets} Beat {beat_index} 不一致: "
            f"actual={actual} expected={expected}"
        )
        beat_index += 1
        if beat_index == len(active_packet):
            active_packet = None
            received_packets += 1

    await FallingEdge(dut.m_clk)
    dut.m_ready.value = 0


@cocotb.test()
async def incomplete_packet_hidden(dut):
    """EOP 未写入时，即使数据 FIFO 已有 Beat，读侧也必须保持不可见。"""
    rng = random.Random(RANDOM_SEED)
    await start_clocks(dut)
    await reset_dut(dut)

    packet = make_packet(rng, 4)
    await send_beat(dut, packet[0])
    await end_source(dut)

    dut.m_ready.value = 1
    for _ in range(20):
        await RisingEdge(dut.m_clk)
        assert int(dut.m_valid.value) == 0, "未完成 Packet 提前可见"


@cocotb.test()
async def directed_packets_and_backpressure(dut):
    rng = random.Random(RANDOM_SEED + 1)
    await start_clocks(dut)
    await reset_dut(dut)

    packets = [make_packet(rng, length) for length in (1, 2, 3, 31, 32, 257, 511, 512)]
    committed = deque()
    producer = cocotb.start_soon(send_packets(dut, packets, committed, rng, True))
    consumer = cocotb.start_soon(receive_packets(dut, committed, len(packets), rng, True))
    await with_timeout(producer, 20, "ms")
    await with_timeout(consumer, 20, "ms")

    assert int(dut.s_overflow.value) == 0
    assert int(dut.m_underflow.value) == 0


@cocotb.test()
async def reset_and_flush_discard_partial(dut):
    rng = random.Random(RANDOM_SEED + 2)
    await start_clocks(dut)
    await reset_dut(dut)

    partial = make_packet(rng, 8)
    for beat in partial[:3]:
        await send_beat(dut, beat)
    await end_source(dut)

    # 只撤销写侧复位，内部公共复位仍必须同时清空两侧。
    await Timer(1300, units="ps")
    dut.s_rst_n.value = 0
    await Timer(100, units="ps")
    assert int(dut.m_valid.value) == 0
    dut.s_rst_n.value = 1
    await ClockCycles(dut.s_clk, 4)
    await ClockCycles(dut.m_clk, 4)

    # SOP 后以及 EOP 已提交但尚未读取时，撤销另一侧复位，同样不得泄漏旧包。
    for cut_after_beats in (1, 4):
        reset_packet = make_packet(rng, 4)
        for beat in reset_packet[:cut_after_beats]:
            await send_beat(dut, beat)
        await end_source(dut)
        await Timer(rng.randint(100, 1900), units="ps")
        dut.m_rst_n.value = 0
        await Timer(100, units="ps")
        assert int(dut.m_valid.value) == 0
        dut.m_rst_n.value = 1
        await ClockCycles(dut.s_clk, 4)
        await ClockCycles(dut.m_clk, 4)
        assert int(dut.s_packet_count.value) == 0
        assert int(dut.m_packet_count.value) == 0

    # Flush 再次覆盖中间 Beat。
    for beat in partial[:2]:
        await send_beat(dut, beat)
    await end_source(dut)
    dut.flush.value = 1
    await Timer(max(S_PERIOD_NS, M_PERIOD_NS), units="ns")
    assert int(dut.m_valid.value) == 0
    dut.flush.value = 0
    await ClockCycles(dut.s_clk, 4)
    await ClockCycles(dut.m_clk, 4)

    packet = make_packet(rng, 5)
    committed = deque()
    producer = cocotb.start_soon(send_packets(dut, [packet], committed, rng))
    consumer = cocotb.start_soon(receive_packets(dut, committed, 1, rng))
    await with_timeout(producer, 1, "ms")
    await with_timeout(consumer, 1, "ms")


@cocotb.test()
async def sticky_error_injection(dut):
    """注入源端边界错误和读端已 Claim/无数据错误，检查 Sticky 状态及 Flush 清除。"""
    rng = random.Random(RANDOM_SEED + 3)
    await start_clocks(dut)
    await reset_dut(dut)

    malformed = make_packet(rng, 1)[0]
    malformed["sop"] = 0
    await send_beat(dut, malformed)
    await end_source(dut)
    await Timer(1, units="ps")
    assert int(dut.s_overflow.value) == 1, "缺失首 SOP 未置位 s_overflow"

    dut.flush.value = 1
    await Timer(max(S_PERIOD_NS, M_PERIOD_NS), units="ns")
    assert int(dut.s_overflow.value) == 0
    assert int(dut.m_underflow.value) == 0
    dut.flush.value = 0
    await ClockCycles(dut.s_clk, 4)
    await ClockCycles(dut.m_clk, 4)

    # 白盒错误注入：模拟已 Claim Packet 时底层数据意外为空。
    dut.m_in_packet.value = 1
    await RisingEdge(dut.m_clk)
    await Timer(1, units="ps")
    assert int(dut.m_underflow.value) == 1, "已 Claim/无数据未置位 m_underflow"

    dut.flush.value = 1
    await Timer(max(S_PERIOD_NS, M_PERIOD_NS), units="ns")
    assert int(dut.s_overflow.value) == 0
    assert int(dut.m_underflow.value) == 0


@cocotb.test()
async def randomized_packets(dut):
    rng = random.Random(RANDOM_SEED + int(S_PERIOD_NS * 100) + int(M_PERIOD_NS * 10))
    await start_clocks(dut)
    await reset_dut(dut)

    lengths = []
    for index in range(RANDOM_PACKETS):
        selector = rng.random()
        if selector < 0.90:
            lengths.append(rng.randint(1, 8))
        elif selector < 0.99:
            lengths.append(rng.randint(9, 64))
        else:
            lengths.append((257, 511, 512)[index % 3])

    packets = [make_packet(rng, length) for length in lengths]
    committed = deque()
    producer = cocotb.start_soon(send_packets(dut, packets, committed, rng, True))
    consumer = cocotb.start_soon(receive_packets(dut, committed, len(packets), rng, True))
    await with_timeout(producer, 60, "ms")
    await with_timeout(consumer, 60, "ms")

    assert not committed
    assert int(dut.s_overflow.value) == 0
    assert int(dut.m_underflow.value) == 0
