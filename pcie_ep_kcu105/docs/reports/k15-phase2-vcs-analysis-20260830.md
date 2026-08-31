# K15 SVT/Xilinx RP Phase2 仿真分析（2026-08-30）

## 目标与当前结论

本轮验收目标是让 Synopsys SVT 和 Xilinx RP 都真实接收 EP 的 Gen3
训练序列并到达 Equalization Phase2（`0x2a`），暂不要求 Phase2 RX
Adapt 完成。

当前仍未达到端到端验收：

- SVT 已锁定 8.0 GT/s 串行时钟并进入 Equalization Phase1，但先报告
  Gen3 framing/SKP 错误，最终 Phase1 timeout。
- Xilinx RP 自身进入 `0x28/0x29`，EP 也能消费 RP 的 Gen3 TS 并进入
  `0x29`；但 RP 的 lane 0 始终 `RXDATA_VALID=0`，没有消费 EP 响应。
- Phase2 TS1 EC/preset 修复是必要修复，但两套端到端环境目前都还没有
  走到可以验证这部分协议语义的位置。

## 暂停提交快照

按 2026-08-30 的暂停要求，本轮不再继续扩大 A/B，先固化以下结论：

1. 现成的 `pcie3_ultrascale_0_ex/vcs/run_vcs.sh` 已恢复为可移植 runner，
   Xilinx RP + Xilinx EP baseline 完整通过：8.0 GT/s、协商 x1、配置空间及
   PIO write/readback 均 PASS，最终时间为 `226115504 ps`。
2. `pcie_phy_0_ex` standalone 只能给出 EIEOS/GT framing golden；真正的
   `EIEOS -> SKP -> TS` 协议 golden 来自通过的
   `pcie3_ultrascale_0_ex` 集成 Xilinx EP。
3. 当前 soft EP 的首个 EIEOS、SKP 和前四个 Phase0 TS 已在 PIPE 和 GT
   输入端与该 Xilinx EP 逐拍对齐；Xilinx RP 仍然不产生
   `RXDATA_VALID`，所以当前剩余首错已位于协议 TS 解析之前。
4. 本轮发现并修复了一个独立、确定的 running-DC 计数错误；修复后虽未
   改变 Xilinx RP 的 `RXDATA_VALID=0`，但必须保留，不能退回旧序列。

严格 Phase2 gate 的暂停结果仍为 FAIL：

```text
K15_XILINX_RP_PHASE2_FAIL
  ep_state=0x29 rp_state=0x0c
  rp_rxvalid=0 rp_rxvalid_beats=0 rp_decoded_ts=0
```

## 已完成实现

- Gen1 ordered-set TX 增加完整 EIOS
  `{COM, K28.3, K28.3, K28.3}` 和完成脉冲。
- Recovery.Speed 等待当前 Gen1 TS 完整结束，再发完整 EIOS；完成后才
  允许 command controller 拉高 Electrical Idle 并改变 PHY rate。
- Gen3 TS mode、OS/SDS/Data source 切换改为四拍 block boundary 锁存。
- Gen3 启动序列改为完整 block 边界上的 `EIEOS -> SKP -> TS`。
- 增加最迟 350 blocks 的周期 SKP 调度。
- 默认 `TXSTART_BLOCK/TXSYNC_HEADER` 保持首拍有效；保留 held-header
  仅用于 A/B。
- EQ 修复包括 Phase2 `EC=10`、preset 从 Symbol 6 解析、按 EC 过滤
  Phase1/Phase2 TS，以及 proposal reflect 后才重试 RX Adapt。
- SVT/Xilinx runner 均使用
  `XILINX_VCS_SIMLIB -> VIVADO_SIMLIB -> 本机已知路径` 的选择顺序，
  每次运行生成临时 `synopsys_sim.setup`。

## VCS setup 的可移植性问题

历史配置

```text
OTHERS=/home/wx/Documents/vcs_compile_simlib/synopsys_sim.setup
```

属于另一台电脑，不能作为仓库默认值。目标 runner 已移除该依赖，仓库
setup 不保存 `/home/wx` 绝对路径。当前机器实际选择到：

```text
/home/ICer/Vivado_prj/xdma_0_ex/xdma_0_ex.cache/compile_simlib/vcs
```

本轮未使用的三个历史 runner 仍有同类 portability debt，暂停点只记录、
不扩大修改范围：

```text
sim/vcs/run_xdma_x1_demo.sh
sim/vcs/run_k02.sh
sim/vcs/k13_phy_rate_change/run_k13_phy_rate_change.sh
```

它们不参与本轮 `k15-vcs-phase2`、`k15-svt-phase2-vcs` 或现成
`pcie3_ultrascale_0_ex/vcs/run_vcs.sh` 的结果。

## SVT 结果

默认 header 与 held-all-beats header A/B 在完全相同时间报告完全相同
的错误，因此 header 保持方式不是当前首因：

| 时间（ps） | 结果 |
| ---: | --- |
| 260392559000 | SVT SERDES 以 0.125 ns bit period 锁定 |
| 262165482900 | `phy_data_block_before_sds` |
| 271631496500 | `pcs_skp_end_not_detected_0` |
| 322203482900 | `RECOVERY_EQUALIZATION_1` timeout |

旧的 `electrical_idle_with_no_eios` 首错已经消失，说明新增 Gen1 EIOS
生效；当前 SVT 首错已经后移到 Gen3 SDS/block framing。

日志：

- `sim/vcs_svt/build_phase2/simulate.log`
- held-header A/B：`/tmp/k15_svt_phase2_header_held/simulate.log`

## pcie_phy_0_ex 可借鉴范围

文件 `pcie_phy_0_ex/imports/phy_ctrl_pat_gen_lane.v` 是 Xilinx
standalone PHY/GT pattern example。它的 Gen3 PIPE 输出为：

```text
beat 0: ff00ff00 valid=1 start=1 header=01
beat 1: ff00ff00 valid=1 start=0 header=01
beat 2: ff00ff00 valid=1 start=0 header=01
beat 3: ff00ff00 valid=1 start=0 header=01
beat 4: beefcafe valid=1 start=1 header=01
beat 5: beefcafe valid=1 start=0 header=01
beat 6: beefcafe valid=1 start=0 header=01
beat 7: beefcafe valid=1 start=0 header=01
```

所以它可以作为以下内容的 PHY framing golden：

- EIEOS 是完整四拍 block；
- `TXSTART_BLOCK` 只在首拍为 1；
- 该 generated PHY example 把 OS header `01` 保持四拍；
- PIPE 到 GT 串行化以及两颗 standalone PHY 的 rate-change contract。

但它不发送 Gen3 SKP、TS1/TS2 或 SDS，因此不能直接作为
`EIEOS -> SKP -> TS` 的协议 golden。SKP_END、scrambler/LFSR 和 TS
字段仍需由 PCIe 协议 directed test/SVT 检查。

### 集成 Xilinx EP 的协议 golden

仓库中的 `pcie3_ultrascale_0_ex` 是另一套现成 example：Xilinx RP 与
Xilinx EP 均为硬核模型。该 baseline 实际协商为 x1（RP core 内部配置仍
是 x8，不能通过 testbench 参数伪装成真正的 x1 core），并完整通过。

在 Xilinx EP lane-0 GT 输入端抓到的首个 Gen3 序列为：

```text
EIEOS: ff00ff00 ff00ff00 ff00ff00 ff00ff00
SKP:   aaaaaaaa aaaaaaaa aaaaaaaa bcbf9de1
TS1#0: 6794221e cef8c65d 8b3fea78 4d89054e
TS1#1: f9c6b91e ab94b0ad 1d86912d 39082304
TS1#2: fcb7901e 5e9a45ee 099d6b18 9abf1766
TS1#3: 7176de1e 57f19dcd eb3c7fe5 082e0630
```

每个 block 都只有第 0 拍 `TXSTART_BLOCK=1/TXSYNC_HEADER=01`，续拍为
`0/00`。这既验证了生产默认的首拍-only header，也给出了本项目
Phase0 TS 的可执行逐拍 golden。

Xilinx EP 进入 `0x28` 后先出现两拍 `valid=1/data=0`，随后在完整 block
边界发送 EIEOS；因此 trace 必须以第一个 `TXSTART_BLOCK=1` 为比较锚点，
不能直接以 LTSSM 状态变化为第 0 拍。

official example 已使用项目当前生成的
`fpga/kcu105/ip/pcie_phy_x1_gen3` 成功运行：

```text
K13_OFFICIAL_PHY_TRACE_PASS
Gen3 ON       103443529 ps
traffic good  204951505 ps
complete      205951505 ps
```

首批有效 RX golden 表明 receiver 可能在 EIEOS 中途才获得 block lock：

```text
ff00ff00 rxvalid=1 start=0 header=11
ff00ff00 rxvalid=1 start=0 header=11
ff00ff00 rxvalid=1 start=0 header=11
beefcafe rxvalid=1 start=1 header=01
```

对应 CSV：

- `sim/vcs/build/k13_official_trace/official_rp_pipe_trace.csv`
- `sim/vcs/build/k13_official_trace/official_ep_pipe_trace.csv`

## Xilinx RP A/B 结果

为了把协议 payload 与 PHY framing 分离，诊断宏
`K15_AB_XILINX_PATTERN` 保留四拍 EIEOS，随后把 EP 的非 EIEOS payload
替换成 official example 的 `beefcafe`，同时保持四拍 header。EP PIPE
逐拍与 passing official example 一致，但集成 Xilinx RP 仍然：

```text
rxvalid_seen=0
rxstart_seen=0
rp_rxvalid_beats=0
rp_decoded_ts=0
ep_state=0x29
rp_state=0x0c
```

因此 Xilinx RP 的当前失败不是由 EP 的 SKP/TS payload 内容单独造成；
故障发生在 RP 产生 PIPE RXVALID 之前。

### running-DC 精确对比与修复

逐拍对比最初发现 soft EP 的 TS 尾字为：

```text
soft:   0889054e ... 08200630
Xilinx: 4d89054e ... 082e0630
```

根因是 `pcie_gen3_os_tx.sv` 在 TS 首拍把 Symbol 0 的 `1E/2D` identifier
排除在 `included_bits=24` 之外，却仍用 32-bit popcount 把它的 4 个置位
计入 `output_ones`。首拍 DC 贡献因此固定偏置 `+8`，导致 Symbol 15/14
substitution 提前或选错。

修复后首四个 Phase0 TS 已逐拍等于上面的 Xilinx golden；directed test
也由“尾字包含任意 `08/F7/20/DF` 即可”收紧为 16 个 dword 精确比较：

```text
K15_EQ_PHASES_DIRECTED_PASS
K15_GEN3_IDLE_STREAM_PASS blocks=19
K15_EQ_EIEOS_SKP_TS_PASS
```

但修复后的 Xilinx RP 严格复跑结果仍是 `RXDATA_VALID=0`。因此该 bug 是
确定协议问题，却不是当前 Xilinx RP 首错的充分根因。

进一步比较了 TXP 串行边沿。passing official PHY 与 failing EP 的首
32 个 edge delta 序列逐项一致：

```text
125, 1125, 1000, 1000, ...,
1125, 250, 875, 125, 125, 125, 125, 250, 750, 125, 375, 125, 625, 125, 125 ps
```

这说明 exact-pattern A/B 下，从 PIPE、generated PHY 128b/130b gearbox
到 serializer 的结果均与 official golden 一致。Xilinx RP 的剩余问题
应优先从集成 RP RX model/configuration 及双方 rate-transition 协同查找。

另外完成了两项 A/B：

- `TXSYNC_HEADER` 首拍-only 与 held-all-beats：结果相同。
- rate envelope 中 `as_cdr_hold_req=0` 与 `1`：结果相同。

P/N 拓扑也已核对：当前 board 与 official example 都是
`TXP -> RXP`、`TXN -> RXN`，未发现静态接反。

## Local loopback 诊断修正

旧 `K15_LOCAL_PHY_LOOPBACK_PASS` 判据在 force 生效后的第一个周期接受了
原 RP 流残留的 `RXVALID`，数据为 `header=10/data=cf4f9450`，属于
假阳性。

判据已经改为：

1. force 后冲刷 64 个 PIPE cycles；
2. 必须看到 `start=1/header=01/data=beefcafe`；
3. 40 us 内没有该 marker 则 FAIL。

修正后结果为：

```text
K15_LOCAL_PHY_LOOPBACK_RESULT
  flush=64 rx_cycles=10000 gen3_rx_seen=0
K15_LOCAL_PHY_LOOPBACK_FAIL
```

该结果说明瞬时切换后的本地串行 loopback 也没有重新获得 block valid；
但由于 force 是在 Gen3 已锁定后切换串行源，不能单独证明 EP TX 错误。
后续应在 reset/rate change 前建立固定 loopback，或直接用一颗 standalone
PHY receiver 替换集成 RP。

## 当前故障分层

### Xilinx RP

当前失败点在 Equalization Phase0/Phase1 协议解析之前：

- RP 自己进入 `0x28/0x29` 不代表它收到 EP；
- EP 进入 `0x29` 是因为 EP 能收到 RP 的 TS；
- RP lane 0 没有 `RXDATA_VALID`，所以 RP 没有消费 EP 的 Phase0/1
  response。
- soft EP 的 GT 输入从 EIEOS、SKP 到前四个 TS 已与 passing Xilinx EP
  精确一致；剩余差异应优先查 rate-transition 协同、GT/RX model 状态和
  electrical-idle 退出相位，而不是继续修改 TS payload。

### SVT

SVT 已进入 Equalization Phase1，但在此之前已经检测到 SDS/block 和
SKP_END framing 错误，随后卡在 Phase1，未进入 Phase2。

## 下一步优先级

1. 用 passing official 2x standalone PHY testbench，将其中一侧 pattern
   generator 替换为当前 EP PIPE source，保持 receiver、reset 和 rate
   sequencer不变；这是最干净的 TX/receiver 隔离实验。
2. 把 official 与 EP 的 GT 输入/输出控制逐项比对：
   `TXDATA/TXCTRL`、rate reset、QPLL、TX/RX reset done、CDR hold、
   Electrical Idle release 和首个串行 edge。
3. 对 SVT 单独修正动态 SKP_END：周期 SKP 的 SKP_END/LFSR 字段不能长期
   使用固定 `BCBF9DE1`。
4. 在 standalone receiver 能稳定产生 RXVALID 后，再恢复真实
   `EIEOS -> SKP -> TS` payload，处理 SDS 和 SVT framing 首错。
5. 最后执行 `k15-svt-phase2-vcs` 与 `k15-vcs-phase2` 的严格
   Phase2 gate。

暂停时仍记录两个未修问题：

- 周期 SKP 目前长期使用固定 `BCBF9DE1`；只有 EIEOS 后 lane seed 对应的
  首个 SKP 可以这样固定，任意 LFSR 相位插入的周期 SKP_END 必须携带当时
  的 23-bit LFSR 状态及 parity。这与 SVT 的
  `pcs_skp_end_not_detected_0` 高度相关。
- 本机仓库内 Verilator 为 3.922，不支持 Makefile 中的 `--build`；本轮
  directed test 使用 `verilator --cc --exe` 后再执行生成 makefile 的两步
  流程。该工具兼容性不是 RTL 失败，但应在后续单独整理 runner。

## 与 0ff2bc6 的关系

`0ff2bc6 fix: preserve Gen1 ordered-set boundaries` 只保护 Gen1
TS1/TS2 切换边界，不包含 Gen1 EIOS、Gen3 128b block source ownership、
周期 SKP 或 Phase2 EQ 字段，因此不能覆盖本轮首错。当前新增修改是在
`0ff2bc6` 基线上增量完成。

## 2026-08-31 PG239 / PCIe EQ closure 实施结果

生产路径已改为由 `pcie_gen3_equalization_ctrl` 持有 PCIe phase semantics，
`pcie_phy_command_ctrl` 继续独占 PG239 raw pins；旧
`pcie_k13_production_ctrl.sv` 及其测试/source-list 保留，本轮未做 legacy cleanup。

Recovery.Speed 默认波形现在是：

```text
TXEI lead -> dynamic Preset -> clear -> Query -> clear -> Rate
```

Gen1/2 EQ TS2 必须有八个连续且完整 tuple 相同，才锁存 Symbol 6 的 P0--P10；
reserved、malformed、tuple 变化或序列中断取消资格，命令层使用 P4 fallback。
Query 可通过 `K15_AB_PRERATE_QUERY=0` 单独关闭。Query 输出只按
`raw/pre/main/post` 记录，不再使用固定 18-bit expected。Preset-only 路径按
FS=40 的名义表生成字段，包括 P10=`{pre,main,post}={0,27,13}`；reserved
输入仍回退 P4。

Equalization Phase0--3 已去掉 generic `TS_REQUIRED=8`：Symbols 6--9 parity
正确且两个完全相同的 TS1 才能推进；transition pair 跨 phase 保存。Phase2 proposal
要求两个完全相同的 reflection 且 Reject=0，Reject=1 进入已有 Gen1 fallback。
Phase3 同时覆盖 Preset/Coefficient apply 后 Query，两个 EC00 才退出，并在已有 PHY
operation 时延迟退出；第二个 EC00 与 Query done 同拍也有 directed coverage。周期
SKP_END 也改为由当前 23-bit LFSR state 动态生成和验证。

静态与 directed gate 通过：

```text
K15_EQ_TS2_PRESET_CAPTURE_PASS
K15_EQ_PHASES_DIRECTED_PASS
K15_EQ_REJECT_FALLBACK_PASS
K15_DYNAMIC_SKP_END_PASS
K15_PHY_AB_MATRIX_PASS variants=2
PHY_COMMAND_OWNERSHIP_PASS
K14_RECOVERY_SPEED_SEMANTIC_PASS
```

Xilinx RP 在固定 `cdr=0 / P4 / dwell=4` 下完成 Query A/B。Query-on 实测为：

```text
raw=18'h00A00  pre=0  main=40  post=0
```

两组都完成 Gen3 rate、QPLL、PhyStatus，并由 EP 消费两个相同 EC01 后进入 Phase1；
但两组 RP 都是 `rxvalid_seen=0 / rp_decoded_ts=0`，最终
`K15_VCS_BLOCKED_RP_EQ_RESPONSE_NOT_CONSUMED`。因此 Figure-1 Query 是已实现、
可开关的 canonical path，但本次 A/B 不支持把缺 Query 认定为 RP 首块接收的充分根因。

持久日志：

- `sim/vcs/build/k15_ab_preset_only.log`
- `sim/vcs/build/k15_ab_preset_query.log`

SVT runner 已启动检查，但当前主机缺少
`/home/ICer/synopsys/designware/bin/dw_vip_setup`，因此 VIP build 尚未执行；这项是
环境阻塞，不作为 RTL pass/fail 证据。

### 2026-08-31 SVT 重跑（使用 `/home/wx/synopsys/designware`）

本次通过 `DESIGNWARE_HOME=/home/wx/synopsys/designware make k15-svt-vcs` 完成了
SVT VIP 生成、VCS compile/elaboration/link 和真实串行仿真。SVT 在
`260552559000 fs` 锁定 8.0 GT/s CDR，随后首错为：

```text
262325482900  phy_data_block_before_sds
271791496500  pcs_skp_end_not_detected_0
322203482900  phy_recovery_equalization_phase1_timeout
324174482900  recovery-speed inferred electrical idle
```

之后 SVT 回退到 2.5 GT/s，测试以错误退出；没有观察到 Phase0/Phase1 的有效
consecutive-TS closure，也没有进入 Phase2/3。该结果与 Xilinx RP 的
`RXDATA_VALID=0 / decoded_ts=0` 相互印证：当前首错仍位于 CDR 之后、有效
128b/130b block/SDS/EIEOS 建立之前，而不是 Phase2/3。

持久日志：`sim/vcs_svt/build/simulate.log`、`sim/vcs_svt/build/elaborate.log`。

### 2026-08-31 SVT EIEOS 后 PIPE 观测

在 `sim/vcs_svt/board_svt_pcie_x1.sv` 加入 observation-only 的 EP TX / SVT RP
PIPE monitor 后重跑。EP 侧在 `260491530000 fs` 附近进入 EIEOS 输出，连续 beat
可见 `phy_txdata_valid=1`、数据为 `ff00ff00`（发送器源码规定 EIEOS 四个 beat
均为该值；监视器在同步边沿上会看到下一 beat 的 word index）。

SVT RP PIPE 侧从 `260484484000 fs` 到 `260579484000 fs` 连续 96 个 `pipe_clk`
仍为 `valid=0, data_valid=0, start_block=0, sync_header=00, data=00000000`；
这覆盖 CDR lock (`260552559000 fs`) 前后。之后首次出现有效输出是在
`261090484000 fs`：`valid=1, data_valid=1`，但数据序列从
`bd 94 67 5d c6 d9 e6 5c ...` 开始，并非 EIEOS 的 `ff00ff00` block。
随后才出现 `start_block=1, sync_header=01, data=1e` 的 TS-like ordered-set
边界（例如 `261105484000 fs`）。`ei_code` 全程为 0。

因此本次证据是：EP 确实在 TX PIPE 侧驱动了 EIEOS，但在 SVT RP 的可见 PIPE
输出上没有观察到一个有效、可识别的 EIEOS block；SVT 后续看到的是先出现的
失步/垃圾字节，再出现 TS-like block 边界。这正好解释了“CDR lock 不等于
EIEOS/SDS/block lock”，也不能把 `phy_data_block_before_sds` 解释为“已识别
EIEOS”。

持久观测日志：`sim/vcs_svt/build/simulate.log`；monitor 定义见
`sim/vcs_svt/board_svt_pcie_x1.sv`。
