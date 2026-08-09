"""cocotbext-pcie SimPort与K07 128-bit Packet Stream之间的测试适配器。

该文件只替代尚未进入K08集成范围的物理层和数据链路层传输。配置TLP本身
必须由生产 ``pcie_tlp_codec`` 解码，Completion也必须由该模块重新编码。
"""

import cocotb
from cocotb.triggers import FallingEdge, RisingEdge
from cocotbext.pcie.core.port import SimPort
from cocotbext.pcie.core.tlp import Tlp, TlpType


def _contiguous_keep(byte_count):
    return (1 << byte_count) - 1 if byte_count else 0


def _word_from_bytes(data):
    return int.from_bytes(data.ljust(16, b"\0"), "little")


def _bytes_from_word(word, keep):
    result = bytearray()
    for lane in range(16):
        if keep & (1 << lane):
            result.append((word >> (8 * lane)) & 0xFF)
    return bytes(result)


class K08SimPortAdapter:
    """连接一个RootComplex Root Port和测试顶层TLP流。

    ``RootComplex.make_port()``仍创建真实的Python Root Port。Root Port把
    下行Type-1配置请求转换为Type-0之后，本类才做TLP对象/Packet Stream的
    无损搬运；它不读取或修改任何配置寄存器内容。
    """

    _FC_INIT = [[64, 1024, 64, 64, 64, 1024] for _ in range(8)]

    def __init__(self, dut):
        self.dut = dut
        self.port = SimPort(fc_init=self._FC_INIT)
        self.port.max_link_speed = 3
        self.port.max_link_width = 1
        self.port.rx_handler = self._handle_root_tlp

        self.root_port = None
        self._tx_monitor_task = None
        self.root_to_dut_count = 0
        self.dut_to_root_count = 0
        self.root_cfg_type0_count = 0
        self.dut_completion_count = 0

    def connect_root_complex(self, rc):
        """用 ``make_port`` 创建并连接Root Port，返回该Root Port对象。"""
        if self.root_port is not None:
            raise RuntimeError("SimPort适配器已经连接Root Complex")
        self.root_port = rc.make_port()
        self.root_port.connect(self.port)
        return self.root_port

    def configure_direct_bus(self, secondary_bus=1):
        """为不执行完整枚举的单次配置读写冒烟测试设置Root Port窗口。"""
        if self.root_port is None:
            raise RuntimeError("请先调用connect_root_complex")
        self.root_port.pri_bus_num = 0
        self.root_port.sec_bus_num = secondary_bus
        self.root_port.sub_bus_num = secondary_bus

    def start(self):
        """启动DUT Completion监视器；只能调用一次。"""
        if self._tx_monitor_task is not None:
            raise RuntimeError("SimPort适配器已经启动")
        self.dut.tx_tlp_ready.value = 1
        self._tx_monitor_task = cocotb.start_soon(self._monitor_dut_tx())
        return self._tx_monitor_task

    async def _handle_root_tlp(self, tlp):
        """SimPort RX回调：把Root Port下行TLP提交给生产K07。"""
        if not isinstance(tlp, Tlp):
            raise TypeError(f"SimPort向K07提交了非TLP对象: {type(tlp)!r}")

        # 直接相连设备的Type-1请求必须已经由Root Port转换为Type-0。
        if tlp.fmt_type in {TlpType.CFG_READ_0, TlpType.CFG_WRITE_0}:
            self.root_cfg_type0_count += 1
        elif tlp.fmt_type in {TlpType.CFG_READ_1, TlpType.CFG_WRITE_1}:
            raise AssertionError("Root Port未把直接相连配置请求转换为Type-0")

        self.root_to_dut_count += 1
        try:
            await self._send_dut_packet(bytes(tlp.pack()))
        finally:
            # K07完整接收EOP后即可向测试传输层归还RX信用。
            tlp.release_fc()

    async def _send_dut_packet(self, packet):
        if not packet or len(packet) > 144 or len(packet) % 4:
            raise AssertionError(f"K07输入TLP长度非法: {len(packet)} Byte")

        offset = 0
        first = True
        while offset < len(packet):
            chunk = packet[offset:offset + 16]
            last = offset + len(chunk) == len(packet)

            await FallingEdge(self.dut.clk)
            self.dut.rx_tlp_valid.value = 1
            self.dut.rx_tlp_data.value = _word_from_bytes(chunk)
            self.dut.rx_tlp_keep.value = _contiguous_keep(len(chunk))
            self.dut.rx_tlp_sop.value = int(first)
            self.dut.rx_tlp_eop.value = int(last)
            self.dut.rx_tlp_error.value = 0

            for _ in range(4096):
                await RisingEdge(self.dut.clk)
                if int(self.dut.rx_tlp_ready.value):
                    break
            else:
                raise AssertionError("等待K07 RX Packet Stream ready超时")

            offset += len(chunk)
            first = False

        await FallingEdge(self.dut.clk)
        self.dut.rx_tlp_valid.value = 0
        self.dut.rx_tlp_data.value = 0
        self.dut.rx_tlp_keep.value = 0
        self.dut.rx_tlp_sop.value = 0
        self.dut.rx_tlp_eop.value = 0
        self.dut.rx_tlp_error.value = 0

    async def _monitor_dut_tx(self):
        packet = bytearray()

        while True:
            await FallingEdge(self.dut.clk)

            if not int(self.dut.rst_n.value):
                packet.clear()
                continue

            if not (int(self.dut.tx_tlp_valid.value) and
                    int(self.dut.tx_tlp_ready.value)):
                continue

            keep = int(self.dut.tx_tlp_keep.value)
            sop = int(self.dut.tx_tlp_sop.value)
            eop = int(self.dut.tx_tlp_eop.value)
            error = int(self.dut.tx_tlp_error.value)

            if error:
                raise AssertionError(f"K07输出TLP错误标志: 0x{error:x}")
            if not keep or keep & (keep + 1):
                raise AssertionError(f"K07输出keep不连续: 0x{keep:04x}")
            if not eop and keep != 0xFFFF:
                raise AssertionError("K07非末拍输出了部分keep")
            if sop != (len(packet) == 0):
                raise AssertionError("K07输出SOP与Packet边界不一致")

            packet.extend(_bytes_from_word(int(self.dut.tx_tlp_data.value),
                                           keep))
            if not eop:
                continue

            raw = bytes(packet)
            packet.clear()
            await RisingEdge(self.dut.clk)

            tlp = Tlp.unpack(raw)
            if not tlp.check():
                raise AssertionError(f"K07输出的TLP未通过cocotbext检查: {tlp!r}")
            if not tlp.is_completion():
                raise AssertionError(f"K08集成平台收到非Completion上行TLP: {tlp!r}")

            self.dut_to_root_count += 1
            self.dut_completion_count += 1
            await self.port.send(tlp)

