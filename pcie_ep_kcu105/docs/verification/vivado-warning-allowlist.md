# Vivado Warning 固定 Allowlist

状态：**K00-v1、K01-v1 冻结；K02-v1 已建立**

K00 的 KU040 M02 OOC 检查只允许以下类型；构建脚本对实际集合做精确比较，出现
任何新增类型即失败。

| 来源 | ID | 原因与处理 |
|---|---|---|
| 综合日志 | `Synth 8-7080` | 小型 OOC 设计未达到并行综合条件，不影响网表 |
| 时序日志 | `Timing 38-242` | OOC 顶层没有系统级 BUFG 位置，无法设置最终 `HD.CLK_SRC`；K11 集成时消除 |
| `report_cdc` | `CDC-6` | Gray 编码多位总线经过两级 `ASYNC_REG`；这是受控 CDC，逐项核对路径 |
| `report_drc` | `CFGBVS-1` | OOC 模块没有板级配置电压属性；K01 顶层 XDC 设置后消除 |

允许 Warning 不代表忽略内容：CDC-6 固定为 6 组，所有路径必须是 Commit/Claim
Gray Counter 或两个 `afifo` 的 Gray Pointer；K00 报告记录实际数量。

## K01 Allowlist

K01 日志只允许以下两种普通 Warning；`report_cdc` 和 `report_drc` 不允许
Warning。构建脚本对实际 ID 集合做精确比较。

| 来源 | ID | 原因与处理 |
|---|---|---|
| 综合日志 | `Synth 8-7080` | K01 只有 8 个寄存器和少量原语，未达到并行综合条件 |
| 时序日志 | `Timing 38-242` | OOC 顶层把 K02 将来输出的 `phy_pclk/phy_coreclk` 建模为输入，尚无最终 `HD.CLK_SRC`；K02 集成时由 PHY 时钟源取代 |

K01 的 CDC 结果固定为 2 组 `CDC-9 Info`，分别是 PERST# 到 Core/PIPE 的四级
同步释放链；DRC 固定为 0 违例。新增 Warning、Critical Warning 或 Error 均失败。

## K02 Allowlist

K02 使用 Vivado 2021.2 自动生成的 `pcie_phy v1.0` 与 GT Wizard RTL。未启用的
外部 PLL、调试、保留端口和非当前配置分支会产生以下固定普通 Warning。构建脚本
精确比较 ID 集合；所有 Critical Warning、Error 和新增普通 Warning 均失败。

| 来源 | ID | 原因与处理 |
|---|---|---|
| PHY 生成 RTL | `Synth 8-3848` | 未选择的外部 PLL、DRP及调试网络无驱动；最终网表已优化，DRC 为 0 |
| PHY 生成 RTL | `Synth 8-6014` | 未使用的 TX EQ/PLL 配置分支寄存器被移除 |
| PHY 生成 RTL | `Synth 8-7023` | 生成器保留的非当前配置端口未连接，实例连接数提示 |
| PHY 生成 RTL | `Synth 8-7071` | 未使用的调试/内部状态输出未连接 |
| 综合器 | `Synth 8-7080` | IP OOC 与 K02 bring-up 顶层规模较小，未达到并行综合条件 |
| PHY/GT Wizard 生成 RTL | `Synth 8-7129` | 未启用的校准、保留和复位输入无负载 |

K02 Route 后 `report_drc` 必须为 0 违例。`report_cdc` 只允许 Xilinx PHY 内部及
K01复位链的 `CDC-3 Info`、`CDC-9 Info`；Critical CDC 固定为 0。`check_timing`
允许 PERST# 和 LED 已显式 false-path 的端口提示，内部无时钟和未约束端点必须为 0。
