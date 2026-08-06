# K01 `kcu105_refclk_reset` 冻结报告

状态：**PASS / K01-v1 已冻结**  
执行日期：2026-08-06  
统一命令：`make k01`

## 1. 冻结结论

K01 已完成 KCU105 PCIe 100 MHz 参考时钟缓冲、PERST# 分发以及 PIPE/Core
复位生成。RTL、接口、仿真计划、负向自检、动态回归、VCS 原语仿真和 KU040
静态签核全部通过。允许下一次单独开始 K02，但本阶段没有生成 standalone PHY
XCI，也没有开始 Receiver Detect、速率切换或均衡逻辑。

KU060 历史工程仍位于 `/home/wx/Documents/PCIe/pcie_ep_ku060`，本阶段未修改。

## 2. 冻结实现

| 文件 | 职责 | SHA-256 |
|---|---|---|
| `rtl/phy/kcu105_reset_ctrl.sv` | 无厂商原语的复位依赖和两组四级同步释放链 | `7c2292e820800cb385c17f4b9f3d71ed3795eeaabb5d73649dc7b261def73dda` |
| `rtl/phy/kcu105_refclk_reset.sv` | `IBUFDS_GTE3`、`BUFG_GT` 和复位控制集成 | `b6913b6acb3e0ef58fd4326830dde1cb54b294d89cf981650f3cb287521ba68d` |
| `fpga/kcu105/k01_refclk_reset.xdc` | AB6/AB5、K22、电压、时钟和复位约束 | `70360004137838c267d6b6163860552b8648e98f8a062779c255cc920ef47aa9` |

复位关系冻结为：

```text
phy_rst_n             = pcie_perst_n
core_async_release_n  = pcie_perst_n
pipe_async_release_n  = pcie_perst_n && !phy_phystatus_rst
```

Core 和 PIPE 均在异步条件出现时立即置位复位，在条件撤销后的第四个本域上升沿
释放。PHY Status Reset 只影响 PIPE，不清空 Core 域状态。

## 3. 测试平台先行结果

故意错误 Stub 永久拉高三个复位输出。`release_and_dependency` 在仿真 0 ns、
PERST# 有效期间检测到 `phy_rst_n=1`，JUnit 记录预期 failure，外层门禁输出
`K01_CHECKER_SELFTEST_PASS`。生产 RTL 在该门禁通过后才加入。

## 4. Verilator/cocotb 结果

Verilator 5.020、cocotb 1.9.2，固定随机种子 `20260806`。

| PIPE 模式 | 周期 | PERST# 随机序列 | PHY Status 随机序列 | Directed | 结果 |
|---|---:|---:|---:|---:|---|
| Gen1 | 16 ns | 1,000 | 250 | 2 | PASS |
| Gen2 | 8 ns | 1,000 | 250 | 2 | PASS |
| Gen3 | 4 ns，起始错相 0.8 ns | 1,000 | 250 | 2 | PASS |

合计 3,000 组 PERST#、750 组 PHY Status 序列。覆盖了随机相位、10～3,000 ps
短脉冲、精确四拍释放、时钟边沿前后、PIPE/Core 域隔离以及停止释放进度。
Lint 为 PASS，无 Error。

JUnit 保存为 `sim/verilator/k01/results_negative.xml` 和
`results_gen1.xml/results_gen2.xml/results_gen3.xml`；这些运行产物由 `.gitignore`
排除。

## 5. VCS Xilinx 原语结果

VCS-MX O-2018.09-SP2 链接 Vivado 2021.2 `unisims_ver`，实例化完整
`kcu105_refclk_reset`：

| 检查 | 结果 |
|---|---|
| `IBUFDS_GTE3.O` / `phy_gtrefclk` | 10.000 ns，PASS |
| `IBUFDS_GTE3.ODIV2 → BUFG_GT` / `phy_refclk` | 10.000 ns，PASS |
| PERST# 直接 PHY 分发 | PASS |
| Core/PIPE 四拍同步释放 | PASS |
| PHY Status 只异步重置 PIPE | PASS |
| PERST# 异步重置全部三个输出 | PASS |

日志标志为 `K01_VCS_PASS`。

## 6. KU040 Vivado 结果

Vivado 2021.2 Build 3367213，器件 `xcku040-ffva1156-2-e`，以 Gen3 最坏情况
250 MHz 对 PIPE/Core 两个复位链执行 OOC 检查。

| 项目 | 结果 |
|---|---:|
| 综合 | 0 Error，0 Critical Warning |
| CLB LUT / Register | 2 / 8 |
| `IBUFDS_GTE3` / `BUFG_GT` | 1 / 1 |
| MMCM/PLL | 0 |
| `ASYNC_REG` | 8，恰好两组四级链 |
| 管脚 | AB6/AB5 REFCLK，K22 PERST# |
| 配置 | LVCMOS18、PULLUP、`CONFIG_VOLTAGE=1.8`、`CFGBVS=GND` |
| WNS / TNS | +3.688 ns / 0.000 ns |
| WHS / THS | +0.103 ns / 0.000 ns |
| CDC | 2×`CDC-9 Info`，0 Warning/Critical |
| DRC | 0 违例 |
| `check_timing` No Clock / Unconstrained Internal Endpoint | 0 / 0 |

普通 Warning 只允许 `Synth 8-7080` 和 `Timing 38-242`，实际集合与 K01 固定
白名单完全一致。静态报告位于 `fpga/kcu105/build_k01/`，属于可再生构建产物。

## 7. 已知限制与 K02 边界

- K01 的 `phy_pclk`、`phy_coreclk` 在 OOC 中是测试边界输入；K02 集成后必须改接
  standalone PHY 输出，并在集成上下文消除 `HD.CLK_SRC` Warning；
- AB6/AB5/K22 的端口属性已经核对，但 GT Common/Channel 的实际放置属于 K02
  完整布局布线验收；
- K01 不验证 Receiver Detect、PLL/CDR、速率切换、均衡或串行收发；
- K01 没有 PHY IP、LTSSM、DLL 或 TLP 功能，也没有可上板运行的完整 Endpoint；
- 复位同步器参数允许 2～8，当前冻结实例固定为 4；更改参数须重新执行本阶段回归。
