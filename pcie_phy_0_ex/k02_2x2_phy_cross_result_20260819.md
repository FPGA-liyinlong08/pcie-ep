# K02 Gen1→Gen3 2×2 Controller × PHY IP 交叉实验结论

日期：2026-08-19
基线：`73e381c7fbee8254dda8051c81432265d8c5a5c7`
对应 bitstream：`pcie_phy_0_ex/board_kcu105/build_k02_phy_cross/`

## 1. 实验目标

定位 K02 Gen1→Gen3 失败 (`dynamic_rate_state==8'h05`) 的根因在控制器侧还是 PHY IP/GT 配置侧。四个 bitstream 排列：

| Cell | Controller | PHY IP | 期望 | 实板结果 |
|------|------------|--------|------|----------|
| baseline | Golden `phy_ctrl.v` | Golden `pcie_phy_0` | PASS | PASS（已确认） |
| A      | K02 `dynamic_rate_*` FSM | K02 `pcie_phy_x1_gen3` | 任意 | **FAIL**：4 个 A/B bitstream 全部停在 `dynamic_rate_state==8'h05` |
| B (#3) | Golden `phy_ctrl.v` | K02 `pcie_phy_x1_gen3` | 隔离 | **PASS**：`seq_state` 走到 `S_DONE`，`debug_state==8'h04` 出现 |
| C (#4) | K02 FSM | Golden `pcie_phy_0` | 留待 | 未做（B 已得结论，C 无新增信息） |

## 2. Cell B 实验结构

### 2.1 文件清单

- `pcie_phy_0_ex/board_kcu105/kcu105_pcie_phy_wrapper_k02.sv`（新）
  - 完全照抄 `kcu105_pcie_phy_wrapper.sv`（Golden）的结构
  - 把 IP module name 由 `pcie_phy_0` 换成 `pcie_phy_x1_gen3`
  - 把 `phy_gtrefclk` 接到 K02 IP（Golden wrapper 漏接这个信号）
- `pcie_phy_0_ex/board_kcu105/kcu105_pcie_phy_bringup_top_k02.sv`（新）
  - 完全照抄 `kcu105_pcie_phy_bringup_top.sv`（Golden）
  - 实例化新的 wrapper
  - 探针 1:1 复用 Golden 的 debug 探针
- `pcie_phy_0_ex/board_kcu105/build_k02_phy_cross.tcl`（新）
  - 完全照抄 `build_hardware_golden.tcl`
  - `read_ip` 指向 K02 已有的 `pcie_phy_x1_gen3.xci`（**不重新生成 IP**）
  - IP module name 由 `pcie_phy_0` 改为 `pcie_phy_x1_gen3`
  - impl summary 标记 `K02_PHY_CROSS_IMPL_PASS`

### 2.2 K02 PHY IP 复用

XCI 直接 `read_ip` 自 K02 项目：

```
pcie_ep_kcu105/fpga/kcu105/ip/pcie_phy_x1_gen3/pcie_phy_x1_gen3.xci
```

这个 XCI 与 Golden 的 `pcie_phy_0` 是 **同一个 Xilinx IP** (`xilinx.com:ip:pcie_phy:1.0`)，区别仅在 K02 用的具体配置：8.0_GT/s、QPLL1、GTHE3_CHANNEL_X0Y7、Add-in_Card ins_loss、`tx_preset=4`、gtwiz_in_core=1、gtcom_in_core=1、phy_async_en=true、ASPM=No_ASPM、pipeline_stages=0。端口集与 Golden 完全一致。

### 2.3 控制路径

`phy_bringup_seq` → 6 个使能 → `phy_ctrl.v`（**未改动**） → `pcie_phy_x1_gen3`。

与 baseline Golden 的唯一差异：PHY IP 实体。

## 3. 构建结果

```
K02_PHY_CROSS_IMPL_PASS
controller=Golden_phy_ctrl
phy_ip=K02_pcie_phy_x1_gen3
k02_xci=.../pcie_ep_kcu105/fpga/kcu105/ip/pcie_phy_x1_gen3/pcie_phy_x1_gen3.xci
part=xcku040-ffva1156-2-e
GTHE3_COMMON_LOC=GTHE3_COMMON_X0Y1
GTHE3_CHANNEL_LOC=GTHE3_CHANNEL_X0Y7
probe0_width=22
probe1_width=12
bitstream=.../build_k02_phy_cross/pcie_phy_0_ex_hardware_golden_k02_phy_ila.bit
probes=.../build_k02_phy_cross/pcie_phy_0_ex_hardware_golden_k02_phy_ila.ltx
```

Worst Setup Slack = 28.964 ns，Hold Slack = 0.045 ns，无时序违例。资源 1× GTHE3_CHANNEL + 1× GTHE3_COMMON，与 K02 IP 自带配置一致。

警告仅 Golden 同款 `PDCN-1569` / `RTSTAT-10`（debug hub 已知），无新增 warning。

## 4. 实板结果

`seq_state` 走完 `S_RESET → S_WAIT_READY → S_POWER_UP → S_GEN1_WAIT → S_GEN1_HOLD → S_GEN1_OFF_GAP → S_GEN3_WAIT → S_GEN3_HOLD → S_DONE`。

ILA 关键证据：
- `seq_state==8` (`S_DONE`) 到达
- `debug_state==8'h04` 在 `S_GEN3_WAIT` / `S_GEN3_HOLD` 期间出现
- QPLL1LOCK 1→0→1
- `as_cdr_hold_req` 由 `phy_ctrl.v` 的 ltssm_mimic 控制，与 baseline 行为一致
- `as_mac_in_detect` 同样由 ltssm_mimic 控制

## 5. 结论

**K02 的 `pcie_phy_x1_gen3` PHY IP / GT 配置完全正确。** 在 Golden `phy_ctrl.v` + `phy_bringup_seq` 驱动下，K02 PHY 能完成 Gen1→Gen3 完整转换。

把 K02 FSM + K02 PHY 失败的差异（Cell A）归因到 K02 控制器：`pcie_ep_kcu105/rtl/phy/kcu105_pcie_phy_bringup_top.sv` 内的 `dynamic_rate_*` 状态机在 `DYN_GEN3_WAIT` 期间没有给 PHY 正确的控制序列。

## 6. 下一步建议

1. **直接替换 K02 FSM 为 Golden `phy_ctrl.v` + `phy_bringup_seq`**：把 Cell B 的 wiring 移植到 K02 项目，使 K02 也用同一套 board.v 风格的 6 个使能驱动 PHY。K02 自身的 `DYN_GEN1_STABLE` / `DYN_GEN1_OFF_GAP` / `DYN_GEN3_WAIT` 节奏可以保留为 `phy_bringup_seq` 的 SEQ_CLK 计数器输入或作为高一层 supervisor。
2. **保留 K02 FSM 但逐项对齐 Golden 时序**：在 K02 FSM 内部用 4-bit `seq_state` 复现 `S_POWER_UP → S_DONE` 的 6 个使能曲线，重点核对 OFF GAP 时长、TXEQ_CTRL/PRESET/COEFF、as_cdr_hold_req 的进入与撤除时序。
3. **Cell C**（K02 FSM + Golden PHY）：本可做但 Cell B 已得结论，C 主要是给后续"对比控制时序差异"提供 ILA 证据，可作为回归项。

A/B 4 个 bitstream（mac / cdr / skiptxeq / all 三开）记录仍保留在 `pcie_ep_kcu105/fpga/kcu105/build_k02_ab_*/`，未 commit。
