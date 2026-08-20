# K13 生产化 PHY Rate-Change 控制架构设计

## 2026-08-20 仿真门更新

许可证已恢复并通过 `27000@wx-linux` 验证。当前可复现的 RTL/行为 Partner 门为：

```text
K13 PHY Rate Contract       10/10 PASS
K13 production controller    4/4 PASS
K13 LTSSM + Partner          2/2 PASS
K13_ENABLE=0 full-top lint   PASS
K11-B2 VCS Gen1/config/BAR   PASS
```

Gen3 EQ 请求已改为使用 Gen3 TS 解析出的 `os_eq_control/os_eq_data`，不再使用
`Rate ID[3]` 作为 EQ 请求代理。VCS 真实 Xilinx Root-Port 串行回归已完成
compile/elaboration，并观察到 Endpoint/Root-Port 进入 Recovery、Gen3 rate 和
`PhyStatus`；但 Vivado 2021.2 导入的 Root-Port GT 仿真模型在 Gen3 仍不释放
RX reset（PIPE RX 数据保持无效），最终停在 `Recovery.Equalization`。该结果记录为
仿真模型限制，不作为 KCU105 线缆、J74、Root Port、PERST# 或 REFCLK 的硬件结论。

因此，上板门仍保持关闭：必须先以寄存化 Gen3 Partner/PIPE 行为模型完成 Gate C
闭环及 fallback 回归，再执行 bitstream、Vivado 物理实现和实板验证。

日期：2026-08-19  
代码基线：`a803dd76429dca4a4db8be71c6ce1e02f8a57bab`  
仓库：`FPGA-liyinlong08/pcie-ep`

## 1. 背景与已闭环事实

K02 最近的 2×2 交叉验证已经确认：

```text
Controller             PHY IP                    Hardware
----------------------------------------------------------
Golden phy_ctrl.v       Golden pcie_phy_0         PASS
K02 dynamic_rate_*      K02 pcie_phy_x1_gen3      FAIL
Golden phy_ctrl.v       K02 pcie_phy_x1_gen3      PASS
```

因此可以冻结：

```text
K02 pcie_phy_x1_gen3 / GT / QPLL1 capability = PASS
旧 K02 dynamic_rate_* direct PHY command FSM = FAIL
Golden phy_ctrl rate-change contract          = PASS
```

当前 `main` 已将 K02 旧 `dynamic_rate_*` FSM 删除，K02 唯一路径为：

```text
phy_bringup_seq
        ↓
Xilinx phy_ctrl.v
        ↓
phy_ctrl_pat_gen
        ↓
K02 pcie_phy_x1_gen3
        ↓
GTHE3 / QPLL1
```

实板已经确认：

```text
seq_state → S_DONE
debug_state == 8'h04
QPLL1LOCK : 1 → 0 → 1
```

下一步不应再重新发明 direct `PHY_RATE` FSM，而应把 Golden 中已被硬件验证的 **rate-change contract** 抽成 K13 LTSSM 可调用的生产接口。

---

## 2. 当前 K13 结构

当前 K13 主链路：

```text
k11a_offline_top
  │
  ├─ retrain_link_pulse
  └─ target_link_speed
          │
          ▼
pcie_k13_production_ctrl
          │
          ├─ pcie_recovery_speed_ctrl
          ├─ pcie_recovery_ts_guard
          ├─ pcie_equalization_ctrl
          └─ pre/post rate EQ bootstrap
          │
          ▼
kcu105_pcie_ep_gen1_top mux
          │
          ├─ phy_rate
          ├─ phy_txelecidle
          ├─ TXEQ/RXEQ
          └─ traffic_quiesce
          │
          ▼
kcu105_pcie_phy_wrapper
          │
          ▼
pcie_phy_x1_gen3
```

LTSSM 已经具备：

```text
RECOVERY_RCVRLOCK
RECOVERY_RCVRCFG
RECOVERY_SPEED
RECOVERY_IDLE
```

并已有接口：

```text
speed_retrain_active
recovery_speed_ready
recovery_speed_done
```

当前 `RECOVERY_SPEED` 中 TX Ordered Set 被关闭，`as_cdr_hold_req=1`，`recovery_speed_ready=1`。这部分应保留。

---

## 3. 当前 K13 的结构性问题

### 3.1 `pcie_recovery_speed_ctrl` 仍直接驱动 `PHY_RATE`

当前 `ST_SPEED_WAIT` 的核心语义仍是：

```text
phy_rate = pending_speed
phy_txelecidle = 1
等待 phy_phystatus
```

这仍属于 direct PHY command 模型。K02 已经通过硬件交叉实验说明：不能把“直接改 `PHY_RATE` 再等 `PHY_PHYSTATUS`”视为已验证的生产控制契约。

因此 K13 不应继续让 `pcie_recovery_speed_ctrl` 成为 raw `PHY_RATE` owner。

### 3.2 raw `phy_rate` 同时充当命令和活动速率

当前顶层把 raw `phy_rate` 同时送到 PHY 和 LTSSM 的 `active_phy_rate`：

```text
phy_rate command
      │
      ├─→ PHY
      └─→ LTSSM active_phy_rate
```

而 LTSSM 内部用：

```text
gen3_mode = (active_phy_rate == 2'b10)
```

因此一旦命令改成 Gen3，而 PHY 尚未完成切换，MAC/parser 已可能提前切换到 Gen3 解释模式。

应严格拆成：

```text
phy_rate_cmd    = 发给 PHY 的目标命令
phy_active_rate = PHY completion 后才提交的实际活动速率
```

原则：

```text
phy_rate_cmd 可以先变
phy_active_rate 只能在 completion 后变
```

### 3.3 PHY command ownership 分散

当前 raw PHY command 分散在 LTSSM、K13、top mux。生产化后应明确每根信号唯一 owner，禁止多个状态机直接抢 `PHY_RATE`。

---

## 4. 目标架构

新增：

```text
rtl/phy/pcie_phy_rate_contract.sv
```

整体结构：

```text
                   ┌────────────────────────┐
Config / Partner ─▶│ K13 Recovery coordinator│
                   │ pcie_recovery_speed_ctrl│
                   └───────────┬────────────┘
                               │ semantic request
                               │ rate_req_valid
                               │ rate_req_target
                               ▼
                   ┌────────────────────────┐
                   │ pcie_phy_rate_contract │
                   │ Golden-derived contract│
                   └───────────┬────────────┘
                               │ raw PHY command
                               ├─ phy_rate_cmd
                               ├─ force_txelecidle
                               │
                               ◀─ phy_phystatus
                               │
                               ├─ rate_done
                               ├─ rate_failed
                               └─ active_rate
                               │
                               ▼
                         pcie_phy_x1_gen3
```

真实 LTSSM 继续负责：

```text
as_mac_in_detect
as_cdr_hold_req
phy_powerdown
Receiver Detect
Ordered Set / TX data
```

EQ 继续由 `pcie_k13_production_ctrl` / `pcie_equalization_ctrl` 负责。

---

## 5. 为什么不直接把完整 Golden `phy_ctrl.v` 塞进 K13

不建议直接把完整 demo 控制器作为生产控制器，原因：

1. `phy_ctrl_pat_gen*` 会自己产生 `PHY_TXDATA/VALID/TXELECIDLE`，与生产 MAC/Ordered Set 数据路径冲突。
2. `as_mac_in_detect/as_cdr_hold_req` 来自 `ltssm_mimic_cnt`，生产设计已有真实 LTSSM，应使用真实 LTSSM 状态。
3. `phy_bringup_seq` 的 50 us / 10 us / 80 us 是 example-design stimulus，不是生产 LTSSM。
4. 真正需要继承的是 `RDY0/RDY1/RDY2/RDY3 + PHY_RATE + PHY_PHYSTATUS + no-rate-change` 的握手语义。

因此应提取“rate contract”，而不是复制整套 demo。

---

## 6. `pcie_phy_rate_contract` 建议接口

```systemverilog
module pcie_phy_rate_contract #(
    parameter integer RATE_TIMEOUT_CYCLES = 1_000_000,
    parameter integer GEN1_RELEASE_GAP_CYCLES = 2500
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       link_ready,
    input  wire       reinitialize_gen1,

    input  wire       rate_req_valid,
    input  wire [1:0] rate_req_target,
    input  wire       fallback_req,
    output wire       rate_req_ready,

    input  wire       phy_phystatus,

    output wire [1:0] phy_rate_cmd,
    output wire       force_txelecidle,

    output wire [1:0] active_rate,
    output wire       rate_busy,
    output wire       rate_done,
    output wire       rate_failed,

    output wire [3:0] dbg_state,
    output wire       phystatus_seen,
    output wire       timeout_sticky
);
```

关键语义：

```text
phy_rate_cmd != active_rate
```

在 rate transition 中是正常状态。例如：

```text
phy_rate_cmd = Gen3
active_rate  = Gen1

      ↓ PHY_PHYSTATUS

active_rate  = Gen3
rate_done    = 1
```

LTSSM 的 `active_phy_rate` 必须接 `active_rate`。

---

## 7. Rate Contract 状态机

状态建议直接映射 Golden `phy_ctrl` 的 RDY 语义：

```text
RC_DISABLED
RC_RDY2_STABLE
RC_RELEASE_RDY3
RC_RDY0_GAP
RC_APPLY_RDY1
RC_WAIT_PHYSTATUS
RC_COMMIT_RDY2
RC_FALLBACK_WAIT
RC_ERROR
```

### 7.1 初始同步

K11 已经有成功的 Receiver Detect + P1→P0 + `PHY_POWERUP` 流程，因此第一阶段 **不要让新 Rate Contract 接管初始 powerdown**。

当 `link_up=1` 时即可认为：

```text
PHY=P0
physical rate=Gen1
active_rate=Gen1
```

Rate Contract 从 `RC_DISABLED` 同步到 `RC_RDY2_STABLE`。

### 7.2 Gen1 → Gen3

协议层：

```text
L0 @ Gen1
   ↓ retrain request
Recovery.RcvrLock/RcvrCfg
   ↓
Recovery.Speed
   ├─ traffic_quiesce=1
   ├─ TX Ordered Set off
   ├─ as_cdr_hold_req=1
   └─ TX Electrical Idle
   ↓
pre-rate TXEQ（若保留）
   ↓
rate_req(target=Gen3)
```

Rate Contract：

```text
RC_RDY2_STABLE
      ↓ accept request
RC_RELEASE_RDY3
      ↓ 等价 Golden all-rate-enable-off
RC_RDY0_GAP
      ↓ 保留第一版 10 us gap
RC_APPLY_RDY1
      ├─ phy_rate_cmd = Gen3
      └─ active_rate  = Gen1
      ↓
RC_WAIT_PHYSTATUS
      ↓ QPLL reset/unlock/relock
      ↓ PHY_PHYSTATUS
RC_COMMIT_RDY2
      ├─ active_rate = Gen3
      └─ rate_done pulse
      ↓
RC_RDY2_STABLE
```

第一版保留 `2500 pclk @ 250 MHz = 10 us`，不是因为生产 PCIe 永久要求 10 us，而是因为这是当前唯一有 KCU105 实板闭环证据的 Golden stimulus。等 K13 实板闭环后再缩短。

### 7.3 Gen3 → Gen1 fallback

fallback 也必须走同一 Rate Contract：

```text
K13 fallback request Gen1
       ↓
force TXEI
phy_rate_cmd=Gen1
       ↓
wait PHY_PHYSTATUS
       ↓
active_rate=Gen1
       ↓
rate_done
```

禁止在 top 中另加 `phy_rate=Gen1` bypass mux。

---

## 8. PHY command ownership

| PHY 信号 | 唯一 owner | 说明 |
|---|---|---|
| `phy_rate` | `pcie_phy_rate_contract` | K13/LTSSM 只发 semantic request |
| `phy_powerdown` | LTSSM | 第一阶段保持 K11 已验证 Detect/P1/P0 |
| `phy_txdetectrx` | LTSSM | Receiver Detect |
| `as_mac_in_detect` | LTSSM | 真实 Detect 状态 |
| `as_cdr_hold_req` | LTSSM | `Recovery.Speed` |
| `phy_txelecidle` | OR arbitration | LTSSM idle OR rate force OR EQ force |
| `phy_txeq_*` | K13 EQ controller | Rate Contract 不碰 EQ |
| `phy_rxeq_*` | K13 EQ controller | RXEQ bootstrap / Equalization |
| TX data/OS | LTSSM/MAC | 不接 Golden pattern generator |

`phy_txelecidle` 推荐：

```text
phy_txelecidle =
    ltssm_phy_txelecidle
  | rate_contract_force_txelecidle
  | k13_eq_force_txelecidle
```

---

## 9. `pcie_recovery_speed_ctrl.sv` 修改

当前 raw 输出：

```text
phy_rate
phy_txelecidle
```

改为 semantic handshake：

```text
rate_req_valid
rate_req_target
rate_req_ready
rate_op_done
rate_op_failed
```

状态建议：

```text
ST_L0
  ↓
ST_QUIESCE
  ↓ wait ltssm_speed_ready
ST_RATE_REQUEST
  ↓ wait rate_req_ready
ST_RATE_WAIT
  ↓ wait rate_op_done
ST_RECOVERY_IDLE
  ↓ peer TS accepted
ST_L0
```

fallback：

```text
failure
  ↓
ST_FALLBACK_REQUEST
  ↓ target Gen1
ST_FALLBACK_WAIT
  ↓ rate_op_done
ST_FALLBACK_IDLE
```

`pcie_recovery_speed_ctrl` 不再直接消费 raw `phy_phystatus`；`phy_phystatus` 归 Rate Contract 层消费。
`rate_done` 和 `rate_failed` 均为单拍结果；每个已接受请求恰好返回一次，same-rate 请求也
返回 `rate_done`。普通升速保留 2500 pclk Golden gap，显式 Gen1 fallback 跳过该 gap。
`reinitialize_gen1` 由真实 LTSSM Detect 指示驱动；初始化完成后 Recovery 中的 `link_up=0`
不会再门控 `rate_req_ready`。

---

## 10. `pcie_k13_production_ctrl.sv` 修改

保留：

```text
CDC mailbox
TS guard
pre-rate TXEQ
post-rate RXEQ bootstrap
Gen3 EQ Phase controller
traffic_quiesce
fallback policy
```

新增 `pcie_phy_rate_contract` 实例。

建议新增输出：

```text
phy_rate_cmd
phy_active_rate
rate_contract_state
rate_contract_busy
rate_contract_done
rate_contract_failed
```

---

## 11. LTSSM 修改

`pcie_ltssm_mac_gen1.sv` 大部分状态无需重写。

保留：

```text
RECOVERY_RCVRLOCK
RECOVERY_RCVRCFG
RECOVERY_SPEED
RECOVERY_IDLE
recovery_speed_ready = (ltssm_state == RECOVERY_SPEED)
```

关键修改：

当前：

```text
.active_phy_rate(phy_rate)
```

改为：

```text
.active_phy_rate(phy_active_rate)
```

结果：

```text
Recovery.Speed期间：
  phy_rate_cmd 可已经为 Gen3
  phy_active_rate 仍为 Gen1

PHY completion：
  phy_active_rate → Gen3
  rate_done → 1

然后：
  recovery_speed_done → 1
  LTSSM → Recovery.RcvrLock
  Gen3 parser/Ordered Set 正式生效
```

这使协议速率状态与物理完成边界一致。

---

## 12. Top-level 修改

文件：

```text
rtl/ep/kcu105_pcie_ep_gen1_top.sv
```

删除当前 K13 对 raw `phy_rate` 的多路 mux ownership。

目标：

```text
K13 semantic request
      ↓
pcie_phy_rate_contract
      ├─ phy_rate_cmd ───────▶ wrapper.phy_rate
      └─ active_rate ────────▶ LTSSM.active_phy_rate
```

`K13_ENABLE=0` 时：

```text
phy_rate_cmd = Gen1
active_rate  = Gen1
```

保持 K11 release 行为。

第一阶段不要改 Receiver Detect/P1/P0 Power-Up；这部分已有实板枚举/BAR/reboot 闭环。

---

## 13. 完整 Gen3 时序

```text
L0 / Gen1
  │
  │ Config Retrain or Partner Speed Change
  ▼
K13 request latched
  ▼
LTSSM Recovery.RcvrLock
  ▼
Recovery.RcvrCfg
  ▼
Recovery.Speed
  ├─ traffic quiesce
  ├─ TX OS disabled
  ├─ as_cdr_hold_req=1
  ├─ TX Electrical Idle=1
  └─ optional TXEQ preset
  ▼
pcie_phy_rate_contract request Gen3
  ├─ Golden-derived release state
  ├─ conservative 10 us gap
  ├─ PHY_RATE=Gen3
  ▼
QPLL1RESET
  ↓
QPLL1LOCK 1→0
  ↓
QPLL1LOCK 0→1
  ↓
PHY_PHYSTATUS
  ▼
active_rate=Gen3
rate_done=1
  ▼
recovery_speed_done=1
  ▼
LTSSM Recovery.RcvrLock @ Gen3
  ├─ Gen3 TS1/TS2
  ├─ RXEQ bootstrap
  └─ EQ Phase 0～3
  ▼
Recovery.Idle
  ▼
L0 / Gen3
```

---

## 14. ILA 必要信号

```text
ltssm_state
k13_speed_state

rate_req_valid
rate_req_target
rate_req_ready

rate_contract_state
rate_contract_busy
rate_contract_done
rate_contract_failed
rate_contract_phystatus_seen

phy_rate_cmd
phy_active_rate
phy_phystatus

phy_txelecidle
as_cdr_hold_req
as_mac_in_detect

QPLL1RESET
QPLL1LOCK
PCIERATEQPLLRESET
PCIERATEGEN3
PCIEUSERGEN3RDY
```

硬件必须满足的不变量：

```text
1. phy_rate_cmd=Gen3 后，phy_active_rate 仍保持 Gen1，直到 completion。
2. QPLL1LOCK 必须在 Gen3 request 仍保持时完成 1→0→1。
3. PHY_PHYSTATUS 到来后才产生 rate_contract_done。
4. active_rate 只能在 completion 时更新。
5. LTSSM 在 rate_done 前必须保持 RECOVERY_SPEED。
6. fallback 也必须通过 Rate Contract，不能 top bypass PHY_RATE。
```

---

## 15. 验证顺序

### Gate A：Rate Contract 单元仿真

覆盖：

```text
Gen1 -> Gen3 PASS
Gen3 -> Gen1 PASS
same-rate request
PHY_PHYSTATUS delayed
PHY_PHYSTATUS timeout
fallback
```

断言：

```text
active_rate cannot change before completion
raw phy_rate can change while active_rate stays old
done is one-cycle pulse
single raw PHY_RATE owner
```

### Gate B：K13 controller integration

验证 Retrain、Recovery.Speed、Rate Contract request/ack、completion、fallback。

### Gate C：LTSSM integration

验证：

```text
LTSSM stays in RECOVERY_SPEED until rate_done
active_phy_rate changes only after rate_done
Gen3 OS/parser begins after physical completion
```

### Gate D：Vivado

```text
lint PASS
Verilator PASS
VCS PASS
CDC no new Critical
DRC 0 Error
WNS >= 0 for release
```

### Gate E：KCU105 ILA

先证明：

```text
Recovery.Speed
  ↓
rate contract
  ↓
QPLL1LOCK 1→0→1 while Gen3 request remains active
  ↓
PHY_PHYSTATUS
  ↓
active_rate=Gen3
  ↓
LTSSM leaves Recovery.Speed
```

### Gate F：Host

```text
LnkSta: Speed 8GT/s, Width x1
LnkSta2 EqualizationComplete+
枚举 PASS
BAR PASS
reboot PASS
```

---

## 16. 推荐实施阶段

### Phase 1

新增：

```text
rtl/phy/pcie_phy_rate_contract.sv
sim/verilator/k13_rate_contract/
```

暂不接硬件顶层。

### Phase 2

改 `pcie_recovery_speed_ctrl.sv`：删除 raw rate ownership，改 semantic request/ack。

### Phase 3

只在 `K13_ENABLE=1` 接入；K11 release 路径保持不变。

### Phase 4

把：

```text
.active_phy_rate(phy_rate)
```

改为：

```text
.active_phy_rate(phy_active_rate)
```

单独做回归。

### Phase 5

KCU105 ILA 先闭环 physical rate contract，再继续 EQ/TS/Host Gen3。

---

## 17. 暂时不要做

1. 不恢复 `dynamic_rate_*`。
2. 不在 top 新增另一个 `PHY_RATE` fallback mux。
3. 不把 Golden pattern generator 接入生产 TX 数据路径。
4. 不使用 `ltssm_mimic_cnt` 替代真实 LTSSM。
5. 不同时重写 Receiver Detect/P1/P0；K11 该部分已经硬件闭环。
6. 不再把 raw `phy_rate` 当 negotiated/active rate。
7. Rate Contract 实板闭环前，不继续堆更多 EQ workaround。

---

## 18. 最终设计原则

生产架构分三层：

```text
Protocol / LTSSM
    决定“什么时候、要切到什么速率”

        ↓ semantic request

PHY Rate Contract
    决定“如何按已验证 Golden contract 完成物理切速”

        ↓ raw PHY command

pcie_phy / GT
    执行物理变化并反馈 completion
```

即：

> LTSSM 决定 **what / when**，Rate Contract 决定 **how**。

K02 已证明 PHY/GT 能工作。K13 下一阶段最关键的架构调整，是让 LTSSM/K13 不再直接操作 raw `PHY_RATE`，而是把 Golden 中已硬件验证的 rate-change handshake 固化成单一、可验证、可复用的生产控制边界。
