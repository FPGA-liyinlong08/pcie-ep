# K11-B6 G10 CFG_COMPLETE 实板调试记录

日期：2026-08-12

本轮在保留 G9 `WAIT_REMOTE_DETECT` 基线的前提下，为
`CFG_COMPLETE -> CFG_IDLE -> L0` 增加 TS2 计数器、字段快照和状态锁存，生成
G10 ILA bit，烧写 KCU105，重启远端主机并回读 ILA。

## 1. 诊断构建

构建配置：

```text
part=xcku040-ffva1156-2-e
top=kcu105_pcie_ep_gen1_board_top
K11B2_ILA_DEBUG=1
K11B2_ILA_PIPE_ONLY=1
G9_WAIT_REMOTE_DETECT=1
G10_CFG_COMPLETE=1
G9_WAIT_REMOTE_DETECT_CYCLES=6250000
```

Vivado 2021.2 实现结果：

```text
K11B3_ILA_IMPL_PASS
WNS=-0.098 ns
failed/unrouted/partially_routed=0/0/0
DRC errors=0
```

这是专用于 ILA 取证的诊断 bit，负 WNS 仅用于本轮定位，不应作为正式量产
配置。初始 32768 深度因 BRAM 容量不足，改为 G10 专用 8192 深度后实现通过。

生成文件：

- bitstream：`fpga/kcu105/build_g10_cfg_complete_ila/impl/k11b2_gen1_endpoint_ila.bit`
- probes：`fpga/kcu105/build_g10_cfg_complete_ila/impl/k11b2_gen1_endpoint_ila.ltx`
- 构建摘要：`fpga/kcu105/build_g10_cfg_complete_ila/impl/summary.txt`

G10 PIPE ILA 新增 probe 14 `dbg_g10_counts[127:0]`、probe 15
`dbg_g10_fields[63:0]`、probe 16 `dbg_g10_state[31:0]`。

## 2. 实板动作

1. 通过 Vivado Hardware Manager 连接 `localhost:3122` 的 `hw_server`。
2. 将 G10 bit 烧写到唯一的 KCU105 `xcku040`，识别到 PIPE ILA 及 G10 三个新 probe。
3. Arm `CFG_COMPLETE` 触发器。
4. 对远端主机 `192.168.11.126` 执行一次重启；SSH 恢复后确认设备重新枚举。
5. 上传本次触发后的 PIPE ILA 数据。

远端重启后的 PCIe 状态：

```text
01:00.0 Unassigned class [ff00]: Device [1234:e001] (rev 01)
Root Port 00:01.0:
LnkSta: Speed 2.5GT/s (downgraded), Width x1 (downgraded)
        TrErr- Train- SlotClk+ DLActive+
```

端点已被 Root Port 枚举；测试镜像下 BAR 和 BusMaster 仍为 disabled，未加载端点
驱动，这不影响本轮 LTSSM 训练取证。

## 3. ILA 结果

有效采样文件：

- CSV：`fpga/kcu105/build_g10_cfg_complete_ila/capture/20260812_162054_u_ila_pipe.csv`
- ILA：`fpga/kcu105/build_g10_cfg_complete_ila/capture/20260812_162054_u_ila_pipe.ila`

采样深度为 8192，触发点为 sample 3072，触发条件为
`dbg_pipe_top[32:27] == CFG_COMPLETE (8)`。

### 3.1 G10 计数器

触发后的窗口内最终值：

| 字段 | 值 |
|---|---:|
| `TS2 any` | 0 |
| `TS2 match` | 0 |
| `TS2 mismatch` | 0 |
| `TS2 link PAD` | 0 |
| `TS2 lane PAD` | 0 |
| `TS2 link mismatch` | 0 |
| `TS2 lane mismatch` | 0 |
| `CFG_COMPLETE seen` | 1 |
| `CFG_IDLE seen` | 0 |
| `L0 seen` | 0 |

### 3.2 当前解码字段和状态

采样末值：

```text
dbg_g10_fields = 0x4afe11f00000f87c
dbg_g10_state  = 0x0900bc93
```

解码结果：

| 字段 | 值 |
|---|---:|
| `LTSSM state` | `CFG_COMPLETE (8)` |
| `state_timer` | `0xbc93` |
| `rx_ts_count` | 0 |
| `os_ts2_valid` | 0 |
| `os_ts1_valid` | 0 |
| `os_malformed` | 0 |
| `os_link_number` | `0x7c` |
| `os_lane_number` | `0x7c` |
| `os_link_is_pad` / `os_lane_is_pad` | `0 / 0` |
| `os_idle_pair_valid` | 1 |
| `phy_rxvalid` | 1 |
| `phy_rxelecidle` | 1 |

`state_timer` 从 `0x9c94` 增加到 `0xbc93`，说明端点在整个采样期间持续停留在
`CFG_COMPLETE`；没有观察到 `CFG_IDLE` 或 `L0` 锁存。

## 4. 结论和下一步

本轮确认：

- G9 结论保持不变：Root Port 已产生 RX 活动，GT/PIPE 基础状态正常。
- Root Port 在重启后链路保持 `DLActive+`，速率为 Gen1、宽度 x1，端点可重新枚举。
- 端点进入 `CFG_COMPLETE` 后，采样窗口内 `pcie_gen1_os_rx` 没有产生
  `os_ts2_valid`；因此 `rx_ts_count` 一直为 0，状态机无法转入 `CFG_IDLE`。
- 当前证据尚不能单独区分“Root Port 没有发送 TS2”和“RX ordered-set 解析/字节对齐
  没有识别 TS2”。不过 `phy_rxvalid=1` 且 `os_ts1_valid/os_ts2_valid=0`，下一轮应
  优先同时抓取原始 `phy_rxdata`、`phy_rxdatak`、`rxstatus`、symbol aligner 输出，
  验证 TS2 是否到达解析器及其字段对齐情况。
- 在 TS2 识别问题解决前，不继续修改 DLL/TLP/配置请求路径；当前阻塞点仍在
  `CFG_COMPLETE -> CFG_IDLE`。

## 5. 验证和相关实现

- 仿真回归：`TESTS=12 PASS=12 FAIL=0`。
- G10 RTL：`rtl/phy/pcie_ltssm_mac_gen1.sv`
- 实现脚本：`fpga/kcu105/run_k11b2_impl.tcl`
- 硬件 ILA 脚本：`fpga/kcu105/run_k11b2_ila_hw.tcl`
- 远端主机密码未写入源码、脚本或本记录。
