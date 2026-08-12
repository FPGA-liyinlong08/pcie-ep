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
