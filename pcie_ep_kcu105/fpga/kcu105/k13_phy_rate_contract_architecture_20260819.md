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
`PhyStatus`；K13 集成路径随后出现 Gen3 PIPE RX 数据，但 TS/EQ 没有收敛，
最终停在 `Recovery.RcvrCfg`。该 K13 集成结果不能再标记为“Vivado 模型限制”：
同一 Vivado 2021.2 体系下的
官方 `pcie3_ultrascale_0_ex` demo 已经完成 Gen3 Link Up。当前应继续定位 K13
PHY/IP wrapper、reset/rate 接线和训练数据路径的第一个分叉；该结果仍不作为
KCU105 线缆、J74、Root Port、PERST# 或 REFCLK 的硬件结论。

因此，上板门仍保持关闭：必须先以寄存化 Gen3 Partner/PIPE 行为模型完成 Gate C
闭环及 fallback 回归，再执行 bitstream、Vivado 物理实现和实板验证。

### 2026-08-20 修正后的单元门与完整 VCS 结果

本轮提交（提交点 `9258645` 之后）完成了以下语义修正：

- `post_rate_ts_seen` 锁存已接受的 TS，Recovery 不会在 RXEQ/EQ 完成前提交
  negotiated speed；
- RXEQ bootstrap 的 `done=1/adapt_done=0` 接入统一 peer-reject/fallback；
- Gen1 fallback 的物理完成可提交 `active_rate=Gen1`，随后允许新的 Root-Port
  retrain 请求；
- Verilator K13 production controller 回归保持 `4/4 PASS`。

真实 Xilinx Root-Port VCS 已观察到第一次失败路径完整下行：
`PhyStatus -> Gen3 -> RXEQ done-only -> Gen1 fallback`。Gate C 激励随后重新写入
Root-Port Retrain；第二次 Gen3 TS1/TS2 已被 Endpoint 接收，但当前 K11 LTSSM 在
fallback 后仍停留在 Recovery.RcvrCfg/Recovery.Speed 边界，未重新产生
`recovery_speed_ready`，因此尚未达到 Gen3 L0/EqualizationComplete。该分叉属于
LTSSM fallback 后重建上下文/重新进入 Recovery.Speed 的集成问题，不是 QPLL 锁定
或线缆、J74、PERST#/REFCLK 问题。bitstream 门继续保持关闭。

另对 LTSSM 的 `recovery_speed_changed` 增加了新 retrain 上升沿清零，避免同一
条链路在 fallback 后永久跳过 Recovery.Speed。该修正已通过 K11B2 顶层 lint；
VCS 仍显示第二次激励在 Endpoint Recovery.RcvrLock 只收到 5 个 TS1 后超时，
尚未形成第二次 `recovery_speed_ready`。因此当前状态是“fallback 语义已闭环、
fallback 后真实 LTSSM/Root-Port 重训练仍未闭环”，不宣称 Gen3 PASS。

### 2026-08-20 完整 VCS 首个分叉定位

在同一套 Vivado 2021.2 XPM、`glbl.v`、IP sim source、GT/SecureIP simlib 和真实
Xilinx Root-Port 下执行：

```text
K13_ENABLE=1 K13_VCS_RETRAIN=1 K11B2_MODE=1
./sim/vcs/run_k11b_serial.sh
```

结果分两步记录：

```text
K11-B2 Gen1 建链/枚举/BAR       PASS
Gen1 Recovery -> Recovery.Speed PASS
phy_rate_cmd=Gen3               PASS
PhyStatus                      PASS
active_rate=Gen3                PASS
Gen3 PIPE RX data_valid         PASS（切速后出现）
完整 TS/EQ/L0                   FAIL
```

首轮默认 `K13_RXEQ_BOOTSTRAP=1` 的关键事件为：

```text
200707604 ps  PhyStatus=1，contract 完成
200903529 ps  Gen3 parser 解出合法 TS1：link=9f、lane=0、Rate ID=0e
之后          speed_ctrl 接受 peer TS 并回到 L0 上下文，但 eq_start_q 未启动
最终          eq_phase=7、eq_done=0、ts_accept=0（测试窗口报告值）
```

第一个 RTL 时序分叉不是 QPLL 或 Gen3 RX reset：`active_rate=2`、`gen3_mode=1`，
而 `eq_start_q` 同时要求 `post_rate_rxeq_ready`。本次真实 PHY 行为模型的
`phy_rxeq_done` 会到达，但 `phy_rxeq_adapt_done` 保持 0；因此 bootstrap 永远
不能置 ready，而 speed controller 又已经因 TS 完成 Recovery Idle/L0 的语义闭环，
EQ 启动窗口被错过。

按计划临时以 `K13_RXEQ_BOOTSTRAP=0` 复跑纯切速门后，结果进一步收敛为：

```text
Gen3 TS1/TS2 parser             PASS
EQ phase 0/1 启动               PASS
RXEQ phase 1                    FAIL（done=1，adapt_done=0）
完整 Gen3 L0                    NOT PASS
```

这证明关闭 bootstrap 可以验证 rate/PhyStatus/TS 数据路径，但不能把该配置标记为
完整 EQ PASS。下一步应在不伪造 `adapt_done`、不增加 EQ workaround 的前提下，
重构 Recovery Idle 与 RXEQ/EQ 的握手：未完成 RXEQ 时保持 Recovery、锁存已接受
的 peer TS，待 RXEQ 合法完成后再启动 EQ；若 RXEQ 明确拒绝或超时，则走统一
Gen1 fallback。该修正完成前，不生成“Gen3 L0 PASS” bit，也不进入上板验证。

日期：2026-08-19  
代码基线：`a803dd76429dca4a4db8be71c6ce1e02f8a57bab`  
仓库：`FPGA-liyinlong08/pcie-ep`

## 2026-08-20 当前状态记录（VCS 与 KCU105 ILA）

本节记录当前真实证据，避免把行为级 VCS 结果、PHY 物理锁定和完整 PCIe Gen3
链路闭环混为一个 PASS。

### 当前实板 ILA

最新抓取文件：

```text
fpga/kcu105/build_k13_gen3_ila_rxeq_off/capture/iladata_retain.csv
fpga/kcu105/build_k13_gen3_ila_rxeq_off/capture/iladata_qplllock_0to1_2608202001.csv
```

`iladata_retain.csv` 的结果：

```text
Recovery.Speed                  PASS
Gen3 pre-rate TXEQ              PASS（phy_txeq_done=1）
rate request / RATE_WAIT        PASS（进入等待PHY完成）
phy_rate_cmd -> Gen3            本窗口尚未采到
QPLL1LOCK                       全程为1
PhyStatus                       未观察到
LTSSM                            仍停在 Recovery.Speed
```

原因是该次采样在约 2344 点接受 rate request，而正常切速保留 2500 个
`phy_pclk` 的 Golden gap；4096 点窗口在真正的 `phy_rate_cmd=Gen3` 之前结束。

`iladata_qplllock_0to1_2608202001.csv` 的结果：

```text
phy_rate / rxrate                采样开始时已为 Gen3（2）
QPLL1LOCK                        sample 2048: 0 -> 1
PCIERATEGEN3                     sample 2060 -> 2260 有效脉冲
QPLL1RESET / QPLL1PD             本探针窗口均为0
RXRESETDONE                      sample 2259: 1 -> 0，之后未恢复
PhyStatus                        0
TS accept / EQ active            0
LTSSM                            全窗口 Recovery.Speed (0x12)
```

这证明 QPLL1LOCK 可以恢复到 1，但不等于 Gen1→Gen3 已闭环。当前失败分叉位于
QPLL lock 之后的 RX reset/PhyStatus/Recovery.Speed 退出路径；本次没有观察到
`QPLL1RESET`，因此不能仅凭该文件确认正确的 QPLL reset→unlock→relock 因果链。
该文件起始时 `fallback/timeout/eq_failed` sticky 位已经为 1，下一轮判断前必须
先经 Detect/重启清除旧上下文。

当前实板结论：

```text
QPLL1LOCK recovery       PASS（观测到0→1）
Gen3 rate command         PASS（第二份文件开始时已为2）
PhyStatus completion      FAIL / 未发生
Recovery.Speed exit       FAIL
完整 Gen1→Gen3 L0         NOT PASS
```

### VCS 仿真已知问题与边界

已完成的 VCS 结果必须按以下边界解释：

1. K13 Rate Contract 单元和窄场景 controller 仿真通过了 Gen1→Gen3 请求、TXEQ
   preset 顺序及行为模型 `PhyStatus` 完成。这只证明 semantic contract 的时序，
   不证明 GT/QPLL 物理锁定或完整 PCIe L0。
2. 真实 Endpoint + Xilinx Root-Port/GT 行为模型已经 compile/elaboration 通过，
   可观察 Recovery、Gen3 rate、`PhyStatus` 和切速后的 PIPE RX 数据；当前联合
   仿真失败在 K13 自有 TS/EQ 握手：默认 RXEQ bootstrap 尚未完成时，speed controller
   已接受 peer TS 并关闭 Recovery，导致 EQ 启动窗口错过；关闭 bootstrap 后又在
   RXEQ phase 1 看到 `done=1, adapt_done=0`，因此不能伪造完整 EQ/L0 PASS。这是
   K13 时序/PHY 合法完成条件尚未闭环，不是线缆、J74、Root Port、PERST# 或 REFCLK
   的结论。
3. 早期 VCS 封装把 `qpll1lock_us_out/qpll1lock_usp_out` 等端口固定为 0，因而旧的
   VCS PASS 不能推导 QPLL 已锁定。当前工程已增加 QPLL observability，但行为模型
   仍不是 GT/QPLL 的物理锁定模型，QPLL 结论必须以实板 ILA 为准。
4. 早期完整联合仿真还暴露了 Gen3 TS/EQ 边界问题：Rate ID capability 位曾被当作
   EQ request 代理，以及独立 Partner/解析器可能形成零时间环路。现已改为解析
   `os_eq_control/os_eq_data`，Partner 发送由独立脚本化状态机驱动；当前已实证
   Gen3 TS parser 和 EQ phase 0/1 的启动，但 RXEQ 合法完成、phase 2/3、
   Recovery.Idle、Gen3 L0 TLP/DLL/BAR 仍未完成。

已解决的控制层问题：

```text
rate_req_ready 不再由实时 link_up 门控
rate_failed 不再作为阻塞 fallback 的 sticky 完成电平
same-rate 请求返回单拍 rate_done
普通升速保留 Golden gap，fallback 走统一 Rate Contract
phy_rate_cmd 与 active_rate 已拆分
QPLL lock 已加入 VCS/ILA 观测路径
```

下一轮硬件抓取应在干净 Detect/Gen1 上下文开始，使用至少 8192 点窗口，并同时
观察 `phy_rate_cmd`、`active_rate`、`PCIERATEGEN3`、GT primitive 的
`QPLL1RESET/QPLL1PD/QPLL1LOCK`、`RXRESETDONE`、`PhyStatus` 和 LTSSM。只有看到
`phy_rate_cmd=Gen3 → QPLL 1→0→1 → PhyStatus → active_rate=Gen3 → 离开
Recovery.Speed`，才能进入真实 Gen3 EQ/L0 验证。

### 官方 `pcie3_ultrascale_0_ex` VCS 训练波形的借鉴

线程 `codex://threads/01a01e97-182a-7d40-bb9e-e38467b7f467` 使用官方
`pcie3_ultrascale_0` Endpoint + Xilinx UltraScale Root-Port example top，在
Vivado 2021.2 VCS 仿真库和完整 `board` testbench 下导出了 EP/RP 两端训练信号。
该波形观察到：

```text
0~143 us       Detect/Polling/Configuration，speed=1
147.8 us       pipe_tx_rate_i: 00 -> 10，Gen3 rate 控制启动
168.4~190.9 us LTSSM 进入 0x28/0x29，Recovery/Equalization 相关阶段
192.3 us       cfg_current_speed: 1 -> 4（8.0 GT/s）
193.4 us       user_lnk_up，PIO 访问通过
```

它对本工程完整 VCS 的直接借鉴不是“把 demo 的 PASS 直接等同于 K13 PASS”，而是
提供了一个已知可工作的**仿真环境基线和事件顺序基线**：

1. 官方 demo 的 Endpoint/RP/GT 模型能完成 Gen3 RX 训练并最终 Link Up。因此我们
   之前完整 K13 VCS 停在 `Recovery.Equalization`，不能再笼统归因于“Vivado
   Gen3 模型必然不支持 RX”。两边现在确认使用同一 Vivado 2021.2 体系，下一步
   应对比 PHY/IP 生成版本、GT wrapper、simlib 实例、reset/clock/rate 接线和
   Endpoint 数据路径的差异。
2. demo 的 Gen3 Link Up 由官方 hard-IP LTSSM/PCS/EQ 自动完成，不能证明我们自有
   `pcie_k13_production_ctrl`、Rate Contract、TS parser 或自有 MAC 的语义正确性。
   它应作为 Partner/PHY 模型资格门，不能替代 K13 控制器集成门。
3. K13 完整 VCS 应复用相同的观测方法：同时记录 EP/RP `cfg_ltssm_state`、
   `cfg_current_speed`、`cfg_negotiated_width`、`cfg_phy_link_status`、
   `pipe_tx_rate_i`、TX/RX Electrical Idle、`PCIERATEGEN3`、`PhyStatus` 和
   `user_lnk_up`，并用第一处分叉事件比较，而不是只看最终 `PhyStatus`。
4. 推荐新增一个“模型资格/适配”阶段：先在同一 VCS/Vivado simlib 下复跑官方 demo，
   再保留官方 Root-Port/GT Partner，只替换为 K13 Endpoint；若 demo 通过而 K13
   仍停在 Equalization，问题就收敛到 K13 的 rate/reset、RX reset release、TS/EQ
   parser 或 128b/130b 接口，而不是主机链路环境。
5. demo 工程还给出了完整 source-list 的最低要求：`board.v`、`imports/*.v`、
   IP `sim/` wrapper、GT/XPM、`glbl.v` 和 `secureip/unisims_ver/xpm` 预编译库。
   这可用于复核 K13 VCS 的源清单，但不能用“compile/elaboration PASS”替代训练
   波形和 L0 断言。

因此，官方 demo 将此前 VCS 结论从“可能是模型限制”进一步收敛为：**同一
Vivado 2021.2 环境本身具备 Gen3 训练能力；K13 完整仿真应定位其与官方模型在
PHY/IP wrapper、reset、rate 握手、RX reset 释放和训练数据路径上的第一个差异。**

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
