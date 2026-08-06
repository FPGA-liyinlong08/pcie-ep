# K02 standalone PCIe PHY 阶段报告

日期：2026-08-06  
状态：**执行中，未冻结，禁止开始 K03**  
接口版本：`K02-PHY32-v1`

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
| VCS 真 IP 动态仿真 | **PENDING** | common elaboration 等待 `VCSCompiler_Net` 300 秒未获许可证 |
| KCU105 Receiver Detect | **PENDING** | Hardware Manager 发现 Digilent 目标，但 JTAG 链上未检测到 FPGA |

因此 K02 不能标记 PASS，也不能按阶段门进入 K03。动态 VCS 和真实硬件验收完成后，
在本报告追加结果并冻结 K02。

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

本机 `vlogan` 已编译上述真实源文件，common elaboration 也识别到
`k02_pcie_phy_tb`、`glbl` 和真实 IP 层次。Xilinx 生成 RTL只出现固定的 `TFIPC`
和 `PCWM-W` 普通提示；随后因 `VCSCompiler_Net` 不存在或席位耗尽而排队，等待
300 秒仍未获得许可证，故没有生成可运行的 `simv`，动态复位/Detect/Rate 用例
仍为 PENDING。

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
`hw_server` 的 `localhost:3122`，前者只读探测，后者才会下载 bitstream。启动命令为
`/home/Xilinx/Vivado/2021.2/bin/hw_server -d -p0 -I60 -stcp::3122`。

## 8. 复现命令

```bash
make k02-checker-selftest
make k02-lint
make k02-verilator
make k02-ip
VCS_LICENSE_TIMEOUT=300 make k02-vcs
make k02-vivado
```

待 VCS 许可证和 KCU105 硬件可用后，只重跑未完成门禁；已经通过的接口和 RTL
范围不得在未重新执行完整 K02 回归的情况下修改。
