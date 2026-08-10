# K03 Gen1 x1 LTSSM/MAC 阶段报告

日期：2026-08-06

状态：**K03-v1.1 条件冻结；软件、静态和VCS真PHY串行验收PASS，实板验收延期**

接口版本：`K03-MAC16-v1`

依赖接口：`K02-PHY32-v1.1`

## 1. 阶段结论

K03 已完成 Gen1 x1 LTSSM、训练序列收发、Receiver Detect 控制、Recovery、
Hot Reset 入口以及 TLP/DLLP Symbol 成帧/解帧。测试平台按计划先于 RTL 建立，
故意错误 Stub 能被 Checker 检出；正式 RTL 的 Directed、错误注入、随机训练、
随机 Packet、Lint、KU040 OOC 综合以及 K02 PHY 联合布局布线均已通过。

用户于2026-08-06批准先记录许可证和板卡问题并继续。VCS许可证随后恢复，真实
串行平台已在K11-B1完成并通过；当前只剩实板门禁延期：

- VCS使用Xilinx `pcie_phy`/GTHE3真模型完成完整LTSSM串行训练：2026-08-10 PASS，
  双方Gen1 x1 L0稳定1024个`phy_pclk`；
- KCU105 与 Root Port 实际训练到 Gen1 x1 L0，因当前未插板无法执行。

实板项必须在K11最终冻结前补测。K03以“条件冻结”
结束，本次没有开始 K04。

## 2. 冻结实现

| 文件 | 职责 |
|---|---|
| `rtl/phy/pcie_gen1_os_rx.sv` | 按两 Symbol/拍接收并校验 TS1、TS2 和 Idle |
| `rtl/phy/pcie_gen1_os_tx.sv` | 生成 16 Symbol TS1/TS2 或连续 Idle |
| `rtl/phy/pcie_gen1_framer.sv` | 插入/删除 STP、SDP、END、EDB，转换 MAC16 Packet |
| `rtl/phy/pcie_ltssm_mac_gen1.sv` | Detect、Polling、Configuration、Recovery、L0 和 Hot Reset 控制 |
| `rtl/phy/kcu105_pcie_gen1_top.sv` | 连接 K01、K02 standalone PHY 和 K03 MAC 的实现顶层 |

K03 状态编码与冻结接口文档一致，共 15 个状态：Detect.Quiet、Detect.Active、
Polling.Active、Polling.Configuration、Configuration.Linkwidth.Start/Accept、
Lanenum.Wait/Accept、Complete、Idle、L0、Recovery.RcvrLock/RcvrCfg/Idle 和 Hot Reset。

## 3. 关键实现决定

- K02 生成物的实际接口在 Gen1 为 `16 bit @ 125 MHz`，不是原计划中的
  `32 bit @ 62.5 MHz`；K03 只使用低 16 bit 和两个 `datak`，高 16 bit 固定为 0。
- 线路先到的 Symbol 固定在 `[7:0]`，TS 每拍发送两个 Symbol，一个 TS 共八拍。
- Ordered Set 固定为 COM、Link、Lane、N_FTS、Rate、Control 和十个 TS1/TS2 ID；
  COM/PAD 为 K-code，Identifier 为 Data-code。
- `phy_rate` 在 K03 永久为 Gen1；升速和 Gen3 Equalization 属于 K12。
- TX Packet 必须完整写入 160 Byte 逻辑缓冲后才上线，避免包内反压造成线路空洞；
  偶/奇 Byte 分银行实现为可综合分布式存储。超长包和非法 `keep/sop/eop` 被丢弃
  并产生错误计数。
- RX MAC16 是 valid-only 接口，没有 backpressure；后续 DLL 必须按线路速率消费。
- `link_up` 在本阶段只表示 LTSSM=L0，不表示 DLL Active。

## 4. 测试平台先行证明

`pcie_ltssm_mac_gen1_bad_stub.sv` 在 Receiver Detect 后非法跳过全部训练并直接进入
L0。`normal_training` 对该 Stub 必须失败，外层脚本确认 JUnit 包含 failure 后才
输出：

```text
K03_CHECKER_SELFTEST_PASS
```

这证明测试会检查合法 LTSSM 状态序列和 Ordered Set，而不是只检查最终
`link_up`。

## 5. Verilator/cocotb 结果

固定随机种子为 `20260806`，正式回归 5/5 PASS：

| 测试 | 结果 | 覆盖重点 |
|---|---|---|
| `normal_training` | PASS | 完整状态序列、TS1/TS2、进入 L0 |
| `detect_errors_recovery_and_hot_reset` | PASS | Detect 失败/超时、错误 TS、Recovery、Hot Reset |
| `packet_framing_randomized` | PASS | 2,000 个 1～160 Byte 随机 TLP/DLLP、奇偶长度、END/EDB、随机输入空拍 |
| `packet_protocol_errors` | PASS | 嵌套 Start、非法 K、非法 keep、超长 TX |
| `one_hundred_random_trainings` | PASS | 100 次随机 Partner 延迟和训练重启 |

回归摘要：

```text
K03_VERILATOR_PASS trainings=100 packets=2000 seed=20260806
```

Verilator 对 K03 单模块以及 K01+K02 行为 PHY Stub+K03 集成顶层均为 0 Error。

## 6. Vivado 2021.2 静态结果

### 6.1 K03 OOC

| 项目 | 结果 |
|---|---:|
| Part | `xcku040-ffva1156-2-e` |
| CLB LUT | 1198 |
| LUT as Memory | 40 |
| CLB Register | 932 |
| BRAM | 0 |
| WNS | 4.709 ns |
| DRC Error/Critical | 0/0 |

OOC 看不到 K01 的四级复位同步释放链，因此只允许 `pipe_rst_n` 输入引起的
CDC-7；来源和数量由脚本逐项检查。该项在完整集成中不再是 Critical。

### 6.2 K02 PHY + K03 完整布局布线

| 项目 | 结果 |
|---|---:|
| 顶层 | `kcu105_pcie_gen1_top` |
| GTHE3 Channel | 1，`GTHE3_CHANNEL_X0Y7` |
| GTHE3 Common | 1，`GTHE3_COMMON_X0Y1` |
| PCIe Hard Block | 0 |
| K03 MAC 层次 | 1 |
| Route 后 CLB LUT/Register | 566 / 456 |
| WNS/TNS | 0.212 ns / 0.000 ns |
| DRC Error/Critical | 0/0 |
| CDC Warning/Critical | 0/0（仅 9 条 Info） |
| Bitstream | `fpga/kcu105/build_k03/impl/k03_gen1_ltssm_mac.bit` |

集成顶层尚未连接 DLL TX，因此综合会移除不可达的部分 TX Framer；完整 Framer 已由
OOC 综合和随机 Packet 回归签核。所有普通 Warning 使用唯一 ID 精确 Allowlist，
新增 Warning、Critical Warning 或 Error 都会使构建失败。

## 7. 已知限制和补测步骤

当前冻结范围明确不含 DLL、CRC、Flow Control、Replay、TLP Codec、配置空间、BAR、
Gen3 升速和枚举。K03 的 PHY Partner 是数字接口模型，不能替代真实 GT/CDR、信号
完整性和 Root Port 兼容性测试。

板卡可用后补测顺序：

1. 确认 KCU105 J74 短接 1、2 脚，插入 x1 插槽；
2. 先复测 K02 Receiver Detect；
3. 下载 K03 bitstream，观察 LTSSM 状态和错误计数；
4. 验证稳定进入 Gen1 x1 L0，并连续执行 100 次 PERST#/重训；
5. 保存 Hardware Manager、ILA、Root Port 日志和结果；
6. VCS真PHY/GTHE3串行训练已经补测PASS，无需重复归为板卡待办；
7. 实板项通过后把 K02、K03 报告从“条件冻结”更新为 PASS。

## 8. 冻结决定

`K03-MAC16-v1` 的架构、端口、状态编码、字节序、超时参数语义、错误计数语义及
上述 RTL/测试/脚本冻结。修改这些内容必须重跑 Checker 自检、Lint、完整
Verilator 回归及 K03 Vivado OOC/实现。动态延期项未完成前，K11 不得冻结。
