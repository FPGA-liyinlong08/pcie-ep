# Phase E2：Gen3 Recovery.RcvrLock阶段报告

日期：2026-08-25
状态：**RTL、仿真与K14实现复验PASS；实板连续20次门禁待实施**

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

## 4. K14实现复验

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

## 5. 未完成边界

本报告不宣称E2硬件门、Gen3链路或Endpoint release完成。下一步需要建立单独E2 debug
build，观察语义状态、block lock与TS1计数，并在真实Root Port同板连续20次到达
RcvrLock终点；同时确认无重复rate transaction、QPLL reloss或raw owner毛刺。完成前
canonical Gen1仍是唯一生产release，也不得进入E3签署。
