# K11-B5 G9 等待 Root Port 活动实板调试记录

日期：2026-08-12

本轮目标是在 KCU105 Endpoint 进入 PHY P1→P0 后暂不发送 TS1，等待 Root Port
RX 活动，以区分“Root Port 没有开始接收训练”与“Endpoint 过早发送/PHY 动态初始化”
两类问题。

## 1. 诊断构建

构建配置：

```text
part=xcku040-ffva1156-2-e
top=kcu105_pcie_ep_gen1_board_top
K11B2_ILA_DEBUG=1
G9_WAIT_REMOTE_DETECT=1
G9_WAIT_REMOTE_DETECT_CYCLES=6250000
ILA_PIPE_ONLY=1
```

Vivado 2021.2 实现结果：

```text
K11B3_ILA_IMPL_PASS
WNS=-0.121 ns
TIMING_POLICY=DIAGNOSTIC_ONLY_NEGATIVE_ALLOWED
```

这是专用于 ILA 取证的诊断 bit，不应作为正式量产配置。生成文件：

- bitstream：`fpga/kcu105/build_g9_wait_remote_detect_ila/impl/k11b2_gen1_endpoint_ila.bit`
- probes：`fpga/kcu105/build_g9_wait_remote_detect_ila/impl/k11b2_gen1_endpoint_ila.ltx`
- 构建摘要：`fpga/kcu105/build_g9_wait_remote_detect_ila/impl/summary.txt`

G9 控制探针 `dbg_g9_control[7:0]` 定义如下：

| 位 | 信号 |
|---:|---|
| 0 | RXELECIDLE |
| 1 | RXVALID |
| 2 | TXELECIDLE |
| 3 | TXDETECTRX |
| 4 | AS_MAC_IN_DETECT |
| 6:5 | PHY_POWERDOWN |
| 7 | 保留 |

## 2. 实板动作

1. 通过 Vivado Hardware Manager 连接本地 `hw_server`。
2. 将 G9 bit 烧写到唯一的 KCU105 `xcku040` 器件，下载成功并识别出 1 个 PIPE ILA。
3. 使用已确认的远端测试主机 `192.168.11.126` 执行一次 `sudo reboot`。
4. 远端主机恢复 SSH 后读取 Root Port 状态。
5. 重新下载并执行 `capture-g9-rxidle-wait`，上传 PIPE ILA 数据。

远端 Root Port 状态：

```text
LnkSta: Speed 2.5GT/s (downgraded), Width x1 (downgraded)
        TrErr- Train- SlotClk+ DLActive+
```

Linux 仍未枚举 `1234:e001` Endpoint。

## 3. ILA 结果

有效采样文件：

- CSV：`fpga/kcu105/build_g9_wait_remote_detect_ila/capture/20260812_151658_u_ila_pipe.csv`
- ILA：`fpga/kcu105/build_g9_wait_remote_detect_ila/capture/20260812_151658_u_ila_pipe.ila`

采样深度为 32768。触发条件为 `dbg_g9_rxelecidle_low_seen=1`。代表性采样值：

| 信号 | 值 | 含义 |
|---|---:|---|
| `dbg_g9_control` | `0x02` | RXELECIDLE=0、RXVALID=1、TXELECIDLE=0、P0 |
| `dbg_g9_active` | 0 | 已离开 G9 等待态 |
| `dbg_g9_rxelecidle_low_seen` | 1 | G9 窗口内观察到 Root Port RX 活动 |
| `dbg_g9_timeout_seen` | 0 | 未发生 G9 等待超时 |
| `pipe_rst_n` | 1 | PIPE 复位已释放 |
| `txresetdone/gtpowergood/qpll1lock` | `1/1/1` | GT 基础状态正常 |
| `pciesynctxsyncdone` | 1 | PCIe TX 同步完成 |
| `phy_txdata_valid` | 1 | Endpoint 正在提交发送数据 |
| `phy_txelecidle` | 0 | Endpoint 已离开 TX Electrical Idle |
| `rxresetdone/rxelecidle/rxvalid` | `1/0/1` | RX 已 ready 且收到有效活动 |
| `dbg_polling_tx_ts1_count` | `0x400` | TS1 发送计数达到 1024 |
| `dbg_pipe_top[32:27]` | `8` | LTSSM=`CFG_COMPLETE` |

## 4. 结论

本轮已经证明：

- Root Port 并非完全没有启动接收；Endpoint 在 G9 窗口内观察到了
  `RXELECIDLE` 拉低。
- G9 等待逻辑没有超时，且 Endpoint 后续进入 P0、接收有效数据并发送 TS1。
- GT TX reset、电源、QPLL 和 TX 同步状态均正常，故障不是“GT 一直未 ready”。
- Endpoint 可推进到 `CFG_COMPLETE`，但仍未进入 `L0`，远端 Linux 也未枚举 Endpoint。

因此，G9 已完成其诊断目的；当前故障范围应从“Root Port 是否产生 RX 活动”转移到
`CFG_COMPLETE → L0`、DLL 初始化/流控以及配置请求完成路径。后续应在不改变 G9
诊断结论的前提下，重新布防 CFG/DLL/Core ILA，重点抓取 Root Port 配置请求、
Completion、DLL Active 和 Endpoint 进入 L0 的最后窗口。

## 5. 相关实现与验证

- G9 RTL：`rtl/phy/pcie_ltssm_mac_gen1.sv`
- KCU105 顶层参数传递：`rtl/ep/kcu105_pcie_ep_gen1_top.sv`、
  `rtl/ep/kcu105_pcie_ep_gen1_board_top.sv`
- 实现脚本：`fpga/kcu105/run_k11b2_impl.tcl`
- 硬件 ILA 脚本：`fpga/kcu105/run_k11b2_ila_hw.tcl`
- 仿真验证：G9 positive path 与 timeout path 均通过；默认关闭配置的
  `normal_training` 也通过。
- 本记录及相关实现变更未保存远端主机密码。
