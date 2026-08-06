# M02 `pcie_async_pkt_fifo` RTL 前仿真计划

状态：**PASS / 已执行并冻结，K00 KU040 复核通过**

## 1. 参考模型与测试平台

- Python Packet Scoreboard：写侧 EOP 握手后才把暂存 Packet 提交到期望队列；
- cocotb Driver：产生合法 128-bit Packet Stream，并遵守 Stall 稳定规则；
- cocotb Monitor：逐 Beat 检查 Data、Keep、SOP、EOP、Error、顺序和整包可见性；
- C++/Verilator 高速压力平台：完成每种时钟组合一百万 Packet 的签核回归；
- VCS：使用同一 RTL 和未修改的外部 `afifo.v` 做编译/基本异步时钟回归；
- Vivado：KU040 OOC 综合、BRAM 推断、CDC、DRC 和时钟约束检查。

固定随机种子为 `20260806`，失败时输出方向、时钟周期、Packet 序号、Beat 序号和
期望/实际值。

## 2. Checker 预期失败自检

先编译同端口错误 Stub。Stub 在收到首 Beat 后立即从读侧输出，不等待 EOP。
测试发送一个多 Beat Packet，并在 EOP 前保持写侧停顿；Checker 必须报告
“未完成 Packet 提前可见”。外层脚本只有检测到该失败才打印
`M02_CHECKER_SELFTEST_PASS`。

## 3. Directed Case

### M02-DIR-001：基本包

- 单 Beat SOP+EOP；
- 2、3、31、32、257、511、512 Beat；
- 最后一拍所有合法 Keep；
- `error[3:0]` 每一位及组合值；
- 检查所有字段逐 Bit 不变。

### M02-DIR-002：整包提交

- 写入 SOP 和多个中间 Beat后暂停，等待至少 20 个读时钟；
- EOP 未握手前断言 `m_valid=0`；
- EOP 握手后允许完整 Packet 顺序输出。

### M02-DIR-003：Backpressure 与边界

- 写侧在 SOP、中间 Beat、EOP 遇到 Full/描述符 Full；
- 读侧在 SOP、中间 Beat、EOP 随机撤销 Ready；
- 指针至少回绕 20 次；
- 同时读写、接近满、接近空和 Packet Count 延迟边界。

### M02-DIR-004：复位与 Flush

- 在空闲、SOP 后、中间 Beat、EOP 同周期及已提交未读取时复位；
- 分别拉低 `s_rst_n`、`m_rst_n`，确认都共同清空两侧；
- 在相同位置拉高 `flush`；
- 恢复后第一个新 Packet 必须正确，旧 Packet 不得泄漏。

### M02-DIR-005：错误状态

- Stall 时改变 Data/Keep/SOP/EOP/Error，必须置位 `s_overflow`；
- 缺失首 SOP、包内重复 SOP 和超长 Packet，必须置位 `s_overflow`；
- 仿真 Force 描述符长度/EOP 不一致，必须置位 `m_underflow`；
- Sticky 状态只允许由复位或 Flush 清除。

## 4. 约束随机回归

K11 所需两个方向全部运行：

| 方向 | 写时钟周期 | 读时钟周期 |
|---|---:|---:|
| RX Gen1 | 16 ns | 4 ns |
| RX Gen2 | 8 ns | 4 ns |
| RX Gen3 | 4 ns | 4 ns，加入 0.8 ns 初始相位差 |
| TX Gen1 | 4 ns | 16 ns |
| TX Gen2 | 4 ns | 8 ns |
| TX Gen3 | 4 ns | 4 ns，加入 1.6 ns 初始相位差 |

每组至少一百万 Packet。长度采用加权随机分布：大量 1～8 Beat，混入 9～64、
257、511 和 512 Beat边界包。随机化写侧空泡、读侧 Backpressure、Keep、Error
和 Payload。Scoreboard 必须无丢包、重复、乱序或字段变化。

## 5. Assertion

- `s_valid && !s_ready` 时输入保持稳定；
- `m_valid && !m_ready` 时输出保持稳定；
- EOP 前不允许读侧出现该 Packet；
- SOP/EOP 嵌套关系合法；
- 底层 Full 时不写、Empty 时不读；
- Packet Count 不超过 `2^LGFIFO`；
- 正常测试中 `s_overflow/m_underflow` 永不置位；
- 复位有效时 `s_ready=0`、`m_valid=0`、计数为 0。

## 6. 覆盖点

- 六种方向/时钟组合；
- 长度 1、2、3、31、32、257、511、512；
- 所有末拍 Keep 长度；
- SOP、中间 Beat、EOP 的写 Stall、读 Backpressure、复位和 Flush；
- Data/Descriptor 指针回绕、Full、Empty、同时跨界；
- Commit/Claim Counter 回绕；
- 两种 Sticky 错误的置位与清除。

## 7. 通过标准

- 错误 Stub 被 Checker 检出；
- Directed、错误注入、六组百万 Packet 回归全部通过；
- Verilator Lint 和 VCS 编译/仿真通过；
- Vivado 推断 Block RAM，`report_cdc` 无 Critical CDC，DRC 无 Error/Critical；
- 正常回归无 Overflow、Underflow、丢包、重复、乱序或字段变化；
- 保存测试摘要、覆盖表、Vivado 报告、已知限制和外部 `afifo.v` 指纹。
