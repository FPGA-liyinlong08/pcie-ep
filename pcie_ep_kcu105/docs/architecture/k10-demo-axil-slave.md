# K10 Demo AXI4-Lite Slave 架构冻结

状态：**PASS / K10-DEMO-AXIL-v1 架构已冻结**

## 1. 职责

`demo_axil_slave`是K09 BAR0 Master后端的4 KiB、32-bit AXI4-Lite从设备，提供：

- 固定签名、版本、链路/LTSSM/DLL状态；
- 12个外部诊断计数器的只读窗口；
- 48个支持Byte Strobe的Scratch DWORD；
- 960个支持Byte Strobe的测试RAM DWORD。

本模块不判断PCIe BAR、不解析TLP、不生成Completion，不清除或累计上游错误计数，
也不实现DMA、中断、原子访问和AXI burst。

## 2. 内部结构

写通道分别锁存一个AW和一个W。两者可按任意顺序到达；全部到齐后只执行一次写入并
产生一个B响应。在B响应被接收前不接收下一组AW/W。读通道最多保存一个R响应，AR
握手后在后续时钟产生RVALID；R被接收前不接受新AR。

写地址低12位选择寄存器；高20位非零或地址低两位非零返回DECERR且无副作用。只读
区域合法写入被忽略并返回OKAY。读保留地址返回0和OKAY；4 KiB外或未对齐读返回0和
DECERR。

Scratch使用48×32-bit寄存器，PERST复位为0。测试RAM为960×32-bit阵列，采用同步读、
逐Byte写，不施加阵列复位，以允许Vivado推断Byte-write BRAM；复位后RAM内容未定义，
软件必须先写后读。RDATA/BRESP及全部valid在反压期间保持稳定。

## 3. 地址表

| 偏移 | 属性 | 内容 |
|---:|---|---|
| `0x000` | RO | 签名`0x50434945`（ASCII `PCIE`） |
| `0x004` | RO | 版本，v1为`0x00010000` |
| `0x008` | RO | `[0] link_up`、`[2:1] link_speed`、`[13:8] ltssm_state` |
| `0x00c` | RO | `[0] dll_active`、`[7:4] dll_state` |
| `0x010～0x03c` | RO | 12个冻结顺序的诊断计数器 |
| `0x040～0x0ff` | RW | 48个Scratch DWORD |
| `0x100～0xfff` | RW | 960个测试RAM DWORD |

计数器顺序为：RX坏Symbol、LTSSM重训、DLL LCRC、DLL NAK、DLL Replay、Replay
Timeout、TL Malformed、TL Unsupported、BAR UR、BAR CA、BAR AXI Error、BAR Payload
Error。

## 4. 状态、缓冲和错误处理

- `aw_pending`、`w_pending`各深度1；B响应深度1；R响应深度1；
- AW/W独立，禁止通过组合READY相互依赖；
- 正常访问BRESP/RRESP=`00`，未对齐或越界=`11`；不产生`SLVERR`；
- WSTRB逐Byte更新Scratch/RAM，`WSTRB=0`为成功的无副作用写；
- PERST#异步清除握手状态、响应valid、Scratch和响应寄存器；RAM不复位；
- 模块单时钟域，无CDC；目标`phy_coreclk=250 MHz`。

## 5. 非职责及后续集成

K10单元测试直接以AXI BFM驱动；K10集成测试把生产K09 Master连接生产K10 Slave。
PHY、DLL和Linux实板路径属于K11，不能用K10 TLP级集成替代。
