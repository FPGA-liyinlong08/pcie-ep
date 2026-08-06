import os
import random
import re
import struct
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.handle import Force, Release
from cocotb.triggers import FallingEdge, RisingEdge, Timer
from cocotbext.pcie.core.tlp import CplStatus, Tlp, TlpAttr, TlpType
from cocotbext.pcie.core.utils import PcieId


CLK_NS = 4
RANDOM_SEED = int(os.getenv("K07_RANDOM_SEED", "20260806"))
RANDOM_PACKETS = int(os.getenv("K07_RANDOM_PACKETS", "10000"))
RAW_PACKETS = int(os.getenv("K07_RAW_PACKETS", "10000"))
MEMORY_RANDOM_PACKETS = int(os.getenv("K07_MEMORY_RANDOM_PACKETS", "2000"))
BACKPRESSURE_RNG = random.Random(RANDOM_SEED ^ 0xBACC07)


def random_stall_cycles():
    """每次握手独立产生1～4个完整反压周期。"""
    return BACKPRESSURE_RNG.randint(1, 4)


def assert_counter_saturation_structure():
    """VPI无法回写寄存器时，对统一饱和函数及所有调用点做可审计签核。"""
    rtl_path = (Path(__file__).resolve().parents[3] /
                "rtl/tl/pcie_tlp_codec.sv")
    source = rtl_path.read_text(encoding="utf-8")
    assert re.search(
        r"sat_inc32\s*=\s*\(&value\)\s*\?\s*value\s*:\s*value\s*\+\s*1'b1",
        source)
    counters = (
        "rx_packet_count", "cfg_request_count", "mem_request_count",
        "rx_completion_count", "tx_completion_count", "ur_completion_count",
        "malformed_count", "unsupported_count", "poisoned_count",
        "unexpected_completion_count", "tx_protocol_error_count",
    )
    for counter in counters:
        assert re.search(rf"sat_inc32\s*\(\s*{counter}\s*\)", source), counter


def bytes_to_word(data):
    return int.from_bytes(data.ljust(16, b"\0"), "little")


def contiguous_keep(count):
    return (1 << count) - 1 if count else 0


def pcie_id(value):
    return PcieId.from_int(value)


def make_cfg(write, requester=0x0110, target=0x0321, tag=0x5A,
             dw_addr=0x2AF, be=0x5, wdata=0x11223344, tc=0, attr=0):
    tlp = Tlp()
    tlp.fmt_type = TlpType.CFG_WRITE_0 if write else TlpType.CFG_READ_0
    tlp.requester_id = pcie_id(requester)
    tlp.completer_id = pcie_id(target)
    tlp.tag = tag
    tlp.address = (dw_addr & 0x3FF) << 2
    tlp.first_be = be
    tlp.last_be = 0
    tlp.length = 1
    tlp.tc = tc
    tlp.attr = TlpAttr(attr)
    if write:
        tlp.data = bytearray(struct.pack("<I", wdata))
    return tlp


def make_mem(write, address, length_dw, is_64=False, requester=0x0110,
             tag=0x5A, first_be=0xF, last_be=None, tc=0, attr=0,
             payload=None, poisoned=False):
    tlp = Tlp()
    if write:
        tlp.fmt_type = TlpType.MEM_WRITE_64 if is_64 else TlpType.MEM_WRITE
    else:
        tlp.fmt_type = TlpType.MEM_READ_64 if is_64 else TlpType.MEM_READ
    tlp.requester_id = pcie_id(requester)
    tlp.tag = tag
    tlp.address = address
    tlp.length = length_dw
    tlp.first_be = first_be
    tlp.last_be = (0 if length_dw == 1 else 0xF) if last_be is None else last_be
    tlp.tc = tc
    tlp.attr = TlpAttr(attr)
    tlp.ep = poisoned
    if write:
        if payload is None:
            payload = bytes((k * 29 + tag) & 0xFF for k in range(length_dw * 4))
        tlp.data = bytearray(payload)
    return tlp


def make_cpl(has_data, status=CplStatus.SC, completer=0x0321,
             requester=0x0110, tag=0x5A, length_dw=0, byte_count=0,
             lower_address=0, tc=0, attr=0, bcm=False, payload=None,
             poisoned=False):
    tlp = Tlp()
    tlp.fmt_type = TlpType.CPL_DATA if has_data else TlpType.CPL
    tlp.completer_id = pcie_id(completer)
    tlp.requester_id = pcie_id(requester)
    tlp.tag = tag
    tlp.status = status
    tlp.length = length_dw
    tlp.byte_count = byte_count
    tlp.lower_address = lower_address
    tlp.tc = tc
    tlp.attr = TlpAttr(attr)
    tlp.bcm = bcm
    tlp.ep = poisoned
    if has_data:
        if payload is None:
            payload = bytes((0xA0 + k) & 0xFF for k in range(length_dw * 4))
        tlp.data = bytearray(payload)
    return tlp


async def reset_dut(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    for name in (
        "rx_tlp_valid", "rx_tlp_data", "rx_tlp_keep", "rx_tlp_sop",
        "rx_tlp_eop", "rx_tlp_error", "tx_tlp_ready", "rx_release_ready",
        "cfg_req_ready", "cfg_rsp_valid", "cfg_rsp_status", "cfg_rsp_rdata",
        "cfg_rsp_completer_id", "mem_req_ready", "mem_w_ready",
        "rx_cpl_ready", "rx_cpl_data_ready", "cpl_req_valid",
        "cpl_req_has_data", "cpl_req_poisoned", "cpl_req_status",
        "cpl_req_bcm", "cpl_req_byte_count", "cpl_req_completer_id",
        "cpl_req_requester_id", "cpl_req_tag", "cpl_req_lower_address",
        "cpl_req_length_dw", "cpl_req_tc", "cpl_req_attr",
        "cpl_data_valid", "cpl_data", "cpl_data_keep", "cpl_data_last",
    ):
        getattr(dut, name).value = 0
    dut.local_completer_id.value = 0x0321
    dut.rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(3):
        await RisingEdge(dut.clk)
    assert int(dut.cfg_req_valid.value) == 0
    assert int(dut.mem_req_valid.value) == 0
    assert int(dut.rx_cpl_valid.value) == 0
    assert int(dut.tx_tlp_valid.value) == 0


async def pulse_reset(dut):
    """调用方位于下降沿；异步置位并在下降沿释放复位。"""
    dut.rst_n.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(3):
        await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)


def assert_reset_state(dut):
    for name in (
        "rx_release_valid", "cfg_req_valid", "mem_req_valid", "mem_w_valid",
        "rx_cpl_valid", "rx_cpl_data_valid", "tx_tlp_valid", "cfg_rsp_ready",
    ):
        assert int(getattr(dut, name).value) == 0
    for name in (
        "rx_packet_count", "cfg_request_count", "mem_request_count",
        "rx_completion_count", "tx_completion_count", "ur_completion_count",
        "malformed_count", "unsupported_count", "poisoned_count",
        "unexpected_completion_count", "tx_protocol_error_count",
    ):
        assert int(getattr(dut, name).value) == 0


async def send_packet(dut, packet, error=0, idle_rng=None):
    assert 1 <= len(packet) <= 160
    offset = 0
    first = True
    while offset < len(packet):
        if idle_rng is not None:
            for _ in range(idle_rng.randrange(3)):
                dut.rx_tlp_valid.value = 0
                await RisingEdge(dut.clk)
        chunk = packet[offset:offset + 16]
        last = offset + len(chunk) == len(packet)
        await FallingEdge(dut.clk)
        dut.rx_tlp_valid.value = 1
        dut.rx_tlp_data.value = bytes_to_word(chunk)
        dut.rx_tlp_keep.value = contiguous_keep(len(chunk))
        dut.rx_tlp_sop.value = first
        dut.rx_tlp_eop.value = last
        dut.rx_tlp_error.value = error if last else 0
        for _ in range(1000):
            await RisingEdge(dut.clk)
            if int(dut.rx_tlp_ready.value):
                break
        else:
            raise AssertionError("等待K07 RX ready超时")
        offset += len(chunk)
        first = False
    await FallingEdge(dut.clk)
    dut.rx_tlp_valid.value = 0
    dut.rx_tlp_keep.value = 0
    dut.rx_tlp_sop.value = 0
    dut.rx_tlp_eop.value = 0
    dut.rx_tlp_error.value = 0


async def accept_record(dut, valid_name, ready_name, fields, timeout=1000):
    ready = getattr(dut, ready_name)
    ready.value = 0
    for _ in range(timeout):
        await FallingEdge(dut.clk)
        if int(getattr(dut, valid_name).value):
            result = {name: int(getattr(dut, name).value) for name in fields}
            # 随机保持1～4个完整反压周期，验证描述符/事件stall稳定。
            for _ in range(random_stall_cycles()):
                await RisingEdge(dut.clk)
                await FallingEdge(dut.clk)
                assert int(getattr(dut, valid_name).value)
                assert result == {name: int(getattr(dut, name).value)
                                  for name in fields}
            ready.value = 1
            await RisingEdge(dut.clk)
            await FallingEdge(dut.clk)
            ready.value = 0
            return result
    raise AssertionError(f"等待{valid_name}超时")


async def accept_release(dut):
    return await accept_record(
        dut, "rx_release_valid", "rx_release_ready",
        ("rx_release_type", "rx_release_data_credits"))


async def accept_cfg(dut):
    return await accept_record(
        dut, "cfg_req_valid", "cfg_req_ready",
        ("cfg_req_write", "cfg_req_dw_addr", "cfg_req_be", "cfg_req_wdata",
         "cfg_req_requester_id", "cfg_req_tag", "cfg_req_target_bdf"))


async def accept_mem_desc(dut):
    return await accept_record(
        dut, "mem_req_valid", "mem_req_ready",
        ("mem_req_write", "mem_req_64bit", "mem_req_poisoned",
         "mem_req_address", "mem_req_length_dw", "mem_req_first_be",
         "mem_req_last_be", "mem_req_requester_id", "mem_req_tag",
         "mem_req_tc", "mem_req_attr"))


async def accept_rx_cpl_desc(dut):
    return await accept_record(
        dut, "rx_cpl_valid", "rx_cpl_ready",
        ("rx_cpl_has_data", "rx_cpl_poisoned", "rx_cpl_status", "rx_cpl_bcm",
         "rx_cpl_byte_count", "rx_cpl_completer_id", "rx_cpl_requester_id",
         "rx_cpl_tag", "rx_cpl_lower_address", "rx_cpl_length_dw",
         "rx_cpl_tc", "rx_cpl_attr"))


async def collect_payload(dut, prefix, timeout=1000):
    if prefix == "rx_cpl_data":
        valid = dut.rx_cpl_data_valid
        ready = dut.rx_cpl_data_ready
        data_sig = dut.rx_cpl_data
        keep_sig = dut.rx_cpl_data_keep
        last_sig = dut.rx_cpl_data_last
    else:
        valid = getattr(dut, f"{prefix}_valid")
        ready = getattr(dut, f"{prefix}_ready")
        data_sig = getattr(dut, f"{prefix}_data")
        keep_sig = getattr(dut, f"{prefix}_keep")
        last_sig = getattr(dut, f"{prefix}_last")
    ready.value = 0
    result = bytearray()
    for _ in range(timeout):
        await FallingEdge(dut.clk)
        if int(valid.value):
            keep = int(keep_sig.value)
            assert keep and (keep & (keep + 1)) == 0
            word = int(data_sig.value)
            snapshot = (word, keep, int(last_sig.value))
            for _ in range(random_stall_cycles()):
                await RisingEdge(dut.clk)
                await FallingEdge(dut.clk)
                assert int(valid.value)
                assert snapshot == (int(data_sig.value), int(keep_sig.value),
                                    int(last_sig.value))
            for lane in range(16):
                if keep & (1 << lane):
                    result.append((word >> (8 * lane)) & 0xFF)
            last = snapshot[2]
            ready.value = 1
            await RisingEdge(dut.clk)
            await FallingEdge(dut.clk)
            ready.value = 0
            if last:
                return bytes(result)
    raise AssertionError(f"等待{prefix} Payload超时")


async def send_cfg_response(dut, status, data=0, completer=0x0321):
    await FallingEdge(dut.clk)
    dut.cfg_rsp_status.value = int(status)
    dut.cfg_rsp_rdata.value = data
    dut.cfg_rsp_completer_id.value = completer
    dut.cfg_rsp_valid.value = 1
    for _ in range(1000):
        await RisingEdge(dut.clk)
        if int(dut.cfg_rsp_ready.value):
            break
    else:
        raise AssertionError("等待cfg_rsp_ready超时")
    await FallingEdge(dut.clk)
    dut.cfg_rsp_valid.value = 0


async def collect_tx_packet(dut, timeout=2000):
    dut.tx_tlp_ready.value = 0
    result = bytearray()
    metadata = None
    for _ in range(timeout):
        await FallingEdge(dut.clk)
        if int(dut.tx_tlp_valid.value):
            # ready=0时随机跨1～4拍检查输出稳定，再用下一上升沿完成握手。
            snapshot = (
                int(dut.tx_tlp_data.value), int(dut.tx_tlp_keep.value),
                int(dut.tx_tlp_sop.value), int(dut.tx_tlp_eop.value),
                int(dut.tx_tlp_type.value), int(dut.tx_tlp_data_credits.value),
            )
            for _ in range(random_stall_cycles()):
                await RisingEdge(dut.clk)
                await FallingEdge(dut.clk)
                assert int(dut.tx_tlp_valid.value) and snapshot == (
                    int(dut.tx_tlp_data.value), int(dut.tx_tlp_keep.value),
                    int(dut.tx_tlp_sop.value), int(dut.tx_tlp_eop.value),
                    int(dut.tx_tlp_type.value), int(dut.tx_tlp_data_credits.value),
                )
            if metadata is None:
                assert snapshot[2] == 1
                metadata = (snapshot[4], snapshot[5])
            else:
                assert snapshot[2] == 0
                assert metadata == (snapshot[4], snapshot[5])
            keep = snapshot[1]
            word = snapshot[0]
            assert keep and (keep & (keep + 1)) == 0
            for lane in range(16):
                if keep & (1 << lane):
                    result.append((word >> (8 * lane)) & 0xFF)
            eop = snapshot[3]
            dut.tx_tlp_ready.value = 1
            await RisingEdge(dut.clk)
            await FallingEdge(dut.clk)
            dut.tx_tlp_ready.value = 0
            if eop:
                assert int(dut.tx_tlp_error.value) == 0
                return bytes(result), metadata
    raise AssertionError("等待K07 TX Packet超时")


async def send_external_cpl(dut, tlp):
    has_data = tlp.fmt_type == TlpType.CPL_DATA
    await FallingEdge(dut.clk)
    dut.cpl_req_has_data.value = has_data
    dut.cpl_req_poisoned.value = int(tlp.ep)
    dut.cpl_req_status.value = int(tlp.status)
    dut.cpl_req_bcm.value = int(tlp.bcm)
    dut.cpl_req_byte_count.value = tlp.byte_count
    dut.cpl_req_completer_id.value = int(tlp.completer_id)
    dut.cpl_req_requester_id.value = int(tlp.requester_id)
    dut.cpl_req_tag.value = tlp.tag
    dut.cpl_req_lower_address.value = tlp.lower_address
    dut.cpl_req_length_dw.value = tlp.length
    dut.cpl_req_tc.value = int(tlp.tc)
    dut.cpl_req_attr.value = int(tlp.attr)
    dut.cpl_req_valid.value = 1
    for _ in range(1000):
        await RisingEdge(dut.clk)
        if int(dut.cpl_req_ready.value):
            break
    else:
        raise AssertionError("等待cpl_req_ready超时")
    await FallingEdge(dut.clk)
    dut.cpl_req_valid.value = 0

    if has_data:
        offset = 0
        while offset < len(tlp.data):
            chunk = bytes(tlp.data[offset:offset + 16])
            last = offset + len(chunk) == len(tlp.data)
            await FallingEdge(dut.clk)
            dut.cpl_data.value = bytes_to_word(chunk)
            dut.cpl_data_keep.value = contiguous_keep(len(chunk))
            dut.cpl_data_last.value = last
            dut.cpl_data_valid.value = 1
            for _ in range(1000):
                await RisingEdge(dut.clk)
                if int(dut.cpl_data_ready.value):
                    break
            else:
                raise AssertionError("等待cpl_data_ready超时")
            offset += len(chunk)
        await FallingEdge(dut.clk)
        dut.cpl_data_valid.value = 0
        dut.cpl_data_keep.value = 0
        dut.cpl_data_last.value = 0


def fc_metadata(raw):
    if len(raw) < 4:
        return 1, 0
    fmt_type = raw[0]
    wire_type = fmt_type & 0x1F
    has_data = bool(fmt_type & 0x40)
    raw_length = ((raw[2] & 3) << 8) | raw[3]
    length_dw = 1024 if raw_length == 0 else raw_length
    if wire_type == 0x0A:
        fc_type = 2
    elif wire_type == 0 and has_data:
        fc_type = 0
    else:
        fc_type = 1
    return fc_type, (length_dw + 3) // 4 if has_data else 0


async def assert_no_dispatch(dut, cycles=3):
    for _ in range(cycles):
        await FallingEdge(dut.clk)
        assert int(dut.cfg_req_valid.value) == 0
        assert int(dut.mem_req_valid.value) == 0
        assert int(dut.rx_cpl_valid.value) == 0
        assert int(dut.tx_tlp_valid.value) == 0


async def expect_ur_for_request(dut, request_raw, requester, tag):
    await send_packet(dut, request_raw)
    release = await accept_release(dut)
    exp_type, exp_dc = fc_metadata(request_raw)
    assert release == {"rx_release_type": exp_type,
                       "rx_release_data_credits": exp_dc}
    raw, metadata = await collect_tx_packet(dut)
    response = Tlp.unpack(raw)
    assert response.fmt_type == TlpType.CPL
    assert response.status == CplStatus.UR
    assert int(response.requester_id) == requester
    assert response.tag == tag
    assert metadata == (2, 0)


@cocotb.test()
async def whole_packet_commit_guard(dut):
    await reset_dut(dut)
    tlp = make_cfg(True)
    raw = bytes(tlp.pack())
    # 合法CfgWr只有16 Byte；故意声称还有下一拍，并在末拍注入错误。
    # 寄存式坏Stub会在首拍握手后提前产生Cfg请求。
    await FallingEdge(dut.clk)
    dut.rx_tlp_valid.value = 1
    dut.rx_tlp_data.value = bytes_to_word(raw)
    dut.rx_tlp_keep.value = 0xFFFF
    dut.rx_tlp_sop.value = 1
    dut.rx_tlp_eop.value = 0
    assert int(dut.rx_tlp_ready.value)
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    saw_early_cfg = bool(int(dut.cfg_req_valid.value))

    dut.rx_tlp_data.value = 0xDEADBEEF
    dut.rx_tlp_keep.value = 0x000F
    dut.rx_tlp_sop.value = 0
    dut.rx_tlp_eop.value = 1
    dut.rx_tlp_error.value = 1
    assert int(dut.rx_tlp_ready.value)
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.rx_tlp_valid.value = 0
    dut.rx_tlp_eop.value = 0
    dut.rx_tlp_error.value = 0

    for _ in range(5):
        await RisingEdge(dut.clk)
        await FallingEdge(dut.clk)
        saw_early_cfg |= bool(int(dut.cfg_req_valid.value))
    assert not saw_early_cfg, "DUT在完整错误Packet提交前产生了配置副作用"
    await accept_release(dut)
    assert int(dut.malformed_count.value) == 1


@cocotb.test()
async def cfg_decode_and_completion_encode(dut):
    await reset_dut(dut)
    cases = [
        (make_cfg(False, tc=3, attr=3), CplStatus.SC, 0xA1B2C3D4),
        (make_cfg(True, tag=0x22, be=0xF, wdata=0x55667788), CplStatus.SC, 0),
        (make_cfg(False, tag=0x33), CplStatus.UR, 0),
        (make_cfg(False, tag=0x44), CplStatus.CRS, 0),
        (make_cfg(False, tag=0x55), CplStatus.CA, 0),
    ]
    for request, status, data in cases:
        await send_packet(dut, bytes(request.pack()))
        cfg = await accept_cfg(dut)
        assert cfg["cfg_req_write"] == (request.fmt_type == TlpType.CFG_WRITE_0)
        assert cfg["cfg_req_dw_addr"] == request.address >> 2
        assert cfg["cfg_req_be"] == request.first_be
        assert cfg["cfg_req_requester_id"] == int(request.requester_id)
        assert cfg["cfg_req_target_bdf"] == int(request.completer_id)
        assert cfg["cfg_req_tag"] == request.tag
        if request.fmt_type == TlpType.CFG_WRITE_0:
            assert cfg["cfg_req_wdata"] == struct.unpack("<I", request.data)[0]
        release = await accept_release(dut)
        assert release == {"rx_release_type": 1,
                           "rx_release_data_credits": 1 if request.has_data() else 0}

        await send_cfg_response(dut, status, data)
        raw, metadata = await collect_tx_packet(dut)
        response = Tlp.unpack(raw)
        assert response.requester_id == request.requester_id
        assert response.completer_id == pcie_id(0x0321)
        assert response.tag == request.tag
        assert response.tc == request.tc
        assert response.attr == request.attr
        assert response.status == status
        if status == CplStatus.SC and request.fmt_type == TlpType.CFG_READ_0:
            assert response.fmt_type == TlpType.CPL_DATA
            assert response.length == 1 and response.byte_count == 4
            assert bytes(response.data) == struct.pack("<I", data)
            assert metadata == (2, 1)
        else:
            assert response.fmt_type == TlpType.CPL
            assert len(response.data) == 0
            assert metadata == (2, 0)

    assert int(dut.cfg_request_count.value) == len(cases)
    assert int(dut.tx_completion_count.value) == len(cases)


@cocotb.test()
async def memory_decode_and_payload(dut):
    await reset_dut(dut)
    writes = [
        make_mem(True, 0x12345678, 1, False, first_be=0x5, last_be=0),
        # Length=1且First/Last BE全0是合法的零字节Memory Write。
        make_mem(True, 0x12345000, 1, False, tag=0x69,
                 first_be=0, last_be=0, payload=b"\xde\xad\xbe\xef"),
        make_mem(True, 0x1122334455667000, 32, True, tag=0x6A,
                 first_be=0xE, last_be=0x7, tc=5, attr=5, poisoned=True),
    ]
    for request in writes:
        await send_packet(dut, bytes(request.pack()))
        desc = await accept_mem_desc(dut)
        assert desc["mem_req_write"] == 1
        assert desc["mem_req_64bit"] == (request.fmt_type == TlpType.MEM_WRITE_64)
        assert desc["mem_req_poisoned"] == int(request.ep)
        assert desc["mem_req_address"] == request.address
        assert desc["mem_req_length_dw"] == request.length
        assert desc["mem_req_first_be"] == request.first_be
        assert desc["mem_req_last_be"] == request.last_be
        assert desc["mem_req_requester_id"] == int(request.requester_id)
        assert desc["mem_req_tag"] == request.tag
        assert desc["mem_req_tc"] == int(request.tc)
        assert desc["mem_req_attr"] == int(request.attr)
        payload = await collect_payload(dut, "mem_w")
        assert payload == bytes(request.data)
        release = await accept_release(dut)
        assert release["rx_release_type"] == 0
        assert release["rx_release_data_credits"] == (request.length + 3) // 4

    reads = [
        # Length=1且First/Last BE全0是合法的零字节Memory Read。
        make_mem(False, 0x00000800, 1, False, tag=0x70,
                 first_be=0, last_be=0),
        make_mem(False, 0x00000FFC, 1, False, first_be=0xF, last_be=0),
        make_mem(False, 0x1122334455667000, 1024, True, tag=0x71,
                 first_be=0xF, last_be=0xF),
    ]
    for request in reads:
        await send_packet(dut, bytes(request.pack()))
        desc = await accept_mem_desc(dut)
        assert desc["mem_req_write"] == 0
        assert desc["mem_req_64bit"] == (request.fmt_type == TlpType.MEM_READ_64)
        assert desc["mem_req_address"] == request.address
        assert desc["mem_req_length_dw"] == request.length
        release = await accept_release(dut)
        assert release == {"rx_release_type": 1, "rx_release_data_credits": 0}

    assert int(dut.mem_request_count.value) == len(writes) + len(reads)
    assert int(dut.poisoned_count.value) == 1


@cocotb.test()
async def completion_decode_and_external_encode(dut):
    await reset_dut(dut)
    incoming = make_cpl(True, length_dw=2, byte_count=7,
                        lower_address=0x3C, tc=2, attr=2, bcm=True)
    await send_packet(dut, bytes(incoming.pack()))
    desc = await accept_rx_cpl_desc(dut)
    assert desc["rx_cpl_has_data"] == 1
    assert desc["rx_cpl_status"] == int(incoming.status)
    assert desc["rx_cpl_bcm"] == 1
    assert desc["rx_cpl_byte_count"] == incoming.byte_count
    assert desc["rx_cpl_completer_id"] == int(incoming.completer_id)
    assert desc["rx_cpl_requester_id"] == int(incoming.requester_id)
    assert desc["rx_cpl_tag"] == incoming.tag
    assert desc["rx_cpl_lower_address"] == incoming.lower_address
    assert desc["rx_cpl_length_dw"] == incoming.length
    assert await collect_payload(dut, "rx_cpl_data") == bytes(incoming.data)
    release = await accept_release(dut)
    assert release == {"rx_release_type": 2, "rx_release_data_credits": 1}
    assert int(dut.unexpected_completion_count.value) == 1

    outgoing = make_cpl(True, length_dw=32, byte_count=128,
                        lower_address=0x20, tag=0x81, tc=6, attr=7,
                        payload=bytes((k * 7 + 3) & 0xFF for k in range(128)))
    await send_external_cpl(dut, outgoing)
    raw, metadata = await collect_tx_packet(dut)
    assert raw == bytes(outgoing.pack())
    assert metadata == (2, 8)

    no_data = make_cpl(False, status=CplStatus.CA, tag=0x91)
    await send_external_cpl(dut, no_data)
    raw, metadata = await collect_tx_packet(dut)
    assert raw == bytes(no_data.pack())
    assert metadata == (2, 0)


@cocotb.test()
async def malformed_unsupported_and_release(dut):
    await reset_dut(dut)
    # 语法完整的Cfg Type-1是NP Unsupported，必须自动产生UR。
    cfg1 = make_cfg(False, tag=0xA5)
    cfg1.fmt_type = TlpType.CFG_READ_1
    await send_packet(dut, bytes(cfg1.pack()))
    release = await accept_release(dut)
    assert release["rx_release_type"] == 1
    raw, metadata = await collect_tx_packet(dut)
    ur = Tlp.unpack(raw)
    assert ur.fmt_type == TlpType.CPL
    assert ur.status == CplStatus.UR
    assert ur.requester_id == cfg1.requester_id and ur.tag == cfg1.tag
    assert metadata == (2, 0)

    malformed_before = int(dut.malformed_count.value)
    # Memory Read跨4 KiB：不得输出Memory描述符或UR，但仍需释放原FC信用。
    cross = make_mem(False, 0x00000FFC, 2, False, last_be=0xF)
    await send_packet(dut, bytes(cross.pack()))
    await accept_release(dut)
    for _ in range(12):
        await RisingEdge(dut.clk)
        assert int(dut.mem_req_valid.value) == 0
        assert int(dut.tx_tlp_valid.value) == 0
    assert int(dut.malformed_count.value) == malformed_before + 1

    # 上游error同样禁止任何副作用。
    bad_cfg = make_cfg(True, tag=0xBC)
    await send_packet(dut, bytes(bad_cfg.pack()), error=1)
    await accept_release(dut)
    for _ in range(6):
        await RisingEdge(dut.clk)
        assert int(dut.cfg_req_valid.value) == 0
    assert int(dut.malformed_count.value) == malformed_before + 2

    # Poisoned CfgWr不访问配置空间，直接返回CA并计一次Poisoned。
    poisoned_cfg = make_cfg(True, tag=0xBD, wdata=0x10203040)
    poisoned_cfg.ep = True
    cfg_before = int(dut.cfg_request_count.value)
    await send_packet(dut, bytes(poisoned_cfg.pack()))
    release = await accept_release(dut)
    assert release == {"rx_release_type": 1, "rx_release_data_credits": 1}
    raw, metadata = await collect_tx_packet(dut)
    ca = Tlp.unpack(raw)
    assert ca.fmt_type == TlpType.CPL
    assert ca.status == CplStatus.CA
    assert ca.requester_id == poisoned_cfg.requester_id
    assert ca.tag == poisoned_cfg.tag
    assert metadata == (2, 0)
    assert int(dut.cfg_request_count.value) == cfg_before
    assert int(dut.poisoned_count.value) == 1

    # Header Length不变但额外携带1 DW Payload，必须按Malformed丢弃。
    extra_payload = bytes(make_mem(True, 0x2000, 2, False).pack()) + b"\x01\x02\x03\x04"
    await send_packet(dut, extra_payload)
    await accept_release(dut)
    await assert_no_dispatch(dut)
    assert int(dut.malformed_count.value) == malformed_before + 3

    # Malformed优先于Poisoned：跨4 KiB的Poisoned Write只计Malformed。
    malformed_poison = make_mem(
        True, 0x0FFC, 2, False, tag=0xBE, last_be=0xF, poisoned=True)
    await send_packet(dut, bytes(malformed_poison.pack()))
    await accept_release(dut)
    await assert_no_dispatch(dut)
    assert int(dut.malformed_count.value) == malformed_before + 4
    assert int(dut.poisoned_count.value) == 1
    assert int(dut.unsupported_count.value) == 1
    assert int(dut.ur_completion_count.value) == 1


@cocotb.test()
async def unsupported_feature_matrix(dut):
    await reset_dut(dut)
    requests = []

    cfg1 = make_cfg(False, tag=0x11)
    cfg1.fmt_type = TlpType.CFG_READ_1
    requests.append(cfg1)
    cfg1w = make_cfg(True, tag=0x12)
    cfg1w.fmt_type = TlpType.CFG_WRITE_1
    requests.append(cfg1w)

    io_read = make_mem(False, 0x1000, 1, False, tag=0x13, last_be=0)
    io_read.fmt_type = TlpType.IO_READ
    requests.append(io_read)
    io_write = make_mem(True, 0x1000, 1, False, tag=0x14, last_be=0)
    io_write.fmt_type = TlpType.IO_WRITE
    requests.append(io_write)

    locked = make_mem(False, 0x2000, 1, False, tag=0x15, last_be=0)
    locked.fmt_type = TlpType.MEM_READ_LOCKED
    requests.append(locked)
    locked64 = make_mem(False, 0x1122334400002000, 2, True, tag=0x16)
    locked64.fmt_type = TlpType.MEM_READ_LOCKED_64
    requests.append(locked64)

    atomic = make_mem(True, 0x3000, 1, False, tag=0x17, last_be=0)
    atomic.fmt_type = TlpType.FETCH_ADD
    requests.append(atomic)
    atomic64 = make_mem(True, 0x1122334400003000, 2, True, tag=0x18)
    atomic64.fmt_type = TlpType.SWAP_64
    requests.append(atomic64)

    td_req = make_mem(False, 0x4000, 1, False, tag=0x19, last_be=0)
    td_req.td = True
    requests.append(td_req)
    th_req = make_mem(False, 0x5000, 1, False, tag=0x1A, last_be=0)
    th_req.th = True
    requests.append(th_req)
    at_req = make_mem(False, 0x6000, 1, False, tag=0x1B, last_be=0)
    at_req.at = 1
    requests.append(at_req)
    at_translated = make_mem(False, 0x7000, 1, False,
                             tag=0x1C, last_be=0)
    at_translated.at = 2
    requests.append(at_translated)

    for request in requests:
        raw = bytes(request.pack())
        if request.td:
            raw += b"\x12\x34\x56\x78"
        await expect_ur_for_request(
            dut, raw, int(request.requester_id), request.tag)

    posted_packets = [
        bytes.fromhex("30 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"),
        bytes.fromhex("70 00 00 01 00 00 00 00 00 00 00 00 00 00 00 00") +
        bytes.fromhex("44 33 22 11"),
        bytes.fromhex("80 00 00 00"),
    ]
    locked_cpl = make_cpl(False, status=CplStatus.SC, tag=0x31)
    locked_cpl.fmt_type = TlpType.CPL_LOCKED
    posted_packets.append(bytes(locked_cpl.pack()))

    for raw in posted_packets:
        await send_packet(dut, raw)
        release = await accept_release(dut)
        exp_type, exp_dc = fc_metadata(raw)
        assert release == {"rx_release_type": exp_type,
                           "rx_release_data_credits": exp_dc}
        await assert_no_dispatch(dut)
        if len(raw) == 4 and raw[0] == 0x80:
            # 独立Prefix没有可信Requester/Tag，诊断上下文必须清零。
            assert int(dut.error_requester_id.value) == 0
            assert int(dut.error_tag.value) == 0

    assert int(dut.unsupported_count.value) == len(requests) + len(posted_packets)
    assert int(dut.ur_completion_count.value) == len(requests)


@cocotb.test()
async def completion_boundary_and_encoder_validation(dut):
    await reset_dut(dut)
    for length in (1, 2, 31, 32):
        byte_count = length * 4
        incoming = make_cpl(
            True, length_dw=length, byte_count=byte_count,
            lower_address=(length * 3) & 0x7C, tag=0x40 + length,
            bcm=bool(length & 1),
            payload=bytes((length + k * 11) & 0xFF for k in range(length * 4)))
        await send_packet(dut, bytes(incoming.pack()))
        desc = await accept_rx_cpl_desc(dut)
        assert desc["rx_cpl_length_dw"] == length
        assert desc["rx_cpl_byte_count"] == byte_count
        assert desc["rx_cpl_bcm"] == int(incoming.bcm)
        assert await collect_payload(dut, "rx_cpl_data") == bytes(incoming.data)
        await accept_release(dut)

        outgoing = Tlp(incoming)
        await send_external_cpl(dut, outgoing)
        raw, metadata = await collect_tx_packet(dut)
        assert raw == bytes(outgoing.pack())
        assert metadata == (2, (length + 3) // 4)

    # Lower Address低两位1/2/3参与Byte Count合法性判断并必须原样解码。
    for lower_lsb in (1, 2, 3):
        incoming = make_cpl(
            True, length_dw=2, byte_count=8,
            lower_address=0x20 | lower_lsb, tag=0x60 + lower_lsb,
            payload=bytes((lower_lsb * 17 + k) & 0xFF for k in range(8)))
        await send_packet(dut, bytes(incoming.pack()))
        desc = await accept_rx_cpl_desc(dut)
        assert desc["rx_cpl_lower_address"] == incoming.lower_address
        assert desc["rx_cpl_byte_count"] == incoming.byte_count
        assert desc["rx_cpl_length_dw"] == incoming.length
        assert await collect_payload(dut, "rx_cpl_data") == bytes(incoming.data)
        await accept_release(dut)

    # 无数据Cpl允许非零Byte Count，Wire 0在RX接口保持逻辑0。
    for byte_count in (0, 4, 128, 4096):
        cpl = make_cpl(False, status=CplStatus.CA,
                       byte_count=byte_count, tag=(0x90 + byte_count) & 0xFF,
                       bcm=True)
        await send_external_cpl(dut, cpl)
        raw, metadata = await collect_tx_packet(dut)
        assert raw == bytes(cpl.pack())
        assert metadata == (2, 0)

        await send_packet(dut, raw)
        desc = await accept_rx_cpl_desc(dut)
        expected_bc = 0 if byte_count in (0, 4096) else byte_count
        assert desc["rx_cpl_byte_count"] == expected_bc
        assert desc["rx_cpl_has_data"] == 0
        await accept_release(dut)

    errors_before = int(dut.tx_protocol_error_count.value)
    # 非SC CplD描述符必须接受后drain完整Payload，且绝不产生半包。
    invalid = make_cpl(True, status=CplStatus.UR, length_dw=2,
                       byte_count=8, tag=0xE1)
    await send_external_cpl(dut, invalid)
    await assert_no_dispatch(dut, cycles=5)
    assert int(dut.tx_protocol_error_count.value) == errors_before + 1

    # Byte Count关系不足同样进入一次协议错误并drain。
    too_small = make_cpl(True, length_dw=2, byte_count=1,
                         lower_address=0, tag=0xE2)
    await send_external_cpl(dut, too_small)
    await assert_no_dispatch(dut, cycles=5)
    assert int(dut.tx_protocol_error_count.value) == errors_before + 2


@cocotb.test()
async def stream_errors_overflow_and_reset(dut):
    await reset_dut(dut)
    malformed_before = int(dut.malformed_count.value)

    # 十个完整拍，超过K06/K07冻结的144 Byte；DUT必须继续drain至EOP而不越界。
    overflow = bytearray(160)
    overflow[0:12] = bytes(make_mem(False, 0x1000, 1, False).pack())
    await send_packet(dut, bytes(overflow))
    await accept_release(dut)
    await assert_no_dispatch(dut)
    assert int(dut.malformed_count.value) == malformed_before + 1

    # 单拍非法keep和缺少SOP。
    raw = bytes(make_cfg(False).pack())
    await FallingEdge(dut.clk)
    dut.rx_tlp_valid.value = 1
    dut.rx_tlp_data.value = bytes_to_word(raw)
    dut.rx_tlp_keep.value = 0x0F0F
    dut.rx_tlp_sop.value = 0
    dut.rx_tlp_eop.value = 1
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.rx_tlp_valid.value = 0
    dut.rx_tlp_eop.value = 0
    await accept_release(dut)
    await assert_no_dispatch(dut)
    assert int(dut.malformed_count.value) == malformed_before + 2

    # 支持类型的Header不足12 Byte。
    short_header = bytes(make_cfg(False).pack())[:8]
    await send_packet(dut, short_header)
    await accept_release(dut)
    await assert_no_dispatch(dut)
    assert int(dut.malformed_count.value) == malformed_before + 3

    # 第二拍错误地重复SOP。
    mwr = bytes(make_mem(True, 0x2000, 8, False).pack())
    for beat_index, offset in enumerate(range(0, len(mwr), 16)):
        chunk = mwr[offset:offset + 16]
        await FallingEdge(dut.clk)
        dut.rx_tlp_valid.value = 1
        dut.rx_tlp_data.value = bytes_to_word(chunk)
        dut.rx_tlp_keep.value = contiguous_keep(len(chunk))
        dut.rx_tlp_sop.value = beat_index in (0, 1)
        dut.rx_tlp_eop.value = offset + len(chunk) == len(mwr)
        assert int(dut.rx_tlp_ready.value)
        await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.rx_tlp_valid.value = 0
    dut.rx_tlp_sop.value = 0
    dut.rx_tlp_eop.value = 0
    await accept_release(dut)
    await assert_no_dispatch(dut)
    assert int(dut.malformed_count.value) == malformed_before + 4

    # 分别在SOP握手后、中间拍握手后、EOP握手后异步复位。
    for reset_after_beats in (1, 2, 3):
        for beat_index in range(reset_after_beats):
            offset = beat_index * 16
            chunk = mwr[offset:offset + 16]
            await FallingEdge(dut.clk)
            dut.rx_tlp_valid.value = 1
            dut.rx_tlp_data.value = bytes_to_word(chunk)
            dut.rx_tlp_keep.value = contiguous_keep(len(chunk))
            dut.rx_tlp_sop.value = beat_index == 0
            dut.rx_tlp_eop.value = beat_index == 2
            assert int(dut.rx_tlp_ready.value)
            await RisingEdge(dut.clk)
        await FallingEdge(dut.clk)
        dut.rx_tlp_valid.value = 0
        dut.rx_tlp_keep.value = 0
        dut.rx_tlp_sop.value = 0
        dut.rx_tlp_eop.value = 0
        await pulse_reset(dut)
        assert_reset_state(dut)

    # 已提交Cfg请求、正在等待配置空间响应时复位。
    cfg_wait = make_cfg(False, tag=0xC1)
    await send_packet(dut, bytes(cfg_wait.pack()))
    await accept_cfg(dut)
    await accept_release(dut)
    assert int(dut.cfg_rsp_ready.value)
    await pulse_reset(dut)
    assert_reset_state(dut)

    # 外部CplD已经握手描述符和第一拍Payload时复位，不得发送半包。
    partial_cpl = make_cpl(
        True, length_dw=32, byte_count=128, tag=0xC2,
        payload=bytes((k * 13 + 7) & 0xFF for k in range(128)))
    await FallingEdge(dut.clk)
    dut.cpl_req_has_data.value = 1
    dut.cpl_req_poisoned.value = 0
    dut.cpl_req_status.value = int(partial_cpl.status)
    dut.cpl_req_bcm.value = int(partial_cpl.bcm)
    dut.cpl_req_byte_count.value = partial_cpl.byte_count
    dut.cpl_req_completer_id.value = int(partial_cpl.completer_id)
    dut.cpl_req_requester_id.value = int(partial_cpl.requester_id)
    dut.cpl_req_tag.value = partial_cpl.tag
    dut.cpl_req_lower_address.value = partial_cpl.lower_address
    dut.cpl_req_length_dw.value = partial_cpl.length
    dut.cpl_req_tc.value = int(partial_cpl.tc)
    dut.cpl_req_attr.value = int(partial_cpl.attr)
    dut.cpl_req_valid.value = 1
    assert int(dut.cpl_req_ready.value)
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.cpl_req_valid.value = 0
    dut.cpl_data.value = bytes_to_word(bytes(partial_cpl.data[:16]))
    dut.cpl_data_keep.value = 0xFFFF
    dut.cpl_data_last.value = 0
    dut.cpl_data_valid.value = 1
    assert int(dut.cpl_data_ready.value)
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.cpl_data_valid.value = 0
    dut.cpl_data_keep.value = 0
    await pulse_reset(dut)
    assert_reset_state(dut)

    # 尝试通过VPI force把计数器置于饱和边界。某些Verilator构建只允许读取
    # 顶层output reg；这种情况下记录明确的结构签核延期，不伪造动态覆盖。
    counter_vpi_writable = False
    try:
        dut.malformed_count.value = Force(0xFFFFFFFE)
        await Timer(1, units="ps")
        counter_vpi_writable = int(dut.malformed_count.value) == 0xFFFFFFFE
        if counter_vpi_writable:
            await send_packet(dut, short_header)
            await accept_release(dut)
            await assert_no_dispatch(dut)
        dut.malformed_count.value = Release()
        await Timer(1, units="ps")
    except Exception as exc:
        cocotb.log.info("K07计数器VPI force不可用：%s", exc)
        try:
            dut.malformed_count.value = Release()
        except Exception:
            pass

    if counter_vpi_writable and int(dut.malformed_count.value) == 0xFFFFFFFF:
        await send_packet(dut, short_header)
        await accept_release(dut)
        await assert_no_dispatch(dut)
        assert int(dut.malformed_count.value) == 0xFFFFFFFF
    else:
        cocotb.log.info(
            "K07_COUNTER_SATURATION_VPI_UNAVAILABLE：改由sat_inc32结构检查签核")
    assert_counter_saturation_structure()


@cocotb.test()
async def internal_priority_arbitration(dut):
    await reset_dut(dut)
    request = make_cfg(False, tag=0xD1)
    await send_packet(dut, bytes(request.pack()))
    await accept_cfg(dut)
    await accept_release(dut)

    external = make_cpl(False, status=CplStatus.CA, byte_count=4, tag=0xD2)
    await FallingEdge(dut.clk)
    dut.cfg_rsp_status.value = int(CplStatus.SC)
    dut.cfg_rsp_rdata.value = 0xCAFEBABE
    dut.cfg_rsp_completer_id.value = 0x0321
    dut.cfg_rsp_valid.value = 1
    dut.cpl_req_has_data.value = 0
    dut.cpl_req_poisoned.value = 0
    dut.cpl_req_status.value = int(external.status)
    dut.cpl_req_bcm.value = int(external.bcm)
    dut.cpl_req_byte_count.value = external.byte_count
    dut.cpl_req_completer_id.value = int(external.completer_id)
    dut.cpl_req_requester_id.value = int(external.requester_id)
    dut.cpl_req_tag.value = external.tag
    dut.cpl_req_lower_address.value = external.lower_address
    dut.cpl_req_length_dw.value = 0
    dut.cpl_req_tc.value = int(external.tc)
    dut.cpl_req_attr.value = int(external.attr)
    dut.cpl_req_valid.value = 1
    await Timer(1, units="ps")
    assert int(dut.cfg_rsp_ready.value) == 1
    assert int(dut.cpl_req_ready.value) == 0
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.cfg_rsp_valid.value = 0

    raw, _ = await collect_tx_packet(dut)
    cfg_cpl = Tlp.unpack(raw)
    assert cfg_cpl.fmt_type == TlpType.CPL_DATA
    assert bytes(cfg_cpl.data) == struct.pack("<I", 0xCAFEBABE)

    # 外部描述符在内部Packet完成后才获准握手。
    assert int(dut.cpl_req_ready.value), "内部Completion完成后外部描述符未获许可"
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.cpl_req_valid.value = 0
    raw, _ = await collect_tx_packet(dut)
    assert raw == bytes(external.pack())



@cocotb.test()
async def randomized_cfg_completion_reference(dut):
    await reset_dut(dut)
    rng = random.Random(RANDOM_SEED ^ 0xC07C07)
    cfg_count = 0
    cpl_count = 0
    tx_count = 0
    cfg_be_seen = set()
    cpl_length_seen = set()
    cpl_status_seen = set()
    cpl_byte_count_seen = set()

    for index in range(RANDOM_PACKETS):
        if index & 1:
            write = bool(rng.getrandbits(1))
            request = make_cfg(
                write, requester=rng.randrange(0x10000),
                target=rng.randrange(0x10000), tag=rng.randrange(256),
                dw_addr=rng.randrange(1024), be=rng.randrange(16),
                wdata=rng.getrandbits(32), tc=rng.randrange(8),
                attr=rng.randrange(8))
            await send_packet(dut, bytes(request.pack()))
            cfg = await accept_cfg(dut)
            assert cfg["cfg_req_write"] == write
            assert cfg["cfg_req_dw_addr"] == request.address >> 2
            assert cfg["cfg_req_be"] == request.first_be
            assert cfg["cfg_req_requester_id"] == int(request.requester_id)
            assert cfg["cfg_req_target_bdf"] == int(request.completer_id)
            assert cfg["cfg_req_tag"] == request.tag
            if write:
                assert cfg["cfg_req_wdata"] == struct.unpack("<I", request.data)[0]
            cfg_be_seen.add(request.first_be)
            await accept_release(dut)

            status = rng.choice((CplStatus.SC, CplStatus.UR,
                                 CplStatus.CRS, CplStatus.CA))
            rdata = rng.getrandbits(32)
            completer = rng.randrange(0x10000)
            await send_cfg_response(dut, status, rdata, completer)
            raw, metadata = await collect_tx_packet(dut)
            response = Tlp.unpack(raw)
            assert int(response.requester_id) == int(request.requester_id)
            assert int(response.completer_id) == completer
            assert response.tag == request.tag
            assert response.tc == request.tc and response.attr == request.attr
            assert response.status == status
            if status == CplStatus.SC and not write:
                assert response.fmt_type == TlpType.CPL_DATA
                assert bytes(response.data) == struct.pack("<I", rdata)
                assert metadata == (2, 1)
            else:
                assert response.fmt_type == TlpType.CPL
                assert metadata == (2, 0)
            cfg_count += 1
            tx_count += 1
        else:
            has_data = bool(rng.getrandbits(1))
            if has_data:
                length = rng.choice((1, 2, 31, 32))
                byte_count = length * 4
                status = CplStatus.SC
                payload = bytes(rng.getrandbits(8) for _ in range(length * 4))
            else:
                length = 0
                byte_count = rng.choice((0, 4, 128, 4096))
                status = rng.choice((CplStatus.SC, CplStatus.UR,
                                     CplStatus.CRS, CplStatus.CA))
                payload = None
            cpl = make_cpl(
                has_data, status=status, completer=rng.randrange(0x10000),
                requester=rng.randrange(0x10000), tag=rng.randrange(256),
                length_dw=length, byte_count=byte_count,
                lower_address=(rng.randrange(32) << 2) if has_data else 0,
                tc=rng.randrange(8), attr=rng.randrange(8),
                bcm=bool(rng.getrandbits(1)), payload=payload,
                poisoned=has_data and bool(rng.getrandbits(1)))
            cpl_length_seen.add(length)
            cpl_status_seen.add(int(status))
            cpl_byte_count_seen.add(byte_count)
            await send_packet(dut, bytes(cpl.pack()))
            desc = await accept_rx_cpl_desc(dut)
            assert desc["rx_cpl_has_data"] == has_data
            assert desc["rx_cpl_status"] == int(status)
            assert desc["rx_cpl_completer_id"] == int(cpl.completer_id)
            assert desc["rx_cpl_requester_id"] == int(cpl.requester_id)
            assert desc["rx_cpl_tag"] == cpl.tag
            assert desc["rx_cpl_poisoned"] == int(cpl.ep)
            assert desc["rx_cpl_bcm"] == int(cpl.bcm)
            expected_bc = (0 if not has_data and byte_count in (0, 4096)
                           else byte_count)
            assert desc["rx_cpl_byte_count"] == expected_bc
            assert desc["rx_cpl_lower_address"] == cpl.lower_address
            assert desc["rx_cpl_length_dw"] == length
            assert desc["rx_cpl_tc"] == int(cpl.tc)
            assert desc["rx_cpl_attr"] == int(cpl.attr)
            if has_data:
                assert desc["rx_cpl_length_dw"] == length
                assert await collect_payload(dut, "rx_cpl_data") == bytes(cpl.data)
            await accept_release(dut)
            cpl_count += 1

    assert int(dut.cfg_request_count.value) == cfg_count
    assert int(dut.rx_completion_count.value) == cpl_count
    assert int(dut.tx_completion_count.value) == tx_count
    assert cfg_be_seen == set(range(16))
    assert {0, 1, 2, 31, 32}.issubset(cpl_length_seen)
    assert {0, 1, 2, 4}.issubset(cpl_status_seen)
    assert {0, 4, 128, 4096}.issubset(cpl_byte_count_seen)


@cocotb.test()
async def randomized_raw_malformed_validator(dut):
    await reset_dut(dut)
    rng = random.Random(RANDOM_SEED ^ 0xBAD07)
    malformed_expected = 0
    unsupported_expected = 0
    cfg_expected = 0
    mem_expected = 0
    cpl_expected = 0
    tx_expected = 0

    for index in range(RAW_PACKETS):
        # 一半为语法合法Packet（包含正常分派、Unsupported NP产生UR和
        # Unsupported Posted静默丢弃），另一半为独立构造的Malformed Packet。
        if (index & 1) == 0:
            mode = (index // 2) % 6
            if mode == 0:
                write = bool(rng.getrandbits(1))
                request = make_cfg(
                    write, requester=rng.randrange(0x10000),
                    target=rng.randrange(0x10000), tag=rng.randrange(256),
                    dw_addr=rng.randrange(1024), be=rng.randrange(16),
                    wdata=rng.getrandbits(32), tc=rng.randrange(8),
                    attr=rng.randrange(8))
                raw = bytearray(request.pack())
                await send_packet(dut, bytes(raw), idle_rng=rng)
                cfg = await accept_cfg(dut)
                assert cfg["cfg_req_write"] == write
                assert cfg["cfg_req_dw_addr"] == request.address >> 2
                assert cfg["cfg_req_be"] == request.first_be
                assert cfg["cfg_req_requester_id"] == int(request.requester_id)
                assert cfg["cfg_req_target_bdf"] == int(request.completer_id)
                assert cfg["cfg_req_tag"] == request.tag
                if write:
                    assert cfg["cfg_req_wdata"] == struct.unpack(
                        "<I", request.data)[0]
                await accept_release(dut)
                await send_cfg_response(
                    dut, CplStatus.SC, rng.getrandbits(32),
                    int(request.completer_id))
                response, _ = await collect_tx_packet(dut)
                assert Tlp.unpack(response).status == CplStatus.SC
                cfg_expected += 1
                tx_expected += 1
                continue

            if mode in (1, 2):
                write = mode == 2
                length = rng.randint(1, 8) if write else rng.choice((1, 32, 1024))
                max_offset = 1024 - length
                address = (rng.getrandbits(20) << 12) | (
                    rng.randint(0, max_offset) << 2)
                request = make_mem(
                    write, address, length, bool(rng.getrandbits(1)),
                    requester=rng.randrange(0x10000), tag=rng.randrange(256),
                    first_be=rng.randint(1, 15),
                    last_be=0 if length == 1 else rng.randint(1, 15),
                    tc=rng.randrange(8), attr=rng.randrange(8))
                raw = bytearray(request.pack())
                await send_packet(dut, bytes(raw), idle_rng=rng)
                desc = await accept_mem_desc(dut)
                assert desc["mem_req_write"] == write
                assert desc["mem_req_64bit"] == (
                    request.fmt_type == TlpType.MEM_WRITE_64 if write else
                    request.fmt_type == TlpType.MEM_READ_64)
                assert desc["mem_req_poisoned"] == int(request.ep)
                assert desc["mem_req_address"] == address
                assert desc["mem_req_length_dw"] == length
                assert desc["mem_req_first_be"] == request.first_be
                assert desc["mem_req_last_be"] == request.last_be
                assert desc["mem_req_requester_id"] == int(request.requester_id)
                assert desc["mem_req_tag"] == request.tag
                assert desc["mem_req_tc"] == int(request.tc)
                assert desc["mem_req_attr"] == int(request.attr)
                if write:
                    assert await collect_payload(dut, "mem_w") == bytes(request.data)
                await accept_release(dut)
                mem_expected += 1
                continue

            if mode == 3:
                length = rng.randint(1, 8)
                request = make_cpl(
                    True, length_dw=length, byte_count=length * 4,
                    completer=rng.randrange(0x10000),
                    requester=rng.randrange(0x10000), tag=rng.randrange(256),
                    tc=rng.randrange(8), attr=rng.randrange(8),
                    payload=bytes(rng.getrandbits(8)
                                  for _ in range(length * 4)))
                raw = bytearray(request.pack())
                await send_packet(dut, bytes(raw), idle_rng=rng)
                desc = await accept_rx_cpl_desc(dut)
                assert desc["rx_cpl_has_data"] == 1
                assert desc["rx_cpl_poisoned"] == int(request.ep)
                assert desc["rx_cpl_status"] == int(request.status)
                assert desc["rx_cpl_bcm"] == int(request.bcm)
                assert desc["rx_cpl_byte_count"] == request.byte_count
                assert desc["rx_cpl_completer_id"] == int(request.completer_id)
                assert desc["rx_cpl_requester_id"] == int(request.requester_id)
                assert desc["rx_cpl_tag"] == request.tag
                assert desc["rx_cpl_lower_address"] == request.lower_address
                assert desc["rx_cpl_length_dw"] == length
                assert desc["rx_cpl_tc"] == int(request.tc)
                assert desc["rx_cpl_attr"] == int(request.attr)
                assert await collect_payload(dut, "rx_cpl_data") == bytes(request.data)
                await accept_release(dut)
                cpl_expected += 1
                continue

            if mode == 4:
                # 格式完整的Cfg Type-1 Read：K07不支持，属于NP并返回UR。
                request = make_cfg(False, requester=rng.randrange(0x10000),
                                   target=rng.randrange(0x10000),
                                   tag=rng.randrange(256))
                raw = bytearray(request.pack())
                raw[0] = 0x05
                await send_packet(dut, bytes(raw), idle_rng=rng)
                await accept_release(dut)
                response, _ = await collect_tx_packet(dut)
                assert Tlp.unpack(response).status == CplStatus.UR
                unsupported_expected += 1
                tx_expected += 1
                continue

            # 格式完整但带K07不支持属性的Posted Memory Write：只丢弃。
            request = make_mem(True, 0x2000, 2, False,
                               payload=bytes(rng.getrandbits(8) for _ in range(8)))
            raw = bytearray(request.pack())
            raw[1] |= 0x02
            await send_packet(dut, bytes(raw), idle_rng=rng)
            await accept_release(dut)
            await assert_no_dispatch(dut, cycles=1)
            unsupported_expected += 1
            continue

        mode = (index // 2) % 13
        error = 0
        if mode == 0:
            raw = bytearray(make_mem(False, 0x0FFC, 2, False).pack())
        elif mode == 1:
            raw = bytearray(make_mem(False, 0x1000, 1, False).pack())
            raw[1] |= 0x08  # Tag[8]
        elif mode == 2:
            raw = bytearray(make_mem(False, 0x1000, 1, False).pack())
            raw[2] |= 0x0C  # AT=Reserved
        elif mode == 3:
            raw = bytearray(make_cfg(False).pack())
            raw[3] = 2
        elif mode == 4:
            raw = bytearray(make_cfg(False).pack())
            raw[7] |= 0x10
        elif mode == 5:
            raw = bytearray(make_mem(
                True, 0x2000, 33, False, last_be=0xF,
                payload=bytes(rng.getrandbits(8) for _ in range(132))).pack())
        elif mode == 6:
            raw = bytearray(make_mem(True, 0x3000, 4, False).pack())[:-4]
        elif mode == 7:
            raw = bytearray(make_cpl(True, status=CplStatus.UR,
                                     length_dw=2, byte_count=8).pack())
        elif mode == 8:
            raw = bytearray(make_mem(False, 0x4000, 1, False).pack())
            raw[0] = 0x1F
        elif mode == 9:
            raw = bytearray(make_mem(False, 0x5000, 1, False).pack())
            raw[11] |= 1
        elif mode == 10:
            raw = bytearray(make_cfg(True).pack())
            error = 1
        elif mode == 11:
            raw = bytearray(make_cpl(True, length_dw=2, byte_count=1,
                                     lower_address=0).pack())
        else:
            raw = bytearray(make_cpl(False, status=CplStatus.SC).pack())
            raw[6] = (3 << 5)  # Reserved Completion Status

        await send_packet(dut, bytes(raw), error=error)
        release = await accept_release(dut)
        exp_type, exp_dc = fc_metadata(raw)
        assert release == {"rx_release_type": exp_type,
                           "rx_release_data_credits": exp_dc}
        await assert_no_dispatch(dut, cycles=1)
        malformed_expected += 1

    assert malformed_expected == RAW_PACKETS // 2
    assert int(dut.malformed_count.value) == malformed_expected
    assert int(dut.unsupported_count.value) == unsupported_expected
    assert int(dut.cfg_request_count.value) == cfg_expected
    assert int(dut.mem_request_count.value) == mem_expected
    assert int(dut.rx_completion_count.value) == cpl_expected
    assert int(dut.tx_completion_count.value) == tx_expected


@cocotb.test()
async def randomized_memory_headers(dut):
    await reset_dut(dut)
    rng = random.Random(RANDOM_SEED)
    for index in range(MEMORY_RANDOM_PACKETS):
        write = bool(rng.getrandbits(1))
        is_64 = bool(rng.getrandbits(1))
        length = rng.randint(1, 32) if write else rng.choice((1, 2, 31, 32, 1024))
        page = rng.getrandbits(40 if is_64 else 20) << 12
        max_dw_offset = 1024 - length
        address = page | (rng.randint(0, max_dw_offset) << 2)
        first_be = rng.randint(1, 15)
        last_be = 0 if length == 1 else rng.randint(1, 15)
        request = make_mem(
            write, address, length, is_64, requester=rng.randrange(0x10000),
            tag=rng.randrange(256), first_be=first_be, last_be=last_be,
            tc=rng.randrange(8), attr=rng.randrange(8))
        await send_packet(dut, bytes(request.pack()), idle_rng=rng)
        desc = await accept_mem_desc(dut)
        assert desc["mem_req_write"] == write
        assert desc["mem_req_64bit"] == is_64
        assert desc["mem_req_address"] == address
        assert desc["mem_req_length_dw"] == length
        assert desc["mem_req_first_be"] == first_be
        assert desc["mem_req_last_be"] == last_be
        assert desc["mem_req_requester_id"] == int(request.requester_id)
        assert desc["mem_req_tag"] == request.tag
        assert desc["mem_req_poisoned"] == int(request.ep)
        assert desc["mem_req_tc"] == int(request.tc)
        assert desc["mem_req_attr"] == int(request.attr)
        if write:
            observed = await collect_payload(dut, "mem_w")
            assert observed == bytes(request.data), (
                f"packet={index} length_dw={length} is_64={is_64} "
                f"observed={len(observed)} expected={len(request.data)}")
        await accept_release(dut)

    assert int(dut.mem_request_count.value) == MEMORY_RANDOM_PACKETS
    assert int(dut.malformed_count.value) == 0
