# K05 DLLP 与 Flow Control 阶段报告

日期：2026-08-06

状态：**PASS / K05-v1 已冻结**

接口版本：`K05-FC16-v1`

## 1. 结论

K05 已实现 6 Byte DLLP 编解码、K04 CRC16 复用、VC0 InitFC1/InitFC2、周期和
释放触发 UpdateFC，以及 P/NP/Cpl 六组 Header/Data 信用管理。`dll_active` 只在
远端三类初始信用收齐并收到任一 InitFC2/UpdateFC 后置位。

本阶段没有加入 ACK/NAK、Sequence 或 Replay，也没有修改 K03 LTSSM。

## 2. RTL 交付

| 模块 | 职责 |
|---|---|
| `pcie_dllp_codec.sv` | K03 可变 1/2 Byte 拍重组、严格6 Byte检查、CRC生成/检查、三拍TX |
| `pcie_dllp_fc_manager.sv` | DOWN/INIT1/INIT2/ACTIVE、远端信用、UpdateFC调度 |
| `pcie_fc_local_credit_pool.sv` | 本地占用和累计allocated计数、上下溢保护 |
| `pcie_dllp_fc.sv` | Codec/Manager集成、错误分类计数 |

架构、端口和 RTL 前计划分别位于 `docs/architecture`、`docs/interfaces` 和
`docs/verification` 的 K05 文档中。

## 3. Checker 与 cocotb

错误 Stub 固定跳过 InitFC并直接输出 Active。测试在 `link_up` 后观察到 state=3，
而期望 INIT1=1，JUnit 正确记录 failure：

```text
K05_CHECKER_SELFTEST_PASS
```

生产 RTL 通过 Verilator 5.020 `--lint-only -Wall`，0 Error、0未说明 Warning。
cocotb 1.9.2 与 cocotbext-pcie 0.2.16 的执行结果：

| 验证项 | 结果 |
|---|---:|
| 9种 InitFC1/InitFC2/UpdateFC 与 `Dllp.pack_crc()` 逐Byte比对 | PASS |
| `2+2+2`、`1+2+2+1`、全1 Byte及独立 `keep=00` EOP | PASS |
| TX随机反压稳定性、CRC/长度/framing/VC/Scale注错 | PASS |
| FC初始化、重复/延迟、有限/无限信用、周期UpdateFC、link下降 | PASS |
| 10,000个随机信用事件，种子`20260806` | PASS |

最终为 `TESTS=5 PASS=5 FAIL=0 SKIP=0`。

## 4. Native百万事件

独立 C++ Scoreboard 不使用 Python Driver 或 DUT 内部状态，签核结果为：

```text
K05_NATIVE_PASS events=1000000 tx_consumes=296162
remote_updates=300542 local_consumes=237749 local_releases=237728
protocol_errors=2999 seed=20260806
```

远端 limit 由 consumed 加合法半范围 grant 生成，持续触发 Header 8-bit 和 Data
12-bit 模计数回绕；本地 Packet 队列逐事件比对六组 occupied，并在结束时确认三类
最新累计 allocated 值都出现在 UpdateFC。

## 5. KU040 OOC

目标器件 `xcku040-ffva1156-2-e`，时钟约束4.000 ns：

| 项目 | 结果 |
|---|---:|
| WNS / TNS | `+0.219 ns / 0.000 ns` |
| WHS / THS | `+0.094 ns / 0.000 ns` |
| CLB LUT / FF / CARRY8 | `1137 / 761 / 57` |
| LUT Primitive | `1335` |
| BRAM / DSP / PCIe Hard Block | `0 / 0 / 0` |
| 无时钟寄存器 / 未约束内部端点 | `0 / 0` |
| CDC | 1×`CDC-9 Info`，0 Warning/Critical |
| DRC | 1×`CFGBVS-1 Warning`，0 Error/Critical |

普通 Warning 精确限定为 `Synth 8-7080`、`Timing 38-242` 和 OOC DRC
`CFGBVS-1`；新增类型会使脚本失败。

## 6. 已知限制与延期

- 只支持 VC0 和非 Scaled FC；VC1～7或Scale非0的FC DLLP被忽略并计错；
- 默认本地分区最坏占用3968 Byte，依赖 M02 默认8192 Byte容量；调整FIFO时必须
  重新计算分区和重跑K05/K11；
- Codec 原始 TX 接口当前只连接 FC Manager，K06 加入 ACK/NAK 时必须在冻结接口
  外增加仲裁，不能更改 Byte 顺序或握手；
- K05 OOC不代替K11完整K03+DLL+FIFO布局布线；
- VCS编译兼容性受 `VCSCompiler_Net` 许可证影响，经批准延期，最迟K11前补测；
  K05不需要独立实板验收。

## 7. 冻结决定

`K05-FC16-v1` 的状态机、DLLP Byte顺序、CRC边界、信用单位/宽度、无限信用语义、
本地默认分区、UpdateFC调度及错误行为全部冻结。K05七步门禁已完成；只有用户继续
要求后才进入K06，本次没有实现ACK/NAK或Replay。
