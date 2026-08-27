# K14 reboot Gen3 当前状态记录

日期：2026-08-27  
分支：`codex/k14-reboot-gen3`  
基线：`7b6899651ca231d8ecfd1c671d44b4ab70a0bf59`

## Git 状态

当前分支已提交到 `265d1bf`（`k14: pass reboot epoch reset sequencing`），包含 warm-reset 时序与观测日志修改；`.Xil/Vivado-3310202-wx-linux/` 是 Vivado 临时目录，不纳入提交。

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

第二次 PERST 已释放，epoch1 现已完整闭环。第二轮同样观察到 RP 自动 `Rate ID=8'h8e` Speed Change TS1、K14 partner accept、Gen3 PHY/PhyStatus/QPLL、自然 timeout fallback、Gen1 PhyStatus，并输出 `K14_REBOOT_EPOCH_PASS epoch=1`。

本轮先将 K14 PERST 保持从 5 us 延长到 100 us；随后将 harness 改为独立的 RP `sys_rst_n` 与 Endpoint `PERST#`：两者同时拉低 100 us，先释放 Endpoint，额外等待 100 us 后释放 RP。该改动仍不注入 TS、配置写或 retrain 请求。独立复位时序已在真实 Xilinx RP/Endpoint PHY VCS 中通过两 epoch 验证。

最终日志中的关键结果：

```text
K14_REBOOT_EPOCH_PASS epoch=0 wait=35511
K14_REBOOT_EPOCH_PASS epoch=1 wait=35342
K14_REBOOT_VCS_PASS epochs=2
```

默认生产配置仍为 `Rate ID=02`，所以 `make k14-reboot-vcs` 在无人工配置、无 `setpci`、无 retrain task、无 force 条件下仍会以 `RP_AUTO_GEN3_REQUEST_MISSING` 停止；这反映的是初始能力声明边界，不是 K14 接收器漏包。

## 后续计划

1. 保持生产默认初始 Rate ID 为 `02`，不把诊断 override `0e` 混入生产构建。
2. 已生成一个独立的实验测试 bit（不覆盖旧 bit）：
   `fpga/kcu105/build_k14_recovery_speed_testbit/impl/k14_recovery_speed_ila.bit`
   配套 LTX、summary 和 SHA256 均在同一目录。该 bit 来自当前 reboot RTL 的 routed DCP，`WNS=-0.118 ns`，`WHS=0.004 ns`，`DRC_ERROR_COUNT=0`；summary 明确记录 `K14_ALLOW_TIMING_VIOLATION=1`，只能用于先行上板观察，不能作为时序通过版本。
3. 另已按要求生成精确对应 `WNS=-0.090 ns` 的独立实验 bit：
   `fpga/kcu105/build_k14_recovery_speed_testbit_wm090/impl/k14_recovery_speed_ila.bit`
   SHA256=`60de9504b1dca9ffc93deb2d143ef6f730180b9a0d806cf1f612e788ced7e975`；LTX、summary 和报告均在同一目录，仍明确标记 `K14_ALLOW_TIMING_VIOLATION=1`。
4. 旧 bit 仍保持原文件和校验：
   `build_k14_recovery_speed/impl/k14_recovery_speed_ila.bit`，SHA256=`27596864131f59ae9fa5b64a56aa4416aedff426adb74314a4b297986828db78`。
5. 如继续做实板验证，烧写上述独立实验 bit 后 ARM ILA，再由远端执行 `sudo reboot`；全程禁止 `setpci`。
6. 实板必须单独记录 RP 自动 Gen3 TS1、Gen3 PHY 成功、自然 fallback 和最终 Gen1 枚举；若没有 RP 自动 TS1，不能仅凭最终 Gen1 枚举判定 PASS。

## 实板前置状态

已用新 bit/LTX 对 `localhost:3122` 做硬件管理器只读连接检查；当前 `hw_server` 不可连接，因此尚未烧写 FPGA，板上状态没有被改变。启动本机 hw_server 或指定实际服务器地址后再执行 `program-arm`。

## 实板 reboot epoch 记录

本轮已使用 `build_k14_recovery_speed_testbit_wm090` 独立 bit 烧写并 ARM ILA，通过 `localhost:3121` 连接目标；随后在 `192.168.11.126` 执行了免密 `sudo reboot`。远端恢复后 K14 endpoint 重新枚举，sysfs 读数为 `current_link_speed=2.5 GT/s PCIe`、`current_link_width=1`。

本轮 ILA 触发 `k14_event_state_w==8` 未命中，没有观察到 Gen3 excursion 证据，因此不能记为 Gen3 reboot PASS。该 bit 保持生产默认 `Rate ID=0x02`，与 VCS 中使用 `0x0e` 的自动请求诊断 override 不同。

## 追加硬件对照（2026-08-27）

为区分“RP 未发请求”和“K14 收到但后续失败”，新增了独立的 `0x02 + partner-request ILA` bit：

`fpga/kcu105/build_k14_recovery_speed_hw02_probe_fixed/impl/k14_recovery_speed_ila.bit`

该 bit 的 summary 为 `LTSSM_TX_RATE_ID=8'h02`、`WNS=0.005 ns`、`WHS=0.004 ns`、`DRC_ERROR_COUNT=0`，SHA256 为：

`a94e2f0a52a00138efede9926580a1b5e8d885e4d9779efd56c191e24fcb0769`

扩展 ILA 直接包含 `k14_rp_gen3_request_seen_w`、partner pending/accept、Gen3 rate success、timeout/fallback、Gen1 fallback success、`auto_retrain` 和 mailbox valid。该 bit 上板后执行完整 `sudo reboot`：Endpoint 约 10 秒后出现并枚举为 `01:00.0 [1234:e001]`，最终 Root Port 为 `2.5 GT/s x1`；以 `k14_rp_gen3_request_seen_w=1` 为触发重新 ARM 后，ILA 报告 `No data to upload`，因此本次 reboot 未观察到 RP 自动 Gen3 speed-change 请求，也不能记为 Gen3 reboot PASS。

为对照，独立 `0x0e` bit：

`fpga/kcu105/build_k14_recovery_speed_hw0e_fixed/impl/k14_recovery_speed_ila.bit`

summary 明确为 `LTSSM_TX_RATE_ID=8'h0e`、`WNS=0.002 ns`、`WHS=0.004 ns`、`DRC_ERROR_COUNT=0`，SHA256 为 `8bb4dd3270aa8a35449ccc9ac1af7d02fb7003b15c186b477e609da78ba5c8f3`。该 bit 的 ILA 捕获到 `event_state=8`，事件记录 `valid=0x3f`，含 QPLL fall/rise/re-loss、PhyStatus、Gen3 wait/done；但由于 `0x0e` 被用于初始训练，实板最终未重新枚举 Endpoint，并出现 Root Port RxErr。它只能作为诊断证据，不能作为生产初始值。

## VCS 与上板是否一致

- VCS `K14_REBOOT_TX_RATE_ID=0e`：真实 XDMA/Xilinx RP 自动发出 `Rate ID=8'h8e` Speed Change TS1，K14 接收/accept，完成 Gen3 PHY/PhyStatus/QPLL，timeout 后回 Gen1；两 epoch PASS。
- VCS `K14_REBOOT_TX_RATE_ID=02`：初始 Gen1 L0 建立后等待 250000 周期，输出 `RP_AUTO_GEN3_REQUEST_MISSING ... auto=0 mailbox=0` 并失败。
- 实板 `0x02`：Endpoint 最终可枚举为 Gen1 x1，直接 RP-request 触发无数据；与 VCS 的“没有自动 Gen3 request”一致。
- 实板 `0x0e`：可观察到 Gen3 PHY 相关事件，但初始训练被破坏，Endpoint 未稳定枚举；这与 VCS 中 `0x0e` 仅作为能力/诊断 override、而不是生产初始训练值的边界一致，不能把两者当成同一测试条件。

当前结论是：VCS 与实板在 `0x02` 的关键差异不是 Root Port 模型能力，而是实板初始 `Rate ID=02` 没有声明可供 RP 使用的 Gen3 capability，因此 RP 没有协议依据自动发起 Speed Change；`0x0e` 实板实验改变了初始训练条件，不能用来证明生产 reboot 流程已经完成 Gen3 excursion。
