# Phase D：Golden方式Gen1→Gen3 PHY Rate Change计划

## 目标

在Phase A–C已签署的Gen1 Endpoint基线上，只加入Recovery.Speed所需的PHY
rate-change transaction，并严格复现K02 Golden的命令顺序。该阶段只证明PHY能够从
Gen1切换到Gen3并完成QPLL/PhyStatus/Gen3 Ready握手，不实现Gen3协议数据通路。

生产边界继续保持：

`pcie_ltssm_mac_gen1 → pcie_phy_command_ctrl → K02 PHY wrapper`

K04～K10保持冻结。K13代码、ILA与报告仅作为失败对照和诊断参考，不重新进入生产源清单。

## 明确不在本阶段实施

- 128b/130b编码和解码；
- Gen3 EIEOS；
- Recovery.RcvrLock和Recovery.RcvrCfg完整协议；
- Equalization Phase 0～3；
- TXEQ/RXEQ系数协商；
- Gen3 L0、Linux Gen3枚举及BAR压力测试。

上述内容仅在Phase D全部通过后进入Phase E。

## D0：锁定并复验Gen1起点

1. 记录Phase C commit、canonical bitstream SHA256、Vivado版本和板卡序列号。
2. 使用Phase C canonical bit重新执行一轮完整Gen1门禁：
   - ownership、controller单元测试、K03回归、K11-B2 lint；
   - VCS serial/stress；
   - 实板3轮Root Port reboot，每轮5次MMIO及AER检查。
3. 若Gen1门禁失败，停止Phase D；保存现场并只修复Gen1基线，不修改K04～K10。

## D1：固化K02 Golden rate-change contract

使用K02 Golden工程采集同一套事件相对时间和逐拍控制值：

1. Gen1稳定状态；
2. Golden pre-rate状态进入；
3. `PHY_RATE=Gen3`；
4. `PCIERATEQPLLRESET`及其脉宽；
5. `QPLL1RESET`及其脉宽；
6. `QPLL1LOCK`下降和恢复；
7. 首个有效`PHYSTATUS`；
8. `PCIERATEGEN3`；
9. `PCIEUSERGEN3RDY`。

同时记录PowerDown、DetectRx、TX Electrical Idle、CDR Hold、TXEQ/RXEQ及reset-done
相关信号，形成机器可比较的Golden trace和文字contract。已知参考值为QPLL1LOCK约
77.5 us恢复、PHYSTATUS约110.7 us出现；最终阈值以同一板卡重复采样结果确定，不能
从K13现有时序反推。

完成条件：至少5次Golden切速的事件顺序一致，时间窗口可重复，且不存在未记录的
并行raw command owner。

## D2：扩展PHY Command Controller

1. 为controller增加独立的`RATE_CHANGE_GEN3`语义transaction；raw命令仍只由该模块
   驱动。
2. 将Golden sequence实现为显式子状态机；K03只发起请求并消费
   `valid/ready/done/result`，继续拥有协议超时和Recovery状态跳转。
3. 明确定义结果：成功、PhyStatus错误、QPLL lock超时、Gen3 Ready超时和取消/复位。
4. 任意PERST、hot reset或link-loss复位必须返回已签署的Gen1静态profile；不得在未知
   中间状态直接重试。
5. TXEQ/RXEQ在本阶段保持为零；禁止顺带加入Equalization控制。

单元测试必须覆盖：

- Golden逐拍命令顺序及全部脉宽；
- 正常完成以及边界拍完成；
- QPLL lock延迟/超时；
- PhyStatus缺失、过早、重复及错误状态；
- Gen3 Ready延迟/超时；
- 每个子状态下的PERST、hot reset和link-loss；
- 连续两次独立rate transaction；
- Gen1非切速路径与Phase C逐周期等价。

ownership负向fixture必须继续通过，生产顶层仍只能有一个controller实例和一个raw
command driver。

## D3：K02 PHY standalone实板证明

先不接入完整Gen3协议，在K02 wrapper边界执行controller生成的rate transaction。

每次实验保存ILA/raw trace，至少验证：

- 命令事件顺序与D1 Golden contract一致；
- QPLL1LOCK在Golden采样窗口内恢复，目标不晚于100 us；
- PHYSTATUS在Golden采样窗口内出现，目标不晚于130 us；
- `PCIERATEGEN3=1`且`PCIEUSERGEN3RDY=1`；
- 无额外QPLL reset、重复transaction或多owner毛刺；
- PERST后可确定性恢复到Gen1起点。

连续10次切速全部通过才进入D4。若出现K13型QPLL1LOCK超过262 us或PhyStatus不完成，
立即停止集成，按D1 trace逐事件定位差异。

## D4：接入K03 Recovery.Speed

1. 只开放K03到controller的Recovery.Speed请求，不改变TS1/TS2、Ordered Set、扰码、
   成帧或16-bit Packet接口。
2. 使用明确的实验使能控制切速；默认release仍保持Phase C Gen1行为，避免未完成的
   Gen3数据通路成为默认启动路径。
3. 证明K03发起一次transaction、controller完成一次Golden sequence，并将语义结果在
   同拍规则下返回K03。
4. 此阶段的成功终点是PHY Gen3 Ready及可解释的后续协议停点，不把Gen3 L0或Linux
   枚举列为通过条件。

验证包括controller/K03定向仿真、真实PHY VCS、实现时序/DRC、ILA trace及不少于10次
实板重复。每次失败先保存trace和Root Port状态，不先remove/rescan。

## D5：签署与Phase E入口

Phase D报告必须包含：

- D1 Golden contract及5次原始测量；
- D2逐周期测试矩阵；
- D3/D4每次实板结果和失败现场；
- WNS/WHS、DRC、debug core、构建参数和bitstream SHA256；
- Phase C Gen1默认路径未退化的完整回归结果；
- K04～K10无源文件差异证明。

仅当D0～D4全部通过时，才允许立项Phase E，并按以下顺序加入协议能力：

1. Gen3 EIEOS与128b/130b；
2. Recovery.RcvrLock；
3. Recovery.RcvrCfg；
4. Equalization Phase 0～3及RXEQ/TXEQ；
5. Gen3 L0；
6. Linux Gen3枚举、BAR和长期压力测试。

任何阶段失败时，Phase C canonical Gen1 bitstream始终作为可恢复基线，不以修改
K04～K10或恢复K13生产MUX作为绕过方案。
