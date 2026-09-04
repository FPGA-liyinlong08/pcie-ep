# K15 Gen3 Recovery.Equalization Phase2 实板排查记录

日期：2026-09-04
对象：KCU105 / KU040，JTAG target `210308AC5C97`，device `xcku040_0`
远端 Root Port：`192.168.11.126`，预期 Endpoint BDF：`01:00.0`
测试 bit：`build_k15_l0_rephase_board_41fdabe/bit_41fdabe/k14_recovery_speed_ila.bit`
bit SHA256：`6baaabe2863e1ebc6e946f3830f31b9f24b74df1d3ac81cf9e3ff99a619b3bc0`

注意：当前 `hw_server` 同时管理 KU060 `210512180081` 和 KU040
`210308AC5C97`。硬件脚本必须按后一个序列号显式打开 target，不能依赖
`open_hw_target` 的默认顺序。

## 测试范围

- 使用已经烧写的 K15 bit，只重新加载 LTX 和设置 ILA 触发器；没有修改 RTL、没有新增 ILA、没有使用 XDMA bit。
- 每次设置触发后重启远端主机，使 Root Port 重新发起链路训练。
- ILA 采样时钟为 250 MHz，8192 点窗口约为 32.8 us。
- K14/K15 PHY 切速是否成功仍以 `event_state=8` 且目标 `phy_rate` 为准；不能直接用裸 `phy_phystatus` 触发，因为它会捕获 Gen1 初始化阶段的电平。

## 触发条件与结果

| 触发条件 | 结果 |
|---|---|
| `k14_ltssm_state_w == 6'h2a` 且 `k14_phy_rate_w == 2` | 命中；8192 点全为 `0x2a`，确认 Phase2 长驻 |
| `k14_speed_state_w == ST_FALLBACK_REQUEST (5)` | 命中；`k14_timeout_fallback_w=1`，LTSSM `0x2a -> 0x12` |
| `k14_speed_state_w == ST_FALLBACK_WAIT (6)` | 命中；`phy_rate` 从 `2 -> 0`，rate state 进入 `WAIT_PHYSTATUS(4)` |
| `k14_event_state_w == 8` 且 `k14_phy_rate_w == 0` | 命中；`k14_gen1_fallback_success_w=1`，Gen1 fallback 完成 |
| `LTSSM=0x2b` 且 Gen3 | 未命中 |
| `LTSSM=0x0c` (Recovery.RcvrCfg) 且 Gen3 | 未命中 |
| `LTSSM=0x0a` (L0) 且 Gen3 | 未命中 |

注意：RTL 定义中 `0x0b=Recovery.RcvrLock`、`0x0c=Recovery.RcvrCfg`、`0x0d=Recovery.Idle`、`0x0a=L0`。

## 原始捕获文件

原始 CSV 当时保存在 `/tmp/pcie_k15_a0/`，摘要及校验如下；若临时目录被清理，以上表格和本记录仍是仓库内的证据摘要。

| 捕获 | 主要观测 | SHA256 |
|---|---|---|
| `phase2_capture/20260904_155038_k15_ab0_recovery.csv` | 8192 点 `LTSSM=0x2a`、`phy_rate=2` | `25cc424c28d0e775bdc3679be82ae768d8fff32acae522d9c9462a2afd129d50` |
| `speed_fallback_capture/20260904_160733_k15_ab0_recovery.csv` | `ST_FALLBACK_REQUEST`、`timeout_fallback=1` | `0a46ea160930bba0edc929c3905b297a4e769940495fa1a8cd7d08c879759a12` |
| `speed_fallback_wait_capture/20260904_160925_k15_ab0_recovery.csv` | `ST_FALLBACK_WAIT`、`phy_rate 2->0` | `f79655aeff58355fa2a79d83fd97007c214584e42108e8ccc44eb50830cb41d0` |
| `speed_fallback_success_capture/20260904_161128_k15_ab0_recovery.csv` | `event_state=8`、Gen1 fallback success | `20e6f25fd1e8411c5b23481b4b612cdcf5cff0523b9e5d7b7000153977e6db8c` |

## 现象与结论

1. K15 已完成 Gen1→Gen3 的 PHY rate operation；此前成功捕获的 event recorder 还记录到 Gen3 `PHYSTATUS` 上升沿。因此当前问题不是“Gen3 rate 没提交”或“PHYSTATUS 永远不来”。
2. 切到 Gen3 后 LTSSM 能进入 `Recovery.Equalization Phase0/Phase1`，随后进入 `Phase2 (0x2a)`，在一个完整采样窗口内没有进入 `Phase3 (0x2b)`。
3. Phase2 超时后，速率控制器置位 `timeout_fallback` 并发起 Gen1 fallback；fallback 的 PHY 操作能完成，说明 fallback 方向的 GT/PHYSTATUS 路径正常。
4. fallback 后 LTSSM 停在 `Recovery.RcvrLock (0x0b)`，Gen3 `RcvrCfg` 和 L0 均未观察到；远程主机当前也没有枚举 `01:00.0`。

### 当前定位

故障范围已收敛到 **Gen3 Equalization Phase2 未完成**，优先排查：

- `RXEQ_ADAPT` 请求是否发出并完成；
- `eq_req_valid/eq_req_ready`、`eq_busy/eq_done/eq_result` 握手；
- GT `PHY_RXEQ_DONE` / `PHY_RXEQ_ADAPT_DONE`；
- 对端 EC=10 TS1 的接收、连续性、preset/coeff 匹配和 Reject 位；
- `eq_phase_done` 是否产生并被 LTSSM 采到。

现有 bit 没有这些 EQ 内部探针，所以本轮只能完成到 Phase2/fallback 边界，不能仅凭当前 ILA 区分 RXEQ 硬件未完成、对端 TS 响应不匹配，还是 `eq_done`/`eq_phase_done` 语义握手问题。功能逻辑暂不应据此修改；后续若允许增加诊断探针，应优先覆盖上述信号。

## Phase2 专用 ILA 版本

2026-09-04 在不修改协议行为的前提下加入观察端口、Phase2 sticky
里程碑和专用 ILA 探针。ILA 仍为 8192 点；切速阶段已经取证完成，因此
移除大部分 QPLL/伙伴请求探针，只保留 LTSSM、Rate、Speed、PHYSTATUS 和
fallback 上下文。

### `probe0`：切速与 LTSSM 上下文（23 bit）

按 Vivado LTX 中的原信号名使用：

- `k14_phy_rate_w[1:0]`
- `k14_rate_state_w[3:0]`
- `k14_speed_state_w[2:0]`
- `k14_ltssm_state_w[5:0]`
- `k14_event_state_w[3:0]`
- `phy_phystatus`
- `k14_gen3_rate_success_w`
- `k14_timeout_fallback_w`
- `k14_gen1_fallback_success_w`

### `probe1`：`k15_phase2_debug_w[117:0]`

| 位 | 信号 |
|---|---|
| `[117:95]` | Phase2 累计周期，23 bit 饱和，覆盖约 33.6 ms |
| `[94:89]` | sticky `{phase_failed, phase_done, proposal_match, proposal, rxeq_done_rise, req_accept}` |
| `[88:86]` | `eq_operation_state` |
| `[85:82]` | `eq_phase_ts_count` |
| `[81] / [80]` | `eq_phase_done / eq_phase_failed` |
| `[79] / [78]` | `eq_req_valid / eq_req_ready` |
| `[77:75]` | `eq_req_kind` |
| `[74] / [73] / [72:70]` | `eq_busy / eq_done / eq_result` |
| `[69:68] / [67:64]` | `phy_rxeq_ctrl / phy_rxeq_txpreset` |
| `[63] / [62] / [61]` | `phy_rxeq_done / adapt_done / preset_sel` |
| `[60:43]` | `phy_rxeq_new_txcoeff` |
| `[42] / [41]` | `os_ts1_valid / os_malformed` |
| `[40:33] / [32:9]` | RX `os_eq_control / os_eq_data` |
| `[8:1] / [0]` | TX `eq_control / os_tx_complete` |

### `probe2`：`k15_phase2_detail_w[37:0]`

- `[23:0]`：TX `eq_data`；
- `[37:24]`：内部 `{exit_pending, request_pending,
  transition_tuple_valid, timeout_expired, last_accepted_valid, incoming_ec,
  legal_ts1, incoming_reject, proposal_content_matches, second_same_ts,
  consecutive_have, proposal_preset_sel, proposal_pending}`。

### 建议复测触发顺序

1. `ltssm=0x2a && debug[79] && debug[78]`：第一次 RX Adapt 请求；
2. `debug[63]==1`：真实 GT `RXEQ_DONE`；
3. `debug[88:86]==2`：已产生 proposal，等待对端反射；
4. `debug[94:89] != 0` 配合 `timeout_fallback=1`：超时后读取完整 sticky；
5. `debug[93]==1`（Phase2 `phase_done` sticky）或 `ltssm=0x2b`：Phase2 正常完成。

每次抓取均应保存 CSV、LTX、bit SHA256 和触发表达式。第一次和第四次
捕获最重要：前者定位 GT 命令响应，后者即使相隔 24 ms 也能凭 sticky
确定此前经过了哪些里程碑。

硬件脚本已提供对应的预定义触发模式，避免手工填写 118 bit mask：

```bash
export K14_BIT_PATH_OVERRIDE=/path/to/k14_recovery_speed_ila.bit
export K14_LTX_PATH_OVERRIDE=/path/to/k14_recovery_speed_ila.ltx
export K14_CAPTURE_DIR=/path/to/capture
export K14_ILA_TRIGGER_POS=1024

# 可选：phase2-request、rxeq-done、proposal-wait、phase2-done、
#       phase2-failed、fallback
export K15_PHASE2_TRIGGER_MODE=phase2-request
make k14-recovery-speed-hw-program-arm KU040_SERVER=localhost:3121
```

随后重启 Root Port，使用 `capture-wait` 或 `upload` 保存结果。后续触发只需
重新设置 `K15_PHASE2_TRIGGER_MODE` 并执行
`make k14-recovery-speed-hw-arm-only`，不必重复烧写 bit。也可以使用
`make k14-recovery-speed-hw-arm-capture-wait` 在设置触发后直接等待并保存。

## Phase2 专用 ILA 实测与根因

第一版诊断 bit：

- SHA256：`e513e5b1f6323349525b2e50f5afbfad3e348d42d366a5ecdf10a17736406e6a`；
- `WNS=-0.359 ns`、`WHS=0.004 ns`、DRC error=0；
- 该 bit 只用于诊断，不作为发布镜像。

`phase2-request` 捕获给出了完整的失败链：

1. 第一次 RX Adapt 被接受，`PHY_RXEQ_CTRL=10`、当前对端 preset=P7；
2. 约 9 拍后 GT 返回 `RXEQ_DONE=1 / ADAPT_DONE=0`，proposal 为 P4；
3. 对端约 210 拍后用两个合法 EC=10 TS1 接受 P4，`malformed=0`；
4. RTL 随即发出第二次 RX Adapt，`PHY_RXEQ_TXPRESET=P4`；
5. 但同一时刻 TX TS1 从 proposal P4 退回 Phase1 留下的旧 P7 请求；
6. 第二次 `RXEQ_DONE` 不再返回，executor 长驻 `OP_WAIT_RX`。

从重新烧写后的干净状态抓取 fallback：触发拍仍为 `LTSSM=0x2a`、
`operation_state=OP_WAIT_RX`、`eq_busy=1`、`PHY_RXEQ_CTRL=10`、
`PHY_RXEQ_DONE=0`；下一拍 LTSSM 才进入 `Recovery.Speed (0x12)`。此时 Phase2
累计 893982 个 250 MHz 周期，约 3.576 ms。单独触发 `phase_failed` 未命中，说明
是外层训练超时先终止 Phase2，而不是 EQ engine 自己完成或报错。

根因位于 `pcie_gen3_equalization_ctrl.sv`：proposal 被接受时仅更新了
`partner_preset` 和历史记录，却没有更新 `reflected_control/reflected_data`。
因此第二次 RX Adapt 的 PHY 参数和线上请求互相矛盾。修复是在接受点把 proposal
写回当前请求流，直到 GT 报 adaptation success。

定向 Verilator 用例已把初始 P7 与 proposal P6 分开，并明确检查第二次 RX Adapt
期间 TX 仍为 P6；`k15-static` 全部通过。K15 SVT Phase2 专项也通过并进入 Gen3
L0。原始 CSV/ILA/LTX 已归档到
`docs/debug/20260904_k15_phase2_rxeq_stall/`。

## P4 保持修复后的实板复验

修复后实现产物：

- bit SHA256：`6accf00ba9013952c86f76622033846a1f627732d12a90bb191cfc6f0a633691`；
- LTX SHA256：`5c87e09a1769423f8bba3795fa3d33419557ffaf5acb2016b8669d3653c8fced`；
- `WNS=-0.283 ns`、`WHS=+0.004 ns`、DRC error=0；
- 通过 `localhost:3121`、KU040 JTAG `210308AC5C97` 烧写；没有使用 XDMA bit。

`phase2-request` 逐拍复核结果：

1. 第一次 RX Adapt 以 P7 发起，GT 返回
   `RXEQ_DONE=1 / ADAPT_DONE=0 / proposal=P4`；
2. 对端用连续两个合法 EC=10/P4 TS1 确认 P4，RX parser 全程
   `malformed=0`；
3. 第二次 RX Adapt 以 `PHY_RXEQ_CTRL=2'b10 / TXPRESET=P4` 发起；
4. 修复后的 TX request 持续为 `0xa2`（Use Preset、P4、EC=10），没有退回
   旧 P7；
5. 但在余下 8192 点窗口内没有出现第二次 `RXEQ_DONE` 或
   `ADAPT_DONE`，控制器保持 `OP_WAIT_RX / eq_busy=1`。

重新进入 Phase2、清除本轮 sticky 后抓取的 `fallback` 显示：触发拍仍为
`LTSSM=0x2a`、`OP_WAIT_RX`、`PHY_RXEQ_CTRL=10/P4`、
`RXEQ_DONE=0 / ADAPT_DONE=0`，下一拍进入 `Recovery.Speed (0x12)`。
单独的 `phase2-done` 触发实际命中 Phase0 的 `phase_done`，捕获只包含
`0x28 -> 0x29`；精确 `LTSSM=0x2b` 未命中。远程主机没有枚举到
`01:00.0`。

该误触发来自旧脚本使用共享的 raw `phase_done`（`debug[81]`）。脚本现已改用
只在 Phase2 内锁存的 `phase_done` sticky（`debug[93]`）；`phase2-failed` 同理改用
Phase2 failure sticky（`debug[94]`）。

| 捕获 | SHA256 |
|---|---|
| `capture/phase2_request/20260904_192205_k14_recovery_speed.csv` | `d5704830b60b754a0d31539f9f96add4bcabb3e0e317e39b6ceb61f6084b7b64` |
| `capture/fallback/20260904_192433_k14_recovery_speed.csv` | `a24dbe6b6f256b195d51cc91d5ab400c8b32dd64c1f65c08cb79f618ba60ef03` |
| `capture/phase2_done/20260904_192634_k14_recovery_speed.csv` | `c80063dc0dfe7d1bc1609766f91837155cb3b80dc8dfcc6f86aa301a25c99150` |

本轮证据包为
`docs/debug/20260904_k15_phase2_rxeq_stall/k15_phase2_p4_hold_retest_raw.tar.gz`。

### 修正后的故障边界

P4 回退是一个真实 RTL 缺陷，当前修复已经由实板证明生效，但它不是 Phase2
不能完成的唯一原因。第二次 RXEQ 不返回只是 EP 侧 Xilinx PHY 接口的观测现象，
不能据此判定 Xilinx IP 故障。第一次 RXEQ 能正常给出 proposal，说明该接口和
适配引擎基本工作。

当前第一嫌疑仍是自研 EP 的 Phase2 控制语义，包括 proposal 被对端接受后的 TX
TS1 表达、第二次 RXEQ 的发起时机，以及
`pcie_gen3_equalization_ctrl -> pcie_phy_command_ctrl` 两阶段事务闭环。后续应在
保持 P4 修复的基础上做上述语义 A/B，不把主板或 Xilinx PHY IP 预设为根因。

## 24 ms EQ timeout 与 Phase3 实板复验

为验证 Phase2 时间预算，新增 `GEN3_EQ_TIMEOUT_CYCLES` 参数并透传到
`pcie_phy_command_ctrl.EQ_TIMEOUT_CYCLES`；Phase2 协议状态机未改动。构建同时
使用 `GEN3_SPEED_TIMEOUT_CYCLES=6000000`、`GEN3_EQ_TIMEOUT_CYCLES=6000000`，并将
构建脚本默认 `LTSSM_TX_RATE_ID` 修正为 `8'h0e`。

实现产物（KU040 `210308AC5C97`）：

- bit SHA256：`3303f2cbf89a23dfb03d839eddc7b9505309f7ff6961e9833f47065df52b5ebc`；
- LTX SHA256：`5c87e09a1769423f8bba3795fa3d33419557ffaf5acb2016b8669d3653c8fced`；
- `LTSSM_TX_RATE_ID=8'h0e`；
- 内外 timeout 均为 `6000000` cycles；
- DRC error=0，WNS/WHS=`-0.482/+0.004 ns`。

实板结果：

1. 第二次 RX Adapt 在 `2000243` 个 250 MHz 周期（约 `8.001 ms`）完成，Phase2
   sticky=`0x1f`，包含 `phase_done`，证明内部 4 ms EQ timeout 已不再提前截断。
2. 精确 `LTSSM=0x2b` 触发命中，Phase3 窗口内保持 `0x2b`；对端重复发送
   `EC=11` 系数请求 `control=0x23/data=0x802800`，本端同样保持 EC=11，未见
   `EC=00` 结束，随后远程主机仍未枚举 `01:00.0`。
3. 下一版诊断 bit 增加独立 54-bit probe，记录 `eq_req_coeff`、
   `phy_txeq_new_coeff`、`eq_rsp_coeff`，用于确认 GT 返回系数与本端反射系数是否
   不一致。

捕获文件位于构建目录
`fpga/kcu105/build_k15_eq_timeout24ms_20260904_0e/capture/`：

- `phase2_request/20260904_232447_k14_recovery_speed.csv`；
- `phase2_done/20260904_232848_k14_recovery_speed.csv`；
- `phase3/20260904_233123_k14_recovery_speed.csv`。
