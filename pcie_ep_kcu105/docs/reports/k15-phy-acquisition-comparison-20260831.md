# K15 Gen3 PHY/PCS acquisition 对比（第一层，2026-08-31）

本轮目标是用户指定的第一层对比：官方 Golden 仿真 → K15 当前实现 →
serial edge → 最小 A/B（`K15_AB_HEADER_HELD`）。Phase0--3 EQ、SKP、TS、
scrambler、rate sequence 均未修改。

执行基线：提交 `46de4899b0f0cb969d6f794442ba4c1d73ec275b`。
license 前提：本会话验证 `27000@wx-linux` 实际可达（`lmstat` 显示
`snpslmd: UP`，`wx-linux = 127.0.1.1`）。此前报告中的 license 阻塞属于
Codex 沙箱环境，不是本机状态。

## 1. 官方 fresh Golden（运行时捕获，非源码推断）

复用 `sim/vcs/k13_phy_rate_change/run_official_trace.sh` +
`official_trace_bind.sv`，本机一次通过：

```text
K13_OFFICIAL_PHY_TRACE_PASS
result_dir = sim/vcs/build/k13_official_trace/
```

simlib 用本机 `/home/wx/Documents/vcs_compile_simlib`
（`K11B_RP_IMPORTS` 相关见第 5 节的环境备注）。

### TX 侧 EIEOS envelope（official_rp_pipe_trace.csv）

| beat | time_ps | txvalid | txstart | txheader | txei | txdata |
| ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 0 | 123967504 | 1 | 1 | 01 | 0 | ff00ff00 |
| 1 | 123971504 | 1 | 0 | 01 | 0 | ff00ff00 |
| 2 | 123975504 | 1 | 0 | 01 | 0 | ff00ff00 |
| 3 | 123979504 | 1 | 0 | 01 | 0 | ff00ff00 |
| 4 | 123983504 | 1 | 1 | 01 | 0 | beefcafe |

官方 example 运行时确实把 `TXSYNC_HEADER=01` 保持四拍（与源码
`GEN3_EIEOS_TX_DATA` 推断一致），随后 `beefcafe` 数据块同样 held 01。

### RX 侧首个 RXDATA_VALID（official_ep_pipe_trace.csv，partner PHY 接收）

| rx_sample | time_ps | rxvalid | rxstart | rxheader | rxdata |
| ---: | ---: | ---: | ---: | ---: | --- |
| 0 | 124595529 | 1 | 1 | 01 | ff00ff00 |
| 1 | 124599529 | 1 | 0 | 11 | ff00ff00 |
| 2 | 124603529 | 1 | 0 | 11 | ff00ff00 |
| 3 | 124607529 | 1 | 0 | 11 | ff00ff00 |
| 4 | 124611529 | 1 | 1 | 01 | beefcafe |

要点：

- 接收端**首个** `RXDATA_VALID` 输出的就是完整 EIEOS block
  （`start=1, header=01, data=ff00ff00`），没有失步垃圾字。
- 从 TX beat0 到首个 `RXDATA_VALID` 延迟 `628025 ps`（≈ 628 ns，
  EIEOS 结束后约 616 ns）。
- 发送侧 pattern PHY 自收（official_rp_pipe_trace.csv）在捕获窗口内
  `RXDATA_VALID=0`，但 `rxdata=ff00ff00, rxstart=1, rxheader=01` 已先于
  valid 出现（124567529 ps 起）——数据先于 valid 是官方接收器的正常
  envelope，不能把 `rxdata≠0 但 rxvalid=0` 读成接收失败。

## 2. K15 当前实现同窗口（sim/vcs/build/k15_ab_header_A.log）

来源：本轮 fresh A 组运行（默认 header），与存档
`k15_gen3_simulate_preAB_20260831.log`（16:54 运行）逐拍一致。

时间线：

```text
EP_PhyStatus            379227604 ps
EP_TXELECIDLE_fall      379363529 ps
EP_first_Gen3_TXSTART   379371529 ps
```

| beat | time_ps | txvalid | txstart | txheader | txei | txdata |
| ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 0 | 379371529 | 1 | 1 | 01 | 0 | ff00ff00 |
| 1 | 379375529 | 1 | 0 | 00 | 0 | ff00ff00 |
| 2 | 379379529 | 1 | 0 | 00 | 0 | ff00ff00 |
| 3 | 379383529 | 1 | 0 | 00 | 0 | ff00ff00 |
| 4 | 379387529 | 1 | 1 | 01 | 0 | aaaaaaaa（SKP） |
| 7 | 379399529 | 1 | 0 | 00 | 0 | bcbf9de1（SKP_END） |
| 8 | 379403529 | 1 | 1 | 01 | 0 | 6794221e（TS1#0，与 Xilinx golden 一致） |

K15 RP 侧（`K15_RP_RX_ENVELOPE`，n=0..11，379365529--379409529 ps）：

```text
valid=0 start=0 header=00 data=00000000
gt_valid=0 gt_start=0 gt_header=00 gt_data=00000000
rxvalid=0 cdrlock=1 rxresetdone=1 rate_gen3=1
user_gen3_rdy=1 user_rate_start=0 rate_idle=1 rx_idle=1
```

对比结论（逐项回答用户清单）：

- 官方 EIEOS 是 4 个 32-bit beat：确认（fresh 运行时 + 源码）。
- 四拍 `TXSTART_BLOCK` 只在首拍：K15 与官方一致。
- 四拍 `TXSYNC_HEADER`：官方 `01,01,01,01`；K15 `01,00,00,00`。
  这是 TX envelope 唯一差异。
- `TXDATA_VALID/TXELECIDLE/payload`：K15 与官方一致（K15 payload
  按协议是 EIEOS→SKP→TS，官方 example 是 EIEOS→beefcafe，属有意差异）。
- RP/SVT 是否真正输出有效 EIEOS block：**否**。Xilinx RP 在整个窗口
  `gt_data=00000000`（GT/PCS 层无输出）；SVT 侧旧观测首有效字为
  `000000bd` 失步垃圾，均非 EIEOS。
- 首个 `RXDATA_VALID` 出现什么数据：Xilinx RP 从未出现
  （`rxvalid_seen=0`）；官方 golden 首个 valid 输出即 EIEOS block。

## 3. Serial edge 对比

官方（123994059 ps 起）与 K15（379398059 ps 起）首 32 个边沿：

| n | 官方 delta_ps | K15 delta_ps | 是否一致 |
| ---: | ---: | ---: | --- |
| 0 | (首个) | (首个) | - |
| 1 | 125 | 125 | ✓ |
| 2 | 1125 | 1125 | ✓ |
| 3--16 | 1000 ×14 | 1000 ×14 | ✓ |
| 17 | 1125 | 1125 | ✓ |
| 18 | 250 | 250 | ✓ |
| 19 | 875 | 125 | **分叉** |
| 20--31 | 125,125,125,125,250,750,125,375,125,625,125,125 | 125 ×12 | 分叉（预期） |

解释：

- n=0--18 覆盖 sync header 2 bit + EIEOS 16 symbol 的全部 run-length
  结构（`FF/00` 交替 → 8 UI=1000 ps run；块尾 0-run 与下一块 sync
  header 首位拼接 → 1125 ps；下一块前 2 bit → 250 ps）。
  **EIEOS 的串行位流与官方逐边一致**，包括块边界相位。
- n=19 起分叉是预期行为：官方在 EIEOS 后发 `beefcafe`
  （irregular 数据 pattern → 875/250/750/375/625 ps），K15 发 SKP
  （`aaaaaaaa` = 1010... → 全部 125 ps）。二者协议 payload 本就不同，
  不构成差异证据。
- PHY/gearbox pipeline 延迟：官方 `首个串行边沿 − beat0 = 26555 ps`，
  K15 = `26530 ps`，差 25 ps（0.2 UI @8 GT/s），可视为一致。
- 结论：**串行输出节奏与官方一致**；失败不可能出在 serializer 或
  EIEOS 位流本身。

物理推论：`TXSYNC_HEADER` 是 PIPE 侧采样信号（PG239：PHY 在
`TXSTART_BLOCK` 有效拍读取 sync header），continuation beat 上的
00/01 不进入串行位流。因此 held-header A/B 若无效果是符合协议的
预期结果，而不是"实验失败"。

## 4. 最小 A/B：`K15_AB_HEADER_HELD`

只切换该宏（A=`01,00,00,00` 默认；B=`01,01,01,01`），其余 TXEI、
valid、start、data、SKP、TS、scrambler、rate sequence、EQ FSM 全部
不动。本轮 fresh 完成 Xilinx RP 两组：

```text
A: sim/vcs/build/k15_ab_header_A.log
B: sim/vcs/build/k15_ab_header_B.log
```

两组结果逐字相同，且与历史基线一致：

```text
K15_AB_LATENCY rate_seen=1 qpll_seen=1 phystatus_seen=1 cdrlock_seen=1
  rxvalid_seen=0 rxstart_seen=0
  T1_rate_to_phystatus_ps=20488000 T2_rate_to_cdrlock_ps=4000
  T3_rate_to_rxdata_valid_ps=0（从未发生）
K15_XILINX_RP_PHASE2_FAIL wait=34491 ep_state=29 rp_state=c
  rp_rxvalid=0 rp_rxvalid_beats=0 rp_decoded_ts=0 timeout=1
```

判定：

- `TXSYNC_HEADER` continuation-beat 取值**不是** Xilinx RP
  `RXDATA_VALID=0` 的根因。结合第 3 节的物理推论（该信号不进串行
  位流），此结果符合协议预期，可以关闭这条排查线。
- `pcie_gen3_os_tx.sv` 中"重复 01 会阻止 PCS 获取块边界"的注释与
  官方 example 的实际行为（held 01 且其接收端成功 block lock）矛盾，
  该注释所述机理没有实验支持。
- SVT held-header B 组（`K15_SVT_HEADER_HELD_AB=1`，
  `sim/vcs_svt/build/simulate_header_B.log`）同样完成且与 A 组
  （`simulate_preAB_20260831.log`）逐拍等价：
  - 宏生效确认：EP TX EIEOS monitor 显示 B 组 continuation beat
    `sh=01`（A 组 `sh=00`），即被观测信号确实不同；
  - 三条首错时间戳逐字相同：`262325482900 phy_data_block_before_sds`、
    `271791496500 pcs_skp_end_not_detected_0`、
    `322203482900 phy_recovery_equalization_phase1_timeout`；
  - SVT RP 首个 `data_valid=1` 仍是 `000000bd` 失步垃圾
    （n=96，261090484000 fs），与 A 组相同，仍非 EIEOS block。
- 至此 `K15_AB_HEADER_HELD` 在 Xilinx RP 与 SVT 两条环境上均为
  "无差异"，该变量可以停止作为候选首因。

## 5. 新的首错定位线索与下一步

A/B 排除 header 后，当前最强信号来自 RP RX 数据通路状态：

```text
cdrlock=1 rate_gen3=1 rxresetdone=1 user_gen3_rdy=1
但 user_rate_start=0 rate_idle=1 rx_idle=1
gt_valid=0 gt_data=00000000（GT/PCS 层无任何输出）
```

即 RP 的 RX 通路在 Gen3 rate change 后从未重新建立：CDR 锁了，但
RX PCS/buffer/user clock 链没有恢复输出。对照官方 fresh golden：

- 官方接收端在 rate change 后约 600 ns 内完成 block lock 并输出
  EIEOS block（数据先于 valid 数百 ns 出现）；
- K15 RP 的 GT 层 `gt_data` 恒为 0，说明问题在 EP 发送端可见证据
  （串行位流正确）与 RP 接收端 GT/PCS 输出之间。

> **（已被第 7 节隔离实验取代）** 第 2 步的 standalone 隔离实验已完成，
> 结论是接收失败发生在 EP **发送流**上（缺少官方节奏的 PIPE
> valid-gap/SKP 替换），不在集成 RP 的 RX 侧——详见第 7 节。

这把首错收敛到报告 2026-08-30 节已指出的"rate-transition 协同 / RP
RX model 状态"层，具体下一步（按性价比排序）：

1. 对比官方 example 接收 PHY 在 Gen3 rate change 后的
   `RXPMARESETDONE/RXCDRLOCK/RXUSERREADY/RXBUFFER` 恢复序列与 K15 RP
   的对应信号，定位 RP RX 未重启的握手中断点。
2. 在官方 2× standalone PHY testbench 中把一侧 pattern generator
   换成 K15 EP PIPE source（报告 2026-08-30 下一步第 1 项），若
   standalone receiver 能出 `RXDATA_VALID`，即可把问题锁到集成 RP
   的 RX 侧而非 EP TX。
3. SVT 侧动态 SKP_END（固定 `BCBF9DE1` 问题）保持待办，但不属于
   Xilinx RP 首错路径。

## 7. Standalone PHY 收发隔离实验（2026-08-31，根因已定位）

按用户指示先提交基线（`26b5fcc`）后执行第②步：在官方 2× standalone
PHY testbench 中，把一侧 `phy_ctrl_pat_gen` 换成 K15 EP 的 PIPE 源
（`sim/vcs/k15_phy_isolation/k15_ep_pat_gen.sv`），接收器/复位/rate
sequencer 全部保持官方不动。判定器仍用官方 `K13_OFFICIAL_PHY_TRACE` 的
`RXDATA_VALID` 出现判 PASS。

### 7.1 A/B 矩阵（全部单旋钮）

| 组 | 改动 | 结果 | 首个 RXDATA_VALID |
| --- | --- | --- | ---: |
| PASSTHROUGH | 官方源直通（管线健全性） | PASS | 124607529 |
| 默认 | K15 `pcie_gen3_os_tx` 原样 | FAIL | 永不 |
| xpattern | EIEOS 后改数据 pattern | FAIL | 永不 |
| phase_shift | 相位偏移 | FAIL | 永不 |
| header_held | EIEOS 四拍 held `01` | FAIL | 永不 |
| valid_gap | K15 136 拍节奏上按 64/129 相位扣拍 | FAIL | 永不 |
| no_first_skp | 去掉 EIEOS 后首个 aaaa SKP 块 | FAIL | 永不 |
| eieos128 / combo128 | EIEOS 周期改 128 / 组合 | FAIL | 永不 |
| **official_gap** | os_tx 内置官方式 1 拍 valid=0 gap（EIEOS 前一拍 + 每 15 块一 gap，周期 130） | **PASS** | 124599529 |
| gap_only | 仅加 gap、EIEOS 周期不动（gap 距 EIEOS 64 拍） | FAIL | 永不 |
| **official_gap+first_skp** | official_gap 且保留 EIEOS 后首个 aaaa SKP 块 | **PASS** | 125655504 |

### 7.2 关键发现：PIPE→GTHE3 映射与 SKP 替换点

- `gtwizard_top.v:757`：`txctrl0_in = {10'd0, GT_TXSYNC_HEADER[1:0],
  GT_TXSTART_BLOCK[0], GT_TXDATA_VALID[0], 2'd0}` —— valid/start/header
  经 TXCTRL0 进入 secureip；`gt.v` 中 `txheader_in=6'h00`、
  `txsequence_in=7'h00`、`rxgearboxslip_in=1'h0` 均为常量绑定。
- **整个 IP RTL 无任何 SKP 替换逻辑**；wire 上的 SKP ordered set 全部由
  secureip 在 `TXDATA_VALID=0` 拍内部替换生成。因此 K15 os_tx
  "valid 恒 1 → 全程无真实 SKP"，其显式 aaaa "SKP" 块不是 wire SKP 内容
  （wire SKP 符号是 `0x1C`）。
- 官方 cadence（`phy_ctrl_pat_gen_lane.v` 解码）：EIEOS_1..4 → 15 数据
  块（60 拍）→ **1 拍 valid=0 gap** → 16 数据块（64 拍）→ **1 拍 gap** →
  EIEOS，周期 130 拍；**每个周期性 EIEOS 的前一拍恰是 gap**（wire 上
  SKP→EIEOS 相邻）；gap 后第一拍必为 `start=1`（新块）；官方对数据拍也
  全程驱动 `header=01`，且从不主动发 SKP 内容。

### 7.3 判定（root cause）

**根因：K15 `pcie_gen3_os_tx` 的 Gen3 流从不 deassert `TXDATA_VALID`，
secureip TX 从不替换出真实 SKP ordered set，接收端 GTHE3 无法完成
128b/130b RX block lock**（cdrlock=1、rxresetdone=1 但
RXDATA/RXHEADERVALID 恒 0）。恢复条件是复现官方节奏的 1 拍 valid=0
gap 结构，且**gap 与 EIEOS 相邻**是实测必要条件：

- official_gap / official_gap+first_skp（gap 紧邻 EIEOS）→ PASS，
  时间 124.60/125.66µs ≈ golden 的 124.61µs；
- valid_gap（gap 与 EIEOS 相位漂移 7 拍）与 gap_only（gap 距 EIEOS
  64 拍）→ FAIL —— 有 gap 但不相邻不足以锁定。

同时正式排除：aaaa 首 SKP 块本身无毒（official_gap+first_skp 仍 PASS）、
EIEOS 周期 128/136 不是首因、TXSYNC_HEADER held 不是首因（第 4 节 +
header_held 组双确认）、RP 集成 RX 侧不是首因（standalone 官方接收器
收 K15 流同样失败，PASSTHROUGH 即恢复）。

### 7.4 修复方向（待另行执行，本轮未动 EP 路径）

把 `pcie_gen3_os_tx` 的周期性显式 SKP 机制替换为官方式 1 拍
valid=0 gap 插入：在块边界扣 1 拍（恢复拍 start=1），并保证每个周期性
EIEOS 的前一拍是 gap（wire SKP→EIEOS 相邻）。os_tx 现有的
"LFSR 在 gap/SKP 期间冻结、EIEOS 后复位 LANE0_SEED" 行为与官方一致，
可保留。stolen-beat/mux 层扣拍与 os_tx 的 4 拍 start_block 刚性节奏
结构性冲突，必须在 os_tx 状态机内实现。

## 8. 环境备注（供后续复现）

- `run_k15_phase2.sh` 默认 legacy `pcie3_ultrascale_0_ex` imports，
  但 `prepare_k11b_rp_usrapp.py` 的 `dmaTestDone` 锚点在该文件中
  从提交 `0aadb23` 起就不存在，prepare 必然失败。本轮所有 phase2
  运行使用 `K11B_RP_IMPORTS=/home/wx/Documents/PCIe/xdma_x1_demo/build/example/xdma_x1_ex/imports`
  （XDMA 份可通过 prepare，且与 `run_k15_gen3.sh` 的默认优先级一致）。
  legacy imports 的可移植性债务需单独清理。
- 官方 runner 本机 simlib 选择：
  `XILINX_VCS_SIMLIB=/home/wx/Documents/vcs_compile_simlib`。
- 产出的持久文件：
  - `sim/vcs/build/k13_official_trace/official_{rp,ep}_pipe_trace.csv`
    （fresh 官方 golden）
  - `sim/vcs/build/k15_ab_header_{A,B}.log`
  - 隔离实验：`sim/vcs/k15_phy_isolation/`（runner + 源），结果目录
    `sim/vcs/build/k15_iso_*`（判定行 `K15_ISO_RECEIVER_ACQ_*`），
    golden GTTX 拍流 `sim/vcs/build/k13_official_trace_gttx/`
  - `sim/vcs/build/k15_gen3_simulate_preAB_20260831.log`
  - `sim/vcs_svt/build/simulate_preAB_20260831.log`、
    `simulate_header_B.log`（SVT A/B）
  - `docs/reports/k15_phy_acquisition_eieos.csv`（已更新为运行时证据）
