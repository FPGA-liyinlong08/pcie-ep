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

### 4.1 XDMA golden RP 实跑对照（2026-08-28）

本轮已直接运行用户指定的 golden 工程，而不是只引用 XDMA demo 的历史日志：

```text
工程：/home/wx/Documents/XDMA/xdma_dec_250922/vcs
入口：board_simv -ucli -licqueue -l /tmp/xdma_dec_250922_golden_rerun.log -do simulate.do
license：SNPSLMD_LICENSE_FILE=27000@wx-linux
         LM_LICENSE_FILE=27000@wx-linux:/home/questasim/mentor.dat
```

golden 结果为 PASS：`Check Max Link Speed = 8.0GT/s`、`Check Negotiated Link
Width = 8`、`SYSTEM CHECK PASSED`，并且 H2C/C2H data match。golden FSDB
`/home/wx/Documents/XDMA/xdma_dec_250922/vcs/tb_xdma.fsdb` 的 EP PIPE 记录还给出
了可复现的 Gen3 contract：`pipe_tx0_rate=10`，每个 32-bit block 仅首拍同时置
`TXSTART_BLOCK=1` 和 `TXSYNC_HEADER=01`，后三拍 header 为 `00`，
`pipe_tx0_char_is_k=00`。

当前 K15 在同一 RP、同一 license 和同一串行连接下已逐拍匹配 golden 的前 24 个
EP Gen3 PIPE words（包括 EIEOS、SKP、TS1 和 block header）。此前固定 header 的
错误已删除，Verilator 定向测试也已改为检查 golden 的首拍/续拍语义。

但真实 K15 run 仍停在 RP Phase 1：EP 侧 TX valid、GT TX ready、Gen3 rate 和
Phystatus 均成立；RP 侧 `GT_RXCDRLOCK=1`、`GT_RXRESETDONE=1`、
`GT_PCIERATEGEN3=1`，但在 RP 进入 `0x28/0x29` 后连续 64 个 PIPE 时钟仍为
`pipe_rx_data_valid=0`，没有 RX block 或可解码 TS。因此这不是“没有运行 golden
RP”的结论，而是已经完成 golden 对照后，定位出的 EP→RP Gen3 PCS 接收边界问题。

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

## 6. 实板 reboot 对照结果（2026-08-28）

本轮使用实验 bit
`fpga/kcu105/build_k15_recovery_speed_hw0e_popcount_opt/impl/k14_recovery_speed_ila.bit`
及对应 LTX，在 KCU105 上明确重新下载、ARM ILA，然后对远端主机执行 reboot。捕获文件为：

`fpga/kcu105/build_k15_recovery_speed_hw0e_popcount_opt/capture_reboot/20260828_144429_k14_recovery_speed.csv`

K14 速率/QPLL ILA 证明了以下路径：

```text
Gen1 -> Recovery.Speed -> Gen3 PHY rate -> QPLL lock -> PhyStatus
```

对应记录为 `qpll_rise_us=87.728`、`phystatus_us=122.000`、
`final_rate=2`、`qpll_lock=1`、`rategen3=1`、`usergen3rdy=1`。

同一捕获中的 EP LTSSM 状态值为：

```text
0x12 (Recovery.Speed)
0x0b (Recovery.RcvrLock)
0x28 (Equalization Phase 0)
0x29 (Equalization Phase 1)
0x2a (Equalization Phase 2)
```

没有采到 `0x2b`（Phase 3），也没有采到 EP `0x0d`（Recovery.Idle）。注意
ILA 中 `k14_speed_state=ST_RECOVERY_IDLE` 是 K14 速率控制器内部状态，不能等同于
PCIe LTSSM 的 `Recovery.Idle`。

因此实板当前进度是 **K15-C 已进入 Phase 2，未完成 Phase 3；尚未达到 Gen3 L0**。
本轮 ILA 未包含 EIEOS、SKP、`TXSTART_BLOCK`、`TXSYNC_HEADER` 和 RX block-valid
原始探针，不能据此宣称 128b/130b block 对齐已经完成。

reboot 后 Linux 未发现 `01:00.0` Endpoint，不能记录为 `LnkSta=8GT/s x1`，也尚未
完成实板 Gen1 fallback 后重新枚举的验证。远端同时出现 Root Port corrected
physical-layer `RxErr`，该现象与 VCS 中 Phase-1 EQ response 未被 RP 消费后回退的
边界相符，但仍需增加原始 Gen3 RX block/TS 探针确认。

该实验 bit 的实现时序为 `WNS=-0.129 ns`、`WHS=+0.004 ns`、DRC 0，且构建使用
`K14_ALLOW_TIMING_VIOLATION=1`，仅用于诊断，不能作为 timing-clean 生产 bit。

## 7. 本轮时序优化记录

为缩短 Gen3 TX 数据路径，本轮保留功能等价性并进行了两项组合逻辑重构：

- `pcie_gen3_scrambler32.sv`：将原先按 bit 串行推进的 32-bit LFSR 反馈循环改为
  4 个 byte stage 的 XOR 矩阵；多项式和输出序列保持不变。
- `pcie_gen3_os_tx.sv`：将 DC balance 的 32-bit 逐 bit 计数改为 4 个 byte
  popcount tree，并保持同一饱和边界和符号计算。

曾尝试加入 `balance_data_q` 的 look-ahead 输出寄存器，但实现后形成约 42 级
`balance_data_q -> GT TXDATA` 路径，WNS 恶化至约 `-8.05 ns`，因此已撤销，最终
版本不包含该寄存器路径。

优化前后实现结果如下：

| 项目 | 优化前 | 当前 bit |
| --- | ---: | ---: |
| WNS | `-2.063 ns` | `-0.129 ns` |
| 关键路径逻辑级数 | 17 | 9 |
| 关键路径数据延迟 | 5.940 ns | 3.688 ns |
| WHS | — | `+0.004 ns` |
| DRC errors | — | 0 |

当前剩余最差路径已从 Gen3 scrambler/DC-balance 路径转移到普通 Gen1
framer→scrambler→OS TX→GT TXDATA 路径；因此优化明显改善了逻辑级数和 WNS，但
`-0.129 ns` 仍未达到 timing-clean，后续生产 bit 仍需继续收敛时序。

## 8. fallback 后 Gen1 重训现象（2026-08-28）

为验证“Phase 2 后没有回退”是否只是 ILA 观察窗口问题，先重新下载同一实验 bit
清除 sticky 状态，再将 ILA 触发条件改为
`k14_timeout_fallback_w == 1`，随后执行一次远端 reboot。新鲜捕获为：

`fpga/kcu105/build_k15_recovery_speed_hw0e_popcount_opt/capture_fallback_fresh/20260828_152630_k14_recovery_speed.csv`

捕获结果：

```text
k14_timeout_fallback_w = 1
k14_phy_rate_w         = 0       // PHY 已回到 Gen1
k14_speed_state_w      = ST_L0  // K14 速率控制器内部状态
k14_ltssm_state_w      = 0x03   // POLLING_CONFIG
k14_gen1_fallback_success_w = 0 // 脉冲未落在捕获窗口
```

因此确认 fallback 已经发生；但 `k14_speed_state=ST_L0` 不能等同于 PCIe LTSSM
L0。EP 在捕获末端实际停留在 `POLLING_CONFIG(0x03)`，没有完成 Gen1
`CFG_* -> L0`，所以 Linux 仍未枚举 `01:00.0`。

旧的 `capture_reboot/20260828_144429...csv` 只在 Gen3 rate 成功事件处触发，8192
采样约对应 32.8 us，而硬件 speed timeout 约为 4 ms，故旧捕获没有看到 fallback
并不能证明 fallback 未执行。第一次使用 `arm-only` 的复核还因 sticky fallback
信号未清除而立即触发，已废弃；本节只采用重新下载后得到的新鲜捕获。

本轮 reboot 后 Root Port 状态为：

```text
LnkSta: 2.5GT/s x1, Train+, DLActive+
LnkSta2: EqualizationComplete-, EqualizationPhase1/2/3-
CESta: RxErr-, BadTLP-, BadDLLP-, Rollover-, Timeout-
```

Endpoint 仍不在总线设备列表中。远端 `dmesg` 从 `15:25:53` 到 `15:28:04` 共统计
111 次 `Corrected, type=Physical Layer, [0] RxErr`，说明 fallback 后 RP 仍持续看到
接收层错误。当前未观察到 BadTLP、BadDLLP 或 Rollover。

本次结果将未闭合边界从“Gen3 fallback 是否触发”进一步收窄为：**fallback 已触发，
但 Gen1 Polling.Config 的 TS/接收或后续配置训练没有推进到 Gen1 L0，且伴随持续
Physical Layer RxErr**。下一轮应增加 fallback 后的 Gen1 TS1/TS2、`RxValid`、
`os_ts1_valid/os_ts2_valid` 和 LTSSM transition ILA 探针。

## 9. `aca2308` 后的 VCS 优先复核与 XDMA demo 对照

本轮首先复跑当前 HEAD 的严格 `make k15-vcs`；其 Root Port 来源明确为
`/home/wx/Documents/XDMA/xdma_dec_250922/imports`，即
`pcie3_uscale_rp_core_top.v`、`pcie3_uscale_rp_top.v` 和
`xilinx_pcie_uscale_rp.v` 三个文件。该工程的通过日志为其 `vcs/simulate.log`。
XDMA example 能完成 8.0 GT/s 测试，因此不再把
“RP 不支持或不会请求 Gen3”作为主假设。官方 example 使用
`PL_SIM_FAST_LINK_TRAINING=TRUE` 和 `PL_EQ_BYPASS_PHASE23=TRUE`，只能证明 RP、串行
通路及 Phase 0/1 快速路径可工作，不能用它替代本项目 Phase 2/3 的严格 Gate。

对比发现 `aca2308` 的 TX 时序优化引入了一个功能回归：
`pcie_gen3_os_tx.sv` 的 byte popcount tree 和 `dc_balance` 寄存器仍在，但所有
`dc_balance <= update_dc_balance(...)` 状态更新被误删。其结果是 TS symbols 14/15
不再根据累计 DC balance 执行 substitution；soft EP 曾发出 `4d89054e` 等错误尾字，
而 XDMA golden 使用 `08xx....`/互补形式的 substitution。

现已在 mode 切换、普通 TS word 和 TS block 尾部恢复 running-DC 更新，并在
`k15_eq_idle_test.cpp` 增加首个 TS 尾字 substitution 断言。修复后的严格 VCS
可见 `K15_EP_TX_PIPE ... data=0820054e`，定向及静态门禁通过：

```text
K15_EQ_PHASES_DIRECTED_PASS
K15_GEN3_IDLE_STREAM_PASS blocks=19
K15_EQ_EIEOS_SKP_TS_PASS
PHY_COMMAND_CTRL_EQUIVALENCE_PASS
K15_PHY_EQ_SEMANTIC_PASS
PHY_COMMAND_OWNERSHIP_PASS
```

这项回归会直接影响真实 partner 对 soft EP Gen3 TS 的接受，因而与实板进入
Phase 2 后不前进高度相关。下一块实板 bit 必须包含此修复并重新跑实现时序；不能
用删除协议状态更新的方式换取 WNS。当前尚未生成新 bit，故不能宣称实板问题已关闭。

K15 testbench 现在在同一个 golden RP 实例上增加了有界的
`K15_RP_TX_PIPE` 记录，与 `K15_EP_TX_PIPE` 使用完全相同的 PIPE/GT 字段；在 FlexNet
许可证恢复后已完成严格 VCS 运行，监视器输出可复现下面的 RX 边界。

严格 VCS 在修复后仍停于较早的独立边界：soft EP 已收到并解码 RP Phase 0/1 TS，
也在 32-bit PIPE TX 上发出修正后的 EIEOS/SKP/TS，但集成 RP 的接收侧从未产生第一个
Gen3 `RXVALID`：

```text
K15_VCS_BLOCKED_RP_EQ_RESPONSE_NOT_CONSUMED
  rp_rxvalid_seen=0 rp_rxvalid_beats=0 rp_decoded_ts=0
```

新增的有界串行边沿记录测得最小相邻翻转间隔为 `125 ps`，证明 standalone PHY
实际按 8.0 GT/s 串行化，而不是 4.0 GT/s 的 PROGDIV/时钟配置错误。因此当前 VCS
第一未闭合点精确为：**soft EP standalone PHY 串行输出到 integrated XDMA RP PCS
的首个 Gen3 block acquisition**，发生在 RP 消费 EQ response 和进入真实 Phase 2
之前。K13 的 local/external loopback 日志也曾出现同类 Gen3 `RXVALID=0`，旧问题并未
形成可复用的闭环修复。

保持严格 Gate：不 force `RXVALID`，不注入 TS，不旁路 Phase 2/3，不以 timeout
自推进。VCS 后续只继续对照 golden GT/PIPE contract、Sync Header 和 PCS reset/block
lock 时序；RTL EQ Phase 2 的实板复测则以包含 running-DC 修复且 timing-clean 的新 bit
为准，两条证据链分开记录。

## 10. Phase 2 自有 RTL 修正（2026-08-28）

继续检查自研 EQ 控制器后，确认 Phase 2 还有一个独立的协议实现缺陷：
`pcie_gen3_equalization_ctrl.sv` 原先在 Phase 2 入口立即发起 RX Adapt，且把
`EQ_DATA[3:0]` 当作 partner preset。Gen3 TS 的 preset 位于最后 EQ 字节的高半字节
`EQ_DATA[23:20]`；低字节属于 FS/LF。该错误在当前 `8a0c28` 样例上数值恰好仍为 8，
因此容易被现有测试掩盖，但对其它 preset 会发出错误的 PHY 命令。

现已改为：先收到至少一个合法 partner TS，再锁存 `EQ_DATA[23:20]` 并启动 RX Adapt；
若字段非法则使用安全 preset 5。定向测试新增了“Phase 2 先等待 TS、再请求 preset 8”
断言，`make k15-static` 全部通过。该修正尚未生成新的上板 bit；随后严格 VCS 已复跑，
但仍停在 RP `RXVALID=0` 的 Gen3 block acquisition 边界，因此不能把它标记为最终
Gate PASS。

## 11. 本地 XDMA Gen3 x1 demo VCS 对照（2026-08-28）

用户指定的 `fpga/kcu105/xdma_x1_demo/build/example/xdma_x1_ex/` 已建立独立
VCS 入口 `sim/vcs/run_xdma_x1_demo.sh`。该入口不复用 K11-B soft EP，而是编译
demo 自己的 `imports/board.v`、RP source、`xdma_x1` 生成的 PCIe/GT 仿真 HDL
和 BRAM model。

在可访问 `27000@wx-linux` 的环境实际运行结果：

```text
Check Max Link Speed = 8.0GT/s - PASSED
Check Negotiated Link Width = 1 - PASSED
SYSTEM CHECK PASSED
*** H2C Transfer Data MATCHES ***
*** C2H Transfer Data MATCHES ***
XDMA_X1_DEMO_VCS_PASS
```

这证明本地 XDMA x1 endpoint + 同版 RP + GT 仿真模型能够完成 Gen3 x1 和 DMA，
因此不能继续把问题归咎于 RP “不支持/不请求 Gen3”。

对照生成参数后，已确认一个确定的 standalone PHY contract 差异：

| contract 字段 | standalone `pcie_phy_x1_gen3` | 本地 XDMA x1 PCIe PHY |
|---|---:|---:|
| `PHY_MAX_SPEED` | 3 | 3 |
| lane / refclk / PLL | x1 / 100 MHz / QPLL1 | x1 / 100 MHz / QPLL1（内部 `PLL_TYPE=2`） |
| `PHY_USERCLK_FREQ` | 2（125 MHz） | 3（250 MHz，PCIe core） |
| `PHY_CORECLK_FREQ` | 1（250 MHz） | 2（500 MHz） |
| GT `C_PCIE_CORECLK_FREQ` | 250 | 500 |
| GT `C_TX/RX_OUTCLK_FREQUENCY` | 400 | 400 |
| `C_TX/RX_INT/USER_DATA_WIDTH` | 20 / 16 | 20 / 16 |
| EQ implementation | standalone PHY ports + our LTSSM/EQ FSM | XDMA core integrated EQ (`PL_EQ_BYPASS_PHASE23=FALSE`) |
| simulation silicon tag | `Production` | XDMA generated example `Pre-Production` |

证据位置分别是 standalone XCI/生成脚本的 `phy_userclk_freq=125_MHz`、
`phy_coreclk_freq=250_MHz`，以及 demo `xdma_x1.sv`/PCIe core 的
`CORE_CLK_FREQ(2)`、`USER_CLK_FREQ(3)` 和 GT model 的
`C_PCIE_CORECLK_FREQ(500)`。所以“contract 不一致”不是抽象判断，至少
`core/user clock enum` 和由此派生的 PCS clocking 已经可定位到具体字段。

另外，`PLL_TYPE` 的文字/整数编码不同（standalone 的 `QPLL1` 对应 XDMA
内部的 `PLL_TYPE=2`），语义上是同一个 QPLL1，并不是当前首要差异。EQ 也不是
同一条实现路径：demo 由 XDMA core 内部 LTSSM/PHY EQ 完成，而本工程由
standalone PHY 端口加自研 EQ FSM 完成。

但这仍是**待 A/B 证明的根因候选**，不是把上板失败简单定性为“只改频率就能修好”。
当前 standalone soft EP 在 golden RP 下的第一失败点仍是 RP Gen3 RX 没有
`RXVALID/block lock`；下一步应生成一份仅把 standalone PHY 改成 XDMA 的可逆
`PHY_USERCLK_FREQ=3 / PHY_CORECLK_FREQ=2` A/B IP（不手改生成 HDL），重跑同一
`run_k11b_serial.sh`，然后比较 RP RXVALID、TS 消费、Phase 2 和上板结果。

同一许可证环境随后重跑当前 HEAD 的 K15 golden-RP gate，结果仍为：

```text
K15_INITIAL_GEN3_CAPABILITY_SEEN rate_id=0e
K14_RP_RAW_GEN3_TS rate_id=8e
K14_PARTNER_REQUEST_ACCEPTED
K14_GEN3_PHYSTATUS_SEEN qpll=1
K15_VCS_BLOCKED_RP_EQ_RESPONSE_NOT_CONSUMED
  rp_rxvalid_seen=0 rp_rxvalid_beats=0 rp_decoded_ts=0
K15_UNEXPECTED_SPEED_TIMEOUT_FALLBACK
```

因此当前证据链是闭合的：本地 XDMA x1 demo 在相同机器、相同 RP/GT 仿真库上
通过，而自研 standalone PHY 仍在 RP Gen3 RX 首个 block acquisition 前失败；
这确认缺陷仍在本工程 endpoint/standalone PHY contract 或其 PIPE/PCS 时序，不能
归因于 RP 不会自动请求。`PHY_CORECLK_FREQ`/`PHY_USERCLK_FREQ` A/B 仍需以
重新生成 IP 后的可重复结果判断是否为唯一根因。
