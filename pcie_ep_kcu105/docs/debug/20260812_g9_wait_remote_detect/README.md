# G9：等待 Root Port Receiver Detect

G9 是一次性冷启动诊断配置，默认关闭。它在本端 Receiver Detect 成功、PHY 完成 P1→P0 后：

- 保持 `phy_powerdown=2'b00`；
- 保持 `phy_txelecidle=1`、`phy_txdetectrx=0`、不发送 TS1；
- 保持 `as_mac_in_detect=1`；
- 等待 `phy_rxelecidle` 从 `1` 变为 `0`。

默认等待 `6_250_000` 个 `phy_pclk` 周期：若时钟为 250 MHz 约 25 ms，若为 125 MHz 约 50 ms。可通过 `G9_WAIT_REMOTE_DETECT_CYCLES` 覆盖。

## 构建

```bash
cd /home/wx/Documents/PCIe/pcie_ep_kcu105/fpga/kcu105
K11B2_ILA_DEBUG=1 \
G9_WAIT_REMOTE_DETECT=1 \
G9_WAIT_REMOTE_DETECT_CYCLES=6250000 \
/home/Xilinx/Vivado/2021.2/bin/vivado -mode batch \
  -source run_k11b2_impl.tcl \
  -nojournal -log g9_wait_remote_detect_impl.log
```

G9 构建只生成 PIPE ILA，并增加 `dbg_g9_control`：

```text
bit 0       RXELECIDLE
bit 1       RXVALID
bit 2       TXELECIDLE
bit 3       TXDETECTRX
bit 4       AS_MAC_IN_DETECT
bit [6:5]   PHY_POWERDOWN
bit 7       reserved
```

## 上板观察

冷启动时使用硬件脚本的以下动作之一：

```bash
G9_WAIT_REMOTE_DETECT=1 \
vivado -mode batch -source run_k11b2_ila_hw.tcl \
  -tclargs localhost:3122 capture-g9-rxidle-wait
```

或者观察超时结果：

```bash
G9_WAIT_REMOTE_DETECT=1 \
vivado -mode batch -source run_k11b2_ila_hw.tcl \
  -tclargs localhost:3122 capture-g9-timeout-wait
```

判定只看两个锁存信号：

- `dbg_g9_rxelecidle_low_seen=1`：Root 已经产生 RX activity，继续查 termination/assist 时序；
- `dbg_g9_timeout_seen=1`：等待窗口内仍未观察到 Root activity，转入 XDMA 与 Standalone 的 GT/PHY 动态初始化对比。

G9 超时后 LTSSM 停在诊断状态，不会继续枚举；这是预期行为。正式配置不设置 `G9_WAIT_REMOTE_DETECT=1`，因此不受影响。
