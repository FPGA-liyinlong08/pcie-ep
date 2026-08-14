# K13 验证基线冻结记录（2026-08-13）

本记录冻结本轮 RTL 验证开始时的工具、源码和远端状态，并追加记录本轮首个
诊断实现产物。工作区仍为未提交修改，bit/LTX 仅用于诊断，不构成正式发布门。

## 源码与工具

```text
HEAD=128b5ef2e1dd08c2b25870998eb7b17873202011
WORKTREE_DIFF_SHA256=c9d1cb3f7208a6e38a2c17f8298c08a7002ac605e19d3b5af1d438e58094c06c
Vivado=Vivado v2021.2 (64-bit), SW Build 3367213
K13_ENABLE=1（仿真及计划中的实现变体）
K13_RXEQ_BOOTSTRAP=0/1（本轮 A/B 参数）
```

历史诊断 bit/LTX 仅作为上一版参考：

```text
bit=fpga/kcu105/build_k13_gen3_ila/impl/k11b2_gen1_endpoint_ila.bit
bit_sha256=eea45005917eafa1e156eba9670dd45e2c005f4ec0d7363f3f16157c71db2664
ltx_sha256=21c9e87d426a30b9c1e0ce23f1eba14c594d1b4afa6acea75e36d2e2def30646c
```

本轮生成并成功写入 KU040 的 RXEQ-OFF 诊断 bit/LTX：

```text
build=fpga/kcu105/build_k13_gen3_ila_rxeq_off/impl
K13_ILA_IMPL_PASS
WNS=0.012
bit_sha256=30b0b16418ccea6d1c52045ed264868a06040958e80ad883653e839230d0e968
ltx_sha256=974d840380ff4721c588e11a68320a3e8281885641dea1a82c0d0e11db9d9e3b
K13_RXEQ_BOOTSTRAP=0
ILA_PROBE_K13_TOP_WIDTH=64
ILA_ARM=program-arm-k13-recovery
```

RXEQ-ON 对照 bit/LTX：

```text
build=fpga/kcu105/build_k13_gen3_ila/impl
K13_ILA_IMPL_PASS
WNS=-0.263
bit_sha256=7965e11c51fcfc1eca3ce2d415d49d5b231bf4ddf413b2454306a10bc386b423
ltx_sha256=6c2b97c3db2d83e01aeb8317f66d5d59fdf8ad0f4601ad6f34a210b932f2ba27
K13_RXEQ_BOOTSTRAP=1
ILA_PROBE_K13_TOP_WIDTH=64
ILA_ARM=program-arm-k13-recovery
```

本轮新增 GT rate-change 诊断探针后的 RXEQ-ON bit/LTX：

```text
build=fpga/kcu105/build_k13_gen3_ila/impl
K13_ILA_IMPL_PASS
WNS=-0.209（诊断构建，不能作为实现时序通过）
bit_sha256=f588f0c050b7d3dd8b09c8023c9db0688d1e6166df1401632a0324788b29469c
ltx_sha256=9213ec0e54f76c73b0d4682d2809f33e61fa72fd827a942697ab3adda68de3ac
新增探针=RATEGEN3、QPLL rate-reset/PD、RXRATE（x1共享QPLL实际为单bit）
ILA_ARM=program-arm-k13-recovery
```

## Root Port 快照

默认远端为 `wx@192.168.11.126`，目标 BDF 为 `01:00.0`。SSH 和远端主机可达：

```text
host=wx-ubuntu
kernel=5.15.0-139-generic
```

本次 `remote-lspci` 没有返回 `01:00.0` 设备，因此尚未取得新的完整 BDF、PCIe
capability offset 或 `lspci -vvv` 快照；不能把旧快照沿用为本轮基线。

## 当前门状态

- `K13_CTRL_AND_LTSSM_INTEGRATION_PASS`：当前 RTL 仿真成立；
- `K13_ILA_IMPL_PASS`：本轮 RXEQ-OFF 诊断 bit 已通过并写入 KU040；ILA 已成功绑定同目录 LTX 并完成 Recovery 触发设置；
- Gen1→Gen2 10 次冷启动/20 次 Retrain：未执行；
- Gen3 RXEQ Bootstrap ON/OFF 硬件 A/B：已完成各 1 次诊断重启，未达到重复性门槛；
- `K13_IMPL_PASS`、`K13_HW_GEN3_X1_PASS`、`K13_BAR_100K_PASS`、`K13_PASS`：未置位。

远端 Root Port 尚未重新枚举 `01:00.0`。受限免密重启规则已验证：`remote-cycle`
能够报告 `REMOTE_REBOOT_SENT` 并在约 34 秒后恢复 SSH；`01:00.0` 仍未枚举。

## 首次硬件 A/B 结果

远端已配置受限规则 `wx -> /usr/sbin/reboot` 的 `NOPASSWD`，并完成两次 Root Port
重启。两次 `lspci -s 01:00.0 -vvv` 均未发现 Endpoint。

RXEQ-OFF 波形：

```text
capture=fpga/kcu105/build_k13_gen3_ila_rxeq_off/capture/20260813_230743_u_ila_pipe.csv
LTSSM=Recovery.Speed(18)
TXELECIDLE=1（切速窗口持续）
TXEQ=ctrl=1,preset=4,done=1
phy_rate=Gen3(2)
PhyStatus=0
RX data_valid/start_block/sync_header=0/0/0
RXEQ ctrl/done/adapt_done=0/0/0
QPLL1 lock：Gen3切速后由1变0，采样结束前未恢复
```

RXEQ-ON 波形：

```text
capture=fpga/kcu105/build_k13_gen3_ila/capture/20260813_232207_u_ila_pipe.csv
LTSSM=Recovery.Speed(18)
TXELECIDLE=1（切速窗口持续）
TXEQ=ctrl=1,preset=4,done=1
phy_rate=Gen3(2)
PhyStatus=0
RX data_valid/start_block/sync_header=0/0/0
RXEQ ctrl/done/adapt_done=0/0/0
QPLL1 lock：Gen3切速后由1变0，采样结束前未恢复
```

结论：本次 ON/OFF 均在 `phy_rate=Gen3` 后、`PhyStatus` 之前失败，RXEQ 尚未被触发；
当前优先级上升为 QPLL1/GT Gen3 rate handshake 或 Gen3 CDR lock，不能归因于 early RXEQ。
由于 RXEQ-ON bit 的 WNS 为负，该结果只能作为诊断证据。

## GT rate-change 追加证据

```text
capture=fpga/kcu105/build_k13_gen3_ila/capture/20260813_234916_u_ila_pipe.csv
LTSSM=Recovery.Speed(18)，speed_state=Gen3等待(2)
phy_rate=Gen3(2)，GT RXRATE=Gen3(2)
pcierategen3_out=0（4096 samples 全程）
rx8b10ben_in=1（Gen3窗口仍保持8b/10b路径）
pcierateqpllreset_out=0 -> 1（sample 701）-> 0（sample 706）
pcierateqpllpd_out=0（全程）
QPLL1 lock：Gen3切速后由1变0，采样结束前未恢复
PhyStatus=0，RX data_valid/start_block/sync_header=0/0/0
```

这说明当前不只是“RXEQ 尚未启动”：`PHY_RATE/RXRATE` 已到 Gen3，
但 GT 的 `PCIERATEGEN3` 未置位，且 RX 仍处于 8b/10b 控制路径；QPLL reset
只出现约 6 个采样周期的脉冲，随后锁定没有恢复。下一步应优先核对生成 PHY
顶层对 `PCIEUSERRATEDONE`、`PCIEUSERRATESTART`、`PCIERATEIDLE` 和
`PCIEUSERGEN3RDY` 的连接/默认值，再做最小 GT rate-handshake A/B；暂不修改
DLL/TLP/BAR 或完整 EQ。

下一次上板前必须重新生成 bit/LTX，并在同一份记录中补充其 SHA256、Root Port
快照和 ILA 触发条件。

## PCIEUSERRATEDONE A/B 结果

本轮使用已成功生成并烧写的诊断 A 版本，将生成 PHY 中的
`GT_PCIEUSERRATEDONE` 从固定 0 改为固定 1；该版本仅用于定位，不是生产修复：

```text
build=fpga/kcu105/build_k13_gen3_ila_gt_rate_done1/impl
K13_ILA_IMPL_PASS
WNS=-0.070（诊断构建，不能作为实现时序通过）
K13_GT_RATE_DONE_TIE_HIGH=1
bit_sha256=58b683f783ea1643d15a73f243bebc8851fad9fd5839c3e2ef4bd4d7901e2bda
ltx_sha256=da4521493fe3fd0e225a81de6eb2ecffada50a53c33713d973af7eb1b6a290f6
capture=fpga/kcu105/build_k13_gen3_ila_gt_rate_done1/capture/20260814_003850_u_ila_pipe.csv
```

远端重启已成功触发采集。A 版与固定 0 对照的关键结果一致：

```text
LTSSM=Recovery.Speed(18)
phy_rate=Gen3(2)
pcierategen3_out=0（4096 samples 全程）
pcierateqpllreset_out=0 -> 1（sample 702）-> 0（sample 707）
pcierateqpllpd_out=0（全程）
QPLL1 lock：Gen3切速后由1变0，采样结束前未恢复
PhyStatus=0
RX data_valid/start_block/sync_header=0/0/0
RXEQ ctrl/done/adapt_done=0/0/0
```

结论：单独把 `PCIEUSERRATEDONE` 拉高不能修复当前故障，不能据此进入 RXEQ、
DLL/TLP/BAR 或最终 Gen3 验收。下一步应保留 `START/IDLE/GEN3RDY/DONE` 全套
GT rate handshake 观测，并核对生成 PHY/IP 配置是否把这些端口正确连接；当前
远端 `lspci` 仍未枚举 `01:00.0`。随后生成的完整 handshake 诊断 bit/LTX 已实际
进入 KU040 ILA；烧写时设备报告 PIPE/Core 两个 ILA，且 LTX 中包含
`QPLL1LOCK`、`PCIERATEIDLE`、`PCIEUSERGEN3RDY`、`PCIEUSERRATESTART`。

```text
bit_sha256=a3bbda2cf2f79028227cb5aa2b3ca1ba1da0a981a8c496b08530d4cadcdf19ad
ltx_sha256=99cab25e12c6296a92c45cd752f8011752a15d2a5cb0caa6f0cb49aecb39098a
capture_pipe=fpga/kcu105/build_k13_gen3_ila_gt_rate_done1/capture/20260814_072033_u_ila_pipe.csv
capture_core=fpga/kcu105/build_k13_gen3_ila_gt_rate_done1/capture/20260814_072033_u_ila_core.csv
remote_cycle=REMOTE_REBOOT_SENT; REMOTE_SSH_READY elapsed=34s
```

解码结果：

```text
LTSSM=Recovery.Speed(18)
PHY_RATE=Gen3(2)
PCIERATEIDLE: 1 -> 0 at sample 700
PCIERATEQPLLRESET: 0 -> 1 at sample 701 -> 0 at sample 706
QPLL1LOCK: 1 -> 0 at sample 701，采集结束前未恢复
PCIERATEGEN3=0（全程）
PCIEUSERGEN3RDY=0（全程）
PCIEUSERRATESTART=0（全程）
PCIERATEQPLLPD=0（全程）
PhyStatus=0
RX data_valid/start_block/sync_header=0/0/0
RXEQ ctrl/done/adapt_done=0/0/0
```

该结果将故障边界明确定位为 `Recovery.Speed → GT rate-change/QPLL`：切速窗口
已经开始，但 GT 没有进入 Gen3、QPLL 锁没有恢复，也没有产生 `PhyStatus`。
因此 RXEQ 尚未参与，暂缓 RXEQ A/B 重复门、DLL/TLP/BAR 和最终 Gen3 验收。
当前仓库的 `G2_GEN1_ONLY` 只是 Gen1/CPLL 对照入口，不足以宣称 Gen1→Gen2
隔离 PASS；需要真实 Gen2 限速配置后再执行该门。

## QPLL1 reset-forward 诊断 A/B（2026-08-14）

新增 `K13_GT_RATE_QPLL_RESET_FORWARD=1` 诊断变体，以排除
`PCIERATEQPLLRESET` 未进入活动 QPLL1RESET 的可能性。静态 routed-DCP 扇出核对确认：

```text
PCIERATEQPLLRESET[0] -> QPLL1RESET driver LUT I1
```

该版本成功生成并上板：

```text
build=fpga/kcu105/build_k13_gen3_ila_gt_qpllreset/impl
K13_ILA_IMPL_PASS
WNS=-0.129（诊断构建，不能作为实现时序通过）
bit_sha256=497008d1f7ec5603f1367c9242238ef88c870f101c3bdd856b2ff575d24fc60f
ltx_sha256=99cab25e12c6296a92c45cd752f8011752a15d2a5cb0caa6f0cb49aecb39098a
capture_pipe=fpga/kcu105/build_k13_gen3_ila_gt_qpllreset/capture/20260814_083316_u_ila_pipe.csv
capture_core=fpga/kcu105/build_k13_gen3_ila_gt_qpllreset/capture/20260814_083316_u_ila_core.csv
```

实板结果仍失败：`PCIERATEIDLE` 在 sample 700 释放，
`PCIERATEQPLLRESET` 在 701～706 拉高，`QPLL1LOCK` 在 701 由 1 变 0 且未恢复；
`PCIERATEGEN3`、`PCIEUSERGEN3RDY`、`PCIEUSERRATESTART`、`PhyStatus` 全程为 0，
LTSSM 停在 `Recovery.Speed (0x12)`。因此“rate reset 未扇出到 QPLL1”已排除为
唯一根因，下一嫌疑转为生成 PHY 中固定为 0 的 `GT_PCIEUSERRATEDONE` 及缺失的
`START/IDLE/GEN3RDY/DONE` 用户握手。RXEQ、DLL/TLP/BAR 和正式 Gen3 门继续冻结。
