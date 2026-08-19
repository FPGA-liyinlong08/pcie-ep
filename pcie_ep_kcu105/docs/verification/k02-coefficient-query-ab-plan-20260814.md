# K02 Coefficient Query A/B 验证

日期：2026-08-14

> **DEPRECATED 2026-08-19**：本计划针对 K02 自有 `dynamic_rate_*` FSM 的 A/B 验证。
> 2026-08-19 K02 Gen1→Gen3 闭环验证显示 K02 FSM 控制器是根因（commit `82db3cd`），
> 改用 Golden `phy_ctrl.v` + `phy_bringup_seq` 路径修复（commit `7d39d60`）。
> 2026-08-19 后续 commit 已**完整删除 `dynamic_rate_*` FSM 与 A/B 路径**（见
> `fpga/kcu105/k02_phyctrl_build_result_20260819.md` §7），本 A/B 计划随路径删除作废。
> K02 PHY 的 Gen1→Gen3 切换现在由 Golden 控制器独立完成，无需 A/B。

## 目的

验证 Gen1→Gen3 动态切速前，是否需要在 TX Preset Apply 完成后额外执行一次
`phy_txeq_ctrl=2'b11` Coefficient Query。

该实验只针对 Standalone PCIe PHY，不包含 LTSSM、TS1/TS2、128b/130b、DLL、TLP
和完整 PCIe Equalization。

## 两个版本

### A：Preset-only 基线

```text
TX Electrical Idle
    -> phy_txeq_ctrl=01, preset=4
    -> phy_txeq_done
    -> phy_txeq_ctrl=00
    -> phy_rate=Gen3
```

### B：Preset + Coefficient Query

```text
TX Electrical Idle
    -> phy_txeq_ctrl=01, preset=4
    -> phy_txeq_done
    -> phy_txeq_ctrl=00，保持一个 pclk
    -> phy_txeq_ctrl=11
    -> phy_txeq_done，记录 phy_txeq_new_coeff
    -> phy_txeq_ctrl=00，保持一个 pclk
    -> phy_rate=Gen3
```

默认构建仍为 A 版本。B 版本由 `K02_DYNAMIC_COEFF_QUERY=1` 开启，产物放在：

```text
fpga/kcu105/build_k02_dynamic_query/
```

## 仿真

A 版本：

```bash
K02_VCS_DYNAMIC_TXEQ=1 K02_VCS_QUERY=0 K02_SKIP_IP_GENERATION=1 ./sim/vcs/run_k02.sh
```

B 版本：

```bash
K02_VCS_DYNAMIC_TXEQ=1 K02_VCS_QUERY=1 K02_SKIP_IP_GENERATION=1 ./sim/vcs/run_k02.sh
```

也可使用：

```bash
make k02-query-vcs
```

## 硬件构建

```bash
make k02-query-vivado
```

硬件 ILA 操作：

```bash
K02_DYNAMIC_GEN1_TO_GEN3=1 K02_DYNAMIC_COEFF_QUERY=1 \
  /home/Xilinx/Vivado/2021.2/bin/vivado -mode batch \
  -source fpga/kcu105/run_k02_phy_ila_hw.tcl -nojournal \
  -tclargs 127.0.0.1:3121 program-arm

K02_DYNAMIC_GEN1_TO_GEN3=1 K02_DYNAMIC_COEFF_QUERY=1 \
  /home/Xilinx/Vivado/2021.2/bin/vivado -mode batch \
  -source fpga/kcu105/run_k02_phy_ila_hw.tcl -nojournal \
  -tclargs 127.0.0.1:3121 capture-wait
```

本机实际运行的 `hw_server` 监听 `3121`；如果按文档启动独立实例，也可以使用
`3122`，但烧写和抓取命令中的端口必须与实际监听端口一致。

## ILA 重点信号

```text
phy_txeq_ctrl
phy_txeq_done
phy_txeq_new_coeff
phy_rate
QPLL1RESET
QPLL1LOCK
QPLL1PD
QPLL1LOCKEN
QPLL1REFCLKSEL
QPLL1REFCLKLOST
QPLL1FBCLKLOST
PCIERATEQPLLRESET[1:0]
PCIERATEQPLLPD[1:0]
TXPLLCLKSEL
RXPLLCLKSEL
TXSYSCLKSEL
RXSYSCLKSEL
PCIERATEIDLE
PCIERATEGEN3
PCIEUSERRATESTART
PCIEUSERGEN3RDY
TXRESETDONE
RXRESETDONE
PhyStatus
```

## 判定

```text
B 版本 QPLL1LOCK 恢复
    -> Query/命令间隔是重要差异，继续把该序列带入 K13

B 版本仍然失败
    -> Query 不是主要原因
    -> 重点分析 QPLL reset release、PLL/SYSCLKSEL、GT reset helper 和动态 DRP
```

## 当前限制

真实 VCS 仿真使用本地 `27000@wx-linux` FlexNet 服务。`sim/vcs/run_k02.sh` 会先设置
`SNPSLMD_LICENSE_FILE/LM_LICENSE_FILE`，并使用 `lmutil lmstat` 做 license preflight。
VCS behavioral model 通过只能证明接口握手，不等价于硬件 QPLL 模拟重新锁定；最终
结论必须以上板 ILA 为准。

## 实测结果（2026-08-14）

### VCS Query B：PASS

使用本地 license 方法执行：

```bash
VCS_LICENSE_TIMEOUT=300 K02_VCS_DYNAMIC_TXEQ=1 K02_VCS_QUERY=1 \
  K02_SKIP_IP_GENERATION=1 ./sim/vcs/run_k02.sh
```

关键输出：

```text
K02_VCS_TXEQ_DONE op=PresetApply
K02_VCS_TXEQ_DONE op=CoefficientQuery
K02_VCS_TXEQ_STATUS op=Gen1ToGen3 rate=10
K02_VCS_DYNAMIC_TXEQ_PASS query=1
K02_VCS_REAL_IP_PASS mode=k02_dynamic_txeq_tb
```

这证明 Query B 在 AMD/Xilinx 真实 PHY、GT Wizard 和 SecureIP behavioral model
中能够完成，但不代表硬件 QPLL 必然重新锁定。

### KCU105 Query B：仍然 FAIL

下载产物：

```text
fpga/kcu105/build_k02_dynamic_query/k02_pcie_phy_bringup_dynamic_query_ila.bit
fpga/kcu105/build_k02_dynamic_query/k02_pcie_phy_bringup_dynamic_query_ila.ltx
```

实现时序为 `WNS=+0.458 ns`。原始 ILA 文件：

```text
fpga/kcu105/build_k02_dynamic_query/capture/20260814_235314_k02_phy.csv
fpga/kcu105/build_k02_dynamic_query/capture/20260814_235314_k02_phy.ila
```

波形关键事件（ILA sample）：

```text
sample 9   Preset Apply done=1
sample 11  Coefficient Query ctrl=11，query_active=1
sample 12  Coefficient Query ctrl=00，query_active=0
sample 13  phy_rate=Gen3
sample 23  QPLL1LOCK: 1->0，QPLL1RESET: 0->1
sample 27  QPLL1RESET: 1->0，但 QPLL1LOCK 仍为0
sample 34  PCIERATEGEN3=1
```

整个采集窗口内 `dynamic_rate_pass=0`、`dynamic_rate_fail=0`、`PhyStatus=0`，
`QPLL1PD=0` 且 `PCIERATEQPLLPD=0`。因此加入 Coefficient Query 后，硬件失败签名
没有改变；当前不能把 QPLL1 失锁归因于缺少 Query。

### 当前结论与下一步

`Query B VCS PASS + Query B Hardware FAIL` 将问题进一步收缩到 behavioral model
未覆盖的硬件动态 PLL/时钟切换路径。下一步优先分析 ILA 中的
`QPLL1LOCKEN/LOCKDETCLK/REFCLKLOST/FBCLKLOST/REFCLKSEL` 和四个
`TX/RX PLLCLKSEL/SYSCLKSEL` 的有效编码及切换时序，并与官方 PHY Demo 的成功
动态切速波形做逐事件对齐；暂不继续在 TXEQ Query 顺序上反复试错。
