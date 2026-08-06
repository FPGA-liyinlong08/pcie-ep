# M01 时钟复位模块冻结报告

状态：**PASS / 已冻结**  
接口版本：M01-v1  
执行日期：2026-08-06（Asia/Shanghai）  
目标器件：`xcku060-ffva1156-2-i`

## 1. 冻结产物

- 架构：`docs/architecture/01-pcie-clk-reset.md`
- 接口：`docs/interfaces/01-pcie-clk-reset-interfaces.md`
- RTL 前仿真计划：`docs/verification/01-m01-verification-plan.md`
- 顶层 RTL：`rtl/phy/pcie_clk_reset.sv`
- 通用 RTL：`rtl/common/pcie_reset_sync.sv`、`pcie_bit_sync.sv`、
  `pcie_clk_reset_ctrl.sv`
- Verilator/cocotb：`sim/verilator/m01/`
- VCS 原语仿真：`sim/vcs/m01_clk_reset_tb.sv`、`sim/vcs/run_m01.sh`
- Vivado 检查：`fpga/ku060/m01_clock_reset.xdc`、
  `fpga/ku060/run_m01_checks.tcl`

## 2. 实现结果

M01 已实现冻结范围内的以下功能：

- `IBUFDS_GTE3` 缓冲 100 MHz PCIe 差分参考时钟；
- `MMCME3_BASE` 将 100 MHz 板载时钟转换为 250 MHz Core 时钟；
- 两个 `BUFG_GT` 分别缓冲 GT TX/RX 用户时钟；
- Core 和 PIPE 域各使用 4 级异步置位、同步释放复位链；
- GT 就绪和 PIPE 复位释放状态经 2 级同步器进入 Core 域；
- `clock_ready` 只在 Core、PIPE 和 GT 均就绪后拉高。

未实现 GT 初始化、速率切换、均衡、PCS 或协议功能，未越过 M01 边界。

## 3. 回归命令

```sh
make m01
```

2026-08-06 已从顶层聚合目标重新执行，退出码为 0。

## 4. 阶段门结果

| 阶段 | 状态 | 证据 |
|---|---|---|
| 架构冻结 | PASS | 职责边界、内部结构、时钟域和错误处理已经固定 |
| 接口冻结 | PASS | M01-v1 端口、时钟域、复位值和允许延迟已经固定 |
| 仿真计划冻结 | PASS | RTL 编写前已固定 Stub、Verilator、VCS 和 Vivado 检查项 |
| 测试平台先行 | PASS | 故意错误的 Stub 在第 4 个 Core 时钟未释放复位，被 Checker 检出 |
| RTL 实现 | PASS | 4 个可综合 SystemVerilog 文件通过 Verilator Lint 和 Vivado 综合 |
| 模块验证 | PASS | Directed、随机复位、Xilinx 原语仿真、CDC 和 DRC 阶段门均通过 |
| 模块冻结 | PASS | 本报告记录结果、覆盖点、限制和接口版本 |

## 5. 详细验证结果

| 测试 | 结果 | 证据 |
|---|---|---|
| Checker 预期失败自检 | PASS | 错误 Stub 的 `release_and_dependency` 如预期失败；外层打印 `M01_CHECKER_SELFTEST_PASS` |
| Verilator Lint | PASS | `pcie_clk_reset_ctrl` 及两个同步器以 `-Wall -Wno-fatal` 检查，无错误 |
| M01-VLT-001 | PASS | Core/PIPE 依赖、4 拍释放、`clock_ready` 顺序全部满足 |
| M01-VLT-002 | PASS | 每种 PIPE 时钟执行 100 次随机相位状态撤销；MMCM lock 和三个 GT ready 均覆盖 |
| M01-VLT-003 | PASS | PIPE 周期 16/8/4 ns 各执行 1000 次，共 3000 次；种子 `20260806` |
| M01-VCS-001 | PASS | VCS-MX O-2018.09-SP2 链接 Vivado 2021.2 `unisims_ver`；Core 平均周期 `4.0000 ns` |
| M01-VCS-002 | PASS | 完整原语模型复位顺序、GT Refclk 和 PERST# 异步置位通过，打印 `M01_VCS_PASS` |
| Vivado 综合 | PASS | KU060 OOC 综合为 0 Error、0 Critical Warning |
| Vivado 原语/属性检查 | PASS | `IBUFDS_GTE3=1`、`MMCME3=1`、`BUFG_GT=2`、Core BUFG 等效项 2、`ASYNC_REG=12` |
| Vivado CDC | PASS | 仅 1 条 CDC-3 Info；PIPE→Core 使用 2 级 `ASYNC_REG`，无 Critical CDC |
| Vivado DRC 阶段门 | PASS | 无 Error 或 Critical Warning；两个 M01 独立 OOC Warning 已在限制中记录 |

## 6. 功能覆盖

| 覆盖点 | 状态 |
|---|---|
| Core lock 有效、GT 未就绪 | 已覆盖 |
| GT ready 三个输入分别参与 PIPE 释放条件 | 已覆盖 |
| MMCM 失锁只直接复位 Core 域 | 已覆盖 |
| GT ready 撤销只直接复位 PIPE 域 | 已覆盖 |
| PERST# 同时异步复位两个域 | 已覆盖 |
| Gen1/Gen2/Gen3 PIPE 周期 | 已覆盖 |
| 复位脉冲随机相位与 0.1～3.0 ns 短脉冲 | 已覆盖 |
| Core/PIPE 四级同步释放不得提前 | 已覆盖 |
| `clock_ready` 跨域同步延迟 | 已覆盖 |

除 3000 次随机 PERST# 外，三种 PIPE 时钟下还执行了共 300 次随机相位状态撤销，
四个状态输入按轮询方式各覆盖 75 次。

M01 没有数据通路、缓冲区或状态编码，因此本阶段不定义数据覆盖和 FSM 覆盖。

## 7. Vivado 报告摘要

- 资源：6 LUT、12 FF、2 BUFG_GT、2 BUFGCE、1 MMCME3_ADV、1
  IBUFDS_GTE3。
- `check_timing`：0 个无时钟寄存器、0 个无约束内部 Endpoint、0 个组合环路。
- 综合前/OOC 时序报告不是最终布局布线签核；M01 不单独给出 WNS 验收值。
- 可重复生成的详细报告位于 `fpga/ku060/build_m01/`，该目录为生成目录，
  执行 `make m01-vivado` 会刷新。

## 8. 已知限制与解释

1. M03 尚未提供 GTHE3 Common/Channel，因此 `gt_refclk` 在 M01 OOC 网表中无
   内部负载，触发 `BUFC-1` Warning；接入 M03 后必须消失。
2. `CFGBVS` 与 `CONFIG_VOLTAGE` 属于整板顶层配置，当前未依据板卡原理图擅自
   固定，触发 `CFGBVS-1` Warning；上板顶层约束冻结时必须补齐。
3. OOC 边界没有最终 GT Clock Buffer 位置，`gt_txoutclk` 和 `sys_clk_100` 的
   `HD.CLK_SRC` 尚未设置；最终集成布局后重新签核时钟偏差和 Hold。
4. GT ready 与 PERST# 是异步控制输入，没有虚构输入延迟；它们只进入异步复位
   或带 `ASYNC_REG` 的同步链。状态输出是后续模块内部连接，M01 OOC 不设置外部
   Output Delay。
5. VCS 原语仿真验证时钟/复位逻辑，不替代 M03 的 GT reset-done、Receiver
   Detect 和动态速率切换验证。

上述限制均属于已冻结的 M01/M03 或板级集成边界，不影响 M01 的功能验收。

## 9. 阶段门决定

M01 以接口版本 M01-v1 冻结，允许开始 M02 的“架构冻结”阶段。M02 尚未开始，
在其架构、接口和 RTL 前仿真计划冻结前，不得编写 M02 RTL。
