# K15 Phase2 第二次 RXEQ 停滞原始取证

本目录保存 2026-09-04 在 KU040 `210308AC5C97` 上取得的关键原始数据。
测试镜像为只增加观察逻辑的 Phase2 诊断 bit；没有使用 XDMA bit。

归档文件 `k15_phase2_rxeq_stall_raw.tar.gz` 包含：

- `20260904_183040_k14_recovery_speed.csv/.ila`：首次 Phase2 RX Adapt 请求触发；
- `20260904_183840_k14_recovery_speed.csv/.ila`：从重新烧写后的干净状态触发外层 fallback；
- 与捕获匹配的 `.ltx` 和实现 `summary.txt`。

诊断 bit SHA256：
`e513e5b1f6323349525b2e50f5afbfad3e348d42d366a5ecdf10a17736406e6a`。
该实现 `WNS=-0.359 ns`、`WHS=0.004 ns`，仅用于诊断。

第一份捕获证明：

1. Phase2 第一次 `RX_ADAPT` 被接受，`PHY_RXEQ_CTRL=2'b10`、preset=P7；
2. GT 返回 `RXEQ_DONE=1 / ADAPT_DONE=0`，给出 preset proposal P4；
3. 对端用两个合法 EC=10 TS1 接受并反射 P4，RX parser 无 malformed；
4. 接受后第二次 `RX_ADAPT` 以 preset=P4 发出，但 wire TX 请求立即退回旧 P7；
5. 第二个 `RXEQ_DONE` 在剩余 8192 点窗口内没有出现，控制器停在 `OP_WAIT_RX`。

第二份捕获证明：外层 fallback 触发时，LTSSM 仍为 `0x2a`，EQ executor
仍为 busy、`PHY_RXEQ_CTRL=2'b10`、`PHY_RXEQ_DONE=0`；下一拍才进入
`Recovery.Speed (0x12)`。Phase2 已累计 893982 个 250 MHz 周期，约 3.576 ms。

根因是接受 proposal 后没有把新的请求写回 `reflected_control/data`：PHY 被要求
适配 P4，而线上同时把对端请求回旧 P7。修复后在第二次 RX Adapt 期间继续发送已
接受的 P4 请求。

## P4 保持修复后的复验

`k15_phase2_p4_hold_retest_raw.tar.gz` 保存修复后 bit 的三组捕获、匹配的 LTX
和实现摘要：

- `phase2_request/20260904_192205_*`：证明第一次 proposal/接受完成，第二次
  RX Adapt 为 P4，TX request 持续 P4、不再退回 P7；
- `fallback/20260904_192433_*`：证明第二次 RX Adapt 长驻
  `OP_WAIT_RX / RXEQ_CTRL=10/P4`，未收到第二次 DONE，随后外层 fallback；
- `phase2_done/20260904_192634_*`：证明旧 `phase2-done` 触发条件会命中
  Phase0 的 `phase_done`（`0x28 -> 0x29`），不能作为进入 Phase3 的证据；
  后续脚本已改为触发 Phase2-gated `phase_done` sticky。

修复后 bit SHA256：
`6accf00ba9013952c86f76622033846a1f627732d12a90bb191cfc6f0a633691`；
LTX SHA256：
`5c87e09a1769423f8bba3795fa3d33419557ffaf5acb2016b8669d3653c8fced`。

结论：P4 回退修复有效，但第二次 RX Adapt 仍没有形成完成闭环。当前优先检查
自研 EP 的 Phase2 TS/PHY 命令语义，不能把边界现象直接归因于 Xilinx PHY IP。

解码命令：

```bash
tar -xzf docs/debug/20260904_k15_phase2_rxeq_stall/k15_phase2_rxeq_stall_raw.tar.gz -C /tmp
python3 scripts/decode_k15_phase2_ila.py /tmp/capture/20260904_183040_k14_recovery_speed.csv
```
