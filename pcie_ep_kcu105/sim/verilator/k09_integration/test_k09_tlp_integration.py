"""K07 + K08 + K09 生产RTL的真实TLP级集成回归。"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer
from cocotbext.pcie.core.rc import RootComplex
from cocotbext.pcie.core.tlp import CplStatus, Tlp, TlpType
from cocotbext.pcie.core.utils import PcieId

from k09_simport_adapter import K09SimPortAdapter


CLK_NS = 4
REQUEST_TIMEOUT_NS = 40_000
ENDPOINT_ID = PcieId(1, 0, 0)


class AxiLiteMemoryBfm:
    """允许AW/W独立握手的4 KiB AXI4-Lite存储器模型。"""

    def __init__(self, dut):
        self.dut = dut
        self.memory = bytearray((index * 37 + 11) & 0xFF
                                for index in range(4096))
        self.aw_queue = []
        self.w_queue = []
        self.pending_b = None
        self.pending_r = None
        self.read_errors = {}
        self.writes = []
        self.reads = []

    def inject_read_error(self, address, response=2):
        self.read_errors[address & 0xFFF] = response

    async def run(self):
        dut = self.dut
        dut.m_axil_awready.value = 0
        dut.m_axil_wready.value = 0
        dut.m_axil_bresp.value = 0
        dut.m_axil_bvalid.value = 0
        dut.m_axil_arready.value = 0
        dut.m_axil_rdata.value = 0
        dut.m_axil_rresp.value = 0
        dut.m_axil_rvalid.value = 0

        while True:
            await FallingEdge(dut.clk)
            # 固定ready令TLP集成用例聚焦于模块互连；随机反压属于K09单元回归。
            dut.m_axil_awready.value = 1
            dut.m_axil_wready.value = 1
            dut.m_axil_arready.value = int(self.pending_r is None)
            await Timer(1, units="ps")

            aw_fire = int(dut.m_axil_awvalid.value) and int(dut.m_axil_awready.value)
            w_fire = int(dut.m_axil_wvalid.value) and int(dut.m_axil_wready.value)
            b_fire = int(dut.m_axil_bvalid.value) and int(dut.m_axil_bready.value)
            ar_fire = int(dut.m_axil_arvalid.value) and int(dut.m_axil_arready.value)
            r_fire = int(dut.m_axil_rvalid.value) and int(dut.m_axil_rready.value)

            aw_value = int(dut.m_axil_awaddr.value) if aw_fire else None
            w_value = ((int(dut.m_axil_wdata.value),
                        int(dut.m_axil_wstrb.value)) if w_fire else None)
            ar_value = int(dut.m_axil_araddr.value) if ar_fire else None

            await RisingEdge(dut.clk)
            await Timer(1, units="ps")

            if aw_fire:
                assert aw_value < 4096 and aw_value & 3 == 0
                self.aw_queue.append(aw_value)
            if w_fire:
                assert w_value[1] != 0
                self.w_queue.append(w_value)
            if b_fire:
                dut.m_axil_bvalid.value = 0
                self.pending_b = None
            if ar_fire:
                assert ar_value < 4096 and ar_value & 3 == 0
                response = self.read_errors.pop(ar_value, 0)
                data = int.from_bytes(self.memory[ar_value:ar_value + 4],
                                      "little")
                self.pending_r = (ar_value, data, response)
            if r_fire:
                dut.m_axil_rvalid.value = 0
                self.pending_r = None

            if self.pending_b is None and self.aw_queue and self.w_queue:
                address = self.aw_queue.pop(0)
                data, strobe = self.w_queue.pop(0)
                for lane in range(4):
                    if strobe & (1 << lane):
                        self.memory[address + lane] = (
                            data >> (8 * lane)) & 0xFF
                self.writes.append((address, data, strobe))
                self.pending_b = 0

            if self.pending_b is not None and not int(dut.m_axil_bvalid.value):
                dut.m_axil_bresp.value = self.pending_b
                dut.m_axil_bvalid.value = 1

            if self.pending_r is not None and not int(dut.m_axil_rvalid.value):
                address, data, response = self.pending_r
                dut.m_axil_rdata.value = data
                dut.m_axil_rresp.value = response
                dut.m_axil_rvalid.value = 1
                self.reads.append((address, data, response))


async def reset_dut(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    dut.rst_n.value = 0
    dut.hot_reset.value = 0
    dut.link_up.value = 1
    dut.link_training.value = 0
    dut.dll_active.value = 1
    dut.link_speed.value = 0
    dut.link_width.value = 1
    dut.rx_tlp_valid.value = 0
    dut.rx_tlp_data.value = 0
    dut.rx_tlp_keep.value = 0
    dut.rx_tlp_sop.value = 0
    dut.rx_tlp_eop.value = 0
    dut.rx_tlp_error.value = 0
    dut.tx_tlp_ready.value = 0
    dut.rx_release_ready.value = 1
    dut.m_axil_awready.value = 0
    dut.m_axil_wready.value = 0
    dut.m_axil_bresp.value = 0
    dut.m_axil_bvalid.value = 0
    dut.m_axil_arready.value = 0
    dut.m_axil_rdata.value = 0
    dut.m_axil_rresp.value = 0
    dut.m_axil_rvalid.value = 0
    for _ in range(6):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(4):
        await RisingEdge(dut.clk)


async def wait_memory(dut, bfm, offset, expected, limit=20000):
    for _ in range(limit):
        await FallingEdge(dut.clk)
        if bfm.memory[offset:offset + len(expected)] == expected:
            return
    raise AssertionError(
        f"等待AXI写副作用超时: offset=0x{offset:03x} expected={expected.hex()}")


def make_direct_read(address, tag):
    req = Tlp()
    req.fmt_type = TlpType.MEM_READ
    req.requester_id = PcieId(0, 0, 0)
    req.tag = tag
    req.set_addr_be(address, 4)
    return req


def assert_clean_codec(dut):
    assert int(dut.codec_malformed_count.value) == 0
    assert int(dut.codec_unsupported_count.value) == 0
    assert int(dut.codec_tx_protocol_error_count.value) == 0


@cocotb.test()
async def enumerate_and_mmio_through_k07_k08_k09(dut):
    """枚举、8/16/32-bit、多DWORD、跨128B、UR和CA均走生产路径。"""
    await reset_dut(dut)
    bfm = AxiLiteMemoryBfm(dut)
    cocotb.start_soon(bfm.run())

    rc = RootComplex()
    adapter = K09SimPortAdapter(dut)
    adapter.connect_root_complex(rc)
    adapter.start()

    await rc.enumerate(timeout=REQUEST_TIMEOUT_NS, timeout_unit="ns")
    dev = rc.find_device(ENDPOINT_ID)
    assert dev is not None
    assert dev.vendor_id == 0x1234 and dev.device_id == 0xE001
    assert dev.bar_size[0] == 0x1000
    assert dev.bar_addr[0] is not None
    bar = int(dev.bar_addr[0])
    assert bar & 0xFFF == 0
    assert int(dut.bar0_base.value) == bar
    assert int(dut.bar0_probe_active.value) == 0

    await dev.enable_device()
    assert int(dut.memory_space_enable.value) == 1
    assert int(dut.local_completer_id.value) == int(ENDPOINT_ID)

    write_cases = (
        (0x041, b"\xa5"),
        (0x046, b"\x34\x12"),
        (0x04c, b"\xef\xbe\xad\xde"),
        (0x070, bytes((index * 13 + 7) & 0xFF for index in range(20))),
    )
    for offset, payload in write_cases:
        await rc.mem_write(bar + offset, payload,
                           timeout=REQUEST_TIMEOUT_NS, timeout_unit="ns")
        await wait_memory(dut, bfm, offset, payload)

    for offset, payload in write_cases:
        actual = await rc.mem_read(bar + offset, len(payload),
                                   timeout=REQUEST_TIMEOUT_NS,
                                   timeout_unit="ns")
        assert actual == payload, (
            f"MMIO读回错误 offset=0x{offset:03x}: "
            f"actual={actual.hex()} expected={payload.hex()}")

    # 33 DWORD 从0x7c开始，K09必须先在128 B边界给出1 DWORD，再给32 DWORD。
    boundary_offset = 0x07c
    boundary_data = bytes((index * 19 + 3) & 0xFF for index in range(132))
    bfm.memory[boundary_offset:boundary_offset + len(boundary_data)] = boundary_data
    history_start = len(adapter.completion_history)
    actual = await rc.mem_read(bar + boundary_offset, len(boundary_data),
                               timeout=REQUEST_TIMEOUT_NS, timeout_unit="ns")
    assert actual == boundary_data
    boundary_cpls = adapter.completion_history[history_start:]
    assert len(boundary_cpls) == 2
    assert [int(cpl.length) for cpl in boundary_cpls] == [1, 32]
    assert [int(cpl.byte_count) for cpl in boundary_cpls] == [132, 128]
    assert [int(cpl.lower_address) for cpl in boundary_cpls] == [0x7C, 0]
    assert all(cpl.status == CplStatus.SC for cpl in boundary_cpls)

    axi_reads_before = int(dut.bar_axi_read_count.value)
    ur = await adapter.send_direct_nonposted(
        make_direct_read(bar + 0x1000, 0xE0))
    assert ur.status == CplStatus.UR
    assert int(ur.length) == 0
    assert int(dut.bar_axi_read_count.value) == axi_reads_before

    bfm.inject_read_error(0x200, response=2)
    ca = await adapter.send_direct_nonposted(
        make_direct_read(bar + 0x200, 0xE1))
    assert ca.status == CplStatus.CA
    assert int(ca.length) == 0

    await Timer(4 * CLK_NS, units="ns")
    expected_mem_requests = (adapter.root_mem_read_count +
                             adapter.root_mem_write_count + 2)
    assert int(dut.codec_mem_request_count.value) == expected_mem_requests
    assert int(dut.bar_mem_request_count.value) == expected_mem_requests
    assert int(dut.bar_mem_write_count.value) == adapter.root_mem_write_count
    assert int(dut.bar_mem_read_count.value) == adapter.root_mem_read_count + 2
    assert int(dut.bar_ur_completion_count.value) == 1
    assert int(dut.bar_ca_completion_count.value) == 1
    assert int(dut.codec_ur_completion_count.value) == 1
    assert int(dut.bar_axi_write_count.value) == 8
    assert int(dut.bar_axi_read_count.value) == 42
    assert adapter.direct_completion_count == 2
    assert adapter.root_cfg_type0_count >= 20
    assert_clean_codec(dut)

    dut._log.info(
        "K09_TLP_INTEGRATION_PASS cfg=%d mem_rd=%d mem_wr=%d cpl=%d "
        "axi_rd=%d axi_wr=%d",
        adapter.root_cfg_type0_count, adapter.root_mem_read_count,
        adapter.root_mem_write_count, adapter.dut_completion_count,
        int(dut.bar_axi_read_count.value), int(dut.bar_axi_write_count.value))
