# B hardware validation — E1 function-only

验证日期：2026-08-26（Asia/Shanghai）

## Bitstream

- 配置：`K14_RECOVERY_SPEED=1`
- `PHASE_E1_FUNCTION_ONLY=1`
- `PHASE_E1_BOARD_DEBUG=0`
- `GEN3_AUTO_RETRAIN_CYCLES=0`
- `K14_PLACE_DIRECTIVE=ExtraTimingOpt`
- E1 recorder/probe2~5：关闭
- E1 reset buffer guard：未执行
- bit SHA256：`4c1b26be4c7e4bd969f3bba209723dd9f8faeefc73ed4c51da445b146b5212ba`

实现结果：WNS=`-0.062 ns`，WHS=`+0.004 ns`，DRC errors=`0`。

## Reboot link result

- Root Port：`2.5 GT/s x1`
- `Train-`
- `DLActive+`
- raw Link Status：`7011`
- Endpoint：`01:00.0 Device 1234:e001`
- Endpoint sysfs：`2.5 GT/s`，width `1`

结论：B 构建重启后 Gen1 枚举和链路状态 PASS。

## Repeated validation

按“烧写同一 bit → reboot → 稳定等待 → 采集”完成 10 次有效验证：

| 有效序号 | 原始运行号 | 结果 | Link Status |
|---:|---:|---|---|
| 1 | 1 | PASS | `7011`, `DLActive+` |
| 2 | 2 | PASS | `7011`, `DLActive+` |
| 3 | 5 | PASS | `7011`, `DLActive+` |
| 4 | 6 | FAIL | `5811`, `Train+`, `DLActive-` |
| 5 | 7 | FAIL | `d011`, `Train-`, `DLActive-` |
| 6 | 8 | PASS | `7011`, `DLActive+` |
| 7 | 9 | PASS | `7011`, `DLActive+` |
| 8 | 10 | PASS | `7011`, `DLActive+` |
| 9 | 11 | PASS | `7011`, `DLActive+` |
| 10 | 12 | PASS | `7011`, `DLActive+` |

有效结果：`8/10 PASS`，`2/10 FAIL`。运行号 3 为 SSH 重启竞态、运行号 4 为过早采集窗口，均未计入有效 10 次统计；原始日志仍保留。

原始记录：

- [`link_status_after_reboot.txt`](link_status_after_reboot.txt)
- [`lspci_full_after_reboot.txt`](lspci_full_after_reboot.txt)
