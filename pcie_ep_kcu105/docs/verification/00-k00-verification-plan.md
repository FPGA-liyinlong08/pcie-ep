# K00 工程骨架与验证基线计划

状态：**K00-v1 冻结并已执行**

## 1. K00 范围

K00 只验证新工程的可复现工具入口、PCIe Python 参考对象、已冻结通用 RTL 在
KU040 上的兼容性，以及 M02 Packet FIFO 的完整再签核。K00 不生成 standalone
PHY，不验证真实串行链路，不实现 K01 及后续协议 RTL。

## 2. 测试平台与参考模型

- cocotb/Verilator Smoke：复位和逐周期计数；
- `cocotbext-pcie 0.2.16`：创建 `RootComplex`、`Device`、`Function`，并对 Memory
  Write TLP 做打包/解包往返；
- M02 Python Packet Scoreboard：仅在 EOP 写握手后提交期望 Packet；
- M02 Native C++/Verilator：六组时钟组合的高吞吐百万 Packet 回归；
- VCS：Xilinx `unisims_ver` Smoke 及外部 `afifo.v` 异步时钟回归；
- Vivado 2021.2：`xcku040-ffva1156-2-e` OOC 综合、BRAM、CDC、DRC 和时序约束检查。

随机种子固定为 `20260806`。失败必须包含测试名、方向、Packet/Beat 和期望/实际值。

## 3. Checker 预期失败自检

M02 先编译故意错误的同端口 Stub。Stub 在收到首 Beat 后立即向读侧暴露内容，
不等待 EOP。测试必须检测“未完成 Packet 提前可见”，并在 JUnit 中留下 failure；
外层 Make 只有观察到该预期失败才报告 `K00_M02_CHECKER_SELFTEST_PASS`。

Smoke 测试内部也包含错误对象自检：修改 TLP 临时副本的 Payload 后，相等比较
必须失败，以证明参考对象比较不是恒真。

## 4. Directed 与随机测试

K00 基线：

| 编号 | 内容 | 通过标准 |
|---|---|---|
| K00-VLT-001 | 可复位 SystemVerilog Counter | 复位值及连续 32 次计数一致 |
| K00-PCIE-001 | 创建 RC、Device、Function 和拓扑 | 对象成功且 Device 接入 RC Port |
| K00-PCIE-002 | Memory Write TLP pack/unpack | Header、Payload 逐字段一致 |
| K00-VCS-001 | 编译 Xilinx `BUFG` Smoke | 解析 `unisims_ver` 并打印 PASS |

M02 Directed、错误注入和断言沿用已冻结的
`docs/verification/02-m02-verification-plan.md`。快速 cocotb 回归对六组时钟各发送
1,000 个随机 Packet；签核回归对每组发送 1,000,000 个 Packet：

| 方向 | 写周期 | 读周期 |
|---|---:|---:|
| RX Gen1 | 16 ns | 4 ns |
| RX Gen2 | 8 ns | 4 ns |
| RX Gen3 | 4 ns | 4 ns，错相 0.8 ns |
| TX Gen1 | 4 ns | 16 ns |
| TX Gen2 | 4 ns | 8 ns |
| TX Gen3 | 4 ns | 4 ns，错相 1.6 ns |

检查无丢包、重复、乱序、字段变化、Overflow 或 Underflow，并覆盖长度/Keep、
Backpressure、复位/Flush、指针和计数器回绕。

## 5. 静态检查

- `afifo.v` SHA-256 必须为
  `e6c8d4731857caf504277dca72967c89dba6e3c83aee95953a0a279ff958cc4c`；
- Verilator `--lint-only -Wall` 通过；
- KU040 OOC 必须推断 Block RAM，最终 Gray 同步级 `ASYNC_REG` 数不少于 40；
- `report_cdc` 不得有 Critical，DRC 不得有 Error/Critical Warning；
- 受版本管理的源目录不得包含复制的 XCI、DCP、Vivado Project 或其他生成物；
  本次 OOC 生成的 DCP 只允许出现在被 `.gitignore` 排除的 `build_*` 目录。

## 6. 执行入口与通过标准

统一命令为 `make k00`。它必须以状态 0 完成并覆盖：

1. Verilator Smoke 与 PCIe 对象自检；
2. VCS/Xilinx 库 Smoke；
3. M02 错误 Stub 自检、Lint 和外部依赖指纹；
4. 六组 cocotb 回归和六组共 600 万 Packet Native 回归；
5. M02 VCS 回归；
6. KU040 OOC 综合、BRAM、CDC 和 DRC。

实际工具版本、结果、报告路径和限制写入 `docs/reports/k00-baseline.md`。只有报告
决定为 PASS 后，K01 才允许开始。
