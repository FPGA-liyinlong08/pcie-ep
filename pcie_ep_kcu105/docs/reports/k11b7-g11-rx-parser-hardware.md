# K11-B7 G11 原始 RX/Ordered-Set 实板调试记录

日期：2026-08-12

本轮针对 G10 暴露的 `CFG_COMPLETE` 阻塞点，增加从 PHY 原始输入到
`pcie_gen1_os_rx` 的逐级取证，区分 PHY 无数据、symbol 对齐/解扰错误和
Root Port 训练序列交接问题。

## 1. 诊断构建

构建配置：

```text
part=xcku040-ffva1156-2-e
top=kcu105_pcie_ep_gen1_board_top
K11B2_ILA_DEBUG=1
K11B2_ILA_PIPE_ONLY=1
G9_WAIT_REMOTE_DETECT=1
G11_RX_PARSER=1
G9_WAIT_REMOTE_DETECT_CYCLES=6250000
```

Vivado 2021.2 实现结果：

```text
K11B3_ILA_IMPL_PASS
WNS=+0.014 ns
failed/unrouted/partially_routed=0/0/0
DRC errors=0
```

G11 PIPE ILA 深度为 4096，新增 probe 17：

```text
dbg_g11_rx[127:0]
```

该总线从低位到高位包含：解析器脉冲、最终 aligned 数据、descrambled 数据、
raw aligned 数据以及 PHY 原始 `rxdata/rxdatak/rxvalid/rxstatus`。

## 2. 实板动作

1. 使用 Vivado 2023.1 Hardware Manager 和匹配版本的 `hw_server` 烧写 G11 bit。
2. 确认 `dbg_g10_counts`、`dbg_g10_fields`、`dbg_g10_state` 和
   `dbg_g11_rx` 全部被识别。
3. Arm `CFG_COMPLETE` 触发器。
4. 重启远端主机 `192.168.11.126`，等待 SSH 恢复。
5. 上传 ILA 数据并读取 Root Port 枚举状态。

有效采样文件：

- CSV：`fpga/kcu105/build_g11_rx_parser_ila/capture/20260812_174936_u_ila_pipe.csv`
- ILA：`fpga/kcu105/build_g11_rx_parser_ila/capture/20260812_174936_u_ila_pipe.ila`
- bitstream：`fpga/kcu105/build_g11_rx_parser_ila/impl/k11b2_gen1_endpoint_ila.bit`
- probes：`fpga/kcu105/build_g11_rx_parser_ila/impl/k11b2_gen1_endpoint_ila.ltx`

本次冷启动后远端 Linux 未枚举 `01:00.0` 端点，和 LTSSM 未进入 L0 的现象一致。

## 3. G11 采样结果

### 3.1 PHY 到解析器链路

4096 个采样点中：

| 信号/事件 | 计数 |
|---|---:|
| PHY `rxvalid=1` | 4096 |
| raw aligned valid | 4096 |
| descrambled valid | 4096 |
| final aligned valid | 4096 |
| `os_ts1_valid` | 487 |
| `os_ts2_valid` | 17 |
| `os_malformed` | 6 |

因此，PHY 有效数据持续到达，三级对齐/解扰链路也持续输出；问题不是
“RX 没数据”或“解析器完全没有输入”。

### 3.2 LTSSM 状态窗口

| LTSSM | 采样数 | TS1 | TS2 | malformed |
|---|---:|---:|---:|---:|
| POLLING_ACTIVE (2) | 1474 | 182 | 0 | 2 |
| POLLING_CONFIG (3) | 1260 | 147 | 8 | 2 |
| CFG_LINKWIDTH_START (4) | 80 | 1 | 9 | 0 |
| CFG_LINKWIDTH_ACCEPT (5) | 128 | 14 | 0 | 1 |
| CFG_LANENUM_WAIT (6) | 2 | 1 | 0 | 0 |
| CFG_LANENUM_ACCEPT (7) | 128 | 16 | 0 | 0 |
| CFG_COMPLETE (8) | 1024 | 126 | 0 | 1 |

最重要的结果是：端点在 `CFG_COMPLETE` 中实际收到了 126 个可识别 TS1，
没有收到任何 TS2。

### 3.3 端点 TX 取证

在 `CFG_COMPLETE` 的 1024 个采样点内：

- `tx_os_mode=2`，`os_tx_valid=1`；
- 发送序列重复为：

```text
COM + Link=0
Lane=0 + N_FTS=0xff
Rate=0x02 + TrainingControl=0x00
TS2 identifier=0x45 0x45
```

这与 RTL 中 `CFG_COMPLETE -> TS2` 的发送定义一致；端点并未误发 TS1。

### 3.4 Root Port RX 取证

在 `CFG_COMPLETE` 窗口，Root Port 返回的有序集被解析为 TS1。典型字段快照
包含 Link Number `0x1c`，并出现 Root Port 训练序列的 TS1 identifier
`0x4a 0x4a`。因此 Root Port 并非停止发送，而是没有接受当前交接状态并
继续发送 TS1。

## 4. 结论

G11 将故障范围进一步收窄：

- PHY RX 有效，`rxstatus=0`，symbol aligner 和 descrambler 有持续输出；
- `pcie_gen1_os_rx` 能识别 TS1 和 TS2，不能归因于解析器完全失效；
- 端点进入 `CFG_COMPLETE` 后确实发送合法 TS2；
- Root Port 在同一窗口继续发送 TS1，导致端点的 CFG_COMPLETE TS2 计数为 0，
  无法进入 `CFG_IDLE` 和 `L0`。

本轮没有直接修改 LTSSM 协议行为，因为现有证据首先需要解释 Root Port 的
TS1→TS2 交接条件。下一轮应做最小化 A/B，重点比较：

1. `N_FTS=0xff` 与从 Root Port TS1 捕获的 N_FTS；
2. TS1/TS2 的 `Rate ID`、`Training Control` 和 Link/Lane Number；
3. CFG_LANENUM_ACCEPT→CFG_COMPLETE 的状态切换时刻与 Root Port TS1/TS2 边界；
4. 在不改变正式训练逻辑的情况下，增加端点 TX TS2 字段可配置参数，验证 Root
   Port 是否因字段不匹配而持续回退 TS1。

## 5. 验证和提交范围

- Verilator 回归：`TESTS=12 PASS=12 FAIL=0`。
- RTL：`rtl/phy/pcie_ltssm_mac_gen1.sv`
- 实现脚本：`fpga/kcu105/run_k11b2_impl.tcl`
- 硬件脚本：`fpga/kcu105/run_k11b2_ila_hw.tcl`
- 本记录未保存远端主机密码。
