# Phase E1 实板隔离调试阶段报告

日期：2026-08-26
状态：**AUTO=1 三次实板捕获均重锁通过；AUTO=0 Root-Port-only 对照已重跑并复现失败，K14保持冻结**

## 1. 本轮目标与边界

上一轮E2实板trace已经证明K14 Golden切速完成并进入Gen3
`Recovery.RcvrLock`，但当时没有观察到有效PIPE block。本轮把E1从E2语义控制中独立
出来，只回答以下问题：

1. Gen1→Gen3的冻结K14 rate transaction是否仍然成功；
2. GT/PCS是否向MAC输出`RxDataValid`、`RxStartBlock`和合法Sync Header；
3. E1 parser是否识别精确EIEOS、建立block lock并解析TS；
4. 是否出现结构失锁或`malformed`。

`PHASE_E1_BOARD_DEBUG`默认值为0。仅在诊断build中，它允许K14成功切速后把LTSSM
保持在Gen3 `Recovery.RcvrLock`并持续发送训练序列，同时抑制E2完成、失败和timeout
退出。它不产生或覆盖`PHY_RATE/POWERDOWN/TXELECIDLE/Detect Assist/CDR Hold`，
raw PHY命令仍只有K14 owner。

## 2. E1实板验收条件

单次E1 trace必须同时满足：

- K14 Golden rate记录通过，requested/active rate均为Gen3；
- 观察到`RxElecIdle=0`、`RxValid`、`RxDataValid`和`RxStartBlock`；
- 观察到Ordered-Set Sync Header、精确EIEOS和`block_locked=1`；
- 至少解析到一个TS1或TS2；
- `RXCDRLOCK=1`、`RXRESETDONE=1`且有效观察时间非零；
- 全窗口无`lock_lost`、无`malformed`。

首次trace通过后才执行同板20次重复门禁。本轮未通过首次trace，因此没有把重复测试
计为PASS，也没有放宽错误条件。

## 3. 诊断实现与保护

- E1 最终 build 关闭自动 retrain；仅由 Root Port 手动请求切速，避免热下载后自动改变速率；
- 32-bit sticky记录保存PIPE、header、EIEOS、lock、TS和错误里程碑；
- 保留K14原`probe0=31`和`probe1=118`逐位顺序；
- 第二版只追加32-bit原始`phy_rxdata`和10-bit实时语义探针，可在
  `os_malformed=1`时抓触发前后block；
- E1同步core-reset网保持fabric routing，避免Vivado自动BUFG插入把异步恢复路径变成
  诊断版WNS限制；该约束不进入release build；
- E1 诊断门限仍为`-0.093 ns`；最终硬件签署要求 WNS/WHS 均非负，E2 仍为`-0.060 ns`。

实现结果：

```text
PHASE_E1_BOARD_IMPL_PASS
K14_PLACE_DIRECTIVE=Explore
GEN3_AUTO_RETRAIN_CYCLES=0
SETUP_TIMING_FLOOR=-0.093
WNS=+0.033 ns
WHS=+0.004 ns
DRC_ERROR_COUNT=0
probe widths=31/118/32/8/32/10, depth=8192
bit SHA256=6682d212bac80f6e5edadd0f6c9e3e0bac8b0c6c40d6d63a3fd94f7ef559c589
```

实际实现为正setup/hold裕量，没有使用允许的负裕量。

## 4. 实板证据

### 4.1 无自动retrain的基线快照

文件：`fpga/kcu105/build_phase_e1_board/capture/20260826_103744_phase_e1_board.csv`

```text
golden=0 elapsed=0 seen=0x000
8192 samples: ltssm=ST_L0, k14_phy_rate_w=0, os_malformed=0
gt_cdr=1 gt_resetdone=1 gt_rateidle=1 gt_datavalid=3
```

结论：下载后连续采样保持 Gen1 L0/rate=0，没有自动切速；手动控制契约成立。

### 4.2 旧自动retrain诊断trace（非最终签署证据）

文件：`fpga/kcu105/build_phase_e1_board/capture/20260826_070811_phase_e1_board.csv`

```text
golden=1 elapsed=1048575 seen=0x9df
pipe=RxDataValid/RxStartBlock=1/1
headers=Ordered/Data=1/0
eieos=1 block_lock=1 ts1/ts2=1/0
lock_lost=0 malformed=1
RXCDRLOCK=1 RXRESETDONE=1
pass=0
```

该trace推翻了“切速后PIPE始终无有效数据”的旧假设：同板上已经收到合法block边界、
精确EIEOS并建立block lock，还成功解析到TS1。唯一未满足的E1条件是sticky
`malformed=1`。因为ILA在下载后才arm，此记录已经饱和，无法从该CSV判断错误发生在
首次EIEOS之前还是lock之后。

### 4.3 最终手动 retrain 复测

最终 bit 在 10:37～10:46 期间完成以下操作：

```text
program + ARM ILA before retrain
trigger_position=4096
malformed-only trigger, then clean os_ts1_valid trigger
./scripts/remote_pcie_host.sh retrain-gen3
```

本次用户提供的原始 `lspci -s 00:01.0 -vvx` 显示 Root Port
`LnkCap: Speed 32GT/s, Width x16`，并且 `LnkCtl2: Target Link Speed: 8GT/s`；
这确认插槽/上游端口具备 Gen3 能力。当前 `LnkSta=2.5GT/s x1`、`Train-` 只表示
链路仍停在 Gen1，不能视为端口能力限制。此前一次工具输出的 `5GT/s` 读数已判定为
异常/不可信，不再作为 E1 阻塞依据。malformed 与 clean TS1 尚未完成有效触发，
因此本次仍不能把 20/20 重复计为通过。

同时修正 `scripts/remote_pcie_host.sh` 的 PCIe capability 偏移：Link Control 使用
`CAP_EXP+10`，Link Control 2 使用 `CAP_EXP+30`；此前的 `+0c/+30` 组合把 Link Cap
误当成了 Link Control。为保持 Root-Port-directed retrain 隔离性，脚本已移除
Endpoint 侧 `CAP_EXP+10` Retrain Link 写入，只保留 Root Port 的 Gen1 normalize、
Gen3 target-speed 设置和 Root Port Retrain；并对 `CAP_EXP+30` 做 Gen3 readback 校验。

### 4.4 `GEN3_AUTO_RETRAIN_CYCLES` 单变量 A/B

为隔离自动切速与 Root-Port-directed Recovery 的上下文差异，重新生成了独立的
AUTO=1 诊断 bit。除该 generic 外，RTL、XCI、E1/K14 debug、ILA probes、约束和
`K14_PLACE_DIRECTIVE=Explore` 均保持一致；本次只让 endpoint 的 auto retrain 自己
发生，没有调用 `retrain-gen3`。下载后等待 2 s，再读取从复位开始工作的 sticky
`k14_event_record_w`，ILA 仅以 `k14_phy_rate_w==2` 作辅助触发。

AUTO=1 bit 实现摘要：

```text
PHASE_E1_BOARD_IMPL_PASS
GEN3_AUTO_RETRAIN_CYCLES=1
K14_PLACE_DIRECTIVE=Explore
WNS=+0.006 ns  WHS=+0.004 ns  DRC_ERROR_COUNT=0
probe widths=31/118/32/8/32/10, depth=8192
bit SHA256=05188e4b66aeace900bd0e119bbb8dc58c451ed1118a6d42f47888c0b6090d84
```

三次 AUTO=1 捕获均为 fresh recorder、完整 `valid=0x3b`，并通过现有 trace analyzer：

| 捕获文件 | QPLL fall | QPLL rise | PhyStatus | 最终状态 |
| --- | ---: | ---: | ---: | --- |
| `build_phase_e1_board_auto1/capture/20260826_122957_phase_e1_board.csv` | 10.044 us | 87.716 us | 127.520 us | rate2/lock1/RATEGEN3=1/USERGEN3RDY=1 |
| `build_phase_e1_board_auto1/capture/20260826_123053_phase_e1_board.csv` | 10.044 us | 88.020 us | 125.452 us | rate2/lock1/RATEGEN3=1/USERGEN3RDY=1 |
| `build_phase_e1_board_auto1/capture/20260826_123124_phase_e1_board.csv` | 10.044 us | 88.120 us | 124.424 us | rate2/lock1/RATEGEN3=1/USERGEN3RDY=1 |

新的 AUTO=0 Root-Port-only 对照为
`build_phase_e1_board/capture/20260826_125735_phase_e1_board.csv`：流程只写 Root Port
`CAP_EXP+30/+10`，并确认 `ROOT_PORT_GEN3_REQUEST_READBACK_PASS value=0003`，没有
写 Endpoint Retrain 位。该 trace 观察到 QPLL fall=10.044 us，但 `qpll_rise`、
`PhyStatus` 均未观察到，最终 `qpll_lock=0`、`RATEGEN3=0`、`USERGEN3RDY=0`
（`valid=0x11`）。旧文件 `20260826_114618` 仍保留为历史方向性证据，但不再作为
严格对照。

因此干净 A/B 现在支持如下结论：`GEN3_AUTO_RETRAIN_CYCLES=0` 没有改动 K14 raw
command bundle 或 Golden gap；在 Root-Port-directed Recovery 上下文中，切速时序仍
导致 QPLL 不重锁，而 endpoint 自主 AUTO=1 路径可稳定重锁。下一轮优先检查 Endpoint
收到 Root Port Recovery TS 后进入 `Recovery.Speed` 的时序，尤其是 RP 是否已停止
Gen1 signaling。该 A/B 仍不等同于最终 E1 签署：旧 AUTO=1 trace 的 `malformed=1`
尚需单独处理，20/20 门禁尚未执行。

## 5. Root-Port-directed Recovery 时序取证实现

为避免把诊断逻辑误混入 K14/E1/E2 功能路径，本轮新增了默认关闭的
`PHASE_E1_TIMING_DEBUG` recorder。它只观察 `partner_retrain_valid`、
`speed_retrain_accept`、LTSSM/RcvrLock/RcvrCfg、`ltssm_speed_ready`、K14
`RATE_RELEASE/GOLDEN_GAP/PHY_RATE`，以及最后的 Gen1 TS、RxElecIdle、
PCIERATEQPLLRESET/IDLE、QPLL lock 和 PhyStatus 边沿。

记录器内部仍保存 20-bit 时间戳，但通过 64-bit、20 行的 compact stream
送入 ILA；`phase_e1_timing_dump_active_w` 只在一次事务快照输出时触发，
因此不会再把 440-bit sticky 总线挂到关键路径。AUTO=0 没有 PHY 完成事件时
由超时快照结束，AUTO=1 则在 PhyStatus 或保护超时后结束。解析命令为：

```text
python3 scripts/analyze_phase_e1_timing_trace.py <capture.csv>
```

对应构建和硬件入口分别是
`make phase-e1-timing-auto0-board-vivado`、
`make phase-e1-timing-auto1-board-vivado` 和
`make phase-e1-timing-auto1-board-hw-capture`。当前仅完成 recorder 集成及
静态/lint 检查；尚未把新的 AUTO=1/AUTO=0 时序 CSV 作为根因结论写入报告。

## 6. 软件与静态门禁

提交前复验结果：

```text
PHASE_E_K14_RATE_GUARD_PASS
PHY_COMMAND_OWNERSHIP_PASS
K14_RECOVERY_SPEED_SEMANTIC_PASS
PHASE_E_GEN3_BLOCK_PASS (1000 randomized rate changes)
K03 lint PASS
K11-B2 lint PASS
PHASE_E1_TRACE_ANALYZER_SELFTEST_PASS
PHASE_E1 hold cocotb: TESTS=1 PASS=1 FAIL=0, 151.113 us
```

E1 hold用例明确检查：进入Gen3 RcvrLock后，即使出现E2 completion、malformed或timeout，
诊断build也保持在RcvrLock；同时raw rate输出仍由原K14路径产生，而非E1覆盖。

## 7. K14冻结证明

```text
rtl/phy/pcie_phy_command_ctrl.sv
  f16097555901f94c1ec04880d8c27c14cfecf874a8445c13b2fc879d4ed40c42
rtl/phy/pcie_recovery_speed_ctrl.sv
  105ca877c0dafd4d380c93b1dd10323837938efb98d3469a14125f60c4e11b84
```

两份哈希与K14冻结值一致；K14原ILA 31/118探针也保持不变。本轮所有新增行为均由
默认关闭的E1 generic限定。

## 8. 阶段结论与下一步

本轮已完成 E1 手动 Retrain 实现、时序签署、Gen1 L0 保持验证，以及干净的 AUTO=1/
AUTO=0 Root-Port-only 单变量 A/B。AUTO=1 三次均完成 QPLL relock，AUTO=0 严格对照
复现 QPLL lock failure；E1 仍未完成最终硬件签署，`malformed=1` 和 20/20 独立重复
仍待处理，E2 不得进入。

下一步基于已闭合的 A/B 检查 Endpoint 收到 Root Port Recovery TS 后进入
`Recovery.Speed` 的具体时序（特别是 RP 是否已停止 Gen1 signaling），再决定是否
需要 RTL 修复。确认修复后仍需重新完成 malformed 首次捕获、clean TS1 捕获及 20/20
门禁。
