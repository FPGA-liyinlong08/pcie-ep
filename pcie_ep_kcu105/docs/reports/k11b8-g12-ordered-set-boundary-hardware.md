# K11-B8 G12 Ordered Set 边界实板调试记录

日期：2026-08-12

## 1. 目标

G12-A 只增加诊断，不修改 LTSSM 行为，验证：

```text
CFG_LANENUM_ACCEPT -> CFG_COMPLETE
```

是否发生在完整 TS1 Ordered Set 边界。

G12 ILA probe `dbg_g12_tx[31:0]` 编码如下：

| 位段 | 内容 |
|---|---|
| `[5:0]` | LTSSM state |
| `[7:6]` | TX mode，1=TS1，2=TS2 |
| `[8]` | `os_tx_complete` |
| `[11:9]` | 原始 `word_index` |
| `[14:12]` | 实际输出 `active_word_index` |
| `[15]` | `os_tx_valid` |

## 2. 构建和硬件动作

- G12 build variant：`build_g12_ordered_set_ila`
- bitstream：`fpga/kcu105/build_g12_ordered_set_ila/impl/k11b2_gen1_endpoint_ila.bit`
- probes：`fpga/kcu105/build_g12_ordered_set_ila/impl/k11b2_gen1_endpoint_ila.ltx`
- 实现：Vivado 2021.2，`K11B3_ILA_IMPL_PASS`
- WNS：`+0.001 ns`
- 目标器件：`xcku040-ffva1156-2-e`
- 远端动作：两次 Linux `sudo reboot`

这里的 reboot 是主机重启触发 PCIe 重训练，不等同于整机断电上电冷启动。

两次 reboot 后远端均出现：

```text
01:00.0 Unassigned class [ff00]: Device [1234:e001] (rev 01)
```

该枚举结果仅说明本次重训练成功，不作为 G12-A 边界判定依据。

## 3. ILA 结果

边界触发采样：

- CSV：`fpga/kcu105/build_g12_ordered_set_ila/capture/20260812_201926_u_ila_pipe.csv`
- ILA：`fpga/kcu105/build_g12_ordered_set_ila/capture/20260812_201926_u_ila_pipe.ila`
- 状态计数：`CFG_LINKWIDTH_START=46`、`CFG_LINKWIDTH_ACCEPT=80`、`CFG_LANENUM_WAIT=2`、`CFG_LANENUM_ACCEPT=128`、`CFG_COMPLETE=3712`

状态转换：

```text
sample 256: CFG_LANENUM_WAIT(6) -> CFG_LANENUM_ACCEPT(7)
sample 384: CFG_LANENUM_ACCEPT(7) -> CFG_COMPLETE(8)
```

转换附近的 TX 取证：

| sample | LTSSM | mode | complete | word | active word |
|---:|---:|---:|---:|---:|---:|
| 380 | 7 | TS1 | 0 | 6 | 6 |
| 381 | 7 | TS1 | 1 | 7 | 7 |
| 382 | 7 | TS1 | 0 | 0 | 0 |
| 383 | 7 | TS1 | 0 | 1 | 1 |
| 384 | 8 | TS2 | 0 | 2 | 0 |
| 385 | 8 | TS2 | 0 | 1 | 1 |

## 4. 结论

G12-A **确认 Ordered Set 边界问题存在**：

- 最近一次完整 TS1 在 sample 381 完成；
- 随后 sample 382、383 已开始发送下一枚 TS1；
- 状态在 sample 384 切换到 `CFG_COMPLETE`，TX mode 同时切换为 TS2；
- 因此线路上的 Ordered Set 形成了 TS1 的前两个 word 后接 TS2 word0，状态切换发生在 Ordered Set 中间。

这与 Root Port 仍持续发送 TS1、端点进入 `CFG_COMPLETE` 后无法稳定进入 `CFG_IDLE/L0` 的现象一致；本轮证据证明了发送边界风险，但不单独证明 Root Port 的全部行为仅由这一项造成。

## 5. 下一步

进入 G12-B，只修改 `CFG_LANENUM_ACCEPT -> CFG_COMPLETE` 这一处状态推进：

1. RX 条件满足时置 `cfg_complete_pending`；
2. 等待当前 TS1 完整发送，即 `os_tx_complete=1`；
3. 再进入 `CFG_COMPLETE`；
4. 重新执行 bit、ILA 和 reboot 验证。

本轮不修改 PHY、RX parser、DLL/TLP 或 N_FTS。
