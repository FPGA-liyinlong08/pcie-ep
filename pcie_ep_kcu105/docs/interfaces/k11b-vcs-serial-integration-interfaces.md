# K11-B VCS 串行集成接口冻结

状态：**v1 已冻结**

## 1. 板级仿真接口

| 信号 | 方向（相对 Endpoint） | 宽度 | 规则 |
|---|---:|---:|---|
| `pcie_refclk_p/n` | 输入 | 1 | 100 MHz 差分，P/N 互补 |
| `pcie_perst_n` | 输入 | 1 | 异步有效低，与 RP `sys_rst_n` 同源 |
| `pcie_rxp/n` | 输入 | 1 | 连接 RP TX Lane 0 |
| `pcie_txp/n` | 输出 | 1 | 连接 RP RX Lane 0 |

Root Port Lane 1～7 不与 Endpoint 相连，其 RXP/RXN 分别固定为 `0/0`，表示没有有效
差分接收端。测试平台不得短接或交换 Lane 0 的 P/N 来制造正常用例。

## 2. Endpoint 内部接口

K02 与 K03 继续使用 `K02-PHY32-v1.1`：Gen1 下每拍有效 Symbol 位于低 16 bit，
线路最先出现的 Symbol 位于 `[7:0]`。K03 与后续 DLL 继续使用 `K03-MAC16-v1`。
本阶段不新增协议接口。

为 VCS 缩短运行时间，`kcu105_pcie_gen1_top` 新增以下**参数**，端口不变：

| 参数 | 硬件默认值 | VCS 覆盖原则 |
|---|---:|---|
| `DETECT_QUIET_CYCLES` | 1,500,000 | 不小于 PHY 初始化完成后的稳定窗口 |
| `DETECT_TIMEOUT_CYCLES` | 3,000,000 | 覆盖一次真实 Receiver Detect |
| `TRAIN_TIMEOUT_CYCLES` | 6,000,000 | 覆盖 Root Port 最慢训练状态 |
| `HOT_RESET_CYCLES` | 250,000 | K11-B1 不主动触发 Hot Reset |

参数只改变超时计数，不得改变 LTSSM 状态图、Ordered Set 内容或综合顶层默认行为。

## 3. 测试结果接口

VCS 日志使用固定机器可读标记：

- `K11B_VCS_CHECKER_SELFTEST_PASS`：断开的串行 Stub 被 Checker 正确判失败；
- `K11B_VCS_GEN1_L0_PASS`：真实串行 B1 门通过；
- `K11B_VCS_GEN1_L0_FAIL`：超时并打印双方状态；
- `K11B_VCS_REAL_PHY_PASS`：脚本确认编译、展开、运行和日志检查全部成功。
