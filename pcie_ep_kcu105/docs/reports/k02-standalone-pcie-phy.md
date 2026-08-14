# K02 standalone PCIe PHY 阶段报告

日期：2026-08-06

状态：**K02-v1.2 条件冻结；VCS动态PASS，实板Receiver Detect延期**

接口版本：`K02-PHY32-v1.1`

## 1. 阶段结论

K02 已完成 standalone `pcie_phy v1.0` 的确定性生成、生产封装、Receiver Detect
bring-up 顶层、行为验证和 KU040 完整实现。当前自动化结果为：

| 门禁 | 结果 | 证据 |
|---|---|---|
| 架构冻结 | PASS | `docs/architecture/k02-standalone-pcie-phy.md` |
| 接口冻结 | PASS | `docs/interfaces/k02-standalone-pcie-phy-interfaces.md` |
| RTL 前仿真计划 | PASS | `docs/verification/k02-verification-plan.md` |
| 错误 Stub 自检 | PASS | 故意错误复位在 1 ns 被 Checker 检出 |
| Verilator 行为回归 | PASS | 2/2 用例，10,000 组随机 PHY32/EQ 向量 |
| XCI/模型生成检查 | PASS | 连续两次 XCI 指纹一致，模型关键参数一致 |
| Vivado OOC/完整实现 | PASS | Route、DRC、CDC、时序、bitstream 全部通过 |
| VCS 真 IP 源码编译 | PASS | PHY、GT Wizard、K01/K02 与 testbench 均通过 `vlogan` |
| VCS 真 IP 动态仿真 | **PASS** | 2026-08-09完成真实IP/secureip仿真、Receiver Detect模型与G1→G2→G3→G1切速 |
| KCU105 Receiver Detect | **DEFERRED** | 当前不方便插入板卡，Hardware Manager 尚未检测到 FPGA |

2026-08-06 用户明确要求记录许可证问题、待板卡可用后再做上板验证，并继续 K03。
因此本阶段采用一次受控的门禁例外继续K03。2026-08-09许可证服务恢复可访问后，
VCS动态门禁已经补齐并转为PASS；当前只剩KCU105实板Receiver Detect延期。

## 2. 已实现内容

- `kcu105_pcie_phy_wrapper`：连接 K01 REFCLK/复位和完整 PHY32 原生接口；
- `kcu105_pcie_phy_bringup_top`：P1/Electrical Idle 下执行一次 Receiver Detect，
  锁存成功、异常或超时并映射到 LED；
- `generate_k02_pcie_phy.tcl`：固定 KU040、x1、Gen3、100 MHz REFCLK、QPLL1、
  125 MHz User Clock、250 MHz Core Clock及 GT 位置；
- `run_k02_ip_generation.sh`：清理并连续生成两次、比较 XCI SHA-256、检查生成模型；
- `run_k02_impl.tcl/.sh`：IP OOC 综合、顶层 synth/opt/place/route、报告、静态断言和
  bitstream；
- Verilator 行为 Stub、故意错误 Stub、cocotb Driver/Checker/Scoreboard；
- VCS 真实 IP 源清单、独立临时 work library、测试平台和许可证超时机制。

K02 没有实现 LTSSM、Ordered Set、DLL、TLP 或枚举功能。

## 3. 重要板级修订

原计划写的 `GTHE3_CHANNEL_X0Y4` 与 KCU105 PCIe Lane 0 管脚冲突，已修正为
`GTHE3_CHANNEL_X0Y7`。管脚本身保持不变：

| 资源 | 冻结位置 |
|---|---|
| Lane 0 RX | `AB2/AB1` |
| Lane 0 TX | `AC4/AC3` |
| REFCLK | `AB6/AB5`，Quad 225 MGTREFCLK0 |
| PERST# | `K22` |
| GT Channel | `GTHE3_CHANNEL_X0Y7` |
| GT Common | `GTHE3_COMMON_X0Y1` |

依据为 UG917 的 Lane 0 管脚命名、KU040 器件数据库，以及本地 KCU105 XDMA
已布局报告。`X0Y4` 对应 Quad 225 Channel 0 的另一组管脚，无法连接板上 PCIe
Lane 0。实现脚本会同时断言管脚和 GT LOC，防止配置再次漂移。

## 4. XCI 与生成模型结果

- VLNV：`xilinx.com:ip:pcie_phy:1.0`，Vivado 2021.2 Revision 19；
- XCI SHA-256：
  `33c7bc66cdf1414ee0ca4f78a2dc32ed73dac8a150e2dd154698f4d6c2ecb345`；
- 连续两次从干净 IP 目录生成，原始 XCI 指纹一致；
- XCI `CONFIG.phy_async_en=true` 对应生成模型 `PHY_ASYNC_EN="FALSE"`；
- GT 模型 `SIM_RECEIVER_DETECT_PASS="TRUE"`；
- GT 模型 `SIM_RESET_SPEEDUP="TRUE"`。

### 4.1 PHY32 Gen1/2 有效宽度勘误

检查 Vivado 实际生成源和 Xilinx KCU105 PHY 示例后，修正原计划的时钟假设：

- Gen1：`phy_pclk=125 MHz`，每拍低 16 bit 有效；
- Gen2：`phy_pclk=250 MHz`，每拍低 16 bit 有效；
- Gen3：`phy_pclk=250 MHz`，32 bit block 数据有效；
- Gen1/2 的 `phy_txdatak/phy_rxdatak[1:0]` 分别对应低 16 bit 的两个字节，
  高 16 bit 不属于 Gen1/2 数据通路。

证据是生成 GT wrapper 的 `TX_DATA_WIDTH/RX_DATA_WIDTH=20`、`GT_TXDATAK[1:0]`
接线以及 Xilinx 示例只生成两个 Gen1/2 Symbol。K03 以这一实际生成接口为准。

只有 XCI 和生成 Tcl 纳入版本管理；生成 Verilog、DCP、XPR 和仿真库均被忽略。

## 5. 仿真结果

### 5.1 Checker 自检

故意错误 Stub 在 PERST# 有效期间错误释放 `pipe_rst_n`。cocotb 在 1 ns 断言失败，
外层脚本确认 JUnit 含 failure 后才输出 `K02_CHECKER_SELFTEST_PASS`。这证明 Checker
能够发现关键复位错误。

### 5.2 Verilator

- `reset_detect_and_rate`：PASS；
- `randomized_native_interface`：PASS；
- 随机种子：`20260806`；
- 随机向量：10,000；
- 检查内容：PHY32 数据、DataK、Gen3 block/header、Receiver Detect、
  Gen1/2/3 Rate、Core/PIPE Reset 和 EQ 字段无位交换或串扰。

### 5.3 VCS

VCS **可以**完成 Xilinx standalone PCIe PHY 的数字仿真，但必须同时具备：

1. Vivado 2021.2 生成的 PHY/GT Wizard simulation source；
2. 同版本预编译 `gtwizard_ultrascale_v1_7_12`、`secureip`、`unisims_ver`、`xpm`；
3. VCS 编译和运行许可证。

本机 `vlogan` 已编译上述真实源文件，common elaboration识别到
`k02_pcie_phy_tb`、`glbl`和真实IP层次。2026-08-09确认本机`snpslmd`正常，
`VCSCompiler_Net`、`VCSRuntime_Net`和`VCSMXRunTime_Net`各有99席且0占用；在可访问
本机27000端口的环境中补跑成功，生成并执行`simv`，输出
`K02_VCS_REAL_IP_PASS`。Xilinx生成RTL只出现冻结的`TFIPC`和`PCWM-W`普通提示。

VCS 中的 Receiver Detect 结果由 `SIM_RECEIVER_DETECT_PASS="TRUE"` 强制返回，
只能验证数字控制、状态编码和时序，不能验证实际接收终端阻抗、信号完整性、CDR
裕量或板级链路质量。

## 6. Vivado 实现结果

目标器件：`xcku040-ffva1156-2-e`。

| 项目 | 结果 |
|---|---|
| GTHE3 Channel 数量/LOC | `1 / GTHE3_CHANNEL_X0Y7` |
| GTHE3 Common 数量/LOC | `1 / GTHE3_COMMON_X0Y1` |
| PCIe Hard Block 数量 | `0` |
| Route 失败网络 | `0` |
| DRC | `0` 违例 |
| Critical CDC | `0` |
| 无时钟寄存器/未约束内部端点 | `0 / 0` |
| Route WNS/TNS | `+1.060 ns / 0.000 ns` |
| Bitstream | `fpga/kcu105/build_k02/k02_pcie_phy_bringup.bit` |

普通综合 Warning 仅允许文档中固定的六类 ID；脚本对实际集合做精确比较。完整
Allowlist 见 `docs/verification/vivado-warning-allowlist.md`。

## 7. 上板步骤与未决项

主机 USB 能识别 FT232H，Vivado Hardware Manager 也能打开 Digilent hardware
target，但 `open_hw_target` 报告 JTAG 链上没有 device。通常表示开发板未上电、JTAG
线缆链路未接通或当前 FT232H 不属于已上电的 KCU105。因此未下载 bitstream，也未
把上板结果标记为 PASS。开发板可访问后按以下步骤完成：

1. 确认 J74 短接 1-2，KCU105 以 x1 接入已上电 Root Port；
2. 下载 `fpga/kcu105/build_k02/k02_pcie_phy_bringup.bit`；
3. 检查 LED0/3/4 为 PHY、PIPE、Core 初始化完成，LED2 为 Detect 完成；
4. 有 Root Port 时 LED1 必须为 1，LED5/6 必须为 0；
5. 无 Root Port 时结果必须与有终端场景不同；
6. 重复 20 次 PERST#/冷启动，结果一致；
7. 保存 Hardware Manager/ILA 记录后，把本报告状态改为 PASS 并冻结 K02。

工程提供 `make k02-hw-probe` 和 `make k02-hw-program`；二者默认连接本机
`hw_server` 的 `127.0.0.1:3122`，前者只读探测，后者才会下载 bitstream。持续运行
服务可使用 `/home/Xilinx/Vivado/2021.2/bin/hw_server -p0 -I300 -stcp::3122`。

## 7.1 K02 Gen3 PHY ILA 实板验证（2026-08-14）

为直接验证 QPLL1 和 Gen3 PHY ready 状态，本轮将 K02 bring-up 顶层改为：
Receiver Detect 成功后进入受控 Gen3 PHY 测试模式（`P0`、`phy_rate=2'b10`、
TX 保持 Electrical Idle）。K02 仍然不实现 LTSSM、TS1/TS2、Equalization 或
Endpoint 枚举，因此该模式验证的是 PHY/GT，不把它等同于完整 PCIe Gen3 链路。

新增 ILA `u_ila_k02`，采样同一 `phy_pclk` 域的以下信号：

- GTHE3_COMMON primitive 的 `QPLL1LOCK`、`QPLL1RESET`、`QPLL1PD`，以及
  GT Wizard `qpll1lock_out`；
- `phy_rate`、`phy_powerdown`、`PCIERATEGEN3`、QPLL rate-reset/PD、
  `PCIEUSERGEN3RDY`、`PCIEUSERRATESTART`；
- `RXRESETDONE`、`RXELECIDLE`、`RXVALID`、`RXSTATUS`、`PhyStatus`；
- bring-up FSM、Detect 结果和 Gen3 测试状态。

重新实现结果：

```text
K02_IMPL_PASS
GTHE3_CHANNEL_LOC=GTHE3_CHANNEL_X0Y7
GTHE3_COMMON_LOC=GTHE3_COMMON_X0Y1
WNS=0.977 ns
GEN3_TEST_MODE=1
```

bit/LTX：

```text
fpga/kcu105/build_k02/k02_pcie_phy_bringup_ila.bit
SHA256 5bc536bcdfb75279ac4ce2b484fde5eb962acc746e61aac1b2bc9ef46b69cb6f

fpga/kcu105/build_k02/k02_pcie_phy_bringup_ila.ltx
SHA256 818de8b04b006e7529edf6685f805335a97327af2c19d4e6ffadd877fb5cab50
```

实板 ILA 采样：

```text
fpga/kcu105/build_k02/capture/20260814_200635_k02_phy.csv
fpga/kcu105/build_k02/capture/20260814_200635_k02_phy.ila
```

8192 点窗口的关键结果如下，所有状态在窗口内均无变化：

| 信号 | 结果 | 结论 |
|---|---:|---|
| GTHE3_COMMON `QPLL1LOCK` | `1` 全程 | QPLL1 已锁定 |
| GT Wizard `qpll1lock_out` | `1` 全程 | PHY 内部也观察到 QPLL1 lock |
| `QPLL1RESET` / `QPLL1PD` | `0 / 0` 全程 | 未处于 QPLL1 reset/powerdown |
| `phy_rate` | `2` 全程 | PHY 请求 Gen3（8.0 GT/s） |
| `PCIERATEGEN3` | `1` 全程 | GT 已处于 Gen3 rate 模式 |
| `PCIEUSERGEN3RDY` | `1` 全程 | GT 报告 Gen3 ready |
| `RXRESETDONE` | `1` 全程 | RX 初始化完成 |
| `RXVALID` / `RXSTATUS` | `0 / 0` | 没有收到协议数据 |
| Detect | `receiver_present=1`、`rxstatus=3` | Root Port 终端检测成功 |

本轮因此确认：**QPLL1 已锁定，Gen3 PHY ready 正常**。但由于 K02 demo 没有
PCIe 协议训练状态机，`RXVALID=0` 是没有 TS/Ordered Set 驱动时的预期结果，不能
据此宣称 Gen3 x1 链路已经进入 L0。完整 Gen3 链路仍需使用 K11/K13 Endpoint
构建，通过 Root Port 枚举、Recovery.Speed、Equalization 和 L0 结果验收。

复现命令：

```bash
make k02-vivado
/home/Xilinx/Vivado/2021.2/bin/vivado -mode batch \
  -source fpga/kcu105/run_k02_phy_ila_hw.tcl -nojournal \
  -tclargs 127.0.0.1:3122 program-arm
/home/Xilinx/Vivado/2021.2/bin/vivado -mode batch \
  -source fpga/kcu105/run_k02_phy_ila_hw.tcl -nojournal \
  -tclargs 127.0.0.1:3122 capture-wait
```

## 8. 复现命令

```bash
make k02-checker-selftest
make k02-lint
make k02-verilator
make k02-ip
VCS_LICENSE_TIMEOUT=300 make k02-vcs
make k02-vivado
```

待KCU105硬件可用后只需补跑实板Receiver Detect；已经通过的接口和RTL范围不得在
未重新执行完整K02回归的情况下修改。实板结果必须在K11-B冻结前补齐。
