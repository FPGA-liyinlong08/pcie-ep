# K04 PCIe CRC 阶段报告

日期：2026-08-06

状态：**PASS / K04-v1 已冻结**

接口版本：`K04-CRC32S-v1`

## 1. 结论

已实现并验证两个可综合流式模块：

- `pcie_crc16_dllp`：PCIe DLLP CRC16，反射多项式 `16'hD008`；
- `pcie_crc32_lcrc`：PCIe TLP LCRC32，反射多项式 `32'hEDB88320`。

两者共用参数化 `pcie_crc_stream`，每拍接收 32 bit，线路首 Byte 固定在
`data[7:0]`，支持全部 15 种非零末拍 `keep`。生成 CRC 与包含接收 CRC 的 residue
检查均已通过。K04 不包含 DLLP 编解码、Flow Control、Sequence、ACK/NAK 或
Replay，这些仍属于 K05/K06。

## 2. 交付文件

| 类型 | 文件 |
|---|---|
| 架构 | `docs/architecture/k04-pcie-crc.md` |
| 接口 | `docs/interfaces/k04-pcie-crc-interfaces.md` |
| RTL 前计划 | `docs/verification/k04-verification-plan.md` |
| RTL | `rtl/dll/pcie_crc_stream.sv`、`pcie_crc16_dllp.sv`、`pcie_crc32_lcrc.sv` |
| cocotb | `sim/verilator/k04/test_pcie_crc.py` |
| 错误 Stub | `sim/verilator/k04/pcie_crc_bad_stub.sv` |
| 百万向量 | `sim/verilator/k04_native/k04_crc_native.cpp` |
| Vivado | `fpga/kcu105/run_k04_crc_ooc.tcl`、`run_k04_crc_ooc.sh` |

## 3. Checker 自检与 Lint

固定返回 0 的错误 Stub 在 `123456789` 已知向量上得到 CRC16 `0000`，期望值为
`0a3d`，JUnit 正确记录 failure，外层门禁输出：

```text
K04_CHECKER_SELFTEST_PASS
```

生产 RTL 通过 Verilator 5.020 `--lint-only -Wall`，0 Error。

## 4. cocotb 回归

环境：Verilator 5.020、cocotb 1.9.2、cocotbext-pcie 0.2.16，时钟 250 MHz，
固定随机种子 `20260806`。

| 用例 | 结果 |
|---|---:|
| 已知向量、全 0/全 1、1～4096 Byte | PASS |
| 全部 15 种末拍 `keep`、DLLP `pack_crc()` 交叉比对 | PASS |
| 正确 residue 和数据/CRC 区单 bit 错误 | PASS |
| 缺 start、嵌套 start、keep=0、非末拍 partial keep、复位恢复 | PASS |
| 10,000 个随机 Packet、随机 valid 空拍 | PASS |

最终结果为 `TESTS=5 PASS=5 FAIL=0 SKIP=0`，并输出：

```text
K04_VERILATOR_PASS packets=10000 seed=20260806
```

## 5. 独立百万向量签核

Native C++ 逐 bit 模型与 cocotb/Python Driver 独立，执行结果：

```text
K04_NATIVE_PASS algorithm_vectors=1000000 residue_vectors=100000
single_bit_error_vectors=100000 total_bytes=23475661 seed=20260806
```

`algorithm_vectors` 由 CRC16 和 CRC32 各 500,000 个构成；长度覆盖
1/2/3/4/15/16/17/127/128/129/255/256/511/512/1024/2048/4096 Byte，且周期性
遍历全部稀疏末拍 mask。

## 6. KU040 OOC 静态结果

器件为 `xcku040-ffva1156-2-e`，以 4.000 ns 时钟约束同时综合一套 CRC16 和一套
CRC32：

| 项目 | 结果 |
|---|---:|
| WNS / TNS | `+0.574 ns / 0.000 ns` |
| WHS / THS | `+0.103 ns / 0.000 ns` |
| LUT / FF | `428 / 108` |
| BRAM / DSP / PCIe Hard Block | `0 / 0 / 0` |
| 无时钟寄存器 / 未约束内部端点 | `0 / 0` |
| CDC | 1×`CDC-9 Info`，4 级复位同步链 |
| DRC | 1×`CFGBVS-1 Warning`，0 Error/Critical |

`CFGBVS-1` 只因 OOC 顶层没有板级配置电压属性；KCU105 集成约束已在 K01/K03
固定为 `CONFIG_VOLTAGE=1.8`、`CFGBVS=GND`。综合日志只允许
`Synth 8-7080` 和 `Timing 38-242`，新增 Warning 会使脚本失败。

## 7. 已知限制与延期

- 每个 CRC 实例一次只处理一个 Packet，不缓存输入或结果；后续 DLL 负责调度；
- 模块不检查 DLLP/TLP 协议长度，硬件也不限制最大 Packet；系统上限为 4096 Byte；
- `crc_match` 采用固定 residue，只在调用方把接收 CRC Byte 一并送入时有意义；
- OOC 结果是综合后静态时序，不代替 K11 完整设计布局布线；
- VCS 编译兼容性因当前 `VCSCompiler_Net` 许可证不可用，经用户批准延期，最迟在
  K11 冻结前补测；K04 不涉及 Xilinx PHY 动态模型或实板验收。

## 8. 冻结决定

架构、端口、Byte/bit 顺序、CRC 常量、结果延迟、错误恢复和接口版本
`K04-CRC32S-v1` 全部冻结。K04 七步门禁已完成，可以在用户明确要求时进入 K05；
本次实施没有加入任何 K05 Flow Control 功能。
