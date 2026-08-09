"""cocotbext-pcie SimPort 与 K07 Packet Stream 的 K09 集成适配器。"""

import cocotb
from cocotb.queue import Queue
from cocotb.triggers import FallingEdge, RisingEdge, with_timeout
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


class K09SimPortAdapter:
    """连接 RootComplex Root Port 与 K07/K08/K09 生产路径。

    类本身只搬运已打包 TLP，不实现 BAR、配置或 Completion 逻辑。额外的
    ``send_direct_nonposted`` 仅用于构造 BAR miss TLP；以保留 Tag 路由该请求
    的 Completion，避免把它误交给 RootComplex 的正常 Tag 表。
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
        self._direct_waiters = {}

        self.root_to_dut_count = 0
        self.dut_to_root_count = 0
        self.root_cfg_type0_count = 0
        self.root_mem_read_count = 0
        self.root_mem_write_count = 0
        self.dut_completion_count = 0
        self.direct_completion_count = 0
        self.completion_history = []

    def connect_root_complex(self, rc):
        if self.root_port is not None:
            raise RuntimeError("SimPort适配器已经连接RootComplex")
        self.root_port = rc.make_port()
        self.root_port.connect(self.port)
        return self.root_port

    def start(self):
        if self._tx_monitor_task is not None:
            raise RuntimeError("SimPort适配器已经启动")
        self.dut.tx_tlp_ready.value = 1
        self._tx_monitor_task = cocotb.start_soon(self._monitor_dut_tx())
        return self._tx_monitor_task

    async def _handle_root_tlp(self, tlp):
        if not isinstance(tlp, Tlp):
            raise TypeError(f"SimPort向K07提交了非TLP对象: {type(tlp)!r}")

        if tlp.fmt_type in {TlpType.CFG_READ_0, TlpType.CFG_WRITE_0}:
            self.root_cfg_type0_count += 1
        elif tlp.fmt_type in {TlpType.CFG_READ_1, TlpType.CFG_WRITE_1}:
            raise AssertionError("Root Port未把直接相连配置请求转换为Type-0")
        elif tlp.fmt_type in {TlpType.MEM_READ, TlpType.MEM_READ_64}:
            self.root_mem_read_count += 1
        elif tlp.fmt_type in {TlpType.MEM_WRITE, TlpType.MEM_WRITE_64}:
            self.root_mem_write_count += 1

        self.root_to_dut_count += 1
        try:
            await self._send_dut_packet(bytes(tlp.pack()))
        finally:
            tlp.release_fc()

    async def send_direct_nonposted(self, tlp, timeout_us=20):
        """发送一个测试专用 NP TLP 并按 Requester ID/Tag 收取 Completion。"""
        if (not isinstance(tlp, Tlp) or
                tlp.fmt_type not in {TlpType.MEM_READ, TlpType.MEM_READ_64}):
            raise TypeError("direct路径只允许Memory Read TLP")
        key = (int(tlp.requester_id), int(tlp.tag))
        if key in self._direct_waiters:
            raise RuntimeError(f"direct Tag重复占用: {key!r}")
        queue = Queue(maxsize=1)
        self._direct_waiters[key] = queue
        try:
            await self._send_dut_packet(bytes(tlp.pack()))
            return await with_timeout(queue.get(), timeout_us, "us")
        finally:
            self._direct_waiters.pop(key, None)

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

            packet.extend(_bytes_from_word(int(self.dut.tx_tlp_data.value), keep))
            if not eop:
                continue

            raw = bytes(packet)
            packet.clear()
            await RisingEdge(self.dut.clk)
            tlp = Tlp.unpack(raw)
            if not tlp.check():
                raise AssertionError(f"K07输出TLP未通过cocotbext检查: {tlp!r}")
            if not tlp.is_completion():
                raise AssertionError(f"集成平台收到非Completion上行TLP: {tlp!r}")

            self.dut_completion_count += 1
            self.completion_history.append(tlp)
            key = (int(tlp.requester_id), int(tlp.tag))
            if key in self._direct_waiters:
                self.direct_completion_count += 1
                await self._direct_waiters[key].put(tlp)
            else:
                self.dut_to_root_count += 1
                await self.port.send(tlp)
