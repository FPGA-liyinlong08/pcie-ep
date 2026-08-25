# Phase E2：Gen3 Recovery.RcvrLock阶段报告

日期：2026-08-25
状态：**RTL/仿真/实现PASS；实板诊断BLOCKED于Gen3 PIPE无有效接收block**

## 1. 入口和K14保护边界

E2从Phase E0/E1提交`f27a0fc`继续，K14生产入口仍为`7b68996`。本阶段明确冻结
raw rate owner，不修改以下控制器：

```text
rtl/phy/pcie_phy_command_ctrl.sv
SHA256=f16097555901f94c1ec04880d8c27c14cfecf874a8445c13b2fc879d4ed40c42

rtl/phy/pcie_recovery_speed_ctrl.sv
SHA256=105ca877c0dafd4d380c93b1dd10323837938efb98d3469a14125f60c4e11b84
```

自动门禁同时固定三条生产接线：Gen3 `peer_speed_ok`必须来自E2完成脉冲，E2失败
必须进入`peer_speed_reject`，并且`speed_recovery_done = rate_op_success`保持K14原边界。

## 2. 实现

- 新增`pcie_gen3_rcvrlock_ctrl`，只消费E1解码事件，不接触raw PHY command；
- EIEOS建立block lock前禁止累计TS1；8个Link/Lane字段匹配的TS1后进入RcvrCfg；
- lock loss、malformed、提前TS2和字段不匹配产生确定性fallback请求；
- Gen3 RcvrLock timeout不再带着已提交的Gen3 active rate直接进入Detect，而是回到
  `Recovery.Speed`，由K14协调器执行Gen1 fallback；
- Gen1 RcvrLock和Gen1 fallback的既有TS1/TS2规则不变；
- K14 ILA继续使用原`probe0_width=31`、`probe1_width=118`，未把E2探针混入K14
  切速证据结构。

## 3. 验证结果

```text
PHASE_E_K14_RATE_GUARD_PASS
K14_RECOVERY_SPEED_SEMANTIC_PASS
PHASE_E2_RCVRLOCK_PASS randomized_contexts=1000
PHASE_E_GEN3_BLOCK_PASS randomized_rate_changes=1000
K03_VERILATOR_PASS trainings=100 packets=2000 seed=20260806
K03 cocotb: TESTS=16 PASS=16 FAIL=0
K11B2 lint: PASS
K11B2_DLL_ACTIVE_PASS
K11B2_CFG_CAP_PASS cap_ptr=40 max_speed=3 max_width=1
K11B2_ENUM_PASS bdf=01a0 bar0=80000000
K11B2_BAR_PASS signature=50434945 scratch=a5c37e19
K11B2_RANDOM_MMIO_PASS transactions=100 seed=1aceb00c
K11B2_BAD_LCRC_PASS lcrc=1 nak=1
K11B2_ACK_LOSS_PASS replay=1 occupancy=0
K11B2_PERST_RECOVERY_PASS vendor=e0011234 signature=50434945
K11B2_STRESS_PASS
K11B2_VCS_PASS
```

E2单元回归覆盖锁前TS、8 TS1完成、EIEOS保持锁、失锁、malformed、提前TS2、字段
不匹配和1000个随机上下文。K03新增三项生产边界集成用例，分别覆盖EIEOS/8 TS1、
StartBlock边界失锁fallback及timeout fallback。

## 4. K14实现复验与E2独立debug build

原`Default` placement尝试的最差路径位于既有Gen1 framer/scrambler到GT TXDATA，
结果为WNS -0.085 ns；E2与K14切速控制路径均不在负时序路径中。K14实验构建改用
`ExtraTimingOpt`并复用同一E2综合设计后通过：

```text
K14_RECOVERY_SPEED_IMPL_PASS
K14_PLACE_DIRECTIVE=ExtraTimingOpt
WNS=0.001
WHS=0.004
DRC_ERROR_COUNT=0
DEBUG_CORE_COUNT=2
bitstream_sha256=27596864131f59ae9fa5b64a56aa4416aedff426adb74314a4b297986828db78
```

`ExtraTimingOpt`只改变K14实验bitstream的布局策略；canonical Gen1构建路径、两份K14
控制器RTL、唯一raw owner和ILA探针宽度均未改变。

E2使用单独的`build_phase_e2_rcvrlock`目录和顶层generic。K14原有`probe0=31`、
`probe1=118`保持逐位不变；E2仅追加`probe2=14`语义状态和`probe3=8`原始PIPE状态，
采样深度8192。经用户明确允许，只有E2诊断构建的setup下限放宽到-0.060 ns；标准
K14和canonical构建仍要求WNS非负。最终诊断bitstream结果为：

```text
PHASE_E2_RCVRLOCK_IMPL_PASS
SETUP_TIMING_FLOOR=-0.06
WNS=-0.053
WHS=0.004
DRC_ERROR_COUNT=0
DEBUG_CORE_COUNT=2
programmed_bitstream_sha256=25bcc8d122ac469da4878c62ec4d90bbc5ed9589bd4fcbdbccab1f261536beeb
routed_dcp_replay_bitstream_sha256=83c8d4cea56e00afd1efc8e1f38ca6433d4c2ff514c0c67d65284e524b94202f
```

两次bit均由同一routed DCP生成；Vivado bit文件头包含生成时间，所以逐文件SHA不同。
上板trace对应`programmed_bitstream_sha256`，后一个SHA记录wrapper复验产物。

## 5. 实板诊断结果

Root Port可发现`1234:e001`，Endpoint最大能力为8.0 GT/s x1，当前链路为Gen1。以K14
Golden成功事件触发采样后，得到：

```text
capture=fpga/kcu105/build_phase_e2_rcvrlock/capture/20260825_231234_phase_e2_rcvrlock.csv
golden=1 complete_samples=0 max_ts1_count=0 rcvrlock=1 rcvrcfg=0
failed=0 fallback=0 rxdata_valid=0 rxstart=0 rxvalid=0
rxsync=[0] rxstatus=[0] rxelecidle=0 pass=0
```

该trace证明K14 raw rate transaction成功并进入Gen3 `Recovery.RcvrLock`，且接收端不在
electrical idle；但是Endpoint PIPE侧没有任何`RxDataValid`、`RxStartBlock`、`RxValid`
或非零`RxStatus`，因而E1无法建立block lock，E2也不可能收到EIEOS/TS1。该失败发生
在E2语义逻辑之前，未发现K14切速回归。

与官方XDMA x1生成源码的只读对照显示，两者关键GTHE3属性均为
`PCS_PCIE_EN=TRUE`、`RXSLIDE_MODE=PMA`、`RXBUF_EN=TRUE`，且Gen3 CDR配置一致；当前
证据不足以支持通过改这些静态GT属性解决问题。

## 6. 未完成边界

本报告不宣称E2硬件门、Gen3链路或Endpoint release完成。由于完成触发条件从未出现，
连续20次RcvrLock门禁没有执行，也未通过；不得进入E3签署。下一步应在不修改K14两个
raw控制器的前提下，继续诊断切速后的GT/PCS到PIPE接收状态、时钟与复位握手，直至
`RxDataValid/RxStartBlock`出现，再恢复E2连续20次验收。完成前canonical Gen1仍是
唯一生产release。
