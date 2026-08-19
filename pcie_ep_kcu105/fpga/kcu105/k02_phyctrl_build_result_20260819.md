# K02_USE_PHY_CTRL=1 构建结果

日期：2026-08-19
基线：a80fc26...（K02 顶层 + build script 改动，未提交）
目标：`make k02-phyctrl-vivado` 在 K02 顶层直接实例化 Golden `phy_ctrl.v` + `phy_bringup_seq`，
      旁路 K02 自有 `dynamic_rate_*` FSM。

## 1. 改动摘要

### 1.1 RTL 新增（5 个文件，从 `pcie_phy_0_ex/` 移植）

- `rtl/phy/phy_ctrl.v` — Xilinx 7-series PCIe PHY controller，未改动。
- `rtl/phy/phy_ctrl_pat_gen.v` / `phy_ctrl_pat_gen_lane.v` — `phy_ctrl` 内部子模块，未改动。
- `rtl/phy/phy_ctrl_defines.vh` — `phy_ctrl_pat_gen_lane.v:62` 的 `\`include` 头。
- `rtl/phy/phy_bringup_seq.sv` — board.v 风格的 6 使能 FSM，未改动。

### 1.2 K02 顶层修改

`rtl/phy/kcu105_pcie_phy_bringup_top.sv`：

- 新参数 `K02_USE_PHY_CTRL=1`（**默认 1 = 旁路 K02 FSM，使用 Golden `phy_ctrl.v` + `phy_bringup_seq`**；
  设为 0 保留原 K02 FSM 行为，作 fallback / A/B 参照）。
- 新参数 `K02_PHY_CTRL_*_NS`（5 个，phy_bringup_seq 计时预算，默认值与 `pcie_phy_0_ex/board_kcu105/phy_bringup_seq.sv` 一致）。
- 顶层 wire：`phy_txdata_w` / `phy_txdatak_w` / ... / `phy_rxeq_txpreset_w`，
  共 13 个 wrapper 输入抽取为 `logic` 信号（K02_USE_PHY_CTRL=0 时由 always_comb 拉常数 0，
  K02_USE_PHY_CTRL=1 时由 Golden `phy_ctrl.v` 的 ctrl_* 输出驱动）。
- 顶层 wire：`ctrl_txdata` / `ctrl_phy_rate` / `as_cdr_hold_req` / `as_mac_in_detect` / ...，
  phy_ctrl.v 的输出。当 K02_USE_PHY_CTRL=1 时实例化。
- 顶层 wire：`seq_tx_elec_idle` / `seq_gen1_en` / `seq_gen3_en` / ...，phy_bringup_seq 的输出。
  当 K02_USE_PHY_CTRL=1 时实例化。
- `always_comb` 顶层：增加 `if (K02_USE_PHY_CTRL != 0) ... else ...` 分支；
  if 分支让 `phy_ctrl.v` 直接驱动所有 wrapper 输入信号 + 标记 debug 的 FSM 命令；
  else 分支保留原 K02 FSM 逻辑（A/B 变量、direct_gen3、off_gap 全部不变）。
- `always_ff` 顶层：K02 FSM body 包裹在 `if (K02_USE_PHY_CTRL == 0)` 内；
  K02_USE_PHY_CTRL=1 时 FSM 旁路，`heartbeat_count` 仍递增。
- `generate if (K02_USE_PHY_CTRL != 0)` 实例化 phy_bringup_seq + phy_ctrl。
- K02 wrapper (`kcu105_pcie_phy_wrapper.sv`) 接口**未改**，K01 共用不受影响。
- LED 映射在两种模式下使用不同语义：
  - K02_USE_PHY_CTRL=0：原 K02 诊断灯（receiver_present / detect_done / detect_timeout / heartbeat）。
  - K02_USE_PHY_CTRL=1：复用同一组灯显示 `phy_bringup_seq` 进度：
    `led[1]=gen3_request`, `led[2]=(phy_ctrl.debug_state==8'h04)`,
    `led[5]=(seq_state==S_DONE)`, `led[6]=ctrl_as_cdr_hold_req`。
  - synthesis 时三目运算会被常量折叠，对 K02_USE_PHY_CTRL=0 路径无影响。

### 1.3 Build Script 修改

- `fpga/kcu105/run_k02_impl.tcl`：
  - 新 env var `K02_USE_PHY_CTRL`；当 =1 时使用 build 目录 `build_k02_phyctrl/` + stem `k02_pcie_phy_bringup_phyctrl`。
  - `read_verilog` 当 K02_USE_PHY_CTRL=1 时额外读 `phy_ctrl_pat_gen_lane.v` / `phy_ctrl_pat_gen.v` / `phy_ctrl.v` / `phy_bringup_seq.sv`。
  - `synth_design` 末尾加 `-generic K02_USE_PHY_CTRL=$k02_use_phy_ctrl`。
  - ILA probe 分两套布局：K02_USE_PHY_CTRL=1 探 GT 关键 pin + phy_ctrl debug_state / phy_rate_cmd / as_cdr_hold_cmd；
                     K02_USE_PHY_CTRL=0 保留原 80-bit 探针 + 3-bit bup_state。
  - impl_summary.txt 末尾追加 `K02_USE_PHY_CTRL=$k02_use_phy_ctrl`。
- `fpga/kcu105/run_k02_hw.tcl`：env var + build_dir 选择同步。
- `fpga/kcu105/run_k02_impl.sh`：warning allowlist 不变（phy_ctrl.v 没引入新 ID）。
- Makefile：新增 `k02-phyctrl-vivado` / `k02-phyctrl-hw-probe` / `k02-phyctrl-hw-program` 三个 target。

## 2. 构建结果

```
$ K02_USE_PHY_CTRL=1 ./fpga/kcu105/run_k02_impl.sh
K02_IMPL_PASS channel=GTHE3_CHANNEL_X0Y7 common=GTHE3_COMMON_X0Y1 WNS=0.792 use_phy_ctrl=1
```

impl_summary.txt:

```
K02_IMPL_PASS
part=xcku040-ffva1156-2-e
top=kcu105_pcie_phy_bringup_top
GTHE3_CHANNEL_COUNT=1
GTHE3_CHANNEL_LOC=GTHE3_CHANNEL_X0Y7
GTHE3_COMMON_COUNT=1
GTHE3_COMMON_LOC=GTHE3_COMMON_X0Y1
PCIE_HARD_BLOCK_COUNT=0
WNS=0.792
K02_ILA_DEBUG=1
GEN3_TEST_MODE=1
DYNAMIC_RATE_TEST_MODE=0
DYNAMIC_COEFF_QUERY_MODE=0
DYNAMIC_GEN1_OFF_GAP_MODE=0
DYNAMIC_GEN1_OFF_GAP_CYCLES=2500
DIRECT_GEN3_MODE=0
DYNAMIC_START_DELAY_CYCLES=1024
DYNAMIC_MAC_IN_DETECT_LOW_MODE=0
DYNAMIC_CDR_HOLD_LOW_MODE=0
DYNAMIC_SKIP_TXEQ_MODE=0
K02_USE_PHY_CTRL=1
bitstream=/home/wx/Documents/PCIe/pcie_ep_kcu105/fpga/kcu105/build_k02_phyctrl/k02_pcie_phy_bringup_phyctrl_ila.bit
```

资源：1× GTHE3_CHANNEL（X0Y7） + 1× GTHE3_COMMON（X0Y1），与 K02 IP 自带配置一致。
警告：K02 IP 固定 allowlist 通过（`run_k02_impl.sh` 末尾的严格集合校验）。

Worst Setup Slack = 0.792 ns，Hold Slack 通过，无时序违例。

## 3. 验证矩阵（实板 ILA）

| 期望项 | probe0 | probe1 |
|--------|--------|--------|
| `QPLL1LOCK` 1→0→1 切换 | QPLL1LOCK / QPLL1RESET | — |
| `phy_rate_cmd` 0b00→0b10 | phy_rate_cmd[1:0] | — |
| `phy_powerdown` 0b10→0b00 | phy_powerdown[1:0] | — |
| `phy_txelecidle_cmd` 周期性拉低 | phy_txelecidle_cmd | — |
| `debug_state` 0x04 出现 ≥1 次 | phy_ctrl_debug_state_w[7:0] | — |
| `as_cdr_hold_cmd` 受 ltssm_mimic 控制 | as_cdr_hold_cmd | — |
| `as_mac_in_detect_cmd` 受 ltssm_mimic 控制 | as_mac_in_detect_cmd | — |
| PCIE rate handshake | PCIERATEQPLLRESET / PCIERATEGEN3 / PCIEUSERGEN3RDY | — |
| `seq_state` 走完 S_POWER_UP→S_DONE | — | seq_state_w[3:0] |
| `gen1_en` / `gen3_en` 切换 | — | gen1_en_w / gen3_en_w |
| `gen3_request` 在 GEN3 阶段拉高 | — | gen3_request_w |
| phy_status 上升沿 | — | u_phy_wrapper/phy_phystatus |
| phy_phystatus_rst 释放 | — | u_phy_wrapper/phy_phystatus_rst |

## 4. 验证记录

- 期望：`seq_state` 走到 `S_DONE`（4'd8），`phy_ctrl.debug_state` 在 `S_GEN3_WAIT`/`S_GEN3_HOLD` 期间
  出现 `8'h04`，`QPLL1LOCK` 经历 1→0→1 切换。
- 与 cell #3 (`pcie_phy_0_ex/board_kcu105/build_k02_phy_cross/`) 的 cell #3 一致：
  同一 K02 `pcie_phy_x1_gen3` PHY IP，同一 `phy_ctrl.v` 控制器，仅 wiring 路径不同
  （cell #3 走 `kcu105_pcie_phy_wrapper_k02` + `kcu105_pcie_phy_bringup_top_k02`；
   K02_USE_PHY_CTRL=1 走原 K02 wrapper + K02 顶层旁路 FSM）。
- **实板 ILA 抓取：2026-08-19 验证 PASS**。
  - `seq_state` 走完 `S_RESET→S_WAIT_READY→S_POWER_UP→S_GEN1_WAIT→S_GEN1_HOLD→S_GEN1_OFF_GAP→S_GEN3_WAIT→S_GEN3_HOLD→S_DONE`。
  - `debug_state==8'h04` 在 `S_GEN3_WAIT` / `S_GEN3_HOLD` 期间出现。
  - `QPLL1LOCK` 1→0→1 切换。
  - `as_cdr_hold_req` / `as_mac_in_detect` 由 `phy_ctrl.v` 的 `ltssm_mimic` 控制，与 cell #3 一致。
- **结论：K02 Gen1→Gen3 dynamic rate 修复闭环。**
  K02 顶层 `K02_USE_PHY_CTRL=1` 路径是 K02 PHY 的 Gen3 working solution。

## 5. 后续步骤

### 已完成

1. ✅ **回归 K02_USE_PHY_CTRL=0**：`make k02-lint`（带 `-GK02_USE_PHY_CTRL=0`）PASS，exit 0；
   `k02-phyctrl-vivado` 与 `k02-vivado` 两条路径在 K02 wrapper 接口上逻辑等价。
2. ✅ **把 K02_USE_PHY_CTRL=1 设为默认**：默认参数从 0 改成 1；
   `run_k02_impl.tcl` 在 env var 未设置时默认 1；`make k02-phyctrl-vivado` 不再需要 env 前缀。
   `make k02-phyctrl-vivado` 重跑：`K02_IMPL_PASS WNS=0.792 use_phy_ctrl=1`，
   bitstream 落到 `build_k02_phyctrl/k02_pcie_phy_bringup_phyctrl_ila.bit`。

### 剩余

3. **清理旧的 K02 FSM**：将 `dynamic_rate_*` FSM 与 A/B 3 变量 (`DYNAMIC_MAC_IN_DETECT_LOW_MODE` /
   `DYNAMIC_CDR_HOLD_LOW_MODE` / `DYNAMIC_SKIP_TXEQ_MODE`) 删除或标 deprecated；这些 4 个 A/B bitstream
   (`build_k02_ab_mac*` / `_cdr*` / `_skiptxeq*` / `_all`) 已 commit 归档但不再被主线使用。
4. **更新 lint / verilator / VCS harness**：`sim/verilator/k02/` 和 `sim/vcs/` 需为新参数添加 case。
5. **删 cell #3**：cell #3 (`pcie_phy_0_ex/board_kcu105/build_k02_phy_cross/`) 是 2x2 验证产物，
   验证目标已达成，可保留作为参考但不再需要重建。

## 6. 相关文件

- `fpga/kcu105/build_k02_phyctrl/k02_pcie_phy_bringup_phyctrl_ila.bit` — 实板烧录位流（16 MB）。
- `fpga/kcu105/build_k02_phyctrl/k02_pcie_phy_bringup_phyctrl_ila.ltx` — ILA probe 描述（27 KB）。
- `fpga/kcu105/build_k02_phyctrl/impl_summary.txt` — K02_IMPL_PASS 元数据。
- `pcie_phy_0_ex/k02_2x2_phy_cross_result_20260819.md` — 上一步 2×2 cell #3 验证记录。
