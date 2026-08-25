# Phase E0/E1：Gen3 Block与Ordered Set阶段报告

日期：2026-08-25
状态：**E0 PASS；E1软件/仿真门禁 PASS；E2实板门禁未开始**

## 1. E0入口复验

起点固定为：

```text
commit=7b68996
branch=codex_phy_rate
canonical_gen1_sha256=1489516e07a8d75b30992a1589805306d2b0e3f4a447bc3ec14e708f3605ee70
GEN3_RATE_CHANGE_ENABLE=0
K14_RATE_DEBUG=0
```

K14提交`7b68996`已包含Phase D成果：canonical Gen1无ILA实现、3轮reboot/15次
MMIO/AER=0、D3/D4 10次有效Gen3 PHY切速和完整报告。本轮在修改E1前重新执行：

```text
PHY_COMMAND_OWNERSHIP_NEGATIVE_FIXTURE_PASS
PHY_COMMAND_OWNERSHIP_PASS
PHY_COMMAND_CTRL_EQUIVALENCE_PASS
PHY_COMMAND_CTRL_GOLDEN_RATE_PASS
K14_RECOVERY_SPEED_SEMANTIC_PASS
K03_VERILATOR_PASS trainings=100 packets=2000 seed=20260806
K11B2_DLL_ACTIVE_PASS
K11B2_ENUM_PASS
K11B2_BAR_PASS signature=50434945 scratch=a5c37e19
K11B2_RANDOM_MMIO_PASS transactions=100 seed=1aceb00c
K11B2_BAD_LCRC_PASS lcrc=1 nak=1
K11B2_ACK_LOSS_PASS replay=1 occupancy=0
K11B2_PERST_RECOVERY_PASS vendor=e0011234 signature=50434945
K11B2_STRESS_PASS
K11B2_VCS_REAL_PHY_PASS
```

K04～K10未修改。E0据此签署PASS。

## 2. K14基线上的历史K13假设审计

逐字段审计发现三项不能进入Phase E的实验假设：

1. K13 TX自动发送`EIEOS → SDS → TS`，但Recovery.RcvrLock要求连续TS1并每32个
   TS1插入EIEOS；SDS是Data Stream边界；
2. K13 RX把`RxDataValid=0`当作block中断，而PG239定义它为整拍忽略；
3. K13 RX固定比较SDS最后32 bit，但已有独立Xilinx partner捕获证明最后3 byte可随
   状态变化。

E1删除上述依赖，并冻结完整128-bit block提交边界。

## 3. 实现

- `pcie_gen3_block_rx`按4个有效32-bit word组装block，支持任意valid bubble；
- EIEOS建立`block_locked`并重置23-bit lane scrambler；锁前禁止消费TS；
- 非法Sync Header和中途StartBlock产生错误、丢锁并要求新EIEOS重获；
- TX改为`EIEOS → 32×TS → EIEOS`，不在Recovery自动插入SDS；
- Gen1/Gen3 parser使能互斥；
- TS字段由独立Python bit-serial scrambler/字段模型比对。

## 4. E1验证

入口：

```bash
make phase-e-gen3-block-test
```

结果：

```text
TESTS=4 PASS=4 FAIL=0
PHASE_E_GEN3_BLOCK_PASS randomized_rate_changes=1000
```

覆盖：

- TX首个EIEOS、首个TS逐word参考向量和32个TS后的EIEOS周期；
- 任意word slip前缀；
- block内部0～2拍随机`RxDataValid` bubble；
- TS在EIEOS前不得产生有效脉冲；
- 非法Sync Header、损坏EIEOS、中途StartBlock和重新获得lock；
- 1000次独立切速上下文，每次随机对齐、bubble、TS1/TS2和全部字段；
- 原K13 SDS聚焦回归更新为固定尾字和变化尾字均接受，2/2 PASS。

## 5. 阶段边界

E1的软件/仿真目标已完成，但本报告不把它升级为Gen3 Endpoint release。进入E2后
必须把`block_locked/eieos_valid/lock_lost`接入Recovery.RcvrLock语义状态和ILA，
完成真实Root Port同板连续20次RcvrLock门禁；在此之前canonical Gen1仍是唯一生产
release。
