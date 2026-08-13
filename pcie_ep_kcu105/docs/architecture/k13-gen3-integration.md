# K13 Gen3 x1 全集成架构基线

状态：**v0.2，在建；Retrain/Recovery.Speed生产接线已修正，Gen3 x1全集成未冻结**

## 1. 阶段目标

K13把K12已经独立验证的Retrain CDC、Recovery.Speed、TS合法性门禁和
Equalization Phase 0～3接入K11生产Endpoint，使链路能够从稳定Gen1 x1 L0
切换到真实Gen3 x1，并在Linux Root Port下完成枚举和BAR访问。

K13的完成状态必须同时满足控制面、真实PHY、协议面、实现和实板五个层级；
`K13-CTRL PASS`只表示控制接线子阶段通过，不等于K13冻结，也不等于Gen3 Endpoint
完成。

## 2. 生产集成结构

生产控制边界由`rtl/phy/pcie_k13_production_ctrl.sv`实现，并在
`rtl/ep/kcu105_pcie_ep_gen1_top.sv`中通过`K13_ENABLE`静态选择：

```text
K08配置空间 Retrain/Target Speed（phy_coreclk）
        │
        ▼
pcie_retrain_cdc_mailbox
        │（phy_pclk）
        ├── pcie_recovery_speed_ctrl ──► rate / electrical idle / quiesce
        ├── pcie_recovery_ts_guard   ──► TS accept/reject
        └── pcie_equalization_ctrl   ──► TX/RX EQ Phase 0～3
                                         │
                                         ▼
                              K02 standalone pcie_phy
```

顶层只允许K13控制器在Recovery或EQ活动期间接管PHY控制。正常Gen1路径仍由生产
LTSSM驱动；事务发送在`traffic_quiesce=1`期间停止提交。协商速率只有在控制器给出
有效结果后才覆盖生产LTSSM的Gen1默认值。

Retrain不再允许旁路控制器在L0直接改变PHY rate。生产LTSSM必须先经过
`Recovery.RcvrLock→Recovery.RcvrCfg`，再用`recovery_speed_ready`授权
`pcie_recovery_speed_ctrl`进入Electrical Idle/切速。`recovery_speed_done`后重新执行
`RcvrLock→RcvrCfg`，并在K13 Speed/EQ释放前保持`Recovery.Idle`。这一顺序
消除了已观察到的“LTSSM仍为L0时PHY被单独切到Gen3”矛盾。

## 3. 静态旁路与回退

`K13_ENABLE=0`必须在elaboration时完全旁路K13控制器：

- 不实例化K13控制器和K13 mux数据路径；
- `phy_rate`、Electrical Idle和EQ控制保持K11 Gen1 release行为；
- `K13_ENABLE=0`的正式K11 bit与K13开发bit使用不同构建目录；
- K11 reboot、枚举和BAR回归不能因K13代码存在而退化。

`K13_ENABLE=1`的任何非法速率、TS拒绝、Speed/EQ超时或CDR失锁必须进入显式
Fallback，清除EQ命令，恢复Gen1速率并重新训练。失败路径不得停留在Electrical
Idle，也不得在半完成的EQ状态恢复TLP/DLLP。

## 4. Ordered Set与Gen3数据路径

K13沿用G12验证过的完整Ordered Set边界：只有`ts_valid && ts_complete`且TS类型、
Lane、Link和Rate全部合法时，控制器才能接受对端训练信息。状态、发送模式和PHY
速率不能在一个TS中途切换。

当前生产LTSSM/MAC的发送和接收主路径仍以Gen1 8b/10b Ordered Set为基础；K13
尚需完成并验证：

- Gen3 128b/130b Sync Header、Block起点和数据有效边界；
- Recovery期间Gen3 TS1/TS2发送字段及完整边界；
- Root Port请求升速后的真实Recovery.Speed与EQ Phase 0～3交互；
- Gen3 L0进入后DLL重新初始化和TLP/DLLP恢复。

在这些路径闭环之前，即使底层IP名称为`pcie_phy_x1_gen3`，生成的bit也不能标记为
Gen3 x1 Endpoint。

## 5. PHY反馈边界

K13复用K02已冻结的`phy_phystatus`、`phy_txeq_done`和`phy_rxeq_done`完成握手。
PHY命令必须保持到done或timeout，不能仅产生单拍。

当前K02 wrapper没有向生产顶层提供独立的真实CDR-loss信号，现有接线使用
`RXELECIDLE && !RXVALID`连续8个`phy_pclk`周期的PIPE代理。这只适用于控制
接线和Gen1回归，不满足K13冻结条件。
冻结前必须从真实PHY可观测反馈构造并验证CDR-loss输入，且证明失锁时能够中止EQ、
回退Gen1并重新训练。

## 6. 当前实现状态

已完成：

- `pcie_k13_production_ctrl`组合K12-A/B/C/D控制单元；
- Retrain命令跨域、Speed握手、TS门禁和EQ Phase 0～3行为级联；
- `K13_ENABLE=0/1`生产顶层静态generate接线；
- K13控制器lint和3项cocotb场景；K12集成回归继续通过；
- `K13_ENABLE=0`的Gen1 x1 ILA诊断bit完成烧写、reboot、枚举和BAR验证。
- 标准Retrain失败定位为L0旁路切速和32周期超时；硬件默认超时已改为
  1,000,000个`phy_pclk`周期，生产LTSSM已加入显式`Recovery.Speed`握手。
- TS Rate ID已按能力位图解析，K13 TX宣告Gen1/2/3的`8'h0e`；K13 ILA已加入
  Speed/EQ/timeout/fallback/TS/CDR观测位。
- K03 LTSSM原有12项回归及新增`Recovery.Speed`边界Directed用例通过；K13控制回归3/3通过。

尚未完成：

- `K13_ENABLE=1`真实Gen3 LTSSM/TS发送和128b/130b数据路径闭环；
- 真实CDR-loss反馈；
- VCS真实PHY/Root Port elaboration和Gen1→Gen3串行仿真；
- K13-enabled Vivado非负WNS、bit生成和ILA验证；
- 实板`LnkSta Speed 8GT/s, Width x1`、10万次随机BAR操作和回退恢复。

## 7. 冻结出口

只有`docs/verification/k13-verification-plan.md`中的所有必需门禁通过，且报告明确
记录K13-enabled bit的参数、SHA256、时序、VCS、ILA、Linux链路状态和BAR压力结果，
才允许标记`K13-FROZEN`并进入K14。当前阶段标签保持`K13-IN-PROGRESS`。
