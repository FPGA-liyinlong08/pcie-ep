# KCU105 PCIe PHY Gen1→Gen3 当前调试记录与差异对比

日期：2026-08-18  
仓库：`FPGA-liyinlong08/pcie-ep`  
当前 `main` 基线：`7afb98db649e48953d4411aa4da863bf9237f83a`  
重点目录：`pcie_phy_0_ex/board_kcu105/`

---

## 1. 当前调试目标

当前目标不是验证完整 PCIe Endpoint 枚举，而是先独立确认：

> KCU105 / KU040 上的 Xilinx standalone `pcie_phy` 是否能够按照 Xilinx example design 的控制方式完成 Gen1 → Gen3 rate change，以及 QPLL1 reset / unlock / relock 是否正常。

本轮使用 `pcie_phy_0_ex` 的 Hardware Golden 方案，核心思路是：

- 保留原始 Xilinx `imports/phy_ctrl.v`；
- 新增可综合的 `phy_bringup_seq.sv`；
- 用 `phy_bringup_seq` 复现原始 `board.v` 的 bring-up stimulus；
- 通过 ILA 直接观察 PHY / GT / QPLL1 状态。

该测试不包含完整 LTSSM、TS1/TS2、DLLP/TLP、配置空间或 BAR，因此不能单独用于判断 Linux 是否枚举成功。

---

## 2. Hardware Golden 当前结构

### 2.1 控制关系

```text
phy_bringup_seq
    │
    ├─ tx_elec_idle
    ├─ phy_ready_en
    ├─ gen1_en
    ├─ gen2_en
    ├─ gen3_en
    └─ gen4_en
           │
           ▼
原始 Xilinx phy_ctrl.v
           │
           ├─ PHY_RATE
           ├─ PHY_POWERDOWN
           ├─ PHY_TXEQ_*
           ├─ as_mac_in_detect
           └─ as_cdr_hold_req
           │
           ▼
Xilinx standalone pcie_phy / GTHE3
           │
           ├─ QPLL1RESET
           ├─ QPLL1LOCK
           ├─ PCIERATEQPLLRESET
           ├─ PCIERATEGEN3
           ├─ PCIEUSERGEN3RDY
           └─ PHY_PHYSTATUS
```

关键点：

> `phy_bringup_seq` 不直接驱动 QPLL1RESET，也不直接驱动 PHY_RATE；它只产生 Xilinx `phy_ctrl.v` 原来从 `board.v` 获得的 6 个控制输入。

---

## 3. `phy_bringup_seq` 状态迁移

当前代码状态定义：

```text
S_RESET          = 0
S_WAIT_READY     = 1
S_POWER_UP       = 2
S_GEN1_WAIT      = 3
S_GEN1_HOLD      = 4
S_GEN1_OFF_GAP   = 5
S_GEN3_WAIT      = 6
S_GEN3_HOLD      = 7
S_DONE           = 8
```

状态迁移：

```text
                 +-----------+
                 |  S_RESET  |
                 +-----------+
                       |
                       v
               +---------------+
               | S_WAIT_READY  |
               | 等PHY状态复位释放 |
               +---------------+
                       |
              phy_status_ready
                       |
                       v
               +---------------+
               |  S_POWER_UP   |
               | 等待 10 us    |
               | READY+GEN1    |
               +---------------+
                       |
                       v
               +---------------+
               |  S_GEN1_WAIT  |
               | gen1_en = 1   |
               | >= 5 us       |
               | 等 debug=04   |
               +---------------+
                       |
                       v
               +---------------+
               |  S_GEN1_HOLD  |
               | 保持 50 us    |
               +---------------+
                       |
                       v
             +-------------------+
             | S_GEN1_OFF_GAP    |
             | gen1_en = 0       |
             | gen3_en = 0       |
             | 等待 10 us        |
             +-------------------+
                       |
                       v
               +---------------+
               |  S_GEN3_WAIT  |
               | gen3_en = 1   |
               | gen3_request=1|
               | 等 debug=04   |
               +---------------+
                       |
                       v
               +---------------+
               |  S_GEN3_HOLD  |
               | 保持 80 us    |
               +---------------+
                       |
                       v
                 +-----------+
                 |  S_DONE   |
                 +-----------+
```

### 3.1 和 QPLL1RESET / QPLL1LOCK 的关系

`seq_state` 与 QPLL1 的关系不是直接组合逻辑关系，而是：

```text
S_GEN3_WAIT
   │
   └─ gen3_en = 1
          │
          ▼
      phy_ctrl.v
          │
          └─ PHY_RATE -> Gen3
                  │
                  ▼
              GTHE3 rate change
                  │
                  ├─ QPLL1RESET 拉高
                  ├─ QPLL1LOCK 1 -> 0
                  ├─ QPLL1RESET 释放
                  └─ QPLL1LOCK 0 -> 1
```

因此 QPLL1RESET / QPLL1LOCK 是 PHY/GT 对 Gen3 rate change 的内部响应，而不是 `phy_bringup_seq` 直接产生的信号。

---

## 4. ILA Probe 关键映射

Hardware Golden 的 `probe0` 关键顺序：

```text
phy_rate[2:0]
phy_phystatus_debug
debug_state[7:0]
as_mac_in_detect
as_cdr_hold_req
QPLL1RESET
QPLL1LOCK
PCIERATEQPLLRESET[1:0]
PCIERATEGEN3
PCIEUSERGEN3RDY
QPLL1REFCLKLOST
QPLL1FBCLKLOST
```

`probe1` 关键顺序：

```text
seq_state[3:0]
gen3_request
tx_elec_idle
phy_ready_en
gen1_en
gen2_en
gen3_en
gen4_en
phy_phystatus_rst_debug
```

Vivado Hardware Manager 中部分 primitive pin 会显示成综合后的内部网络名，因此应以 probe 插入顺序和 primitive pin 定义确认真实含义，不应只根据显示名猜测。

---

## 5. 本轮实板观测结果

### 5.1 第一次：观察 Gen3 请求

ILA 中确认：

```text
S_GEN1_HOLD
    ↓
S_GEN1_OFF_GAP
    ↓
S_GEN3_WAIT
```

同时：

```text
gen1_en      : 1 -> 0
gen3_en      : 0 -> 1
gen3_request : 0 -> 1
phy_rate     : Gen1 -> Gen3
```

结论：

> `phy_bringup_seq` 已正常执行到 Gen3 request，Gen1 → OFF GAP → Gen3 的控制链路成立。

---

### 5.2 第二次：QPLL1RESET

以 `QPLL1RESET` 上升沿触发，确认：

```text
Gen3 request
    ↓
QPLL1RESET : 0 -> 1
```

说明 Gen3 rate change 已真正进入 GT/QPLL 处理流程。

---

### 5.3 第三次：QPLL1LOCK

继续观察 QPLL1LOCK，确认同一次 Gen3 rate change 中出现：

```text
QPLL1RESET : 0 -> 1 -> 0

QPLL1LOCK  : 1 -> 0 -> 1
```

即：

```text
QPLL1 RESET assert
       ↓
QPLL1 unlock
       ↓
QPLL1 RESET release
       ↓
QPLL1 relock
```

这说明：

> 当前 Hardware Golden 下 QPLL1 的 reset / unlock / relock 流程是正常的。

此前“QPLL1 reset 后无法重新锁定”的旧结论，不适用于当前 Hardware Golden 实测结果。

---

### 5.4 最终状态

最终 ILA 观察到：

```text
seq_state = S_DONE
gen3_request = 0
gen3_en = 0
QPLL1RESET = 0
QPLL1LOCK = 1
```

说明 `phy_bringup_seq` 已完整跑完：

```text
Gen1
  ↓
Gen1 OFF GAP
  ↓
Gen3 request
  ↓
QPLL1 reset / unlock / relock
  ↓
Gen3 hold
  ↓
S_DONE
```

当前 Hardware Golden 可以判定为：

> **Gen1 → Gen3 PHY/GT rate-change 路径完成，QPLL1 重锁正常。**

注意：`S_DONE` 后 `gen3_en` 被撤销，因此最终 `phy_rate` 回到默认状态是当前 stimulus 设计的结果，不代表 Gen3 rate-change 过程失败。

---

## 6. Hardware Golden 与 K02 Dynamic 的核心差异

这两套测试虽然都叫“Gen1→Gen3”，但控制模型不同。

### 6.1 控制架构差异

#### Hardware Golden

```text
phy_bringup_seq
    ↓
gen1_en / gen3_en 等6个 board.v 控制
    ↓
原始 Xilinx phy_ctrl.v
    ↓
PHY_RATE / POWERDOWN / TXEQ / CDR hold
    ↓
pcie_phy
```

#### K02 Dynamic

```text
K02 自研测试状态机
    ↓
直接控制：
phy_rate_cmd
phy_powerdown
phy_txeq_ctrl
phy_txeq_preset
as_cdr_hold_cmd
    ↓
pcie_phy
```

也就是说：

> Golden 走的是 Xilinx 原始 `board.v -> phy_ctrl.v` 控制路径；K02 Dynamic 是自研的直接 PHY command 流程。

---

## 7. 详细时序差异

| 项目 | Hardware Golden | K02 Dynamic |
|---|---|---|
| 前置流程 | 等 PHY ready | 先 Receiver Detect |
| Gen1 前等待 | 10 us | 当前 dynamic build 有额外 start delay |
| Gen1 稳定判断 | >=5 us 且 `debug_state==04` | 固定计数 |
| Gen1 保持 | 50 us | 默认 1024 pclk ≈ 4.096 us |
| Gen1→Gen3 空档 | **明确 10 us OFF GAP** | **无等价 10 us OFF GAP** |
| Gen3控制 | `gen3_en` → `phy_ctrl.v` 决定 `PHY_RATE=010` | 直接 `phy_rate_cmd=2'b10` |
| TXEQ | 原始 `phy_ctrl.v` 处理 | K02 主动发 preset/query |
| CDR Hold | 原始 `phy_ctrl.v` mimic LTSSM 控制 | K02 在 TXEQ/Gen3 wait 强制拉高 |
| Gen3完成判据 | 等 `debug_state==04` | 直接等 `phy_phystatus` |
| Gen3完成后 | 保持80 us后撤销 `gen3_en` | `DYN_PASS` 后保持 Gen3 rate |

---

## 8. 最值得关注的差异：10 us Gen1 OFF GAP

Golden 中：

```text
Gen1稳定
   ↓
gen1_en = 0
gen2_en = 0
gen3_en = 0
gen4_en = 0
   ↓
等待 10 us
   ↓
gen3_en = 1
```

这个“10 us OFF GAP”不只是一个普通延时。

在原始 `phy_ctrl.v` 中，当它处于 `PHY_BUP_PHY_RDY2` 且检测到：

```text
gen1_en = 0
gen2_en = 0
gen3_en = 0
gen4_en = 0
```

会主动走：

```text
PHY_BUP_PHY_RDY2
      ↓
PHY_BUP_PHY_RDY3
      ↓ 等 PHY_PHYSTATUS
PHY_BUP_PHY_RDY0
      ↓
等待下一次 gen3_en
      ↓
PHY_BUP_PHY_RDY1
      ↓ 等 PHY_PHYSTATUS
PHY_BUP_PHY_RDY2@Gen3
```

也就是说：

> Golden 的 OFF GAP 实际触发了一次完整的 `RDY2 → RDY3 → RDY0` 状态回归，再重新发起 Gen3 请求。

K02 Dynamic 直接把 `phy_rate_cmd` 从 Gen1 改成 Gen3，并没有经过这套 `phy_ctrl` 状态转换。

因此当前最重要的差异不一定只是“10 us 延时长度”，而是：

> **是否遵循了 Xilinx `phy_ctrl` 所要求的完整状态切换语义。**

---

## 9. 第二个关键差异：CDR Hold

Golden：

```text
as_cdr_hold_req
```

由原始 `phy_ctrl.v` 根据其内部模拟 LTSSM 状态产生。

K02 Dynamic：

```text
DYN_TXEQ
DYN_TXEQ_GAP
DYN_QUERY
DYN_QUERY_GAP
DYN_GEN3_WAIT
```

期间主动：

```text
as_cdr_hold_cmd = 1
```

直到 `DYN_PASS` 才释放。

因此 K02 和 Golden 的 CDR hold 拉起/释放时刻并不一致，也应作为后续差分重点。

---

## 10. 当前结论

### 已经证明

1. KCU105 / KU040 的 standalone PCIe PHY 能执行 Gen1 → Gen3 rate change。
2. 当前 Hardware Golden 下：
   - QPLL1RESET 正常拉起并释放；
   - QPLL1LOCK 正常 `1 → 0 → 1`；
   - `phy_bringup_seq` 最终进入 `S_DONE`。
3. 因此当前不应继续把主要怀疑点放在：
   - QPLL1 本身；
   - GTHE3_COMMON 是否能重新锁定；
   - KCU105 是否天然不能 Gen3。

### 尚未证明

1. K02 Dynamic 的直接 PHY command 流程是否等价于 Xilinx `board.v + phy_ctrl.v`。
2. K02 的 Gen1→Gen3 时序是否满足 Xilinx PHY 的完整状态切换语义。
3. K13 完整 Endpoint 的 Gen3 retrain / LTSSM / TS1/TS2 是否正确。

---

## 11. 下一步建议

建议不要继续修改 QPLL/GT 配置，优先对 K02 Dynamic 做最小 A/B Test。

优先级：

### A/B Test 1：补齐 Gen1 OFF GAP

先让 K02 Dynamic 增加与 Golden 等价的：

```text
Gen1
  ↓
全部 rate enable / request 释放
  ↓
等待约 10 us
  ↓
再请求 Gen3
```

重点观察：

```text
QPLL1RESET
QPLL1LOCK
PCIERATEQPLLRESET
PCIERATEGEN3
PCIEUSERGEN3RDY
phy_phystatus
```

### A/B Test 2：对齐 CDR Hold

比较：

```text
Golden as_cdr_hold_req
vs
K02 as_cdr_hold_cmd
```

的拉起/释放时刻。

### A/B Test 3：比较 TXEQ

确认 K02 主动 TXEQ preset/query 与 Xilinx `phy_ctrl.v` 的 TXEQ 时机是否一致。

---

## 12. 当前调试方向

当前问题已经从：

```text
“QPLL1 为什么无法重新锁定？”
```

转变为：

```text
“为什么 Xilinx 原始 Golden 序列可以完成，
而 K02/K13 自研 PHY control 序列仍存在 Gen3 问题？”
```

后续定位重点应放在：

```text
Golden stimulus / phy_ctrl
           VS
K02 / K13 自研 PHY control
```

而不是继续围绕 QPLL1 hardware capability 排查。
