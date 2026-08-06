# Vivado Warning 固定 Allowlist

状态：**K00-v1 冻结**

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
