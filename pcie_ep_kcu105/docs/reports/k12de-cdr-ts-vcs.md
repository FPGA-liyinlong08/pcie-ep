# K12-D/E CDR、TS 合法性与真实 PHY/VCS 执行记录

日期：2026-08-13  
状态：**K12-D PASS；K12-E真实PHY影子适配门禁 PASS**

## 1. K12-D 实现

新增 `rtl/phy/pcie_recovery_ts_guard.sv`，在完整 Ordered Set 边界检查：

- TS1/TS2 类型必须且只能有一个有效；
- Rate 不能为非法值 `2'b11`；
- Lane/Link 必须匹配本端期望值；
- EQ 请求只允许在 Gen3 速率出现；
- 非法输入产生一次 `ts_reject` 并锁存分类错误。

行为 PHY Partner 同时接入 `phy_cdr_lost`。CDR loss 会触发 Recovery.Speed
Gen1 fallback，并复位 EQ 控制器，确保 TX/RX EQ 控制清零。

## 2. K12-D 回归

`make k12-integration-sim`：

```text
TESTS=7 PASS=7 FAIL=0 SKIP=0
K12_INTEGRATION_PASS
```

覆盖正常速率/EQ、Peer Reject、EQ timeout、提前 done 边界负向、CDR loss、
非法 TS 类型/速率和 Lane mismatch。

## 3. K12-E VCS 真实 PHY 门禁

命令：

```bash
make k12de-vcs-serial
```

执行结果：

```text
357 modules and 7 UDPs read.
K12E_REAL_PHY_ADAPTER_PASS gen1_phy_feedback=known eq_controls=zero
K11B2_DLL_ACTIVE_PASS
K11B2_ENUM_PASS
K11B2_BAR_PASS
K11B2_VCS_PASS
K11B2_VCS_REAL_PHY_PASS
K12E_VCS_REAL_PHY_PASS
```

这次 VCS 将 K12-D/E RTL 和影子适配器与真实 standalone `pcie_phy`、Xilinx
Root Port 联合展开，观测真实 `phy_pclk`、`phy_rate`、`phy_phystatus`、
`phy_txeq_done` 和 `phy_rxeq_done`。Gen1 release 状态下连续确认 PHY feedback
为已知值且 TX/RX EQ 控制为零，同时原有 K11-B2 枚举、BAR 和 DLL 门禁保持通过。

## 4. 边界与下一步

K12-E 本次完成的是“真实 PHY 接口展开 + Gen1 安全影子适配”门禁，适合确认
接口和默认行为没有破坏 K11 release。影子适配器不驱动生产 LTSSM/PHY 控制线，
因此本记录不宣称真实 Gen3 retrain、TS1/TS2 交换和真实 EQ Phase 0～3 已在
生产 Endpoint 上通过；这些驱动接线和 Gen3 枚举属于下一阶段 K13 生产集成门。
