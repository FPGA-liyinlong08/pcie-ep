# KCU105 Gen1→Gen3 实板采样（2026-08-17）

硬件：KCU105 / `xcku040`，Digilent JTAG `210308AC5C97`。

按照 `pcie_ep_kcu105/docs/kcu040-hardware-and-remote.md` 启动本机
`hw_server`，`make ku040-hw-probe` 通过，随后下载：

```text
pcie_phy_0_ex_gen1_to_gen3_ila.bit
```

## 采样文件

```text
capture/20260817_094808_phy.csv
capture/20260817_094808_phy.ila
capture/20260817_095202_phy.csv
capture/20260817_095202_phy.ila
```

## 结果

第一次以 `dynamic_rate_txeq_active` 触发：

| 采样点 | 状态 |
|---:|---|
| 0～8 | `phy_rate=0`，动态状态 TXEQ，`QPLL1LOCK=1` |
| 9 | `phy_txeq_done=1` |
| 10 | `phy_rate=2`，进入 Gen3 wait |
| 19 | `PCIERATEIDLE=0` |
| 20～24 | `QPLL1RESET=1`，`QPLL1LOCK=0` |
| 25～8191 | `QPLL1RESET=0`，但 `QPLL1LOCK` 未恢复 |

第二次以 `dynamic_rate_fail` 触发，覆盖完整 Gen3 等待超时：

```text
dynamic_rate_state = DYN_FAIL (5)
dynamic_rate_fail  = 1
QPLL1LOCK          = 0
QPLL1RESET         = 0
phy_rate           = 0
phy_phystatus      = 0
```

## 结论

当前 standalone `pcie_phy_0_ex` 的 Gen1→Gen3 切换结果为 **FAIL**：
Gen1 阶段 QPLL1 能锁定，但 Gen3 rate-change 触发 QPLL1 reset 后，QPLL1 没有
重新锁定，PHY 也没有产生 `phy_phystatus`，最终进入动态切换 timeout。

`QPLL1PD=0`；`QPLL1REFCLKLOST` 和 `QPLL1FBCLKLOST` 在本次窗口中保持为 1。
这两个 loss 指示需要结合 GTHE3_COMMON 的状态语义进一步确认，但不能改变
`QPLL1LOCK` 从 1 变 0 且未恢复这一直接结论。

该结果只针对当前 standalone PHY 诊断 bit，不等同于完整 PCIe endpoint 的
LTSSM/Gen3 链路训练结果。
