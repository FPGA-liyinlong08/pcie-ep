"""K07+K08生产路径的SimPort配置读写与RootComplex枚举测试。"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotbext.pcie.core.caps import PciCapId
from cocotbext.pcie.core.rc import RootComplex
from cocotbext.pcie.core.utils import PcieId

from k08_simport_adapter import K08SimPortAdapter


CLK_NS = 4
REQUEST_TIMEOUT_NS = 20_000
ENDPOINT_ID = PcieId(1, 0, 0)


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

    for _ in range(6):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(4):
        await RisingEdge(dut.clk)

    assert int(dut.bdf_valid.value) == 0
    assert int(dut.codec_cfg_request_count.value) == 0
    assert int(dut.codec_tx_completion_count.value) == 0


def make_root_and_adapter(dut):
    """构造顺序不能插入await，避免SimPort在尚未连接时发送FC DLLP。"""
    rc = RootComplex()
    adapter = K08SimPortAdapter(dut)
    root_port = adapter.connect_root_complex(rc)
    adapter.start()
    return rc, root_port, adapter


def assert_clean_codec(dut):
    assert int(dut.codec_ur_completion_count.value) == 0
    assert int(dut.codec_malformed_count.value) == 0
    assert int(dut.codec_unsupported_count.value) == 0
    assert int(dut.codec_tx_protocol_error_count.value) == 0


def assert_real_k07_path(dut, adapter, minimum_requests):
    """防止未来把该测试误改为Python Function直接响应。"""
    codec_requests = int(dut.codec_cfg_request_count.value)
    codec_completions = int(dut.codec_tx_completion_count.value)
    dut._log.info(
        "K07+K08真实路径计数：下行Type-0=%d，K07请求=%d，上行Completion=%d",
        adapter.root_cfg_type0_count, codec_requests, codec_completions)
    assert adapter.root_cfg_type0_count >= minimum_requests
    assert adapter.root_to_dut_count == adapter.root_cfg_type0_count
    assert adapter.dut_to_root_count == adapter.dut_completion_count
    assert codec_requests == adapter.root_cfg_type0_count
    assert codec_completions == adapter.dut_completion_count


@cocotb.test()
async def root_complex_config_read_write_through_k07_k08(dut):
    """先行门禁：一次身份读取、一次部分BE写和一次读回都走生产K07+K08。"""
    await reset_dut(dut)
    rc, _, adapter = make_root_and_adapter(dut)
    adapter.configure_direct_bus(secondary_bus=1)

    identity = await rc.config_read_dword(
        ENDPOINT_ID, 0x00, timeout=REQUEST_TIMEOUT_NS, timeout_unit="ns")
    assert identity == 0xE001_1234
    assert int(dut.bdf_valid.value) == 1
    assert int(dut.captured_bdf.value) == int(ENDPOINT_ID)
    assert int(dut.local_completer_id.value) == int(ENDPOINT_ID)

    # 只写Command低Byte，明确验证Tlp.first_be经过K07抵达K08。
    await rc.config_write_byte(
        ENDPOINT_ID, 0x04, 0x06,
        timeout=REQUEST_TIMEOUT_NS, timeout_unit="ns")
    command_status = await rc.config_read_dword(
        ENDPOINT_ID, 0x04,
        timeout=REQUEST_TIMEOUT_NS, timeout_unit="ns")
    assert command_status & 0xFFFF == 0x0006
    assert command_status >> 16 & 0x0010 == 0x0010
    assert int(dut.memory_space_enable.value) == 1
    assert int(dut.bus_master_enable.value) == 1

    await Timer(2 * CLK_NS, units="ns")
    assert_real_k07_path(dut, adapter, minimum_requests=3)
    assert_clean_codec(dut)


@cocotb.test()
async def root_complex_enumerates_rtl_endpoint(dut):
    """执行真实RootComplex.enumerate，不创建Python Device/Function端点。"""
    await reset_dut(dut)
    rc, _, adapter = make_root_and_adapter(dut)

    await rc.enumerate(timeout=REQUEST_TIMEOUT_NS, timeout_unit="ns")

    dev = rc.find_device(ENDPOINT_ID)
    assert dev is not None, "RootComplex未发现01:00.0 RTL Endpoint"
    assert dev.pcie_id == ENDPOINT_ID
    assert dev.vendor_id == 0x1234
    assert dev.device_id == 0xE001
    assert dev.class_code == 0xFF0000
    assert dev.revision_id == 0x01
    assert dev.header_type == 0x00

    assert dev.get_capability_offset(PciCapId.EXP) == 0x40
    assert dev.pcie_mpss == 0
    link_cap = await dev.config_read_dword(0x4C)
    assert link_cap & 0xF == 3
    assert link_cap >> 4 & 0x3F == 1

    assert dev.bar_size[0] == 0x1000
    assert dev.bar_addr[0] is not None
    assert dev.bar_addr[0] & 0xFFF == 0
    assert all(size == 0 for size in dev.bar_size[1:])
    assert int(dut.bar0_base.value) == dev.bar_addr[0]
    assert int(dut.bar0_probe_active.value) == 0

    await dev.enable_device()
    command = await dev.config_read_word(0x04)
    assert command & 0x2
    assert int(dut.memory_space_enable.value) == 1

    await Timer(2 * CLK_NS, units="ns")
    assert_real_k07_path(dut, adapter, minimum_requests=20)
    assert_clean_codec(dut)
