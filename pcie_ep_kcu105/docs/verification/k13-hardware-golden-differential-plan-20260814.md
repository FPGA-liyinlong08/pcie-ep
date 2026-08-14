# K13 Hardware Golden Differential 逐条验证计划

日期：2026-08-14

状态：**P1-1 部分完成；P2-1/P2-2 完成，P2-3 三次重复完成；官方硬件 bit/LTX 基线缺失，P1-2 暂停**

目标：利用已经通过上板验证的官方 PCIe PHY Demo，加入与 K13 相同层级的 ILA，直接比较真实硬件 Gen1→Gen3 动态切速过程，定位官方成功路径与 K13 失败路径的**第一个不同事件/第一个不同 `phy_pclk`**。

相关工程：

- 官方 PHY Demo：`/home/wx/Documents/KCU105/pcie_phy_0_ex/`
- K13 工程：`/home/wx/Documents/PCIe/pcie_ep_kcu105/`
- K13 当前失败记录：[k13-cdr-hold-validation-20260814.md](../reports/k13-cdr-hold-validation-20260814.md)
- K13 VCS 窄场景记录：[k13-vcs-phy-rate-change-diff-20260814.md](../reports/k13-vcs-phy-rate-change-diff-20260814.md)

## 0. 当前执行进度

### P1-1：官方 Demo 基线——部分完成

已确认：

- Vivado：2021.2，器件 `xcku040-ffva1156-2-e`；
- 顶层：`xilinx_pcie_phy_top`；
- IP：`pcie_phy_0`，x1、Gen3、GTH、QPLL1、100 MHz REFCLK、125 MHz User Clock、250 MHz Core Clock；
- GT Channel：`GTHE3_CHANNEL_X0Y7`；
- REFCLK：`Bank_225_MGTREFCLK0`；
- 官方 VCS Gen1→Gen3：PASS，已有 `Test Completed Successfully` 和 8.0 GT/s 流量证据；
- 官方工程已有综合 DCP，综合入口和源文件完整。

当前缺口：

- `/home/wx/Documents/KCU105/pcie_phy_0_ex/` 下没有可下载的官方 `.bit` 或 `.ltx`；
- 该工程的 `imports/xilinx_pcie_phy.xdc` 只有 `sys_clk` 时钟/复位约束，没有 KCU105 PCIe Lane/REFCLK 的完整 package pin 约束；
- 工程日志显示执行过 `synth_1`，没有发现 `impl_1`/`write_bitstream` 完成证据；
- 因此当前不能从该目录独立复现“官方硬件 PASS”，也不能安全地直接给这个工程插入 ILA 后上板。

判定：此前实际下载到 KCU105 的 `k02_pcie_phy_bringup_ila.bit` 是仓库内 K02 顶层生成的 **K02 PHY 稳态 Golden**，不是 `/home/wx/Documents/KCU105/pcie_phy_0_ex` 原始工程直接生成的官方 Demo bit。它已经证明 QPLL1 锁定和 Gen3 steady state 正常，但不能替代官方 Demo 的动态 Gen1→Gen3 Golden。

现有 K02 硬件证据：`QPLL1LOCK=1`、`phy_rate=Gen3`、`PCIERATEGEN3=1`、`PCIEUSERGEN3RDY=1`、`RXRESETDONE=1`。当前 K02 流程是 Receiver Detect 后进入 P0 并直接请求 Gen3，尚未完整复现 Gen1/CPLL→Gen3/QPLL1 动态切速，因此 P1-2 仍不标记完成。

### 下一步入口

需要找到以下任一完整基线：

1. 官方 Demo 实际上板使用的 bit/LTX 及其生成工程/约束；或
2. 能从 `/home/wx/Documents/KCU105/pcie_phy_0_ex` 生成 KCU105 可下载 bit 的完整顶层、PCIe REFCLK/Lane 约束和控制输入方案。

拿到官方基线后，继续执行 P1-2：官方 Demo 加同构 ILA、重新实现、下载和抓取。当前 K02
P2 已先行完成一次有效动态抓取，结果见 `docs/reports/k02-standalone-pcie-phy.md`；
官方硬件工程仍不可复现，因此暂不能形成 Official vs K02 的完整 Golden 对照。

### P2 当前实测结果（2026-08-14）

K02 dynamic bit/LTX 已完成实现并上板，ILA probe0 为 49 位、深度 8192，WNS=`+0.704 ns`。
有效抓取：

```text
fpga/kcu105/build_k02_dynamic/capture/20260814_220214_k02_phy.csv
fpga/kcu105/build_k02_dynamic/capture/20260814_220214_k02_phy.ila
fpga/kcu105/build_k02_dynamic/capture/20260814_220532_k02_phy.csv
fpga/kcu105/build_k02_dynamic/capture/20260814_220532_k02_phy.ila
fpga/kcu105/build_k02_dynamic/capture/20260814_220635_k02_phy.csv
fpga/kcu105/build_k02_dynamic/capture/20260814_220635_k02_phy.ila
```

波形显示 `TXEQ_DONE=1`，随后 `PHY_RATE=00→10`；之后
`PCIERATEQPLLRESET` 和实际 `QPLL1RESET` 拉高，`QPLL1LOCK=1→0`，复位释放后
锁定未恢复，`PCIEUSERGEN3RDY/PhyStatus` 未完成。四个 `PLLCLKSEL/SYSCLKSEL`
在窗口内保持不变。当前结论为 **K02 dynamic FAIL，首个明确分叉为 QPLL1 reset/relock**。
这不是最终 K13 根因，因为 K02 TXEQ 是受控替代序列，且官方动态硬件 Golden 尚缺失。

## 1. 验证边界和总原则

本计划分三条主线执行：

| 主线 | 目的 | 预期结论 |
|---|---|---|
| P1 Hardware Golden Differential | 官方 Demo 与 K13 使用同一组硬件 ILA 信号做动态切速对齐 | 找到第一个分叉点 |
| P1.1 SYSCLKSEL 补充观测 | 确认 Channel 实际 PLL/系统时钟源是否正确切换 | 区分 source switching 与 QPLL 本体问题 |
| P2 K02 Dynamic Rate Change | 在最小 PHY 环境复现 Gen1/CPLL→Gen3/QPLL1 | 判断问题是否来自 K13 集成、时序或控制时序 |

执行时必须遵守：

- 官方 Demo 和 K13 使用相同 ILA 采样时钟、相同采样深度、相同 pre-trigger 配置；
- 以 `PHY_RATE` 第一次从 Gen1 (`2'b00`) 变为 Gen3 (`2'b10`) 的采样点定义 `T0`；
- 不能只比较最终 PASS/FAIL，必须逐采样比较 `T0` 前后每个信号的边沿和保持时间；
- ILA 探针连接失败、位宽不一致或层次不唯一时，构建必须失败，禁止生成“缺探针但看似成功”的 bit；
- 每个实验保存 bit、LTX、原始 CSV/ILA、SHA-256、Vivado 日志和环境变量。

## 2. 统一 ILA 采集信号

官方 Demo 和 K13 的 PIPE/PHY ILA 至少包含以下信号。每个多位信号都要在报告中明确 bit 顺序。

### 2.1 PHY 控制与 TXEQ

| 信号 | 宽度 | 说明 |
|---|---:|---|
| `PHY_RATE` / `phy_rate` | 2 | T0 的基准信号，Gen1=`00`，Gen3=`10` |
| `PHY_POWERDOWN` / `phy_powerdown` | 2 | P0/P1 等 PHY 电源状态 |
| `PHY_TXELECIDLE` / `phy_txelecidle` | 1 | TX Electrical Idle 时序 |
| `TXEQ_CTRL` | 2 | TXEQ 控制命令 |
| `TXEQ_PRESET` | 4 | TXEQ preset 值 |
| `TXEQ_DONE` | 1 | TXEQ 完成应答 |
| `as_cdr_hold_req` | 1 | CDR hold 请求 |

### 2.2 PCIe rate-change 控制与 QPLL1

| 信号 | 宽度 | 说明 |
|---|---:|---|
| `PCIERATEIDLE` | 1 | rate-change 空闲/窗口 |
| `PCIERATEQPLLRESET` | 1 | PHY rate 控制器请求 QPLL reset |
| `PCIERATEQPLLPD` | 1 | PHY rate 控制器请求 QPLL powerdown |
| `QPLL1RESET` | 1 | GTHE3_COMMON 实际 QPLL1 reset pin |
| `QPLL1PD` | 1 | GTHE3_COMMON 实际 QPLL1 powerdown pin |
| `QPLL1LOCK` | 1 | GTHE3_COMMON primitive 直接输出，不能只取软件别名 |
| `PCIERATEGEN3` | 1 | Gen3 rate 控制状态 |
| `PCIEUSERRATESTART` | 1 | 用户 rate-change start 脉冲 |
| `PCIEUSERGEN3RDY` | 1 | GT 报告 Gen3 ready |
| `PhyStatus` | 1 | PHY rate-change 完成指示 |

### 2.3 PLL/系统时钟源

四个信号必须在同一 ILA 中同时采集：

| 信号 | 宽度 | 目的 |
|---|---:|---|
| `TXPLLCLKSEL` | 2 | TX PLL 选择 |
| `RXPLLCLKSEL` | 2 | RX PLL 选择 |
| `TXSYSCLKSEL` | 2 | TX system clock source 选择 |
| `RXSYSCLKSEL` | 2 | RX system clock source 选择 |

当前 K13 已采集 `TXPLLCLKSEL/RXPLLCLKSEL`，但还没有完整采集
`TXSYSCLKSEL/RXSYSCLKSEL`；因此 P1.1 必须优先补齐这两个信号。

## 3. P1：官方 Hardware Golden Differential

### P1-1：冻结官方 Demo 基线

- [ ] 确认官方 Demo 当前 bit/LTX、Vivado 版本、目标器件、GT LOC、REFCLK 和 Lane 0 管脚。
- [ ] 确认官方 Demo 已通过 Gen1→Gen3 上板验证，并保存原有 PASS 证据。
- [ ] 记录官方 Demo 的 PHY IP/XCI、GT Wizard 参数和生成源路径。
- [ ] 确认官方 Demo 的切速触发方式：Root Port retrain、PERST#、软件控制或其他方式。
- [ ] 对同一触发方式至少重复 3 次；若三次 `PHY_RATE` 不出现 Gen1→Gen3 边沿，先修复触发流程，不进入差分分析。

产出：

```text
/home/wx/Documents/KCU105/pcie_phy_0_ex/vcs_results/official_trace/
official_build_manifest.txt
official_ila_<timestamp>.csv
official_ila_<timestamp>.ila
```

### P1-2：给官方 Demo 加 PHY ILA

- [ ] 在官方 Demo 的真实 GT/PHY 层次插入 ILA，采样时钟使用官方 PHY 的 `phy_pclk`。
- [ ] 按第 2 节接入全部信号；优先接 GTHE3 primitive pin，避免只接 wrapper 重新命名的副本。
- [ ] ILA 深度建议 `8192`，pre-trigger 建议 `4096`；如果官方 Demo 资源不足，记录实际深度并让 K13 使用完全相同配置。
- [ ] 为 `PHY_RATE==2'b10` 配置触发/捕获条件，但分析时以实际 Gen1→Gen3 边沿确定 T0，不以 ILA 触发位置代替 T0。
- [ ] 构建阶段检查所有信号各有且仅有一个网络，输出 probe 位序映射表。
- [ ] 重新综合/实现，检查 DRC、CDC、时序和 bitgen。
- [ ] 下载官方 bit/LTX，执行一次相同的 Gen1→Gen3 动态切速，保存 CSV/ILA。

### P1-3：给 K13 加同构 ILA

K13 现有入口：

- 实现脚本：`fpga/kcu105/run_k11b2_impl.tcl`
- ILA 实现脚本：`fpga/kcu105/run_k11b2_ila_impl.sh`
- 上板脚本：`fpga/kcu105/run_k11b2_ila_hw.tcl`
- 当前 K13 PIPE ILA：`u_ila_pipe`，已有 `probe6/probe20` 的 rate/QPLL 观测。

- [ ] 保留现有 `dbg_pipe_top[57]` 的 Recovery 触发能力。
- [ ] 将第 2 节的信号统一加入 K13 ILA，保持与官方 Demo 相同的 probe 位序。
- [ ] 直接增加 `TXSYSCLKSEL/RXSYSCLKSEL` primitive pin；若综合网表无法保留，修改实现脚本使缺失直接报错。
- [ ] 同时保留 `dbg_pipe_top`、LTSSM、RXRESETDONE、RXVALID、RXSTATUS 等 K13 上下文信号。
- [ ] 用 `K13_ENABLE=1`、`K13_GT_PRIMITIVE_DEBUG=1`、`K13_GT_QPLL_PREREQ_DEBUG=1` 重新实现并记录 bit/LTX SHA-256。
- [ ] 下载 K13 bit/LTX，使用与官方 Demo 相同的 Root Port 触发方式抓取 Recovery.Speed。

### P1-4：统一 T0 和比较窗口

对每个 CSV 执行以下确定性处理：

1. 找到 `PHY_RATE` 从 `00` 到 `10` 的第一个上升边沿，记为 `T0=0`。
2. 截取 `T0-256` 到 `T0+1024` 个 `phy_pclk` 样本；如果采样深度不足，标记为无效实验。
3. 对每个信号记录：首次变化点、变化值、持续长度、恢复点、窗口末值。
4. 对官方和 K13 按同名信号、同一 bit 顺序生成事件表。
5. 找到按时间顺序排列的第一个值不同事件；若同一采样出现多个不同信号，按信号依赖顺序记录为同一分叉组，不随意挑选结论。

推荐输出格式：

```text
signal,official_first_change,official_value,K13_first_change,K13_value,delta_pclk,classification
PHY_RATE,0,2,0,2,0,match
QPLL1RESET,...
QPLL1LOCK,...
TXSYSCLKSEL,...
RXSYSCLKSEL,...
PCIEUSERGEN3RDY,...
PhyStatus,...
```

### P1-5：官方/K13 对齐表

第一轮报告必须形成以下表格，不能用“官方 PASS、K13 FAIL”替代：

| 事件 | Official | K13 | 差值/结论 |
|---|---:|---:|---|
| `PHY_TXELECIDLE` 上升 | 待测 | 待测 | |
| TXEQ start | 待测 | 待测 | |
| `TXEQ_DONE` | 待测 | 待测 | |
| `PHY_RATE: Gen1→Gen3` (`T0`) | `0` | `0` | 对齐基准 |
| `PCIERATEIDLE` 变化 | 待测 | 已有 K13 记录 | |
| `PCIERATEQPLLRESET` 上升 | 待测 | 已观察 | |
| `QPLL1RESET` 上升 | 待测 | 已观察 | |
| `QPLL1LOCK` 下降 | 待测 | 已观察 | |
| `QPLL1RESET` 下降 | 待测 | 已观察 | |
| `QPLL1LOCK` 恢复 | PASS 目标 | 当前 FAIL | 关键判定 |
| `PCIERATEGEN3` 上升 | 待测 | 已观察 | |
| `PCIEUSERRATESTART` | 待测 | 已观察 pulse | |
| `PCIEUSERGEN3RDY` 上升 | PASS 目标 | 当前 FAIL | |
| `PhyStatus` 上升 | PASS 目标 | 当前 FAIL | |

P1 完成条件：

- [ ] 官方和 K13 均成功捕获同一类 Gen1→Gen3 动态切速；
- [ ] 两份数据以 `PHY_RATE` 的 Gen1→Gen3 边沿完成 T0 对齐；
- [ ] 已找出第一个不同事件/第一个不同 PCLK；
- [ ] 已判断该分叉属于 TXEQ、QPLL reset、PLL source switching、rate FSM 或后续 PHY handshake。

## 4. P1.1：补齐 TXSYSCLKSEL/RXSYSCLKSEL

### P1.1-1：信号连接检查

- [ ] 从 GTHE3_CHANNEL primitive 直接取 `TXPLLCLKSEL[1:0]`、`RXPLLCLKSEL[1:0]`。
- [ ] 从同一 GTHE3_CHANNEL primitive 直接取 `TXSYSCLKSEL[1:0]`、`RXSYSCLKSEL[1:0]`。
- [ ] 确认四个信号属于实际 Channel 配置网络，而不是 RTL 默认值或未连接常量。
- [ ] 在 Vivado 中打印每个 pin 的 cell、REF_PIN_NAME、net 和 probe 位序。
- [ ] 官方 Demo 和 K13 使用相同编码解释；若编码由 GT Wizard 文档定义，记录编码表后再比较。

### P1.1-2：按三种情况判别

#### 情况 A：SYSCLKSEL 没有切换

```text
PHY_RATE=Gen3
PCIERATEGEN3=1
TXSYSCLKSEL/RXSYSCLKSEL 仍为 Gen1/CPLL 状态
```

判定：问题位于 PCIe PHY rate FSM 到 Channel PLL source selection 的连接或控制路径。

#### 情况 B：SYSCLKSEL 过早切到 QPLL1

```text
QPLL1RESET=1
QPLL1LOCK=0
TXSYSCLKSEL/RXSYSCLKSEL 已切到 QPLL1
```

判定：重点检查 GT rate sequencer 是否在 QPLL1 ready 之前切换 Channel clock source。

#### 情况 C：SYSCLKSEL 正确但 QPLL1 不锁

```text
QPLL1RESET=0
QPLL1PD=0
TX/RXSYSCLKSEL=QPLL1
TX/RXPLLCLKSEL=QPLL1
QPLL1LOCK=0
```

判定：再进入 QPLL1 reset/relock、LOCKDETCLK、REFCLK/FBCLK 和动态 rate 配置分析；在此之前不修改 QPLL 参数。

P1.1 完成条件：

- [ ] 四个 PLL/SYSCLKSEL 信号同时出现在官方/K13 对齐表；
- [ ] 已排除“只观察 PLLCLKSEL、没有观察 SYSCLKSEL”造成的误判；
- [ ] 已给出 A/B/C 三种情况之一，或用数据说明三者均不成立。

## 5. P2：K02 Gen1→Gen3 Dynamic Rate Change

### P2-1：新增最小动态切速模式

新增构建选项：

```text
K02_DYNAMIC_GEN1_TO_GEN3=1
```

K02 必须复现最小控制序列，但不实现完整 PCIe 协议层：

```text
Reset
  ↓
Receiver Detect
  ↓
P0
  ↓
phy_rate = Gen1
  ↓
等待 Gen1 稳定
  ↓
TX Electrical Idle = 1
  ↓
as_cdr_hold_req = 1
  ↓
TXEQ_CTRL/TXEQ_PRESET
  ↓
等待 TXEQ_DONE
  ↓
phy_rate = Gen3
  ↓
观察 PCIERATEQPLLRESET 和实际 QPLL1RESET
  ↓
QPLL1LOCK: 1 → 0 → 1
  ↓
PCIERATEGEN3 = 1
  ↓
PCIEUSERGEN3RDY = 1
  ↓
PhyStatus
  ↓
PASS
```

### P2-2：K02 RTL/ILA 实施要求

- [x] K02 初始状态为 Gen1/CPLL，不是上电即 Gen3 steady state。
- [x] Gen1 稳定延时参数化；硬件版本使用 `DYNAMIC_START_DELAY_CYCLES=1000000000`。
- [x] `TXEQ_CTRL/TXEQ_PRESET/TXEQ_DONE/as_cdr_hold_req` 已接入；明确标注为 K02“受控替代序列”，不是官方 TXEQ 行为。
- [x] ILA 已加入 PHY/QPLL/rate/SYSCLKSEL 信号并保留 K02 FSM 状态，probe0=49 位。
- [x] 直接连接 GTHE3 primitive `QPLL1LOCK/QPLL1RESET/QPLL1PD/TXSYSCLKSEL/RXSYSCLKSEL`。
- [x] 以 `dynamic_rate_txeq_active` 捕获前置分叉，并在波形中以 `PHY_RATE` 的 Gen1→Gen3 边沿作为 T0。
- [x] 构建门禁、bit/LTX SHA-256 和抓取路径已写入报告。

### P2-3：K02 动态实验执行

- [x] `make k02-lint` 通过。
- [x] `make k02-verilator` 通过；既有 K02 行为回归 2/2 PASS，10,000 组随机向量 PASS。
- [x] 动态 Vivado 实现通过，WNS=`+0.704 ns`。
- [x] 已启动 `hw_server`，下载 K02 dynamic bit/LTX 并成功 arm ILA。
- [x] 已重复 3 次冷启动/编程切速，三次结果一致。
- [x] 已观察 `QPLL1LOCK` 的 `1→0`；本次窗口内未出现 `0→1`。
- [x] 已确认 `PCIEUSERGEN3RDY` 和 `PhyStatus` 未在 QPLL1 lock 未恢复时出现。
- [x] 已将 K02 四个 PLL/SYSCLKSEL 加入 ILA 并记录其窗口内保持值；官方对照待补。

### P2-4：结果分支

| 结果 | 解释 | 后续 |
|---|---|---|
| K02 dynamic PASS，K13 FAIL | 问题集中在 K13 integration、时序、控制序列或 full-design routing/fanout | 优先比较 K02/K13 第一个分叉点 |
| K02 dynamic FAIL，官方 Demo PASS | K02/K13 与官方 Demo 的 dynamic rate-control sequence 仍有差异 | 对比 TXEQ、rate FSM、SYSCLKSEL 和 QPLL reset 顺序 |
| K02 dynamic PASS，K13 WNS≥0 后 PASS | K13 负时序可能是重要因素 | 固化时序约束和实现结果 |
| K02 dynamic PASS，K13 WNS≥0 后仍 FAIL | 不是单纯时序问题 | 聚焦 production rate controller、SYSCLKSEL/PLLCLKSEL、QPLL reset sequencing |

P2 完成条件：

- [x] K02 已完成 3 次动态切速抓取；
- [x] 结果不是只看最终 LED，已有 QPLL1 lock/reset 和 Gen3 ready 的 ILA 证据；
- [ ] K02 与官方/K13 已使用相同 T0 对齐格式；官方硬件 Golden 尚缺。

## 6. 逐条执行顺序和停止条件

按以下顺序执行，不跨步修改生产控制器：

1. [ ] P1-1：冻结官方 Demo 硬件基线。
2. [ ] P1-2：官方 Demo 加同构 ILA，生成 bit/LTX 并抓取成功窗口。
3. [ ] P1-3：K13 补齐同构 ILA，特别是 `TXSYSCLKSEL/RXSYSCLKSEL`。
4. [ ] P1-4：统一 T0，生成逐 PCLK 事件表。
5. [ ] P1-5：确定第一个不同事件；若未确定，不进入修复。
6. [ ] P1.1：按 A/B/C 判别 PLL source switching 与 QPLL 本体问题。
7. [x] P2-1/P2-2：实现 K02 dynamic mode 和 ILA。
8. [x] P2-3：完成 K02 三次以上实板动态切速。
9. [ ] P2-4：依据结果选择 K13 integration、时序或 PLL/rate FSM 分支。

以下情况必须停止并补证据：

- 官方和 K13 的 T0 无法确定；
- 两个 ILA 的采样时钟或 probe 位序不同；
- bitgen 成功但 DRC/CDC/时序门禁失败；
- `QPLL1LOCK` 只取了 wrapper 别名，没有 primitive 直接观测；
- K02 的 TXEQ 信号是人为常量，却被当作官方 TXEQ 完成证据；
- 只看到最终 `PCIEUSERGEN3RDY/PhyStatus` 失败，没有记录前置事件顺序。

## 7. 最终交付物

- [ ] 官方 Demo 带 ILA 的 bit/LTX、构建日志和 SHA-256；
- [ ] K13 带同构 ILA 的 bit/LTX、构建日志和 SHA-256；
- [ ] K02 dynamic bit/LTX、构建日志和 SHA-256；
- [ ] 官方/K13/K02 原始 CSV/ILA；
- [ ] 统一 T0 后的逐 PCLK 差分 CSV；
- [ ] `Official vs K13 vs K02` 事件对齐表；
- [ ] 第一个分叉点的结论及证据截图/采样点；
- [ ] 根据分叉点制定的唯一下一项 RTL 或约束修改；
- [ ] 修改后重复实验的 PASS/FAIL 记录。

最终成功标准不是“某个状态最终为 1”，而是能够回答：

> 官方成功路径和 K13 失败路径，从哪个信号、哪个 `phy_pclk` 开始不同？这个差异是否能够在 K02 最小动态切速实验中复现？
