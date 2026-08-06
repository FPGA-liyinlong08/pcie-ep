import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotbext.pcie.core.dllp import Dllp, DllpType, FcScale


FC_TYPES = (0, 1, 2)
INIT1_TYPES = (DllpType.INIT_FC1_P, DllpType.INIT_FC1_NP, DllpType.INIT_FC1_CPL)
INIT2_TYPES = (DllpType.INIT_FC2_P, DllpType.INIT_FC2_NP, DllpType.INIT_FC2_CPL)
UPDATE_TYPES = (DllpType.UPDATE_FC_P, DllpType.UPDATE_FC_NP, DllpType.UPDATE_FC_CPL)
LOCAL_H_CAP = (32, 32, 8)
LOCAL_D_CAP = (128, 16, 32)


def fc_dllp(dllp_type, hdr, data, vc=0, hdr_scale=0, data_scale=0):
    pkt = Dllp()
    pkt.type = dllp_type
    pkt.vc = vc
    pkt.hdr_scale = FcScale(hdr_scale)
    pkt.data_scale = FcScale(data_scale)
    pkt.hdr_fc = hdr
    pkt.data_fc = data
    return pkt


async def cycles(dut, count=1):
    for _ in range(count):
        await RisingEdge(dut.clk)
    await Timer(1, units="ps")


async def reset_dut(dut):
    cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
    for name in (
        "link_up", "mac_rx_valid", "mac_rx_sop", "mac_rx_eop",
        "mac_rx_is_dllp", "mac_tx_ready", "tx_tlp_consume_valid",
        "rx_tlp_consume_valid", "rx_tlp_release_valid"
    ):
        getattr(dut, name).value = 0
    dut.mac_rx_data.value = 0
    dut.mac_rx_keep.value = 0
    dut.mac_rx_error.value = 0
    dut.tx_tlp_check_type.value = 0
    dut.tx_tlp_check_data_credits.value = 0
    dut.tx_tlp_consume_type.value = 0
    dut.tx_tlp_consume_data_credits.value = 0
    dut.rx_tlp_consume_type.value = 0
    dut.rx_tlp_consume_data_credits.value = 0
    dut.rx_tlp_release_type.value = 0
    dut.rx_tlp_release_data_credits.value = 0
    dut.rst_n.value = 0
    await cycles(dut, 4)
    assert int(dut.fc_state.value) == 0
    assert int(dut.dll_active.value) == 0
    assert int(dut.mac_tx_valid.value) == 0
    assert int(dut.tx_tlp_credit_available.value) == 0
    dut.rst_n.value = 1
    await cycles(dut, 2)


async def inject_bytes(dut, payload, chunks=(2, 2, 2), frame_error=0):
    assert sum(chunks) == len(payload)
    offset = 0
    for index, size in enumerate(chunks):
        assert size in (0, 1, 2)
        part = payload[offset:offset + size]
        dut.mac_rx_valid.value = 1
        dut.mac_rx_is_dllp.value = 1
        dut.mac_rx_sop.value = int(index == 0)
        dut.mac_rx_eop.value = int(index == len(chunks) - 1)
        dut.mac_rx_keep.value = (1 << size) - 1
        dut.mac_rx_data.value = int.from_bytes(part, "little") if part else 0
        dut.mac_rx_error.value = frame_error if index == len(chunks) - 1 else 0
        await cycles(dut)
        offset += size
    dut.mac_rx_valid.value = 0
    dut.mac_rx_sop.value = 0
    dut.mac_rx_eop.value = 0
    dut.mac_rx_keep.value = 0
    dut.mac_rx_error.value = 0


async def wait_rx_event(dut, timeout=40):
    for _ in range(timeout):
        if int(dut.rx_dllp_valid.value):
            return (
                int(dut.rx_dllp_data.value),
                int(dut.rx_dllp_crc_good.value),
                int(dut.rx_dllp_error.value),
            )
        await cycles(dut)
    raise AssertionError("等待 RX DLLP event 超时")


async def send_partner_dllp(dut, pkt, chunks=(2, 2, 2)):
    packed = pkt.pack_crc()
    await inject_bytes(dut, packed, chunks)
    event = await wait_rx_event(dut)
    assert event[0] == int.from_bytes(packed[:4], "little")
    assert event[1] == 1
    assert event[2] == 0
    await cycles(dut, 2)
    return event


async def recv_tx_dllp(dut, rng=None, timeout=200):
    output = bytearray()
    saw_sop = False
    stalled = None
    for _ in range(timeout):
        valid = int(dut.mac_tx_valid.value)
        if valid:
            snapshot = (
                int(dut.mac_tx_data.value), int(dut.mac_tx_keep.value),
                int(dut.mac_tx_sop.value), int(dut.mac_tx_eop.value),
                int(dut.mac_tx_is_dllp.value), int(dut.mac_tx_bad.value),
            )
            take = 1 if rng is None else rng.randint(0, 1)
            dut.mac_tx_ready.value = take
            if stalled is not None:
                assert snapshot == stalled, "MAC TX 在反压期间发生变化"
            if not take:
                stalled = snapshot
            else:
                stalled = None
                word, keep, sop, eop, is_dllp, bad = snapshot
                assert is_dllp == 1 and bad == 0 and keep == 3
                assert sop == int(not saw_sop)
                saw_sop = True
                output.extend(word.to_bytes(2, "little"))
                if eop:
                    assert len(output) == 6
                    result = bytes(output)
                    await cycles(dut)
                    dut.mac_tx_ready.value = 0
                    return result
        else:
            dut.mac_tx_ready.value = 0
        await cycles(dut)
    raise AssertionError("等待 TX DLLP 超时")


async def pulse_tx_consume(dut, fc_type, data_credits):
    dut.tx_tlp_consume_type.value = fc_type
    dut.tx_tlp_consume_data_credits.value = data_credits
    dut.tx_tlp_consume_valid.value = 1
    await cycles(dut)
    dut.tx_tlp_consume_valid.value = 0


async def pulse_rx_event(dut, consume, fc_type, data_credits):
    prefix = "rx_tlp_consume" if consume else "rx_tlp_release"
    getattr(dut, prefix + "_type").value = fc_type
    getattr(dut, prefix + "_data_credits").value = data_credits
    getattr(dut, prefix + "_valid").value = 1
    await cycles(dut)
    getattr(dut, prefix + "_valid").value = 0


async def initialize_fc(dut, remote=((5, 9), (0, 0), (7, 11)), rng=None):
    dut.link_up.value = 1
    await cycles(dut, 2)
    assert int(dut.fc_state.value) == 1
    assert int(dut.dll_active.value) == 0

    observed = []
    while len(observed) < 3:
        pkt = Dllp.unpack_crc(await recv_tx_dllp(dut, rng))
        if pkt.type in INIT1_TYPES:
            observed.append(pkt)
    assert {pkt.type for pkt in observed} == set(INIT1_TYPES)
    expected_local = {
        DllpType.INIT_FC1_P: (32, 128),
        DllpType.INIT_FC1_NP: (32, 16),
        DllpType.INIT_FC1_CPL: (8, 32),
    }
    for pkt in observed:
        assert (pkt.hdr_fc, pkt.data_fc) == expected_local[pkt.type]
        assert pkt.vc == 0 and int(pkt.hdr_scale) == 0 and int(pkt.data_scale) == 0

    for index in FC_TYPES:
        await send_partner_dllp(
            dut, fc_dllp(INIT1_TYPES[index], remote[index][0], remote[index][1]),
            chunks=(1, 2, 2, 1) if index == 1 else (2, 2, 2)
        )
    assert int(dut.fc_state.value) == 2

    # 允许 Codec 中已经排队的最后一个 InitFC1 先发完，直到看到 InitFC2。
    for _ in range(8):
        pkt = Dllp.unpack_crc(await recv_tx_dllp(dut, rng))
        if pkt.type in INIT2_TYPES:
            break
    else:
        raise AssertionError("DUT 未发送 InitFC2")

    await send_partner_dllp(dut, fc_dllp(DllpType.INIT_FC2_P, *remote[0]))
    assert int(dut.fc_state.value) == 3
    assert int(dut.dll_active.value) == 1


@cocotb.test()
async def initialization_and_credit_gating(dut):
    await reset_dut(dut)
    rng = random.Random(19)
    await initialize_fc(dut, rng=rng)

    assert int(dut.tx_ph_available.value) == 5
    assert int(dut.tx_pd_available.value) == 9
    assert int(dut.tx_nph_available.value) == 0xFF
    assert int(dut.tx_npd_available.value) == 0xFFF
    assert int(dut.tx_cplh_available.value) == 7
    assert int(dut.tx_cpld_available.value) == 11

    dut.tx_tlp_check_type.value = 0
    dut.tx_tlp_check_data_credits.value = 1
    await Timer(1, units="ps")
    assert int(dut.tx_tlp_credit_available.value) == 1
    for _ in range(5):
        await pulse_tx_consume(dut, 0, 1)
    assert int(dut.tx_ph_available.value) == 0
    assert int(dut.tx_pd_available.value) == 4
    await Timer(1, units="ps")
    assert int(dut.tx_tlp_credit_available.value) == 0

    await send_partner_dllp(dut, fc_dllp(DllpType.UPDATE_FC_P, 8, 20))
    assert int(dut.tx_ph_available.value) == 3
    assert int(dut.tx_pd_available.value) == 15
    await Timer(1, units="ps")
    assert int(dut.tx_tlp_credit_available.value) == 1


@cocotb.test()
async def codec_crosscheck_errors_and_passthrough(dut):
    await reset_dut(dut)
    dut.link_up.value = 1
    await cycles(dut, 2)

    all_fc = INIT1_TYPES + INIT2_TYPES + UPDATE_TYPES
    patterns = ((2, 2, 2), (1, 2, 2, 1), (1, 1, 2, 1, 1), (2, 2, 2, 0))
    for index, dllp_type in enumerate(all_fc):
        pkt = fc_dllp(dllp_type, 0x41 + index, 0x321 + index)
        packed = pkt.pack_crc()
        await inject_bytes(dut, packed, patterns[index % len(patterns)])
        data, good, error = await wait_rx_event(dut)
        assert data == int.from_bytes(packed[:4], "little")
        assert good == 1 and error == 0
        decoded = Dllp.unpack_crc(packed)
        assert decoded.type == dllp_type
        assert decoded.hdr_fc == 0x41 + index
        assert decoded.data_fc == 0x321 + index

    ack = Dllp.create_ack(0xA53)
    packed = ack.pack_crc()
    await inject_bytes(dut, packed, (1, 1, 1, 1, 1, 1))
    data, good, error = await wait_rx_event(dut)
    assert data == int.from_bytes(packed[:4], "little")
    assert good == 1 and error == 0

    bad_crc = bytearray(fc_dllp(DllpType.UPDATE_FC_P, 9, 17).pack_crc())
    bad_crc[5] ^= 0x20
    await inject_bytes(dut, bytes(bad_crc))
    _, good, error = await wait_rx_event(dut)
    assert good == 0 and error & 0x4

    await inject_bytes(dut, b"\x40\x00\x00\x00\x00", (1, 2, 2))
    _, good, error = await wait_rx_event(dut)
    assert good == 0 and error & 0x1

    valid = fc_dllp(DllpType.UPDATE_FC_NP, 4, 8).pack_crc()
    await inject_bytes(dut, valid, frame_error=1)
    _, good, error = await wait_rx_event(dut)
    assert good == 0 and error & 0x2
    await cycles(dut)
    assert int(dut.bad_crc_count.value) >= 1
    assert int(dut.malformed_dllp_count.value) >= 2


@cocotb.test()
async def local_credit_release_and_periodic_update(dut):
    await reset_dut(dut)
    await initialize_fc(dut)

    await pulse_rx_event(dut, True, 0, 3)
    assert int(dut.rx_ph_occupied.value) == 1
    assert int(dut.rx_pd_occupied.value) == 3
    await pulse_rx_event(dut, False, 0, 3)
    assert int(dut.rx_ph_occupied.value) == 0
    assert int(dut.rx_pd_occupied.value) == 0

    found_updated_p = False
    seen_types = set()
    for _ in range(30):
        pkt = Dllp.unpack_crc(await recv_tx_dllp(dut))
        if pkt.type in UPDATE_TYPES:
            seen_types.add(pkt.type)
        if (pkt.type == DllpType.UPDATE_FC_P and
                pkt.hdr_fc == 33 and pkt.data_fc == 131):
            found_updated_p = True
            break
    assert found_updated_p

    # 周期调度最终必须重发全部三类。
    for _ in range(30):
        pkt = Dllp.unpack_crc(await recv_tx_dllp(dut))
        if pkt.type in UPDATE_TYPES:
            seen_types.add(pkt.type)
        if seen_types == set(UPDATE_TYPES):
            break
    assert seen_types == set(UPDATE_TYPES)

    # 非法 release 不改变占用，只增加协议错误。
    before = int(dut.fc_protocol_error_count.value)
    await pulse_rx_event(dut, False, 1, 1)
    await cycles(dut)
    assert int(dut.rx_nph_occupied.value) == 0
    assert int(dut.rx_npd_occupied.value) == 0
    assert int(dut.fc_protocol_error_count.value) == before + 1


@cocotb.test()
async def invalid_fc_and_link_reset(dut):
    await reset_dut(dut)
    await initialize_fc(dut)
    before = int(dut.fc_protocol_error_count.value)

    await send_partner_dllp(dut, fc_dllp(DllpType.UPDATE_FC_P, 9, 9, vc=1))
    assert int(dut.fc_protocol_error_count.value) == before + 1
    before += 1
    await send_partner_dllp(
        dut, fc_dllp(DllpType.UPDATE_FC_P, 9, 9, hdr_scale=1)
    )
    assert int(dut.fc_protocol_error_count.value) == before + 1

    await pulse_rx_event(dut, True, 2, 4)
    assert int(dut.rx_cplh_occupied.value) == 1
    dut.link_up.value = 0
    await cycles(dut, 2)
    assert int(dut.fc_state.value) == 0
    assert int(dut.dll_active.value) == 0
    assert int(dut.tx_tlp_credit_available.value) == 0
    assert int(dut.rx_cplh_occupied.value) == 0
    assert int(dut.fc_protocol_error_count.value) == before + 1


@cocotb.test()
async def randomized_credit_events(dut):
    await reset_dut(dut)
    await initialize_fc(dut, remote=((200, 3000), (180, 2500), (160, 2000)))
    seed = int(os.getenv("K05_RANDOM_SEED", "20260806"))
    count = int(os.getenv("K05_RANDOM_EVENTS", "10000"))
    rng = random.Random(seed)
    local_h = [0, 0, 0]
    local_d = [0, 0, 0]

    for _ in range(count):
        fc_type = rng.randrange(3)
        if rng.randrange(2) == 0:
            # 只生成合法本地 consume/release；错误路径由 Directed 覆盖。
            if (local_h[fc_type] == 0 or rng.randrange(2) == 0) and local_h[fc_type] < LOCAL_H_CAP[fc_type]:
                amount = rng.randrange(0, min(4, LOCAL_D_CAP[fc_type] - local_d[fc_type]) + 1)
                await pulse_rx_event(dut, True, fc_type, amount)
                local_h[fc_type] += 1
                local_d[fc_type] += amount
            else:
                amount = rng.randrange(0, local_d[fc_type] + 1) if local_d[fc_type] else 0
                await pulse_rx_event(dut, False, fc_type, amount)
                local_h[fc_type] -= 1
                local_d[fc_type] -= amount
        else:
            dut.tx_tlp_check_type.value = fc_type
            dut.tx_tlp_check_data_credits.value = rng.randrange(0, 5)
            await Timer(1, units="ps")
            if int(dut.tx_tlp_credit_available.value):
                await pulse_tx_consume(
                    dut, fc_type, int(dut.tx_tlp_check_data_credits.value)
                )

        assert int(dut.rx_ph_occupied.value) == local_h[0]
        assert int(dut.rx_pd_occupied.value) == local_d[0]
        assert int(dut.rx_nph_occupied.value) == local_h[1]
        assert int(dut.rx_npd_occupied.value) == local_d[1]
        assert int(dut.rx_cplh_occupied.value) == local_h[2]
        assert int(dut.rx_cpld_occupied.value) == local_d[2]

    dut._log.info("K05 cocotb随机信用回归完成 events=%d seed=%d", count, seed)
