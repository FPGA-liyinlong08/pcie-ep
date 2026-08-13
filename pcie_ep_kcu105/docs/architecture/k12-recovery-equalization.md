# K12 Recovery.Speed 与 Equalization 架构基线

状态：**v0.3；K12-D及K12-E真实PHY影子适配PASS，Gen3生产驱动接线前冻结中**

## 1. 目标

K12在`K11-PHASE-RELEASE-v1`的稳定Gen1 x1链路上加入：

1. 配置触发的Retrain与目标速率传播；
2. Recovery.RcvrLock/RcvrCfg/Speed/Idle完整路径；
3. Gen1→Gen3速率切换握手；
4. Gen3 Equalization Phase 0～3；
5. 拒绝、非法Preset/系数、PHY超时、CDR失锁和Gen1回退。

K12不改变DLL/TLP/BAR语义，不承担K13的Gen3完整枚举/MMIO压力，也不替代K14最终
稳定性发布门。

## 2. 现有接口基线

K02已经冻结并接通PHY速率/EQ端口：`phy_rate`、`phy_txeq_*`、`phy_rxeq_*`及对应
done/系数反馈。K08已经提供`retrain_link_pulse`和`target_link_speed`，但K11生产顶层
尚未把它们可靠跨到PIPE/LTSSM域；这是K12第一项集成工作。

K11 release中`phy_rate=Gen1`、TX/RX EQ控制为0、Rate ID只宣告Gen1。K12必须通过
参数或新模块显式启用升速，默认配置继续保持K11 Gen1行为，保证可回退和回归隔离。

## 3. 建议状态分层

- `Recovery.RcvrLock`：接收TS1并恢复Symbol/Block锁；不发起速率切换。
- `Recovery.RcvrCfg`：交换TS2，锁存双方速率能力与EQ请求。
- `Recovery.Speed`：请求Electrical Idle，驱动`phy_rate`，等待PHY完成速率握手。
- `Recovery.Equalization`：Phase 0～3独立子状态，所有PHY EQ命令保持到done或timeout。
- `Recovery.Idle`：双方新速率Idle确认后进入L0。
- `Fallback`：任何非法请求、超时、CDR失锁或EQ拒绝都回到Gen1恢复路径；清理半完成
  命令和计数，不污染K11 DLL/TL状态。

状态跳转必须在完整Ordered Set边界发生，沿用G12-B已经证明的pending/complete模式。

## 4. 安全与错误策略

- PHY命令使用请求/完成语义，不能生成单拍后丢失的控制。
- 每个Speed/EQ阶段都有有限超时和饱和错误计数器。
- Preset、Coefficient和Phase字段先做合法性检查，再驱动PHY。
- 切速期间禁止TLP/DLLP提交；进入新L0后重新执行必要的DLL初始化。
- 默认或失败路径必须能够回到已冻结的Gen1 release行为。
- K12开发bit与K11 release bit分目录；K11 release SHA256保持不变。

## 5. 实施顺序

1. K12-A：冻结接口、状态编码、CDC和行为PHY模型；建立错误Stub自检。
2. K12-B：实现Retrain CDC与Recovery.Speed骨架，仅验证Gen1↔目标速率握手/回退。
3. K12-C：实现EQ Phase 0～3及Preset/Coefficient合法性。
4. K12-D：注入拒绝、超时、CDR失锁和非法系数，证明Gen1回退。
5. K12-E：VCS真实PHY串行验证与KU040实现复签，形成K12冻结报告。

K12-A已完成CDC mailbox代码和cocotb正/负向门禁；K12-B已完成独立Recovery.Speed
状态骨架和fallback门禁；K12-C已完成独立EQ Phase 0～3和done/timeout门禁；行为PHY
Partner已将三者串接，并通过正常速率/EQ、Peer Reject、EQ timeout和Ordered Set边界
负向集成门禁；K12-D已加入CDR loss、TS类型/速率/Lane/Link合法性和安全回退；
K12-E已在真实standalone PHY + Root Port VCS中完成影子适配展开，确认Gen1默认
PHY feedback已知且EQ控制为0。真实Gen3 retrain/EQ驱动接线仍留给K13生产集成门。

完成验证计划的全部门禁前，不宣称Gen3 Endpoint完成；Gen3枚举和BAR压力属于K13。
