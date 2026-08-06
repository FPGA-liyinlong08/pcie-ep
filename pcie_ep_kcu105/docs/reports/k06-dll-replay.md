# K06 ACK/NAK 与 Replay 阶段报告

日期：2026-08-06

状态：**PASS / K06-v1 已冻结**

接口版本：`K06-REPLAY128-v1`

## 1. 结论

K06已实现12-bit Sequence、TLP LCRC32、累计ACK/NAK、Replay Timer、Replay
Buffer、RX去重/顺序检查和累计ACK调度。生产顶层`pcie_dll`已集成K05 DLLP
Codec/FC Manager，并用ACK优先的Raw DLLP仲裁器和Packet边界锁定仲裁器连接K03。

本阶段没有实现TLP完整解码、配置空间、BAR或DMA，也没有修改K03 LTSSM。

## 2. RTL交付

| 模块 | 职责 |
|---|---|
| `pcie_dll_replay.sv` | TX/RX Sequence、LCRC、累计ACK/NAK、Timer、Replay Window和统计 |
| `pcie_dllp_tx_arbiter.sv` | ACK/NAK优先的Raw DLLP单拍仲裁 |
| `pcie_dll_mac_tx_arbiter.sv` | DLLP优先、选择后锁定到EOP的MAC Packet仲裁 |
| `pcie_dll.sv` | K05 Codec/FC Manager与K06 Replay/仲裁器生产集成 |
| `k06_dll_ooc_top.sv` | KU040完整DLL OOC签核包装 |

TX Replay Window默认16项，每项最大144 Byte；RX使用8个150 Byte物理Frame槽和
8个144 Byte Payload槽。三个浅存储体在当前KU040 OOC中推断为LUTRAM。FC许可、
ACK/NAK事件和Payload RAM写请求各打一拍，K04 CRC接口和结果延迟保持不变。

## 3. Checker、Lint与cocotb

错误Stub接受TL Packet但不添加Sequence/LCRC，也不产生MAC输出。首个TX用例在
等待MAC Packet时超时，JUnit正确记录failure：

```text
K06_CHECKER_SELFTEST_PASS
```

Replay Core和完整`pcie_dll`均通过Verilator 5.020 `--lint-only -Wall`，0 Error、
0未说明Warning。cocotb 1.9.2及cocotbext-pcie 0.2.16结果：

| 验证项 | 结果 |
|---|---:|
| Sequence Byte顺序、TLP透明传输、zlib LCRC逐Byte比对 | PASS |
| 累计ACK、NAK Replay、ACK丢失、Timer Replay和fatal/recovery | PASS |
| RX唯一/重复/未来Sequence、坏LCRC、MAC错误及合法恢复 | PASS |
| 最大144 Byte RX、独立EOP、TL/MAC随机反压 | PASS |
| ACK/NAK与`cocotbext-pcie Dllp.pack()`逐Byte一致 | PASS |
| 固定种子`20260806`的10,000个随机Packet和完整Sequence回绕 | PASS |
| Raw DLLP优先及MAC Packet边界锁定仲裁器 | 2/2 PASS |

Replay Core最终为`TESTS=5 PASS=5 FAIL=0 SKIP=0`，仲裁器为
`TESTS=2 PASS=2 FAIL=0 SKIP=0`。

## 4. Native签核

Native C++ Scoreboard逐包独立生成Sequence/TLP/LCRC期望值，确认累计ACK释放，
并周期插入NAK、逐Byte比较Replay与首次发送。签核目标为1,048,576个事务，覆盖
256次完整12-bit回绕：

```text
K06_NATIVE_PASS events=1048576 nak_replays=257 sequence_wraps=256 final_seq=0
```

原始摘要由`sim/verilator/k06_native/summary.txt`保存并可确定性重建。

## 5. KU040 OOC

目标器件`xcku040-ffva1156-2-e`，时钟约束4.000 ns：

| 项目 | 结果 |
|---|---:|
| WNS / TNS | `+0.400 ns / 0.000 ns` |
| WHS / THS | `+0.080 ns / 0.000 ns` |
| CLB LUT / LUT as Memory / FF / CARRY8 | `5403 / 1788 / 2225 / 115` |
| LUT Primitive | `4025` |
| BRAM / DSP / PCIe Hard Block | `0 / 0 / 0` |
| 无时钟寄存器 / 未约束内部端点 | `0 / 0` |
| CDC | 1×`CDC-9 Info`，0 Warning/Critical |
| DRC | 1×`CFGBVS-1 Warning`，0 Error/Critical |

普通Warning按ID和数量精确限制为`Synth 8-6779`×44、`Synth 8-7080`×1和
`Timing 38-242`×2；实际集合或数量变化、任何Critical Warning或Error都会使
构建失败。

## 6. 已知限制与延期

- 只支持VC0、最多144 Byte原始TLP和默认16项TX Replay Window；
- 仅为K05信用做最小P/NP/Cpl分类，完整Fmt/Type/Length错误处理属于K07；
- K03 RX没有ready，RX槽满时丢弃到EOP并增加`buffer_error_count`；正常信用配置
  必须保证不会发生该路径；
- 当前浅存储映射为1,788个LUT Memory，K11完整集成时需重新评估资源和布局；
- OOC时序不代替K11完整PHY/MAC/DLL/FIFO布局布线；
- VCS编译兼容性受`VCSCompiler_Net`许可证影响，经批准延期，最迟K11前补测；
- K06没有独立上板门禁；K11统一完成Gen1链路、枚举和BAR上板验收。

## 7. 冻结决定

`K06-REPLAY128-v1`的Sequence、Byte顺序、LCRC边界、累计ACK/NAK语义、Replay
Timer/Window、RX去重、信用事件、仲裁优先级、Buffer深度和错误计数全部冻结。
K06七步门禁已完成；本次停止在K06，没有开始K07 TLP Codec。
