# Phase E1 实板隔离调试阶段报告

日期：2026-08-26
状态：**阶段记录完成；E1软件/仿真PASS，E1实板FAIL于一次性`malformed`；K14保持冻结**

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

- E1 build在Gen1 L0建立后产生一次语义retrain请求，避免热下载bit后一直停留在L0；
- 32-bit sticky记录保存PIPE、header、EIEOS、lock、TS和错误里程碑；
- 保留K14原`probe0=31`和`probe1=118`逐位顺序；
- 第二版只追加32-bit原始`phy_rxdata`和10-bit实时语义探针，可在
  `os_malformed=1`时抓触发前后block；
- E1同步core-reset网保持fabric routing，避免Vivado自动BUFG插入把异步恢复路径变成
  诊断版WNS限制；该约束不进入release build；
- E1诊断WNS门限经确认设为`-0.093 ns`；E2仍为`-0.060 ns`，release仍要求非负。

实现结果：

```text
PHASE_E1_BOARD_IMPL_PASS
K14_PLACE_DIRECTIVE=ExtraTimingOpt
GEN3_AUTO_RETRAIN_CYCLES=1
SETUP_TIMING_FLOOR=-0.093
WNS=+0.030 ns
WHS=+0.004 ns
DRC_ERROR_COUNT=0
probe widths=31/118/32/8/32/10, depth=8192
bit SHA256=681ebab7e4419416a60982a97240b2c1e4ade91429a0acb07900cd780e39a4a4
```

实际实现为正setup/hold裕量，没有使用允许的负裕量。

## 4. 实板证据

### 4.1 无自动retrain的基线快照

文件：`fpga/kcu105/build_phase_e1_board/capture/20260826_063023_phase_e1_board.csv`

```text
golden=0 elapsed=0 seen=0x000
gt_cdr=1 gt_resetdone=1 gt_rateidle=1 gt_datavalid=3
ltssm=Gen1 L0 active_rate=Gen1
```

结论：热下载后GT已经ready，但没有任何事件请求重训；这不是PIPE故障证据。随后加入
默认关闭、E1 build专用的一次语义retrain。

### 4.2 自动retrain与E1 hold有效trace

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

### 4.3 `malformed`精确触发复测

增强诊断bit在2026-08-26 07:21:58完成arm，条件为：

```text
active_rate=Gen3 AND os_malformed=1
trigger_position=2048
```

观察到07:23:55，约117秒内没有再次触发，手动结束等待，因此没有生成新的CSV。
这不证明首次脉冲无害，但说明它不是稳定RcvrLock阶段持续重复的错误；当前更可信的
定位是切速/首次block-lock窗口的一次性事件。由于没有原始触发block证据，本提交不
修改SKP、TS或scrambler解析逻辑。

## 5. 软件与静态门禁

提交前复验结果：

```text
PHASE_E_K14_RATE_GUARD_PASS
PHY_COMMAND_OWNERSHIP_PASS
K14_RECOVERY_SPEED_SEMANTIC_PASS
K03 lint PASS
K11-B2 lint PASS
PHASE_E1_TRACE_ANALYZER_SELFTEST_PASS
PHASE_E1 hold cocotb: TESTS=1 PASS=1 FAIL=0, 151.113 us
```

E1 hold用例明确检查：进入Gen3 RcvrLock后，即使出现E2 completion、malformed或timeout，
诊断build也保持在RcvrLock；同时raw rate输出仍由原K14路径产生，而非E1覆盖。

## 6. K14冻结证明

```text
rtl/phy/pcie_phy_command_ctrl.sv
  f16097555901f94c1ec04880d8c27c14cfecf874a8445c13b2fc879d4ed40c42
rtl/phy/pcie_recovery_speed_ctrl.sv
  105ca877c0dafd4d380c93b1dd10323837938efb98d3469a14125f60c4e11b84
```

两份哈希与K14冻结值一致；K14原ILA 31/118探针也保持不变。本轮所有新增行为均由
默认关闭的E1 generic限定。

## 7. 阶段结论与下一步

本轮已把阻塞从“Gen3 PIPE完全无有效接收”缩小为“首次建锁窗口出现一次
`malformed`”。E1仍未硬件签署，E2也不据此宣告实板通过。

下一步应先获得可重复的首次窗口抓取：让ILA在retrain之前arm，或提供可控的第二次
retrain，然后以原始四word block区分boundary error、非法Sync Header、坏TS和合法但
尚未支持的OS。根因修复后重新执行E1首次trace和20次重复门禁，再恢复E2同板20次
`Recovery.RcvrLock`验收。
