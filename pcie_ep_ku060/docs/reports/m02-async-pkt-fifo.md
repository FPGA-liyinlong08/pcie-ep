# M02 异步 Packet FIFO 冻结报告

状态：**PASS / 已冻结**  
接口版本：M02-v1  
执行日期：2026-08-06（Asia/Shanghai）  
目标器件：`xcku060-ffva1156-2-i`

## 1. 冻结产物

- 架构：`docs/architecture/02-pcie-async-pkt-fifo.md`
- 接口：`docs/interfaces/02-pcie-async-pkt-fifo-interfaces.md`
- RTL 前仿真计划：`docs/verification/02-m02-verification-plan.md`
- 主 RTL：`rtl/common/pcie_async_pkt_fifo.sv`
- Gray 状态同步：`rtl/common/pcie_gray_sync.sv`
- cocotb：`sim/verilator/m02/`
- 百万 Packet 高速 Scoreboard：`sim/verilator/m02_native/`
- VCS：`sim/vcs/m02_async_pkt_fifo_tb.sv`、`sim/vcs/run_m02.sh`
- Vivado：`fpga/ku060/m02_async_pkt_fifo.xdc`、
  `fpga/ku060/run_m02_checks.tcl`

## 2. 外部 `afifo.v` 依赖

M02 没有重新编写底层异步 FIFO，直接实例化用户指定文件：

`/home/wx/Documents/AXI/prj_wb2axip_master/wb2axip-master/rtl/afifo.v`

- 来源：WB2AXIP，Dan Gisselquist；
- 许可证：Apache License 2.0；
- SHA-256：`e6c8d4731857caf504277dca72967c89dba6e3c83aee95953a0a279ff958cc4c`；
- 源文件保持未修改；
- 所有 M02 构建先执行 `sim/common/check_afifo_dependency.sh`，内容变化立即失败。

## 3. 实现结果

默认一个 `pcie_async_pkt_fifo` 包含：

- 512 × 150 bit 数据 `afifo`；
- 512 × 10 bit Packet 长度描述符 `afifo`；
- EOP 描述符提交门控，保证半包在读侧不可见；
- 1～512 Beat Packet、包内 Backpressure 和顺序传输；
- 任一侧复位或公共 Flush 同时清空两侧；
- Commit/Claim Gray 状态计数及双时钟 `packet_count`；
- Sticky `s_overflow` 和 `m_underflow` 一致性诊断。

M13 分别实例化 RX 和 TX 两个模块；本阶段没有开始 M03 或其他协议 RTL。

## 4. 回归命令

```sh
make m02
```

也可分别执行 Checker、Lint、cocotb、百万包签核、VCS 和 Vivado 目标。

## 5. 阶段门结果

| 阶段 | 状态 | 证据 |
|---|---|---|
| 架构冻结 | PASS | 整包提交、深度、复位、错误和第三方依赖已经固定 |
| 接口冻结 | PASS | M02-v1 两侧 Packet Stream、Flush、Count 和 Sticky 状态已经固定 |
| 仿真计划冻结 | PASS | RTL 编写前已固定参考模型、测试列表、百万包标准和通过条件 |
| 测试平台先行 | PASS | 错误 Stub 在 EOP 前输出首 Beat，被 Checker 检出 |
| RTL 实现 | PASS | 仅封装未修改的 `afifo.v`，增加描述符和状态控制 |
| 模块验证 | PASS | cocotb、600 万包、VCS、Lint、综合、CDC 和 DRC 均通过 |
| 模块冻结 | PASS | 本报告记录证据、覆盖、限制和接口版本 |

## 6. 详细验证结果

| 测试 | 结果 | 证据 |
|---|---|---|
| `afifo.v` 指纹 | PASS | 每次构建检查 SHA-256，与冻结值一致 |
| Checker 预期失败 | PASS | 错误 Stub 报告“未完成 Packet 提前可见”，打印 `M02_CHECKER_SELFTEST_PASS` |
| Verilator Lint | PASS | 本地 RTL 无 Error；仅对第三方文件缺少 Timescale 的已知 Warning 定向屏蔽 |
| 整包可见性 | PASS | 写入 SOP/中间 Beat 后等待 20 个读时钟，EOP 前 `m_valid=0` |
| 长度边界 | PASS | 1、2、3、31、32、257、511、512 Beat 全部逐 Beat 比对通过 |
| Backpressure | PASS | 写空泡、读端 SOP/中间/EOP 随机停顿，无丢包、重复、乱序或字段变化 |
| 复位/Flush | PASS | SOP 后、中间 Beat、EOP 已提交未读以及两侧单独复位均不泄漏旧包 |
| 错误注入 | PASS | 缺失 SOP 置位 `s_overflow`；Claim 后无数据置位 `m_underflow`；Flush 清除 Sticky |
| cocotb 六组合 | PASS | RX/TX Gen1/2/3 每组 1000 个随机 Packet，五项测试全部通过 |
| 百万 Packet 签核 | PASS | 六组各 1,000,000 Packet，共 6,000,000 Packet；种子 `20260806` |
| VCS | PASS | 8 ns→4 ns 异步时钟、整包提交、复位、Flush 和 Count Drain 通过，打印 `M02_VCS_PASS` |
| Vivado 综合 | PASS | KU060 OOC 综合 0 Error、0 Critical Warning，Block RAM 推断成功 |
| Vivado CDC | PASS | 124 个 `ASYNC_REG`；2 条 CDC-3 Info、6 条 Gray Bus CDC-6 Warning，无 Critical/缺失属性 |
| Vivado DRC/时序 | PASS | DRC 无 Error/Critical；OOC WNS `1.561 ns`、WHS `0.098 ns`，时序约束满足 |

百万 Packet 明细保存在生成文件：

`sim/verilator/m02_native/build/summary.txt`

六组 Commit 和 Receive 都等于 1,000,000；Packet Counter 在回归中完成大量回绕。

## 7. 功能覆盖

| 覆盖点 | 状态 |
|---|---|
| RX/TX Gen1、Gen2、Gen3 六种时钟/相位组合 | 已覆盖 |
| 单 Beat、最大 512 Beat及关键长度边界 | 已覆盖 |
| Data/Descriptor FIFO Empty、Full、接近满和指针回绕 | 已覆盖 |
| SOP、中间 Beat、EOP 的写空泡与读 Backpressure | 已覆盖 |
| SOP 后、中间 Beat、EOP 提交后的复位 | 已覆盖 |
| 写侧复位、读侧复位和公共 Flush | 已覆盖 |
| Data、Keep、SOP、EOP、Error 全字段 Scoreboard | 已覆盖 |
| Commit/Claim Count 回绕及最终 Drain 为 0 | 已覆盖 |
| Overflow/Underflow 置位、Sticky 和 Flush 清除 | 已覆盖 |

## 8. Vivado 资源与 CDC

- 资源：252 LUT、415 FF、2 × RAMB36E2、2 × RAMB18E2，共 3 个 Block RAM
  Tile；
- 数据 RAM：512 × 150 bit；描述符 RAM：512 × 10 bit；
- `check_timing`：0 个无时钟寄存器、0 个无约束内部 Endpoint、0 个组合环路；
- 第三方 `afifo.v` 最终 `wr_rgray/rd_wgray` 同步级的 `ASYNC_REG` 属性由 M02
  Vivado 脚本补齐，第三方源码不变；
- CDC-6 是工具对多位 Gray Bus 的预期 Warning。数据指针、描述符指针和
  Commit/Claim 都采用相邻值单 Bit 变化的 Gray 编码，并经过两级同步。

## 9. 已知限制

1. `afifo.v` 当前以绝对路径引用。移动工程前必须同步设置 `AFIFO_RTL`，并保证
   SHA-256 不变。
2. `s_packet_count` 是写侧保守上界，`m_packet_count` 是读侧保守下界；CDC 延迟
   期间二者允许短暂不同，不能用于协议 Flow Control。
3. 任何一侧复位或 Flush 都会丢弃全部已提交/未提交 Packet，不支持保留或 Drain。
4. 单 Packet 最大 512 Beat。超长包会 Sticky Overflow 并需要 Flush；PCIe 正常
   TLP 长度不会达到该限制。
5. OOC 没有最终 Clock Buffer 位置和外部 I/O Delay；`HD.CLK_SRC`、CDC Bus Skew
   和最终布局布线必须在 M13 集成时再次签核。
6. `CFGBVS/CONFIG_VOLTAGE` 属于板级顶层，M02 OOC DRC 保留一条已解释 Warning。

## 10. 阶段门决定

M02 以接口版本 M02-v1 冻结，允许开始 M03 的“架构冻结”阶段。M03 尚未开始，
在其架构、接口和 RTL 前仿真计划冻结前不得编写 M03 RTL。

