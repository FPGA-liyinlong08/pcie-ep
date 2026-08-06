# K02 standalone PCIe PHY RTL 前验证计划

状态：**K02-v1 已冻结；测试平台先行**

## 1. 验证分层和参考

| 层次 | DUT/模型 | 目的 |
|---|---|---|
| Verilator | `kcu105_pcie_phy_wrapper` + 自建行为 PHY Stub + 原语 Stub | 封装端口、复位依赖、数据/控制直通和 Checker 自检 |
| XCI 静态检查 | Tcl 生成结果、XML/生成顶层 | 配置、端口、模型参数和两次生成指纹 |
| VCS IP 编译 | Vivado 生成目录的固定源清单 + 预编译库 | 证明完整 PHY/GT Wizard/secureip 可编译和 elaboration |
| VCS GT 动态仿真 | 完整 K01 + `pcie_phy_x1_gen3` + GTHE3 模型 | 复位、时钟、Receiver Detect、Gen1/2/3 Rate Change |
| Vivado | OOC + bring-up 顶层完整实现 | GT/COMMON/REFCLK/管脚放置、DRC、CDC、时序、bitstream |
| KCU105 | J74=x1，真实 Root Port | Receiver Present 的最终物理验收 |

本地参考只用于交叉检查：

- `/home/wx/Documents/KCU105/pcie_phy_0_ex`：同器件/同配置 standalone PHY 示例；
- `/home/wx/Documents/KCU105/kcu105_pcie`：GT/REFCLK 放置和板级结果；
- `/home/wx/Documents/vcs_compile_simlib`：Vivado 2021.2 VCS 预编译库。

## 2. 错误 Stub 自检

先编译与冻结顶层同端口的故意错误 Stub。它在 PERST# 有效期间错误地释放
`pipe_rst_n/core_rst_n`，且不响应 Receiver Detect。测试必须在初始复位检查中
失败，JUnit 包含 failure 后外层才输出 `K02_CHECKER_SELFTEST_PASS`。

该步骤通过前禁止加入生产 `kcu105_pcie_phy_wrapper`。

## 3. Verilator 行为测试

行为 PHY Stub 必须使用与生成 IP 完全相同的模块名和端口宽度，只实现可预测的：

- 参考时钟直通测试时钟；
- PERST#/PhyStatus Reset 行为；
- PHY32 TX→RX 回环；
- Receiver Detect 后一拍产生 `phystatus=1, rxstatus=3'b011`；
- Rate 改变后产生 PhyStatus/PhyStatus Reset；
- EQ 控制到状态的最小可检查响应。

Directed Case：

1. PERST# 置位/释放与 PIPE/Core 四拍释放；
2. PHY32 数据、DataK、DataValid、StartBlock、SyncHeader 逐字段直通；
3. Receiver Detect 控制保持和 `011` 状态；
4. `00→01→10→00` Rate Change，Core 不复位、PIPE 重新同步释放；
5. Polarity、Powerdown、TX/RX EQ 每个控制字段的连线覆盖；
6. 非法 Rate `11` 只由断言报告，不发送给真实 IP。

随机测试至少 10,000 组 PHY32/控制向量，Scoreboard 检查无位交换、宽度截断或
跨字段串扰。断言检查复位期默认值、Rate 握手和 Detect 合法前置条件。

## 4. XCI 确定性与生成检查

- 使用 Vivado 2021.2、固定器件和固定绝对工程根执行生成 Tcl；
- 连续生成两次，XCI SHA-256 必须一致；
- 逐项检查所有架构文档中的固定 CONFIG 值；
- VLNV 必须为 `xilinx.com:ip:pcie_phy:1.0`、Revision 19；
- 生成顶层端口必须与接口文档逐名称、方向、宽度一致；
- 生成模型必须为 `PHY_LANE=1`、`PHY_MAX_SPEED=3`、`PHY_DATA_WIDTH=32`、
  `PHY_ASYNC_EN="FALSE"`；
- GT Wrapper 必须包含 `SIM_RECEIVER_DETECT_PASS="TRUE"` 和
  `SIM_RESET_SPEEDUP="TRUE"`；
- 版本管理目录不得出现生成 Verilog、DCP、XPR 或仿真库。

## 5. VCS 编译和动态测试

### 5.1 编译门

VCS 脚本按 Vivado 2021.2 生成目录和编译顺序维护固定源清单。VCS 必须编译：

- `gtwizard_ultrascale_v1_7_12` 静态 RTL；
- PHY 生成的 GT Common/Channel Wrapper；
- PHY source/sim 顶层；
- K01/K02 RTL 和 K02 testbench；
- `unisims_ver`、`secureip` 与 `xpm` 预编译映射。

不允许用空黑盒代替 GTHE3；elaboration 层次必须包含真实
`GTHE3_CHANNEL/GTHE3_COMMON` 模型。

### 5.2 动态用例

1. 100 MHz REFCLK、PERST# 保持至少 100 ns；
2. 等待 `phy_phystatus_rst` 撤销和 PIPE/Core 时钟稳定；
3. 测量 `phy_coreclk=250 MHz`、`phy_userclk=125 MHz`；
4. Gen1 下测量 `phy_pclk=125 MHz`；
5. 在 P1/Electrical Idle 下发 Receiver Detect，等待 PhyStatus，检查 RxStatus=011；
6. 执行 Gen1→Gen2→Gen3→Gen1，每次等待 PhyStatus 并测量 PCLK；
7. Rate Change 期间检查 Core Reset 保持释放、PIPE Reset 正确重新同步；
8. 每个操作设置独立超时并打印阶段状态，最终打印 `K02_VCS_PHY_PASS`。

VCS 的 `SIM_RECEIVER_DETECT_PASS=TRUE` 只证明数字控制路径。无 Root Port 串行模型
时，不声称验证模拟终端阻抗、CDR 锁定质量或 PCIe 链路训练。

## 6. Vivado 静态与实现检查

- OOC：IP 状态、综合 DCP、0 Error/0 Critical Warning；
- 完整实现：`kcu105_pcie_phy_bringup_top` 完成 opt/place/route/bitstream；
- Lane 0 RX/TX 管脚分别为 AB2/AB1、AC4/AC3；REFCLK 为 AB6/AB5；PERST# 为 K22；
- 恰好一个 `GTHE3_CHANNEL`，LOC=`GTHE3_CHANNEL_X0Y7`；
- 恰好一个 `GTHE3_COMMON`，LOC=`GTHE3_COMMON_X0Y1`，使用 QPLL1；
- REFCLK 必须落在 Quad 225 MGTREFCLK0；
- 不得出现 PCIe Endpoint/XDMA/PCIe Hard Block 协议实例；
- `report_cdc` 无 Critical，DRC 无 Error/Critical Warning；
- Route 后 WNS/TNS ≥ 0/0；普通 Warning 与 K02 固定白名单精确一致。

## 7. 上板计划和通过标准

上板前确认 J74 短接 1-2（x1）。KCU105 插入 Root Port 后：

1. 下载 K02 bring-up bitstream；
2. LED0 指示 PHY 初始化完成，LED1 指示 Receiver Present；
3. LED2 指示 Detect 完成，LED3/4 指示 PIPE/Core 复位释放；
4. ILA/Hardware Manager 核对 `rxstatus=011` 和无 Detect Timeout；
5. 分别在无主机和有主机条件测试，结果必须不同；
6. 重复 20 次 PERST#/冷启动，Receiver Detect 结果一致。

正常门禁要求错误 Stub、Verilator、XCI 指纹、VCS 真 IP、OOC、完整实现和真实
KCU105 Receiver Detect 全部 PASS。2026-08-06 用户批准把 VCS 动态和实板验证延期
并开始 K03；该例外只允许条件冻结，延期项最迟必须在 K11 Gen1 集成冻结前补齐。
