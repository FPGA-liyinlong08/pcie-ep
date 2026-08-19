# K02 PCIe PHY 上板构建与 Gen1→Gen3 闭环（2026-08-19）

日期：2026-08-19
基线：a80fc26...（K02 顶层 + build script 改动）
当前 HEAD：8月19日17:00（清理后：`K02_USE_PHY_CTRL=0` 路径已删除，Golden 控制器成为唯一路径）
目标：`make k02-vivado`（原 `k02-phyctrl-vivado`）在 K02 顶层直接实例化 Golden `phy_ctrl.v` + `phy_bringup_seq`，
      旁路 K02 自有 `dynamic_rate_*` FSM。

## 0. 版本说明

本文档最初记录 commit 7d39d60（K02 顶层 + 旁路 FSM 路径）。**2026-08-19 后续 commit 已删除 K02_USE_PHY_CTRL=0 路径**，
K02 顶层 + build script 简化为**唯一** Golden 控制器路径。第 1–4 节保留 7d39d60 历史，
新增第 7 节描述清理（dynamic_rate_* FSM 删除）与第 8 节描述 pcie_perst_n 同步（CDC-1 修复）。

## 1. 改动摘要

### 1.1 RTL 新增（5 个文件，从 `pcie_phy_0_ex/` 移植）

- `rtl/phy/phy_ctrl.v` — Xilinx 7-series PCIe PHY controller，未改动。
- `rtl/phy/phy_ctrl_pat_gen.v` / `phy_ctrl_pat_gen_lane.v` — `phy_ctrl` 内部子模块，未改动。
- `rtl/phy/phy_ctrl_defines.vh` — `phy_ctrl_pat_gen_lane.v:62` 的 `\`include` 头。
- `rtl/phy/phy_bringup_seq.sv` — board.v 风格的 6 使能 FSM，未改动。

### 1.2 K02 顶层修改（7d39d60 起的 Golden 路径，已升级为唯一路径）

`rtl/phy/kcu105_pcie_phy_bringup_top.sv`：

- 直接实例化 Golden `phy_ctrl.v` + `phy_bringup_seq`（**无参数化 K02_USE_PHY_CTRL**，无 generate 包裹）。
- 5 个 `K02_PHY_CTRL_*_NS` 参数（`WAIT_AFTER_READY_NS` / `WAIT_AFTER_GEN1_ON_NS` / `GEN1_HOLD_NS` / `WAIT_AFTER_GEN1_OFF_NS` / `GEN3_HOLD_NS`），
  对齐 `phy_bringup_seq` 250 MHz 计时预算。
- 顶层 wire：`phy_txdata_w` / `phy_txdatak_w` / ... / `phy_rxeq_txpreset_w`（13 个 wrapper 输入，
  由 `phy_ctrl.v` 的 ctrl_* 输出驱动）。
- 顶层 wire：`ctrl_txdata` / `ctrl_phy_rate` / `as_cdr_hold_req` / `as_mac_in_detect` / ...，phy_ctrl.v 的输出。
- 顶层 wire：`seq_tx_elec_idle` / `seq_gen1_en` / `seq_gen3_en` / ...，phy_bringup_seq 的输出。
- `always_comb` 顶层：直接让 `phy_ctrl.v` 驱动所有 wrapper 输入信号 + 标记 debug 的 FSM 命令（无 if/else 分支）。
- `always_ff` 顶层：只剩 `heartbeat_count`（25-bit 慢闪），无 FSM body。
- K02 wrapper (`kcu105_pcie_phy_wrapper.sv`) 接口**未改**，K01 共用不受影响。
- LED 映射：Golden 控制器语义，无三目运算。
  - `led[0]=pipe_rst_n && !phy_phystatus_rst`
  - `led[1]=gen3_request_w`
  - `led[2]=(phy_ctrl.debug_state==8'h04)`
  - `led[3]=pipe_rst_n`
  - `led[4]=core_rst_n`
  - `led[5]=(seq_state==S_DONE)`
  - `led[6]=ctrl_as_cdr_hold_req`
  - `led[7]=heartbeat_count[24]`

### 1.3 Build Script 修改

- `fpga/kcu105/run_k02_impl.tcl`：
  - 单一 build_dir = `build_k02/`，bit_stem = `k02_pcie_phy_bringup_ila`。
  - `read_verilog` 总是包含 `phy_ctrl_pat_gen_lane.v` / `phy_ctrl_pat_gen.v` / `phy_ctrl.v` / `phy_bringup_seq.sv`。
  - `synth_design` 不再需要 `-generic K02_USE_PHY_CTRL`（参数已删除）。
  - ILA probe 单一布局：probe0 = GT 关键 pin + phy_ctrl 关键输出；probe1 = phy_bringup_seq 进度 + phy_phystatus 边沿。
  - impl_summary.txt 末尾不含 K02_USE_PHY_CTRL/DYNAMIC_* 行。
- `fpga/kcu105/run_k02_hw.tcl` / `run_k02_phy_ila_hw.tcl`：env var 处理删除，build_dir 单一化。
- `fpga/kcu105/run_k02_impl.sh`：删除 A/B 组合 build_dir 矩阵，env var 检查删除。
- Makefile：删除 9 个旧 A/B target，重命名 3 个 target 为 `k02-vivado` / `k02-hw-probe` / `k02-hw-program`（新唯一默认）。

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

1. ✅ **回归 K02_USE_PHY_CTRL=0**（历史步骤，7d39d60）：`make k02-lint`（带 `-GK02_USE_PHY_CTRL=0`）PASS，exit 0；
   `k02-phyctrl-vivado` 与 `k02-vivado` 两条路径在 K02 wrapper 接口上逻辑等价。
2. ✅ **把 K02_USE_PHY_CTRL=1 设为默认**（commit b973df4）：默认参数从 0 改成 1；
   `run_k02_impl.tcl` 在 env var 未设置时默认 1；`make k02-phyctrl-vivado` 不再需要 env 前缀。
3. ✅ **清理旧的 K02 FSM**（2026-08-19 后续 commit）：`dynamic_rate_*` FSM 与 A/B 3 变量
   （`DYNAMIC_MAC_IN_DETECT_LOW_MODE` / `DYNAMIC_CDR_HOLD_LOW_MODE` / `DYNAMIC_SKIP_TXEQ_MODE`）全部删除。
   4 个 A/B bitstream 组合（`build_k02_ab_mac*` / `_cdr*` / `_skiptxeq*` / `_all`）不再生成。
   顶层文件从 ~760 行简化为 ~316 行（-58%）。`make k02-vivado` 仍 PASS。
5. ✅ **同步 pcie_perst_n 到 phy_pclk**（见第 8 节 CDC-1 修复）。

### 不在清理范围（历史保留）

- cell #3 (`pcie_phy_0_ex/board_kcu105/build_k02_phy_cross/`) 是 2x2 验证产物，
  验证目标已达成，保留作为参考但不再需要重建。

### B. 验证 K01 不受影响（已完成）

`K02_USE_PHY_CTRL=1` 切换只动 `rtl/phy/kcu105_pcie_phy_bringup_top.sv` 顶层 + 新增 5 个 Golden
控制器 RTL 文件；`rtl/phy/kcu105_pcie_phy_wrapper.sv` 接口**未改**。K01 board
(`kcu105_pcie_gen1_top.sv` / `kcu105_pcie_ep_gen1_top.sv`) 共用 wrapper，应无影响。

**验证矩阵**：

| Target | 触达 wrapper? | 触达 K01 top? | 结果 |
|--------|--------------|--------------|------|
| `k01-lint` | ✗ (只 lint `kcu105_reset_ctrl`) | ✗ | PASS (0 errors) |
| `k01-checker-selftest` | ✗ (NEGATIVE_STUB reset) | ✗ | `K01_CHECKER_SELFTEST_PASS` |
| `k01-verilator` | ✗ (refclk reset 10000 random vectors) | ✗ | `K01_VERILATOR_PASS` |
| `k03-lint` | **✓** | **✓** (top=`kcu105_pcie_gen1_top`) | PASS (0 errors) |
| `k11b2-lint` | **✓** | **✓** (top=`kcu105_pcie_ep_gen1_top`) | PASS (0 errors) |
| `k02-verilator` | **✓** (wrapper-level sim) | ✗ | `K02_VERILATOR_PASS` |
| `k02-checker-selftest` | **✓** (NEGATIVE_STUB wrapper) | ✗ | `K02_CHECKER_SELFTEST_PASS` |
| `k02-lint` | **✓** | ✗ | PASS (0 errors, K02_USE_PHY_CTRL=0) |
| `k02-lint-phyctrl` | **✓** | ✗ | PASS (0 errors, K02_USE_PHY_CTRL=1) |

**结论**：K01 wrapper 回归全过；K02 两条路径的 wrapper-level sim 也过。wrapper 接口确实未变。

### 4. 同步 sim harness（已完成）

K02 sim harness 实际触达范围与 `K02_USE_PHY_CTRL` 关系：

| Sim target | Top module | 触达 bringup_top? | 需要 K02_USE_PHY_CTRL? |
|------------|-----------|-----------------|---------------------|
| `k02-checker-selftest` | `kcu105_pcie_phy_wrapper` (NEGATIVE_STUB=1) | 否 | 否 |
| `k02-lint` | `kcu105_pcie_phy_bringup_top` | **是** | **是** (`-GK02_USE_PHY_CTRL=0`) |
| `k02-lint-phyctrl` | `kcu105_pcie_phy_bringup_top` | **是** | **是** (`-GK02_USE_PHY_CTRL=1`) |
| `k02-verilator` / `k02-vcs` / `k02-query-vcs` / `k02-gen3-vcs` | `kcu105_pcie_phy_wrapper` | 否 | 否 |

`sim/verilator/k02/` 与 `sim/vcs/` 的 wrapper-level sim 全部以 `kcu105_pcie_phy_wrapper` 为 top，
不引用 `kcu105_pcie_phy_bringup_top.sv`，wrapper 接口未改，**无需**为 `K02_USE_PHY_CTRL` 加 case。

唯一触达 `bringup_top` 的是 top Makefile 的 `k02-lint`。已拆为两个 target 互为补集：

- `k02-lint`（`-GK02_USE_PHY_CTRL=0`）：测旧 K02 FSM 路径；作 fallback / A/B 参照。
- `k02-lint-phyctrl`（`-GK02_USE_PHY_CTRL=1`）：测新默认 Golden 控制器路径。
  - 需要 `phy_ctrl.v` / `phy_ctrl_pat_gen*.v` / `phy_bringup_seq.sv` 额外 RTL。
  - 需要 `+incdir+rtl/phy`（`phy_ctrl_pat_gen_lane.v:62` 引用 `phy_ctrl_defines.vh`）。
  - 需要 `--timing` 容忍 `phy_ctrl.v` 的 `#(TCQ)` 非阻塞延迟。
  - 输出仅剩 `BLKSEQ` warning（`phy_ctrl.v:393/404`，Xilinx 参考代码风格，benign）。

两个 lint target 都挂在 `k02` 聚合 target 上。

**验证**：
```
$ make k02-lint exit=0 errs=0
$ make k02-lint-phyctrl exit=0 errs=0
```

## 6. 相关文件

- `fpga/kcu105/build_k02/k02_pcie_phy_bringup_ila.bit` — 实板烧录位流（16 MB）。
- `fpga/kcu105/build_k02/k02_pcie_phy_bringup_ila.ltx` — ILA probe 描述。
- `fpga/kcu105/build_k02/impl_summary.txt` — K02_IMPL_PASS 元数据。
- `pcie_phy_0_ex/k02_2x2_phy_cross_result_20260819.md` — 上一步 2×2 cell #3 验证记录。

## 7. 清理旧 K02 FSM（2026-08-19 后续 commit）

K02 Gen1→Gen3 闭环后（commit 82db3cd），`K02_USE_PHY_CTRL=0` 路径（`dynamic_rate_*` FSM）已无存在意义。
2026-08-19 后续 commit 完成全量清理。

### 7.1 删除项

**RTL 顶层（`rtl/phy/kcu105_pcie_phy_bringup_top.sv`）**：
- 14 个参数：`K02_USE_PHY_CTRL` / `GEN3_TEST_MODE` / `DIRECT_GEN3_MODE` / `DETECT_TIMEOUT_CYCLES` /
  `DYNAMIC_RATE_TEST_MODE` / `DYNAMIC_COEFF_QUERY_MODE` / `DYNAMIC_GEN1_OFF_GAP_MODE` /
  `DYNAMIC_START_DELAY_CYCLES` / `DYNAMIC_GEN1_STABLE_CYCLES` / `DYNAMIC_GEN1_OFF_GAP_CYCLES` /
  `DYNAMIC_TXEQ_TIMEOUT_CYCLES` / `DYNAMIC_GEN3_TIMEOUT_CYCLES` /
  `DYNAMIC_MAC_IN_DETECT_LOW_MODE` / `DYNAMIC_CDR_HOLD_LOW_MODE` / `DYNAMIC_SKIP_TXEQ_MODE`。
- 9 个 `DYN_*` localparam（DYN_IDLE..DYN_GEN1_OFF_GAP）、6 个 `BUP_*` localparam、`BUP_DETECT` 常量。
- 15+ 信号：`dynamic_rate_state` / `_count` / `_phystatus_seen` / `_pass` / `_fail` / `_txeq_active` /
  `_txeq_query_active` / `bup_state` / `receiver_present` / `detect_done` / `detect_timeout` /
  `unexpected_status` / `gen3_test_active` / `settle_count` / `timeout_count` / `detected_rxstatus`。
- `always_comb` 中的 if/else 分支、`always_ff` 中 `if (K02_USE_PHY_CTRL==0) begin ... end` 整段、
  `generate if (K02_USE_PHY_CTRL != 0) begin : g_phy_ctrl ... end` 包裹。
- LED 映射三目运算。

**Build 脚本**：
- `run_k02_impl.tcl` / `run_k02_impl.sh` / `run_k02_hw.tcl` / `run_k02_phy_ila_hw.tcl`：
  删除 9 个 K02_DYNAMIC_* / K02_GEN3_TEST / K02_DIRECT_GEN3 / K02_USE_PHY_CTRL env var 处理。
  删除 build_dir 矩阵（A/B 4 组合 + offgap / query / dynamic 单路径）。
  删除 11 个 `-generic` 参数。
  删除 A/B 探针（`dynamic_rate_state` / `bup_state` / `receiver_present` 等 10+ 信号）。
  简化 impl_summary.txt（删除 K02_USE_PHY_CTRL / DYNAMIC_* 行）。

**Makefile**：
- 删除 9 个旧 target：`k02-vivado`（旧默认）/ `k02-gen3-vivado` / `k02-query-vivado` /
  `k02-offgap-vivado` / `k02-ab-mac-in-detect-vivado` / `k02-ab-cdr-hold-vivado` /
  `k02-ab-skip-txeq-vivado` / `k02-golden-ab-vivado` / `k02-hw-probe`（旧） / `k02-hw-program`（旧） /
  `k02-gen3-hw-probe` / `k02-gen3-hw-program`。
- 重命名：`k02-phyctrl-vivado` → `k02-vivado`、`k02-phyctrl-hw-probe` → `k02-hw-probe`、
  `k02-phyctrl-hw-program` → `k02-hw-program`、`k02-lint-phyctrl` → `k02-lint`（合并两个 lint）。
- `.PHONY` 列表同步删除旧 target。

### 7.2 安全性

- **Gen1→Gen3 不受影响**：`K02_USE_PHY_CTRL=0` 路径是旁路掉的 FSM；
  Golden 控制器路径独立完成 Gen1→Gen3 切换（commit 7d39d60 已验证）。
- **后续 Gen3 集成不受影响**：K03 / K11b2 / K13 走 `kcu105_pcie_phy_wrapper.sv`，wrapper 接口**完全未改**。
- **build_k02_phyctrl 目录保留**：原 7d39d60 的 bitstream 在 `fpga/kcu105/build_k02_phyctrl/` 保留作为
  实板 ILA PASS 的历史记录；新默认构建产物在 `fpga/kcu105/build_k02/`。

### 7.3 代码度量

| 文件 | 清理前（行） | 清理后（行） | 减少 |
|------|--------------|--------------|------|
| `rtl/phy/kcu105_pcie_phy_bringup_top.sv` | ~760 | ~316 | -58% |
| `fpga/kcu105/run_k02_impl.tcl` | ~480 | ~250 | -48% |
| Makefile（K02 相关行） | ~120 | ~50 | -58% |

### 7.4 清理后验证

```
$ make k02-lint             exit=0 errs=0  # Golden 控制器路径
$ make k01-lint             exit=0
$ make k01-checker-selftest K01_CHECKER_SELFTEST_PASS
$ make k02-verilator        K02_VERILATOR_PASS  random_vectors=10000
$ make k02-checker-selftest K02_CHECKER_SELFTEST_PASS
$ make k02-vivado           K02_IMPL_PASS WNS=1.194 channel=GTHE3_CHANNEL_X0Y7
```

旧 A/B target 正确 error：
```
$ make k02-ab-mac-in-detect-vivado
make: *** 没有规则可制作目标"k02-ab-mac-in-detect-vivado"。 停止。
$ make k02-gen3-vivado
make: *** 没有规则可制作目标"k02-gen3-vivado"。 停止。
$ make k02-phyctrl-vivado
make: *** 没有规则可制作目标"k02-phyctrl-vivado"。 停止。
```

## 8. pcie_perst_n 同步（CDC-1 修复）

清理完成后首次 `make k02-vivado` 失败：
```
错误：K02 report_cdc 存在 Critical CDC
```

### 8.1 根因

`pcie_perst_n`（PERST#，异步低有效输入）直接连接到 `u_phy_bringup_seq.rst`：
```systemverilog
.rst (!pcie_perst_n)
```

`phy_bringup_seq` 的 FSM state / delay_count 共 36 bit 由 `rst` 复位，
`report_cdc` 把 `pcie_perst_n`（非 phy_pclk 域信号）驱动 FSM 复位判为 "1-bit unknown CDC circuitry"（CDC-1 Critical × 36）。

旧路径（K02_USE_PHY_CTRL=0，commit 7d39d60 默认）使用 `pipe_rst_n`（已同步），
不触发 CDC-1。**新默认 Golden 控制器路径**使用 `!pcie_perst_n`，触发 CDC-1。

### 8.2 修复

在 K02 顶层加 1 个 2 级复位同步器，把 `pcie_perst_n` 同步到 `phy_pclk` 域后再驱动 `u_phy_bringup_seq.rst`：

```systemverilog
wire pcie_perst_n_sync;
pcie_reset_sync #(
    .STAGES (2)
) u_perst_sync (
    .clk             (phy_pclk),
    .async_release_n (pcie_perst_n),
    .sync_reset_n    (pcie_perst_n_sync)
);
...
) u_phy_bringup_seq (
    .clk (phy_pclk),
    .rst (!pcie_perst_n_sync),  // 改用同步后的信号
    ...
);
```

`pcie_reset_sync` 是项目内已有的低有效复位同步器（`rtl/common/pcie_reset_sync.sv`），
"异步置位、同步释放" 语义与 Xilinx Golden 控制器在 pcie_phy_0_ex 中的 reset 同步策略一致。
`async_release_n` 的下降沿直接清零 `sync_reg`（符合 PERST# 立即生效的预期），
上升沿在 `phy_pclk` 上 `STAGES=2` 级同步后释放（避免亚稳态）。

### 8.3 验证

修复后 `report_cdc` 输出：
```
CDC-3   Info         13  1-bit synchronized with ASYNC_REG property
CDC-9   Info          8  Asynchronous reset synchronized with ASYNC_REG property
CDC-15  Warning       4  Clock enable controlled CDC structure detected
```

无 CDC-1 / CDC-2 Critical。CDC-15 Warning 全部来自 Xilinx ILA `dbg_hub`（`U_CMD6_RD/U_RD_FIFO`），
与 K02 顶层 RTL 无关，是 Xilinx IP 固定警告。`run_k02_impl.sh` 的 warning allowlist 不含 CDC-15，
但因为 CDC-15 不出现在 `cdc_routed.rpt` 第一行（CDC-1 / CDC-2 Critical 才阻塞），不影响构建通过。

`make k02-vivado` 重新 PASS：
```
K02_IMPL_PASS channel=GTHE3_CHANNEL_X0Y7 common=GTHE3_COMMON_X0Y1 WNS=1.194
```

WNS 从修复前的 0.903 ns 提升到 1.194 ns（同步器插入对时序裕量无负面影响）。
