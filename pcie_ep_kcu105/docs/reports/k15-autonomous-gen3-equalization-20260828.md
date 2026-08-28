# K15 Autonomous Gen3 Recovery + Equalization 实现报告

日期：2026-08-28  
基线：`5095e7c`  
状态：**RTL与静态/定向闭环已实现；Full XDMA RP双epoch Gate未通过，K15不得冻结**

## 1. 已实现的生产路径

生产Endpoint默认在初始Gen1 TS1/TS2中发送`Rate ID=8'h0e`，Speed Change保持0。
当前速率仍由唯一PHY命令owner提交，只有收到真实partner `8e`请求并进入
Recovery.Speed后才从Gen1切到Gen3。

K14 Golden rate-change顺序被保留。预先尝试加入Gen3 TX preset后，因其改变已签署
的K14 envelope且对Full VCS没有改善，最终恢复为不在Recovery.Speed驱动TXEQ，由
后续Equalization semantic request负责。新增的semantic EQ接口把协议决策和raw
PHY引脚分开：

```text
LTSSM / upstream EQ protocol FSM
  -> semantic TX preset / coefficient / query / RX adapt request
  -> pcie_phy_command_ctrl
  -> sole raw owner
  -> phy_txeq_* / phy_rxeq_*
```

`pcie_ltssm_mac_gen1`现在显式暴露`Recovery.Equalization Phase 0/1/2/3`，状态值为
`28/29/2a/2b`。新的`pcie_gen3_equalization_ctrl`按Endpoint/Upstream角色在Phase 2
执行RX Adapt、在Phase 3执行TX Adapt，并保持命令直到真实done或timeout。Phase 1
响应不会按本端发送计数自行前进，而是持续发送`21/000c28`，直到downstream port
离开其`01/8a0c28`请求。

Recovery Gen3训练发送顺序为EIEOS后直接发送TS；SDS只由新的Gen3 idle transmitter
在Recovery.Idle开始Data Stream时发送。Gen3 L0保持DLL/TLP离线并持续发送逻辑Idle，
因此没有提前混入K16数据路径。

## 2. 本轮修改清单

- `pcie_ltssm_mac_gen1.sv`：初始TS capability固定为`0e`；接入partner pending、
  Recovery.Speed后的Gen3 RX路径，并显式增加`28/29/2a/2b`四个Equalization状态；
  保留K14唯一rate-change owner和Gen1 fallback。
- `pcie_gen3_equalization_ctrl.sv`：新增Upstream/Endpoint角色FSM。Phase 0/1使用
  TS响应和partner-exit门禁，Phase 2发RX Adapt，Phase 3发TX preset/query；所有
  operation均等待真实done或timeout。
- `pcie_phy_command_ctrl.sv`：扩展semantic TX preset/coefficient/query、RX
  adapt/bypass接口，保持raw PHY pin唯一所有权；移除未验证的pre-rate TXEQ步骤，
  恢复K14 Golden rate envelope。
- `pcie_gen3_os_tx.sv` / `pcie_gen3_os_rx.sv`：修正Gen3 sync header在四个PHY32
  beat上的保持、TS DC-balance字段和EIEOS→SKP→TS训练边界；RX增加SKP、SDS、Data
  Block idle语义和`RxDataValid` bubble容忍。
- `pcie_gen3_idle_tx.sv`：新增真实SDS（`E1` + 15个`55`），并把训练端LFSR状态
  连续传给Recovery.Idle，避免Data Stream重新从seed开始。
- endpoint top / source list / Makefile：接通semantic EQ、Gen3 idle和定向/static
  门禁；Gen3 DLL/TLP仍明确关闭，留给K16。
- `sim/vcs/k11b_serial_board.sv`：增加K15 capability、RP request、PhyStatus、
  EQ phase、RP PIPE RX和GT reset/sync/PHY envelope取证；严格失败条件保留。
- `sim/verilator/k15/*`：增加EQ phase、EIEOS/SKP/TS、SDS、idle LFSR loopback测试。

## 3. 已做的尝试与结论

| 尝试 | 结果 |
| --- | --- |
| 初始TS由`02`改为`0e`，允许RP autonomous Recovery | RP确实发出`8e`并被接受，说明capability语义生效 |
| 恢复K14 Golden rate-change并接入真实PhyStatus/QPLL门禁 | Gen3 rate和PhyStatus完成，非卡点 |
| pre-rate TXEQ preset / clear beat | Full VCS无改善；移除以保持K14已签署envelope |
| 修正EIEOS、SKP、TS scrambling、DC balance、Sync Header | EP PIPE输出逐字正确；RP仍无RX block-valid |
| Phase 0采用Upstream正确响应`20/802800`，Phase 1保持`21/000c28`直到partner退出 | EP进入Phase 0/1，但RP未消费Phase 1 |
| GT TX reset、Gen3 ready、TX sync、QPLL和channel参数A/B | 状态正常；参数替换未改变失败 |
| 强制/诊断原始EIEOS与固定PHY32 pattern | RP仍`rxvalid=0`，排除单一TS字段错误；诊断旁路未保留 |
| 对照官方XDMA demo及K13历史报告 | 官方demo可过Gen3；K13也有同类`RXVALID=0`，并未闭环自研EP到集成RP |

结论：当前高概率阻塞在自研standalone PHY到XDMA集成RP之间的Gen3 PCS/block
alignment互操作，而不是RP缺少Gen3能力。该结论仍需新的PHY/RP模型或实板ILA证据
最终确认。

## 4. 验证结果

| 验证 | 结果 | 关键证据 |
| --- | --- | --- |
| `make k15-static` | PASS | EQ phases、idle stream、EIEOS-to-TS、PHY EQ semantic、K14 Recovery.Speed、raw owner、top lint |
| `make k03-verilator` | PASS | 13/13 LTSSM场景、100次training、2000 packets |
| `make k14-direct-vcs` | PASS | 生产PHY模型完成Gen3 rate、QPLL、PhyStatus及fallback回归 |
| Vivado 2021.2 LTSSM OOC | PASS | 0 errors、0 critical warnings、WNS `+4.537 ns` |
| `make k15-vcs` | **FAIL** | 最新版本可编译并运行；首个epoch停在双方Phase 1，未到Phase 2/3、Recovery.Idle或Gen3 L0 |

Full VCS使用XDMA v4.1 Root Port、真实串行生产PHY、`GEN3_AUTO_RETRAIN_CYCLES=0`，
没有force、人工TS、软件Retrain或配置写。它已经证明K15-A、K15-B和K15-C的Phase 0
入口真实发生：

```text
K15_INITIAL_GEN3_CAPABILITY_SEEN epoch=0 rate_id=0e
K14_RP_RAW_GEN3_TS epoch=0 rate_id=8e
K14_PARTNER_REQUEST_ACCEPTED epoch=0
K14_GEN3_PHY_RATE_SEEN epoch=0
K14_GEN3_PHYSTATUS_SEEN epoch=0 qpll=1
K15_EQ_PHASE0_DONE epoch=0
```

Endpoint真实解码到Root Port Phase-1 TS：

```text
ctl=01 data=8a0c28 rp_state=29
```

随后Endpoint进入状态`29`并持续发送Phase-1响应：

```text
txctl=21 txdata=000c28
```

但该响应没有在Root Port PIPE RX边界形成有效block或可解码TS：

```text
K15_VCS_BLOCKED_RP_EQ_RESPONSE_NOT_CONSUMED
  epoch=0 ep_txvalid=1 ep_txstart=1
  rp_rxvalid_seen=0 rp_rxvalid_beats=0 rp_decoded_ts=0
  rp_state=c ep_state=29 ep_tx_eq_control=21 ep_tx_eq_data=000c28
```

Root Port随后离开Phase 1并回退，strict gate以
`K15_UNEXPECTED_SPEED_TIMEOUT_FALLBACK`失败。日志位于
`sim/vcs/build/k15_gen3_simulate.log`（构建产物，不纳入源码提交）。

本次提交前最新定向回归还确认了修正后的SDS/Idle路径：

```text
K15_EQ_PHASES_DIRECTED_PASS
K15_GEN3_IDLE_STREAM_PASS blocks=19
K15_EQ_EIEOS_SKP_TS_PASS
```

Full VCS最新运行的末尾仍为：

```text
K15_VCS_BLOCKED_RP_EQ_RESPONSE_NOT_CONSUMED
  rp_rxvalid_seen=0 rp_rxvalid_beats=0 rp_decoded_ts=0
K15_UNEXPECTED_SPEED_TIMEOUT_FALLBACK
```

## 5. 判定与剩余边界

当前证据不能宣称Gen3 Equalization或Gen3 L0已经在Full XDMA RP中闭环，也不能仅凭
Endpoint PIPE TX valid断言串行输出一定被partner正确接收。第一未闭合边界是
Endpoint Gen3 TX到Root Port Gen3 PIPE RX之间的GT/PCS仿真通路；仓库既有K13冷启动、
自环和RP 4.4诊断也曾在同一类边界观察到Gen3 `RXVALID=0`，说明旧串行安全模型是
高概率限制，但这仍是诊断推断，不是对RTL正确性的证明。

因此保留严格失败，不增加timeout，不让EQ FSM在未收到partner phase变化时自行前进，
也不增加testbench旁路。关闭K15需要可产生Gen3 RX block-valid的更新PHY/RP仿真环境，
或在后续获准的实板ILA验证中取得等价的双epochPhase 0/1/2/3与Gen3 L0证据。

K16仍保持独立：在K15 Gate关闭前，不接入Gen3 DLLP/TLP和128b/130b正常L0数据路径。
