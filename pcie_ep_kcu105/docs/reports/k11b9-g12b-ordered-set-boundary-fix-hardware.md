# K11-B9 / G12-B Ordered Set boundary fix — hardware record

日期：2026-08-12  
目标板：KCU105，远端设备 `192.168.11.126`  以及时序：PCIe Gen1 x1

## 结论

G12-A 已确认 LTSSM 从 `CFG_LANENUM_ACCEPT` 切换到 `CFG_COMPLETE` 时，发送序列可能已经进入 TS1 的 `word_index=1`，而不是在完整 TS1 的 `word_index=7` 结束点切换。G12-B 增加 `cfg_complete_pending`，只有当前 TS1 的 `os_tx_complete=1` 时才允许进入 `CFG_COMPLETE` 并切换 TS2。

G12-B 在远端 reboot 后成功枚举：

```text
01:00.0 Unassigned class [ff00]: Device [1234:e001] (rev 01)
```

这次测试是主机 reboot 触发的 PCIe retraining，不等同于断电意义上的严格 cold boot。

## 软件/逻辑验证

- `make k11b2-lint K11B2_LINT_DEFINES=-GK11B2_ILA_DEBUG=1`：通过。
- `make k11b2-vcs-serial`：通过，包含 `K11B2_ENUM_PASS`、`K11B2_BAR_PASS`、`K11B2_VCS_REAL_PHY_PASS`。
- G12-B implementation：`K11B3_ILA_IMPL_PASS`。
- DRC：0 errors，4 warnings（ILA/调试核相关）。
- 最终 WNS：`-0.037 ns`；该 bit 为诊断版，使用 `DIAGNOSTIC_ONLY_NEGATIVE_ALLOWED` 策略。

Bitstream 和 probes：

```text
fpga/kcu105/build_g12_ordered_set_ila/impl/k11b2_gen1_endpoint_ila.bit
fpga/kcu105/build_g12_ordered_set_ila/impl/k11b2_gen1_endpoint_ila.ltx
```

## ILA 边界证据

采样文件：

```text
fpga/kcu105/build_g12_ordered_set_ila/capture/20260812_203648_u_ila_pipe.csv
```

`dbg_g12_tx` 编码为：低 6 位 LTSSM，`[7:6]` TX mode，`[8]` `os_tx_complete`，`[11:9]` raw word index，`[14:12]` active word index。

关键相邻采样：

```text
sample 382: state=7, mode=1(TS1), complete=0, word=6, active=6
sample 383: state=7, mode=1(TS1), complete=1, word=7, active=7
sample 384: state=8, mode=2(TS2), complete=0, word=0, active=0
sample 385: state=8, mode=2(TS2), complete=0, word=1, active=1
```

因此 G12-B 已把状态边界修正为：完整 TS1 的 `word=7 / complete=1` 之后，下一采样才进入 `CFG_COMPLETE` 并开始 TS2；不再出现 G12-A 中 `word=1 / complete=0` 时提前切换的现象。

## 备注

本次硬件结果证明 Ordered Set 边界修复已生效，并且 reboot 后端点可枚举。后续若要做严格 cold-boot 结论，还需对 KCU105 和 Root Port 做实际断电/上电测试，并单独记录电源时序。

## 第二次 reboot 复核

2026-08-12 21:21（Asia/Shanghai）再次对远端主机执行 reboot。SSH 恢复后 PCIe 仍成功枚举：

```text
01:00.0 Unassigned class [ff00]: Device [1234:e001] (rev 01)
```

该结果与前一次 reboot 一致，说明当前 G12-B bit 在连续两次 reboot/retraining 后均能保持端点枚举。BAR MMIO 访问仍需单独修复/验证：此前 `pci_bar_mmap_test` 读回 `0xffffffff`，因此不能把本次枚举成功等同于 BAR 访问成功。

## reboot 与 remove/rescan 的 BAR0 A/B 现象

连续 reboot 后，Linux 均能枚举 `01:00.0 1234:e001`，BAR0 分配为
`0x82800000`。Linux 初始 `Command=0000`；写成 `0006` 开启 Memory Space 与
Bus Master 后，第一次 BAR 测试出现如下结果：

```text
BAR_MMAP signature=50434945 version=00010000 link=00000a01 before=00000000 scratch=ffffffff ur=ffffffff ca=ffffffff axi=ffffffff
BAR_MMAP_FAIL
```

也就是说，最开始的只读寄存器和 scratch 初值能够正确返回；向 `BAR0+0x40`
执行一次 Posted Write 后，scratch 以及后续错误计数读均变为 `0xffffffff`。
Root Port 同期记录一个可纠正 Data Link Layer `Replay Number Rollover`：

```text
pcieport 0000:00:01.0: AER: Corrected error message received
pcieport 0000:00:01.0: PCIe Bus Error: severity=Corrected, type=Data Link Layer
[ 8] Rollover
```

不重新烧写 FPGA，仅执行下面的 Linux PCI 生命周期操作：

```text
echo 1 > /sys/bus/pci/devices/0000:01:00.0/remove
echo 1 > /sys/bus/pci/rescan
setpci -s 01:00.0 COMMAND.W=0006
```

端点重新枚举为相同的 `01:00.0 1234:e001`，随后同一个 C 程序通过：

```text
BAR_MMAP signature=50434945 version=00010000 link=00000a01 before=00000000 scratch=a5c37e19 ur=00000000 ca=00000000 axi=00000000
BAR_MMAP_PASS
```

因此 BAR0 地址译码、AXI-Lite slave 和 Completion 基本功能已由正常样本证明；
剩余问题集中在 reboot 首次枚举后的 DLL/事务状态生命周期。下一步对比 reboot
首次 BAR 事务和 remove/rescan 后同一事务的 RX sequence、ACK/NAK、Replay、FC
以及 Completion 发送状态。

### 后续复现修正

开始 DLL A/B 取证后，又执行了两次 reboot：一次在 BAR 测试前连接并 Arm ILA，
另一次完全不连接 JTAG、SSH 恢复后立即测试。两次均未执行 remove/rescan，且 BAR
测试都直接通过：

```text
BAR_MMAP signature=50434945 version=00010000 link=00000a01 before=00000000 scratch=a5c37e19 ur=00000000 ca=00000000 axi=00000000
BAR_MMAP_PASS
```

所以现阶段不能把 remove/rescan 认定为必需修复条件。更准确的描述是：曾出现一次
reboot 后可枚举、前几次 BAR read 正常，但一次 Posted Write 后后续 read 全为
`0xffffffff`；remove/rescan 后恢复，而后续 reboot 暂未复现。该故障具有偶发性，
也可能与烧写后首次主机生命周期、链路时序或 DLL Replay 状态有关。

正常 ILA 基线：

```text
capture/20260812_222938_u_ila_pipe.csv
FC_ACTIVE=1, replay_active=0, replay_fatal=0, replay_occupancy=0
next_tx_seq=1245, next_rx_seq=1247, last_acked_seq=1244
lcrc_error=0, sequence_error=0, NAK=0
```

另一个 reboot 后直接通过的样本为
`capture/20260812_223226_u_ila_pipe.csv`。下一步改为连续 reboot+BAR 压力复现；
若失败，保持现场不做 remove/rescan，立即抓取失败状态。

### 连续 reboot + BAR 压力结果

随后执行 3 轮连续 reboot。每轮 SSH 恢复后均先确认 `01:00.0 1234:e001`，设置
`Command=0006`，再连续执行 5 次 `pci_bar_mmap_test`。结果为：

```text
reboot: 3/3 枚举成功
BAR mmap: 15/15 PASS
signature=50434945
scratch=a5c37e19
ur=0, ca=0, axi=0
```

第 3 轮结束后，Root Port 当前启动周期的 `dmesg` 中没有新的 `PCIe Bus Error`、
`Rollover`、`BadDLLP` 或 `BadTLP`；Endpoint 保持 `Command=0006`、
`BAR0=0x82800000`。

因此尚未获得可重复的失败样本，不应在没有证据的情况下修改 DLL 功能逻辑。
当前动作是保留 `arm-rx-tlp` 无重烧抓取入口，等待下一次 BAR 失败时原地捕获；
失败前不执行 remove/rescan，以免清掉关键 DLL/配置生命周期状态。

## 无调试 release bit 验证

为排除 ILA/`mark_debug` 对资源、布局和时序的影响，先归档当前 G12 诊断版，再生成
保留 G9 `WAIT_REMOTE_DETECT` 和 G12 Ordered Set 边界修复、但设置
`K11B2_ILA_DEBUG=0` 的 release 版本。

诊断版归档：

```text
fpga/kcu105/archive/g12_debug_20260812_203305/
debug bit SHA256=c591953399c9ceb1ab33b7676a082bd258769ab107244959162a0fdb368790d7
debug ltx SHA256=79e3f09464b69e3a230c9550b47017495d38bfd01c439b4763f95acfc58d115d
```

Release 构建：

```text
fpga/kcu105/build_g12_ordered_set_release/impl/k11b2_gen1_endpoint.bit
SHA256=026b92b3d2c8586cc5e7809b3c8a0f4d2ff97349e8ea09ff803a9f2899117628
K11B2_IMPL_PASS
ILA_DEBUG=0
WNS=+0.019 ns
DRC=0 errors
```

Vivado Hardware Manager 在烧写后明确报告该设计没有 supported debug core。远端主机
reboot 后成功枚举：

```text
01:00.0 Unassigned class [ff00]: Device [1234:e001] (rev 01)
Command before enable=0000
BAR0=82800000
```

写 `Command=0006` 后连续执行 5 次 BAR mmap，结果 `5/5 PASS`；签名、版本和
scratch 均正确，UR/CA/AXI 错误计数均为 0。本次启动周期没有新增 `PCIe Bus
Error`、`Rollover`、`BadDLLP` 或 `BadTLP`。
