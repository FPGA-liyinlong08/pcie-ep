import asyncio
import os
import random
import zlib

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotbext.pcie.core.dllp import Dllp, DllpType


CLK_NS = 8
RANDOM_SEED = int(os.getenv("K06_RANDOM_SEED", "20260806"))


def contiguous_keep(count):
    return (1 << count) - 1


def bytes_to_int(data):
    return int.from_bytes(data, "little")


def lcrc_bytes(protected):
    return zlib.crc32(protected).to_bytes(4, "little")


def ack_raw(seq, nak=False):
    return bytes_to_int(bytes([0x10 if nak else 0x00, 0x00,
                               (seq >> 8) & 0x0F, seq & 0xFF]))


async def reset_dut(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    for name in (
        "dll_active", "mac_rx_valid", "mac_rx_data", "mac_rx_keep",
        "mac_rx_sop", "mac_rx_eop", "mac_rx_is_dllp", "mac_rx_error",
        "rx_dllp_valid", "rx_dllp_data", "rx_dllp_crc_good",
        "rx_dllp_error", "tx_tlp_valid", "tx_tlp_data", "tx_tlp_keep",
        "tx_tlp_sop", "tx_tlp_eop", "tx_tlp_error", "tx_tlp_type",
        "tx_tlp_data_credits",
    ):
        getattr(dut, name).value = 0
    dut.mac_tx_ready.value = 1
    dut.tx_ack_dllp_ready.value = 1
    dut.rx_tlp_ready.value = 1
    dut.tx_fc_credit_available.value = 1
    dut.rst_n.value = 0
    for _ in range(4):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    dut.dll_active.value = 1
    for _ in range(3):
        await RisingEdge(dut.clk)


async def send_tlp(dut, packet, tlp_type=0, data_credits=0):
    assert 12 <= len(packet) <= 144 and len(packet) % 4 == 0
    offset = 0
    first = True
    while offset < len(packet):
        chunk = packet[offset:offset + 16]
        last = offset + len(chunk) == len(packet)
        dut.tx_tlp_valid.value = 1
        dut.tx_tlp_data.value = bytes_to_int(chunk)
        dut.tx_tlp_keep.value = contiguous_keep(len(chunk))
        dut.tx_tlp_sop.value = first
        dut.tx_tlp_eop.value = last
        dut.tx_tlp_error.value = 0
        dut.tx_tlp_type.value = tlp_type
        dut.tx_tlp_data_credits.value = data_credits
        while True:
            await RisingEdge(dut.clk)
            if int(dut.tx_tlp_ready.value):
                break
        offset += len(chunk)
        first = False
    dut.tx_tlp_valid.value = 0
    dut.tx_tlp_sop.value = 0
    dut.tx_tlp_eop.value = 0
    dut.tx_tlp_keep.value = 0


async def collect_mac_packet(dut, timeout_cycles=300):
    result = bytearray()
    saw_sop = False
    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        await Timer(1, units="ps")
        if int(dut.mac_tx_valid.value) and int(dut.mac_tx_ready.value):
            keep = int(dut.mac_tx_keep.value)
            word = int(dut.mac_tx_data.value)
            if int(dut.mac_tx_sop.value):
                assert not saw_sop
                saw_sop = True
            for lane in range(2):
                if keep & (1 << lane):
                    result.append((word >> (8 * lane)) & 0xFF)
            if int(dut.mac_tx_eop.value):
                assert saw_sop
                assert int(dut.mac_tx_is_dllp.value) == 0
                assert int(dut.mac_tx_bad.value) == 0
                return bytes(result)
    raise AssertionError("等待K06 MAC TLP超时")


async def collect_rx_tlp(dut, timeout_cycles=300):
    result = bytearray()
    dut.rx_tlp_ready.value = 1
    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        await Timer(1, units="ps")
        if int(dut.rx_tlp_valid.value) and int(dut.rx_tlp_ready.value):
            keep = int(dut.rx_tlp_keep.value)
            word = int(dut.rx_tlp_data.value)
            assert keep != 0 and (keep & (keep + 1)) == 0
            if not result:
                assert int(dut.rx_tlp_sop.value) == 1
            for lane in range(16):
                if keep & (1 << lane):
                    result.append((word >> (8 * lane)) & 0xFF)
            if int(dut.rx_tlp_eop.value):
                assert int(dut.rx_tlp_error.value) == 0
                return bytes(result)
    raise AssertionError("等待K06 TL RX Packet超时")


async def send_rx_wire(dut, wire, independent_eop=False, error=0):
    assert len(wire) >= 18
    dut.rx_tlp_ready.value = 0
    offset = 0
    first = True
    # 模拟STP位于Symbol0：首拍只含一个Byte，后续恢复2 Byte节拍。
    beat_sizes = [1]
    remaining = len(wire) - 1
    beat_sizes.extend([2] * (remaining // 2))
    if remaining & 1:
        beat_sizes.append(1)

    for index, size in enumerate(beat_sizes):
        chunk = wire[offset:offset + size]
        last_data = index == len(beat_sizes) - 1
        dut.mac_rx_valid.value = 1
        dut.mac_rx_data.value = bytes_to_int(chunk)
        dut.mac_rx_keep.value = contiguous_keep(size)
        dut.mac_rx_sop.value = first
        dut.mac_rx_eop.value = last_data and not independent_eop
        dut.mac_rx_is_dllp.value = 0
        dut.mac_rx_error.value = error if last_data else 0
        await RisingEdge(dut.clk)
        offset += size
        first = False

    if independent_eop:
        dut.mac_rx_valid.value = 1
        dut.mac_rx_data.value = 0
        dut.mac_rx_keep.value = 0
        dut.mac_rx_sop.value = 0
        dut.mac_rx_eop.value = 1
        dut.mac_rx_is_dllp.value = 0
        dut.mac_rx_error.value = error
        await RisingEdge(dut.clk)

    dut.mac_rx_valid.value = 0
    dut.mac_rx_keep.value = 0
    dut.mac_rx_sop.value = 0
    dut.mac_rx_eop.value = 0
    dut.mac_rx_error.value = 0


def make_rx_wire(seq, packet, corrupt_lcrc=False):
    sequence = bytes([(seq >> 8) & 0x0F, seq & 0xFF])
    protected = sequence + packet
    crc = bytearray(lcrc_bytes(protected))
    if corrupt_lcrc:
        crc[1] ^= 0x20
    return protected + bytes(crc)


async def collect_ack_dllp(dut, timeout_cycles=300):
    dut.tx_ack_dllp_ready.value = 1
    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        await Timer(1, units="ps")
        if int(dut.tx_ack_dllp_valid.value):
            raw = int(dut.tx_ack_dllp_data.value).to_bytes(4, "little")
            # ready在本协程开头驱动，额外等待一个边沿，明确保证握手被RTL采样。
            await RisingEdge(dut.clk)
            return raw
    raise AssertionError("等待K06 ACK/NAK DLLP超时")


def expected_dllp(seq, nak=False):
    obj = Dllp()
    obj.type = DllpType.NAK if nak else DllpType.ACK
    obj.seq = seq
    return bytes(obj.pack())


async def send_ack_event(dut, seq, nak=False, crc_good=True, error=0):
    dut.rx_dllp_valid.value = 1
    dut.rx_dllp_data.value = ack_raw(seq, nak)
    dut.rx_dllp_crc_good.value = crc_good
    dut.rx_dllp_error.value = error
    await RisingEdge(dut.clk)
    dut.rx_dllp_valid.value = 0
    dut.rx_dllp_crc_good.value = 0
    dut.rx_dllp_error.value = 0


def make_tlp(seed, length=12, fmt_type=0x00):
    rng = random.Random(seed)
    data = bytearray(rng.getrandbits(8) for _ in range(length))
    data[0] = fmt_type
    data[1] &= 0xFF
    data[2] = (data[2] & 0xFC) | ((length // 4) >> 8)
    data[3] = (length // 4) & 0xFF
    return bytes(data)


@cocotb.test()
async def tx_sequence_lcrc_and_credit(dut):
    await reset_dut(dut)
    packet = make_tlp(1, 20, 0x40)
    await send_tlp(dut, packet, tlp_type=0, data_credits=1)
    wire = await collect_mac_packet(dut)
    protected = bytes([0x00, 0x00]) + packet
    assert wire == protected + lcrc_bytes(protected)
    assert int(dut.next_tx_seq.value) == 1
    assert int(dut.replay_occupancy.value) == 1
    assert int(dut.tx_tlp_count.value) == 1

    await send_ack_event(dut, 0)
    for _ in range(3):
        await RisingEdge(dut.clk)
    assert int(dut.replay_occupancy.value) == 0
    assert int(dut.last_acked_seq.value) == 0


@cocotb.test()
async def cumulative_ack_nak_and_timer_replay(dut):
    await reset_dut(dut)
    packets = [make_tlp(10 + k, 20 + 4 * k, 0x40) for k in range(3)]
    first_wires = []
    for packet in packets:
        await send_tlp(dut, packet, tlp_type=0, data_credits=1)
        first_wires.append(await collect_mac_packet(dut))

    assert int(dut.replay_occupancy.value) == 3
    assert [wire[:2] for wire in first_wires] == [b"\x00\x00", b"\x00\x01", b"\x00\x02"]

    # NAK 0累计释放seq0，只重放seq1、seq2，且不重复消耗信用。
    consume_before = int(dut.tx_tlp_count.value)
    await send_ack_event(dut, 0, nak=True)
    replay1 = await collect_mac_packet(dut)
    replay2 = await collect_mac_packet(dut)
    assert replay1 == first_wires[1]
    assert replay2 == first_wires[2]
    for _ in range(3):
        await RisingEdge(dut.clk)
    assert int(dut.tx_tlp_count.value) == consume_before
    assert int(dut.replay_count.value) >= 2

    await send_ack_event(dut, 2)
    for _ in range(3):
        await RisingEdge(dut.clk)
    assert int(dut.replay_occupancy.value) == 0
    assert int(dut.last_acked_seq.value) == 2

    # 单包ACK丢失后由Timer重放，第二次连续超时置fatal。
    packet = make_tlp(99, 32, 0x40)
    await send_tlp(dut, packet, tlp_type=0, data_credits=2)
    original = await collect_mac_packet(dut)
    timer_replay1 = await collect_mac_packet(dut, timeout_cycles=500)
    timer_replay2 = await collect_mac_packet(dut, timeout_cycles=500)
    assert timer_replay1 == original
    assert timer_replay2 == original
    assert int(dut.replay_fatal.value) == 1
    await send_ack_event(dut, 3)


@cocotb.test()
async def rx_unique_duplicate_bad_lcrc_and_future(dut):
    await reset_dut(dut)
    dut.tx_ack_dllp_ready.value = 0

    p0 = make_tlp(200, 20, 0x40)  # Memory Write，1个Data Credit
    await send_rx_wire(dut, make_rx_wire(0, p0), independent_eop=True)
    assert await collect_rx_tlp(dut) == p0
    raw = await collect_ack_dllp(dut)
    assert raw == expected_dllp(0)
    assert int(dut.next_rx_seq.value) == 1
    assert int(dut.rx_tlp_count.value) == 1

    # Duplicate不再次提交，立即ACK最后正确Sequence。
    dut.tx_ack_dllp_ready.value = 0
    await send_rx_wire(dut, make_rx_wire(0, p0))
    raw = await collect_ack_dllp(dut)
    assert raw == expected_dllp(0)
    assert int(dut.rx_tlp_count.value) == 1
    assert int(dut.duplicate_tlp_count.value) == 1

    # 坏LCRC和未来Sequence都NAK expected-1，并保持next_rx_seq。
    dut.tx_ack_dllp_ready.value = 0
    await send_rx_wire(dut, make_rx_wire(1, p0, corrupt_lcrc=True))
    assert await collect_ack_dllp(dut) == expected_dllp(0, nak=True)
    assert int(dut.lcrc_error_count.value) == 1
    assert int(dut.next_rx_seq.value) == 1

    dut.tx_ack_dllp_ready.value = 0
    await send_rx_wire(dut, make_rx_wire(2, p0))
    assert await collect_ack_dllp(dut) == expected_dllp(0, nak=True)
    assert int(dut.sequence_error_count.value) == 1
    assert int(dut.next_rx_seq.value) == 1

    # MAC报告EDB/成帧错误时不得向TL提交，且立即NAK。
    dut.tx_ack_dllp_ready.value = 0
    await send_rx_wire(dut, make_rx_wire(1, p0), error=0b0001)
    assert await collect_ack_dllp(dut) == expected_dllp(0, nak=True)
    assert int(dut.lcrc_error_count.value) == 2
    assert int(dut.next_rx_seq.value) == 1

    # 合法seq1恢复，并验证Completion分类。
    p1 = make_tlp(201, 16, 0x4A)
    dut.tx_ack_dllp_ready.value = 0
    await send_rx_wire(dut, make_rx_wire(1, p1))
    assert await collect_rx_tlp(dut) == p1
    assert await collect_ack_dllp(dut) == expected_dllp(1)
    assert int(dut.next_rx_seq.value) == 2

    # 最大144 Byte TLP覆盖9个128-bit Payload RAM节拍及随机反压。
    p2 = make_tlp(202, 144, 0x40)
    dut.tx_ack_dllp_ready.value = 0
    await send_rx_wire(dut, make_rx_wire(2, p2), independent_eop=True)
    dut.rx_tlp_ready.value = 0
    for ready in (0, 1, 0, 1, 1):
        dut.rx_tlp_ready.value = ready
        await RisingEdge(dut.clk)
    assert await collect_rx_tlp(dut, timeout_cycles=600) == p2
    assert await collect_ack_dllp(dut) == expected_dllp(2)
    assert int(dut.next_rx_seq.value) == 3


@cocotb.test()
async def invalid_ack_and_link_reset(dut):
    await reset_dut(dut)
    packet = make_tlp(300, 12, 0x00)
    await send_tlp(dut, packet, tlp_type=1, data_credits=0)
    await collect_mac_packet(dut)
    await send_ack_event(dut, 7)
    for _ in range(2):
        await RisingEdge(dut.clk)
    assert int(dut.ack_error_count.value) == 1
    assert int(dut.replay_occupancy.value) == 1

    dut.dll_active.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, units="ps")
    assert int(dut.replay_occupancy.value) == 0
    assert int(dut.next_tx_seq.value) == 0
    assert int(dut.next_rx_seq.value) == 0
    assert int(dut.mac_tx_valid.value) == 0
    assert int(dut.tx_tlp_ready.value) == 0


@cocotb.test()
async def randomized_sequence_wrap(dut):
    await reset_dut(dut)
    rng = random.Random(RANDOM_SEED)
    count = int(os.getenv("K06_RANDOM_PACKETS", "10000"))
    assert count >= 4096

    for index in range(count):
        length = 12 + 4 * rng.randrange(0, 8)
        packet = make_tlp(RANDOM_SEED + index, length, 0x40)
        dut.mac_tx_ready.value = rng.randrange(0, 2)
        await send_tlp(dut, packet, tlp_type=0,
                       data_credits=max(1, (length - 12 + 15) // 16))
        dut.mac_tx_ready.value = 1
        wire = await collect_mac_packet(dut, timeout_cycles=500)
        seq = index & 0xFFF
        sequence = bytes([(seq >> 8) & 0x0F, seq & 0xFF])
        assert wire == sequence + packet + lcrc_bytes(sequence + packet)
        await send_ack_event(dut, seq)
        if index % 257 == 0:
            await RisingEdge(dut.clk)

    for _ in range(3):
        await RisingEdge(dut.clk)
    assert int(dut.replay_occupancy.value) == 0
    assert int(dut.next_tx_seq.value) == (count & 0xFFF)
    assert int(dut.last_acked_seq.value) == ((count - 1) & 0xFFF)
    assert int(dut.tx_tlp_count.value) == count
    dut._log.info("K06完整Sequence回绕完成 packets=%d seed=%d", count, RANDOM_SEED)
