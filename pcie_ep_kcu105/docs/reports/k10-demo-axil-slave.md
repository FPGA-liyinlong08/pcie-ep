# K10 Demo AXI4-Lite Slave 阶段冻结报告

日期：2026-08-09

状态：**PASS / K10-DEMO-AXIL-v1 已冻结**

## 1. 阶段结论

K10完成4 KiB、32-bit、单Outstanding AXI4-Lite从设备。地址空间包含固定签名/版本、
链路与DLL状态、12个诊断计数器、48 DWORD Scratch和960 DWORD测试RAM。AW/W可任意
顺序独立握手；Scratch/RAM支持全部16种WSTRB；未对齐或4 KiB外访问返回DECERR。

错误Stub、7项单模块回归、100,000请求随机反压、生产K09+K10集成、严格lint和KU040
250 MHz routed OOC全部通过。测试RAM最终推断为一个RAMB36E2，LUTRAM为0。

## 2. 七步门禁

| 门禁 | 证据 | 状态 |
|---|---|---:|
| 架构冻结 | `docs/architecture/k10-demo-axil-slave.md` | PASS |
| 接口冻结 | `docs/interfaces/k10-demo-axil-slave-interfaces.md` | PASS |
| RTL前仿真计划 | `docs/verification/k10-verification-plan.md`，早于生产RTL建立 | PASS |
| 测试平台先行 | 错误Stub同时检出signature/strobe/decerr | PASS |
| RTL | `rtl/tl/demo_axil_slave.sv`，未扩展到K11 | PASS |
| 模块验证 | 7项单元、100k随机、K09集成、lint和routed OOC | PASS |
| 模块冻结 | 本报告、接口版本、白名单和已知限制已保存 | PASS |

## 3. 实现结果

- `0x000`签名=`0x50434945`，`0x004`版本=`0x00010000`；
- `0x008/0x00c`读取链路、LTSSM、DLL状态；`0x010～0x03c`为12个只读计数器；
- `0x040～0x0ff`为48个复位清零Scratch；
- `0x100～0xfff`为960个软件可见RAM DWORD，物理阵列深度1024以稳定推断BRAM；
- RAM无复位，采用同步读和逐Byte写；所有AXI读先锁存地址，再产生稳定R响应；
- 只读写入忽略并返回OKAY；WSTRB=0为成功无副作用写；错误访问无副作用并返回DECERR。

## 4. 错误Stub自检

同一个checker对故意错误替身得到预期失败：

```text
K10_NEGATIVE_CHECKER_OBSERVED signature strobe decerr
K10_CHECKER_SELFTEST_PASS signature=1 strobe=1 decerr=1
```

首次运行曾被替身文件名Warning提前终止，该次不计为有效自检；只对负向替身关闭
`DECLFILENAME`后，checker实际运行并同时命中三个数据守卫。

## 5. 单模块与随机回归

Verilator 5.020生产JUnit共7项，全部PASS：寄存器映射/只读保护、48 Scratch与16种
WSTRB、960 RAM全地址/walking-one、反压与错误路径、复位中断、checker守卫以及随机
参考模型。最终仿真时间`5,073,132.01 ns`，墙钟约`81.62 s`。

固定seed证据为：

```text
K10_RANDOM_SIGNOFF seed=20260810 requests=100000 writes=54720 reads=45280 decerr=5060 strobes=16 max_aw_w_delay=5 max_response_delay=3 writable_dwords=1008
```

随机回归初始化并覆盖全部1008个可写DWORD，AW/W间隔0～5拍、B/R响应反压0～3拍；
每1000个随机事务全量读回比较1008个DWORD，结束后再次全空间比较。

## 6. K09+K10生产集成

集成顶层实例化生产`pcie_bar_axil_master`和生产`demo_axil_slave`。结构化Memory请求
通过K09 AXI Master完成：签名读取、链路状态读取、Scratch全写+部分Byte写、以及BAR
末地址`0xffc` RAM写回。JUnit 1/1 PASS：

```text
K10_BAR_DEMO_INTEGRATION_PASS signature status scratch ram
```

该测试证明K09冻结AXI契约与K10逐位兼容，但不替代K11的K07/配置/DLL/PHY/VCS/Linux
完整路径。

## 7. KU040 250 MHz OOC

| 项目 | 结果 |
|---|---:|
| Implementation | ROUTED；routing error=0 |
| WNS / TNS | `+0.413 / 0.000 ns` |
| WHS / THS | `+0.049 / 0.000 ns` |
| Input / Output Setup Slack | `+0.413 / +1.615 ns` |
| Input / Output Hold Slack | `+0.277 / +0.539 ns` |
| LUT Primitive / FF | `847 / 1686` |
| RAMB36E2 / LUTRAM | `1 / 0` |
| DSP / PCIe Hard Block | `0 / 0` |
| 动态Partition Pin端口 | `545` |
| check_timing | no_clock、unconstrained、no/partial I/O delay全部0 |
| CDC | `All paths are Safely Timed.` |
| DRC | 仅OOC板级`CFGBVS-1 ×1` |
| 普通Warning | `Netlist 29-101 ×1`、`Synth 8-6779 ×8`、`Synth 8-7080 ×1` |

输入`MinDelay=-1 ns`只补偿OOC缺失的父层共享BUFG source insertion，不是硬件负hold
预算；K11完整共享时钟树必须取消并重检。失败运行不会发布摘要，最终routed结果又用
`K10_REUSE_BUILD=1`独立通过后置门禁。

## 8. 实施中闭合的问题

1. 修正cocotb driver在时钟沿后读取已下降READY造成的握手漏判；改为沿前采样握手。
2. 初版960深度、分离读写风格被推断为960个LUTRAM；改为`ram_style=block`的1024深度
   同步读写阵列，并增加统一读地址寄存级，最终为一个RAMB36E2。
3. 初版未限制OOC逻辑区域，虚拟输入的时钟插入偏差和只读大MUX导致setup/hold失败；
   使用真实`phy_coreclk` Clock Region的SLICE/RAMB36范围后，setup/hold均转正。
4. RAMB18非Tile边界范围产生`Vivado 12-4775`；改用实际RAMB36 Tile范围消除，未把
   可修复Warning加入白名单。
5. 候选摘要只在路由、时序、CDC、DRC、BRAM资源和Warning精确比较全部通过后发布。

## 9. 已知限制与冻结决定

- 单Outstanding、无burst，不追求每拍吞吐；
- RAM在PERST后内容未定义，软件必须先写后读；
- 只实现OKAY和DECERR，不主动产生SLVERR；
- 诊断计数器由上游维护，K11负责时钟域和具体信号连接；
- VCS串行、Linux枚举和实板BAR访问属于K11延期/集成门禁。

K10七步门禁全部通过，`K10-DEMO-AXIL-v1`正式冻结。K11尚未开始。
