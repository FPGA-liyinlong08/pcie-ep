# Vivado Warning 固定 Allowlist

状态：**K00-v1～K10-v1 已建立并冻结**

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

## K03 Allowlist

K03 OOC 允许以下唯一 Warning ID：

| ID | 原因 |
|---|---|
| `Synth 8-3917` | K03 固定 Gen1，Gen3/EQ/协商状态输出按契约固定为常量 |
| `Synth 8-7080` | OOC 模块规模不足以启用并行综合 |
| `Synth 8-7129` | PHY32 高 16 bit 在 Gen1 契约中明确不采样 |
| `Timing 38-242` | OOC 顶层没有 K02 BUFG_GT 的实际 `HD.CLK_SRC` |

K03+K02 完整集成允许 K02 的六类固定 Warning，并新增 `Synth 8-3332`：集成
bring-up 顶层在 DLL 尚未实现时把 TX Packet 输入固定为空，综合会移除不可达的 TX
Framer 状态；Framer 完整实现由 K03 OOC 综合和随机回归签核。脚本比较唯一 ID 的
精确集合，任何新增或减少均要求复核。

OOC `report_cdc` 允许且只允许 `pipe_rst_n` 输入产生 CDC-7；这是单模块边界看不到
K01 四级同步释放链造成的工具局限。完整集成 `report_cdc` 必须只把该链报告为
CDC-9 Info，并保持 0 Critical。

## K04 Allowlist

K04 CRC 的 KU040 OOC 检查只允许以下固定普通 Warning；脚本对实际 ID 和数量
做精确比较：

| 来源 | ID | 原因与处理 |
|---|---|---|
| 综合日志 | `Synth 8-7080` | 两个 CRC 引擎规模较小，未达到并行综合条件 |
| 时序日志 | `Timing 38-242` | OOC 顶层没有最终 `phy_pclk` BUFG_GT 位置，无法设置系统级 `HD.CLK_SRC` |
| `report_drc` | `CFGBVS-1` | OOC 模块没有板级配置电压属性；K01/K03 集成顶层已固定 `1.8 V/GND` |

`report_cdc` 固定只有一组 `CDC-9 Info`，来源必须是 OOC 顶层 `rst_n` 到
`pcie_reset_sync` 四级同步链；不允许 CDC Warning/Critical。`report_drc` 的
`CFGBVS-1` 固定为 1 个，其他 DRC Warning、所有 Critical Warning 和 Error 均失败。

## K05 Allowlist

K05 DLLP/FC 的 KU040 OOC 检查允许且只允许：

| 来源 | ID | 原因与处理 |
|---|---|---|
| 综合日志 | `Synth 8-7080` | K05 OOC 规模不足以启用并行综合 |
| 时序日志 | `Timing 38-242` | OOC 顶层没有最终 `phy_pclk` BUFG_GT 位置 |
| `report_drc` | `CFGBVS-1` | OOC 无板级配置属性；K01/K03 集成约束已固定 `1.8 V/GND` |

`report_cdc` 固定只有 OOC `rst_n` 到四级同步链的一组 `CDC-9 Info`。Codec 内部
CRC enable reset 来自同一 `phy_pclk` 域并经两级同步释放，不产生跨时钟路径。
新增 Warning、CDC Warning/Critical、DRC Critical 或 Error 均失败。

## K06 Allowlist

K06完整`pcie_dll`的KU040 250 MHz OOC检查按ID和数量精确限定：

| 来源 | ID / 数量 | 原因与处理 |
|---|---|---|
| 综合日志 | `Synth 8-6779` ×44 | OOC未布局条件下，LUTRAM wire-load没有专用延迟模型；已通过综合静态时序门禁，K11再做完整布局布线 |
| 综合日志 | `Synth 8-7080` ×1 | OOC层次未达到并行综合条件，不影响网表 |
| 时序日志 | `Timing 38-242` ×2 | OOC顶层没有K02 `phy_pclk` BUFG_GT最终位置，K11集成时消除 |
| `report_drc` | `CFGBVS-1` ×1 | OOC无板级配置属性；K01/K03集成约束已固定`1.8 V/GND` |

`report_cdc`固定只有OOC `rst_n`四级同步释放链的一组`CDC-9 Info`。构建脚本将
普通Warning实际ID和数量与`k06_vivado_warning_allowlist.txt`逐行比较；任何新增、
减少或数量改变均要求复核，所有Critical Warning和Error直接失败。

## K07 Allowlist

K07 TLP Codec的KU040 250 MHz OOC检查按ID和数量精确限定：

| 来源 | ID / 数量 | 原因与处理 |
|---|---|---|
| 综合日志 | `Synth 8-6779` ×1 | OOC未布局条件下，综合网表wire-load没有专用延迟模型；已通过综合静态时序门禁，K11再做完整布局布线 |
| 综合日志 | `Synth 8-7080` ×1 | OOC层次未达到并行综合条件，不影响网表 |
| 综合网表 | `Netlist 29-101` ×1 | Codec在OOC综合网表中包含较多Primitive，不适合作为独立Floorplan单元；K11完整集成重新布局布线 |
| 时序日志 | `Timing 38-242` ×2 | OOC顶层没有K02 `phy_coreclk` BUFG最终位置，K11集成时消除 |
| `report_drc` | `CFGBVS-1` ×1 | OOC无板级配置属性；K01/K03集成约束已固定`1.8 V/GND` |

签核包装层只为工具重建K01已经提供的四级异步置位/同步释放链；`report_cdc`必须
只有1项`CDC-9 Info`，且目的端固定为`u_ooc_reset_sync/sync_reg_reg[0]/CLR`。
`rx_mem`、`rx_payload_flat`和`tx_words`数据阵列不复位，不能出现`Synth 8-7137`；
任何新增/减少的普通Warning、所有CDC Warning/Critical、DRC Critical或Error均失败。

## K08 Allowlist

K08 Type-0配置空间的KU040 250 MHz OOC检查按ID和数量精确限定：

| 来源 | ID / 数量 | 原因与处理 |
|---|---|---|
| 综合日志 | `Synth 8-3917` ×3 | MPS固定为128 B，三个编码输出位均为常量0 |
| 综合日志 | `Synth 8-7080` ×1 | OOC层次未达到并行综合条件，不影响网表 |
| 综合日志 | `Synth 8-7129` ×48 | Requester ID与Tag按K07接口保留，但K08响应上下文由K07保存；生产层和OOC顶层各报告一次 |
| 时序日志 | `Timing 38-242` ×2 | OOC顶层没有K02 `phy_coreclk` BUFG最终位置，K11集成时消除 |
| `report_drc` | `CFGBVS-1` ×1 | OOC无板级配置属性；K01/K03集成约束已固定`1.8 V/GND` |

K08全部同步边界端口必须有max/min input/output delay，`no_input_delay`、
`no_output_delay`、`partial_input_delay`和`partial_output_delay`都必须为0。
`report_cdc`必须明确给出`All paths are Safely Timed.`，且无CDC Warning/Critical；
任何普通Warning数量变化、所有Critical Warning和Error均失败。

## K09 Allowlist

K09 BAR0-to-AXI4-Lite的KU040 250 MHz routed OOC检查按ID和数量精确限定：

| 来源 | ID / 数量 | 原因与处理 |
|---|---|---|
| 综合网表 | `Netlist 29-101` ×1 | OOC层次包含较多Primitive，不适合作为独立Floorplan单元；本轮仍完成实际布局布线，K11在完整层次重新实现 |
| 综合日志 | `Synth 8-6779` ×1 | OOC综合阶段的wire-load没有专用延迟模型；最终routed STA已通过 |
| 综合日志 | `Synth 8-7080` ×1 | OOC层次未达到并行综合条件，不影响网表 |
| `report_drc` | `CFGBVS-1` ×1 | OOC无板级配置电压属性；K11顶层设置后消除 |

只有连接真实动态net的普通端口才施加局部`HD.PARTPIN_RANGE`；常量或未连接端口不施加，
最终动态端口数固定为1062，routing error必须为0。输入接口`MinDelay=-1.000 ns`只透明
补偿OOC模型缺失的父层共享BUFG source insertion，输出接口为`0.000 ns`；报告中两向
必须显示`MinDelay Path`且不得出现`False Path`。该补偿不是硬件负hold预算，K11完整
共享时钟树必须取消后重检。

`check_timing`的no_clock、unconstrained internal、no/partial input/output delay必须全为
0；`report_cdc`必须为`All paths are Safely Timed.`；DRC只允许一个`CFGBVS-1`。普通
Warning任何增减、所有Critical Warning/Error、routing error或负setup/hold slack均失败。

## K10 Allowlist

K10 Demo AXI4-Lite Slave的KU040 250 MHz routed OOC普通Warning固定为：

| ID / 数量 | 原因 |
|---|---|
| `Netlist 29-101` ×1 | OOC层次包含BRAM及较多Primitive，不适合作为独立Floorplan单元；实际route已完成 |
| `Synth 8-6779` ×8 | OOC综合wire-load缺少专用延迟模型；最终routed STA通过 |
| `Synth 8-7080` ×1 | OOC规模未达到并行综合条件 |

测试RAM必须实现为至少一个RAMB primitive且LUTRAM为0；本版固定一个RAMB36E2。
`CFGBVS-1 ×1`仍是OOC唯一DRC Warning。`Vivado 12-4775`曾由非Tile对齐的RAMB18范围
引起，已通过使用实际RAMB36 Tile范围消除，不在Allowlist中。所有Critical/Error、
新增或减少普通Warning、routing error、未约束/partial接口或负setup/hold均失败。
