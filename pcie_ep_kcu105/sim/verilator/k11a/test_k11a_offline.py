import struct
import zlib

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotbext.pcie.core.dllp import Dllp, DllpType, FcScale
from cocotbext.pcie.core.tlp import Tlp, TlpType
from cocotbext.pcie.core.utils import PcieId


def make_fc(kind, hdr, data):
    pkt = Dllp()
    pkt.type = kind
    pkt.vc = 0
    pkt.hdr_scale = FcScale(0)
    pkt.data_scale = FcScale(0)
    pkt.hdr_fc = hdr
    pkt.data_fc = data
    return pkt


async def reset(dut):
    cocotb.start_soon(Clock(dut.pipe_clk, 8, units="ns").start())
    cocotb.start_soon(Clock(dut.core_clk, 4, units="ns").start())
    dut.pipe_rst_n.value = 0
    dut.core_rst_n.value = 0
    dut.link_up.value = 0
    dut.ltssm_state.value = 0
    dut.link_speed.value = 0
    dut.link_width.value = 1
    dut.hot_reset.value = 0
    dut.mac_rx_valid.value = 0
    dut.mac_rx_data.value = 0
    dut.mac_rx_keep.value = 0
    dut.mac_rx_sop.value = 0
    dut.mac_rx_eop.value = 0
    dut.mac_rx_is_dllp.value = 0
    dut.mac_rx_error.value = 0
    dut.mac_tx_ready.value = 1
    for _ in range(8):
        await RisingEdge(dut.core_clk)
    dut.pipe_rst_n.value = 1
    dut.core_rst_n.value = 1
    dut.link_up.value = 1
    dut.ltssm_state.value = 16
    for _ in range(8):
        await RisingEdge(dut.pipe_clk)


async def inject_frame(dut, payload, is_dllp):
    offset = 0
    first = True
    sizes = [2] * (len(payload) // 2)
    if len(payload) & 1:
        sizes.append(1)
    for index, size in enumerate(sizes):
        part = payload[offset:offset + size]
        dut.mac_rx_valid.value = 1
        dut.mac_rx_data.value = int.from_bytes(part, "little")
        dut.mac_rx_keep.value = (1 << size) - 1
        dut.mac_rx_sop.value = int(first)
        dut.mac_rx_eop.value = int(index == len(sizes) - 1)
        dut.mac_rx_is_dllp.value = int(is_dllp)
        dut.mac_rx_error.value = 0
        await RisingEdge(dut.pipe_clk)
        await Timer(1, units="ps")
        offset += size
        first = False
    dut.mac_rx_valid.value = 0
    dut.mac_rx_sop.value = 0
    dut.mac_rx_eop.value = 0
    dut.mac_rx_keep.value = 0


async def inject_dllp(dut, pkt):
    await inject_frame(dut, bytes(pkt.pack_crc()), True)


async def collect_frame(dut, wanted_dllp=None, timeout=20000):
    packet = bytearray()
    packet_kind = None
    for _ in range(timeout):
        await Timer(1, units="ps")
        take = int(dut.mac_tx_valid.value) and int(dut.mac_tx_ready.value)
        if take:
            data = int(dut.mac_tx_data.value)
            keep = int(dut.mac_tx_keep.value)
            sop = int(dut.mac_tx_sop.value)
            eop = int(dut.mac_tx_eop.value)
            kind = int(dut.mac_tx_is_dllp.value)
            if sop:
                packet = bytearray()
                packet_kind = kind
            for lane in range(2):
                if keep & (1 << lane):
                    packet.append((data >> (lane * 8)) & 0xff)
        await RisingEdge(dut.pipe_clk)
        if take and eop:
            if wanted_dllp is None or packet_kind == int(wanted_dllp):
                return bytes(packet)
            packet = bytearray()
            packet_kind = None
    raise AssertionError("等待MAC Frame超时")


async def initialize_fc(dut):
    init1 = {DllpType.INIT_FC1_P, DllpType.INIT_FC1_NP,
             DllpType.INIT_FC1_CPL}
    observed = set()
    while observed != init1:
        pkt = Dllp.unpack_crc(await collect_frame(dut, True))
        if pkt.type in init1:
            observed.add(pkt.type)

    await inject_dllp(dut, make_fc(DllpType.INIT_FC1_P, 32, 128))
    await inject_dllp(dut, make_fc(DllpType.INIT_FC1_NP, 32, 16))
    await inject_dllp(dut, make_fc(DllpType.INIT_FC1_CPL, 32, 32))

    while True:
        pkt = Dllp.unpack_crc(await collect_frame(dut, True))
        if pkt.type in {DllpType.INIT_FC2_P, DllpType.INIT_FC2_NP,
                        DllpType.INIT_FC2_CPL}:
            break
    await inject_dllp(dut, make_fc(DllpType.INIT_FC2_P, 32, 128))
    for _ in range(20):
        await RisingEdge(dut.pipe_clk)
        if int(dut.dll_active.value):
            return
    raise AssertionError("DLL未进入Active")


def cfg_tlp(write, dw_addr, tag, value=0):
    tlp = Tlp()
    tlp.fmt_type = TlpType.CFG_WRITE_0 if write else TlpType.CFG_READ_0
    tlp.requester_id = PcieId(0, 0, 0)
    tlp.completer_id = PcieId(1, 0, 0)
    tlp.tag = tag
    tlp.address = dw_addr << 2
    tlp.first_be = 0xf
    tlp.last_be = 0
    tlp.length = 1
    if write:
        tlp.data = bytearray(struct.pack("<I", value))
    return tlp


def mem_read(address, tag):
    tlp = Tlp()
    tlp.fmt_type = TlpType.MEM_READ
    tlp.requester_id = PcieId(0, 0, 0)
    tlp.tag = tag
    tlp.set_addr_be(address, 4)
    return tlp


async def send_tlp(dut, sequence, tlp):
    packet = bytes(tlp.pack())
    protected = bytes([(sequence >> 8) & 0x0f, sequence & 0xff]) + packet
    await inject_frame(dut, protected + zlib.crc32(protected).to_bytes(4, "little"), False)


async def get_completion_and_ack(dut):
    wire = await collect_frame(dut, False)
    assert len(wire) >= 18
    tx_seq = ((wire[0] & 0x0f) << 8) | wire[1]
    assert wire[-4:] == zlib.crc32(wire[:-4]).to_bytes(4, "little")
    tlp = Tlp.unpack(wire[2:-4])
    await inject_dllp(dut, Dllp.create_ack(tx_seq))
    return tlp


@cocotb.test()
async def gen1_dll_cfg_bar_demo_path(dut):
    await reset(dut)
    await initialize_fc(dut)

    await send_tlp(dut, 0, cfg_tlp(False, 0, 0x10))
    identity = await get_completion_and_ack(dut)
    assert bytes(identity.data) == struct.pack("<I", 0xE0011234)
    assert int(dut.captured_bdf.value) == int(PcieId(1, 0, 0))

    await send_tlp(dut, 1, cfg_tlp(True, 4, 0x11, 0x80000000))
    await get_completion_and_ack(dut)
    await send_tlp(dut, 2, cfg_tlp(True, 1, 0x12, 0x00000002))
    await get_completion_and_ack(dut)
    assert int(dut.bar0_base.value) == 0x80000000
    assert int(dut.memory_space_enable.value) == 1

    await send_tlp(dut, 3, mem_read(0x80000000, 0x13))
    signature = await get_completion_and_ack(dut)
    assert bytes(signature.data) == struct.pack("<I", 0x50434945)

    # PIPE域Hot Reset单拍必须跨到Core域，并只复位配置状态。
    dut.hot_reset.value = 1
    await RisingEdge(dut.pipe_clk)
    dut.hot_reset.value = 0
    for _ in range(12):
        await RisingEdge(dut.core_clk)
    assert int(dut.bar0_base.value) == 0
    assert int(dut.memory_space_enable.value) == 0
    assert int(dut.dll_active.value) == 1
    assert int(dut.cdc_errors.value) == 0
