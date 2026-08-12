# KCU105 冷启动 Polling.Active 验证

日期：2026-08-12
工程：`pcie_ep_kcu105`
主机：`192.168.11.126`
目标：验证 Polling.Active 是否在发送至少 1024 个完整 TS1 前过早进入 Polling.Configuration。

## 修改内容

- `pcie_gen1_os_tx.sv` 增加完整 Ordered Set 完成事件 `os_complete`。
- `pcie_ltssm_mac_gen1.sv` 按完整 TS1 数量累计 TX 条件，并同时接受连续合法 TS1/TS2 作为 RX 条件。
- 只有 TX TS1 数量达到 1024 且 RX 连续训练条件达到 8 个时，才允许离开 `POLLING_ACTIVE`。
- 增加 `dbg_polling_tx_ts1_count` 调试信号。
- K11 ILA 深度临时扩展为 32768，覆盖 PHY 复位和 Polling.Active 窗口。

## 实板结果

### 第一次 32K PERST 触发采集

采集文件：`raw/20260812_114357_u_ila_pipe.csv`

- `rxresetdone`：sample 17410 释放。
- PHY `phystatus`：sample 23155 产生。
- `pipe_rst_n`：sample 23159 释放。
- 触发窗口在进入 Polling.Active 前结束，因此该次采集用于确认 PHY/PIPE 复位时序，不用于判断 TS1 门限。

### 第二次 DETECT_ACTIVE 触发采集

采集文件：`raw/20260812_114759_u_ila_pipe.csv`

| 事件 | sample |
|---|---:|
| 进入 `DETECT_ACTIVE` | 3072 |
| 进入 `PHY_POWERUP` | 3154 |
| 进入 `POLLING_ACTIVE` | 3292 |
| `polling_tx_ts1_count` 达到 1024 | 11484 |

从 `POLLING_ACTIVE` 到 1024 个 TS1 共 8192 个 125 MHz PIPE 周期，即 65.536 us，符合 Gen1/16-bit PIPE 的计算。

RX 结果：

- GT `rxresetdone`：全窗口有效；
- `rxelecidle`：全窗口为 1；
- `rxvalid`：0；
- RX TS1：0；RX TS2：0；
- LTSSM 保持 `POLLING_ACTIVE`，未进入 `POLLING_CONFIG`。

Root Port 重启后状态：

- `Speed 2.5GT/s (downgraded)`；
- `Width x1 (downgraded)`；
- `Train+`；
- `DLActive-`；
- AER 中 `DLP/TLP/RxErr/BadTLP/BadDLLP/Completion Timeout` 均未置位；
- Endpoint `1234:e001` 未枚举。

## 结论

本次修改在实板上生效，并排除了“TX TS1 少于 1024 导致 Polling.Active 过早结束”的假设。当前冷启动阻塞点是 Root Port 没有返回有效 TS1/TS2，Endpoint 因此停留在 `POLLING_ACTIVE`。后续应优先检查 Root Port 训练启动、电气连接、GT RX 电气状态以及双方 Detect/Recovery 时序，不再继续扩大 Polling.Active 修改范围。

## 原始文件校验

原始 ILA/bitstream 文件位于本目录 `raw/`，并已打包归档为：
`docs/debug/20260812_polling_active/20260812_polling_active_raw.tar.gz`。
校验和记录见同目录的 `SHA256SUMS`。原始二进制文件不纳入 Git，避免污染源码仓库。
