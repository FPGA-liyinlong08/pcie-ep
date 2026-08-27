# K14 reboot Gen3 当前状态记录

日期：2026-08-27  
分支：`codex/k14-reboot-gen3`  
基线：`7b6899651ca231d8ecfd1c671d44b4ab70a0bf59`

## Git 状态

当前 `HEAD` 仍为基线提交。K14 RTL、VCS、Verilator、Makefile 和报告改动已经暂存，但此前提交因 `.git` 只读而失败。`.Xil/Vivado-3310202-wx-linux/` 是未跟踪的 Vivado 临时目录，不纳入提交。

## VCS 模型

完整板级 VCS 使用 XDMA v4.1 Xilinx Root Port 模型，源码来自：

`/home/wx/Documents/XDMA/xdma_dec_250922/imports`

RP 实例为 `pcie3_uscale_rp_top/core`，Endpoint 使用生产版 `pcie_phy_x1_gen3` PHY 模型，不是 behavioral stub。

## A/B 结论：初始 Rate ID

### `Rate ID=8'h02`

- Gen1 L0 建立；
- Endpoint 初始 TS 的 Rate ID 为 `02`；
- Root Port 原始 PIPE 发送端未观察到 Gen3 Speed Change TS1；
- `auto_retrain_pulse=0`、mailbox=0。

结果见 [k14_rate_id_02_simulate.log](../../sim/vcs/build/k14_rate_id_02_simulate.log)。

### `Rate ID=8'h0e`

- Root Port 在初始 Gen1 配置后自动发送 `Rate ID=8'h8e` Speed Change TS1；
- K14 真实接收并接受 partner request；
- K14 成功切换 `PHY_RATE=Gen3`；
- 该过程发生在稳定双方 Gen1 L0 之前，因此 `l0=0` 是正常观察结果，不代表 RP 不支持 Gen3。

结果见 [k14_rate_id_0e_simulate.log](../../sim/vcs/build/k14_rate_id_0e_simulate.log)。

结论：此前“RP 模型没有自动发起 Gen3”的判断不成立。`Rate ID=02` 隐藏了 K14 的 Gen3 能力，RP 因而没有协议依据发出自动 Speed Change；`Rate ID=0e` 时 RP 自动请求已被原始 PIPE 证据确认。

## 已完成 RTL 修改

- 新增 `pcie_partner_retrain_pending.sv`：partner request 锁存到 accept；重复 TS1 不重复创建事务；reset/PERST 清除并重新 arm。
- `LTSSM_TX_RATE_ID` 提升为顶层参数，默认仍为 `8'h02`，仅 VCS A/B 可 override。
- `peer_speed_ok` 收紧为 LTSSM 真正进入 Recovery.Idle 后才成立，避免第一批 Gen3 TS 过早宣告成功。
- fallback 先等待 LTSSM 进入 Recovery.Speed，再发 Gen1 PHY rate 请求，避免错过一次性的 `rate_op_done`。
- fallback 完成且 PHY 已为 Gen1 时，不再重复进入 Recovery.Speed。
- 增加 K14 partner pending/accept、Gen3 rate、PhyStatus、QPLL、timeout/fallback、auto/mailbox 观测信号。

## 已通过验证

`make k14-direct-sim` 已通过，包含：

- 真实 VCS + 生产 `pcie_phy_x1_gen3` PHY 模型；
- Verilator Recovery.Speed 回归；
- PHY command ownership 检查；
- pending/accept、重复请求抑制、reset re-arm；
- Gen3 PHY rate、fresh PhyStatus、QPLL lock；
- timeout 后 Gen1 fallback；
- `auto=0`、`mailbox=0`、`ts=0`。

`make k14-recovery-speed-test` 和带 `GEN3_RATE_CHANGE_ENABLE=1`、`K14_RATE_DEBUG=1` 的生产 lint 也已通过。

## Full reboot 结果

使用 VCS-only 诊断 override：

```text
K14_REBOOT_TX_RATE_ID=0e make k14-reboot-vcs
```

第一个 reboot epoch 已观察到完整链路：

```text
K14_PARTNER_REQUEST_ACCEPTED
K14_GEN3_PHY_RATE_SEEN
K14_GEN3_PHYSTATUS_SEEN
K14_TIMEOUT_FALLBACK_SEEN
K14_GEN1_FALLBACK_PHYSTATUS_SEEN
K14_REBOOT_EPOCH_PASS epoch=0
```

日志见 [k14_reboot_simulate.log](../../sim/vcs/build/k14_reboot_simulate.log)。

第二次 PERST 已释放，但尚未得到 `K14_REBOOT_EPOCH_PASS epoch=1`。第二轮 RP 进入反复 Detect/Configuration 重试，仿真被手动停止。因此“reset 后重新接收且每 epoch 仅一次 excursion”目前只在第一个 epoch 被证明，第二个 epoch 尚未闭环。

默认生产配置仍为 `Rate ID=02`，所以 `make k14-reboot-vcs` 在无人工配置、无 `setpci`、无 retrain task、无 force 条件下仍会以 `RP_AUTO_GEN3_REQUEST_MISSING` 停止；这反映的是初始能力声明边界，不是 K14 接收器漏包。

## 下一步

1. 恢复 `.git` 可写并提交当前暂存内容。
2. 专门处理第二个 PERST epoch 的 warm-reset 条件，确认 PHY/RP reset 完成、第二轮只出现一次 partner request，并使 `K14_REBOOT_VCS_PASS epochs=2` 通过。
3. 在 epoch 验证完成后，再决定生产默认初始能力是否应改为正确的 Gen3 capability advertisement。
