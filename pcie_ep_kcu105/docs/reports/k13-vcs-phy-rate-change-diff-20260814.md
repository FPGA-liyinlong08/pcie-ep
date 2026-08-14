# K13 VCS PHY 速率切换差分验证结果

日期：2026-08-14

## 结论

按 `k13_vcs_phy_rate_change_diff_verification.md` 的仿真边界，本轮已完成：

- 官方 KCU105 PHY demo Golden：通过；
- K13 生产控制器窄场景 Test B：通过 Gen1→Gen3、TXEQ 预置、`PhyStatus`；
- 官方与 K13 的逐周期信号 trace：已生成；
- 发现并修复了 K13 mailbox 接收边界绕过 Gen3 TXEQ 预置窗口的问题。

尚未完成的是完整 PCIe Gen3 协议链路的 TS/EQ Phase 0～3、Recovery.Idle、DLL/TLP/BAR/枚举。这些不属于文档定义的“结束于 PhyStatus”的窄场景，但现有完整 K11B2 集成仿真仍在 `ts_accept=0` 处失败，不能标成全链路通过。

## 结果分层

| 项目 | 结果 | 证据 |
|---|---|---|
| VCS 许可证/工具链 | PASS | `27000@wx-linux`；官方和 K13 均完成编译、展开、运行 |
| Test A 官方 baseline | PASS | `Test Completed Successfully`，仿真时间 `205951505 ps` |
| Test B K13 窄场景 | PASS | `K13_PRODUCTION_PHY_RATE_CHANGE_VCS_PASS` |
| TXEQ preset-before-rate | PASS | K13 trace 先出现 `TXEQ_CTRL=01/Preset=4`，后出现 `rate=10` |
| Gen1→Gen3 `PhyStatus` | PASS | K13 trace 的 Gen3 `PhyStatus=1` |
| 完整 Gen3 链路/EQ/DLL/TLP/BAR | 未完成 | 完整 K11B2 日志为 `K13_VCS_GEN3_RETRAIN_FAIL`，`ts_accept=0` |

因此，文档的 PHY 速率切换验证主体已完成；剩余工作是更高层的 TS/EQ/链路收敛，不应与本次 PHY rate-change PASS 混写。

## 官方 baseline trace

官方 demo 通过非侵入式 `bind` 观测 `xilinx_pcie_phy_top` 和 `xilinx_pcie_phy_model`，没有修改 demo RTL。

官方 RP/EP 两侧 trace 一致，关键事件为：

- Gen1：`rate=000`；
- Gen3：`rate=010`，约 `103451529 ps`；
- Gen3 `PhyStatus`：约 `123951504 ps`；
- 官方控制器不发 `TXEQ_CTRL=01/Preset=4`，`as_cdr_hold_req` 由官方 demo 控制器产生相应变化。

## K13 窄场景 trace

测试使用官方 demo 生成的同一份 `pcie_phy_0`、GT Wizard 和 SecureIP 行为模型，接入 `pcie_k13_production_ctrl`，测试边界明确停在 `PhyStatus`。

关键事件：

- retrain 发出：`29467504 ps`；
- 进入 Recovery.Speed：trace cycle `132`，`29507504 ps`；
- TXEQ 预置首次有效：trace cycle `133`，`29515504 ps`，`rate=00, TXEI=1, TXEQ_CTRL=01, Preset=4`；
- `TXEQ_DONE=1`：trace cycle `142`，约 `29587504 ps`；
- 首次 Gen3：trace cycle `144`，`29603504 ps`，`rate=10, TXEI=1, CDR hold=1`；
- Gen3 `PhyStatus=1`：trace cycle `4151`，`50111504 ps`；
- 最终标记：`K13_PRODUCTION_PHY_RATE_CHANGE_VCS_PASS rate=gen1_to_gen3 pre_rate_txeq=1 phystatus=1`。

## 修复内容

原实现中 `active_target` 与 mailbox 请求在不同 NBA 边界更新。首次进入 Recovery.Speed 时，`speed_boundary_ready` 可能暂时把 Gen3 请求当作非 Gen3，从而在 TXEQ preset 之前改变 PIPE Rate。

已在 `rtl/phy/pcie_k13_production_ctrl.sv` 增加 `gen3_target_active`：在 `active_target` 尚未锁存时同时参考 live mailbox request，并让 `speed_boundary_ready` 等待 `pre_rate_txeq_ready`。最终 VCS trace 证明顺序为：

```text
TXEQ_CTRL=01 + Preset=4 -> TXEQ_DONE=1 -> rate=10 -> PhyStatus=1
```

## 运行方法

在仓库目录执行：

```bash
export SNPSLMD_LICENSE_FILE=27000@wx-linux
export LM_LICENSE_FILE=27000@wx-linux:${LM_LICENSE_FILE:-}
./sim/vcs/k13_phy_rate_change/run_official_trace.sh
./sim/vcs/k13_phy_rate_change/run_k13_phy_rate_change.sh
```

两个脚本均复用官方 demo 的生成 PHY 源文件和预编译 Xilinx 仿真库；K13 脚本额外编译生产控制器及窄场景 testbench。

## 产物位置

- 官方 trace：`/home/wx/Documents/KCU105/pcie_phy_0_ex/vcs_results/official_trace/`
- K13 trace：`/home/wx/Documents/KCU105/pcie_phy_0_ex/vcs_results/k13_phy_rate_change/`
- 官方 baseline 原始结果：`/home/wx/Documents/KCU105/pcie_phy_0_ex/vcs_results/vcs_simulation.log`
- 完整 K11B2 K13 集成结果：`/home/wx/Documents/PCIe/pcie_ep_kcu105/sim/vcs/build/k13_external_loopback.log`

## 剩余任务

1. 把 K13 窄场景从单端 PHY 控制扩展到真实 Recovery TS1/TS2 输入，并保持 `PhyStatus` 之后的 EQ 验证独立可判定。
2. 针对完整 K11B2 仿真的 `ts_accept=0`，生成 RP/EP TS 字段 trace，定位首次非法/缺失 TS。
3. 在 EQ 通过后再恢复 DLL/TLP/BAR/枚举测试；不要用完整链路失败反推本次 PHY rate-change 失败。
4. 结合已有硬件 ILA 的 QPLL1 lock 失败继续做硬件侧 rate handshake 验证；VCS 行为模型不能替代 GT/QPLL 模拟硬件行为。
