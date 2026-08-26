# Phase E1 实板隔离调试阶段报告

日期：2026-08-26
状态：**阶段记录完成；E1软件/仿真PASS，手动 Retrain bit 时序签署条件PASS；实板验收被当前 Root Port 不支持 Gen3 阻塞，K14保持冻结**

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

远端 Root Port 报告 `LnkCap: Speed 5GT/s`，每次轮询均为
`2.5 GT/s PCIe, width=1`，`Train-`；malformed 与 clean TS1 ILA 均未触发
（状态 `CORE_STATUS=IDLE`, `SAMPLE_COUNT=0`）。因此当前主机平台无法请求/完成
Gen3，不能用该平台生成 E1 clean trace，也不能把 20/20 重复计为通过。

同时修正 `scripts/remote_pcie_host.sh` 的 PCIe capability 偏移：Link Control 使用
`CAP_EXP+0c`，Link Control 2 使用 `CAP_EXP+2c`；此前的 `+10/+30` 分别不是这两个
寄存器，已避免后续硬件测试产生假阴性。

## 5. 软件与静态门禁

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

本轮已完成 E1 手动 Retrain 实现、时序签署和 Gen1 L0 保持验证；E1 仍未完成最终
硬件签署，原因是当前 Root Port 能力只有 5GT/s，无法产生 Gen3 clean TS1 trace。
因此 20/20 独立重复未执行，E2 不得进入。

下一步需要接入 Gen3-capable Root Port/主机（或提供等效 PCIe Gen3 retrain 环境），
重新执行 malformed 首次捕获、clean TS1 捕获及 20/20 门禁；在此之前保持 E1 阻塞，
不得进入 E2。
