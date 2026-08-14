# 官方 KCU105 PHY Demo Hardware Golden 基线核对记录

日期：2026-08-14

## 核对范围

核对目录：`/home/wx/Documents/KCU105/pcie_phy_0_ex/`

本记录只确认官方 Demo 的工程/IP/仿真基线，不把 VCS PASS 或用户口头确认直接等同于可复现的官方硬件 bit。

特别说明：此前 KCU105 上实际下载并抓取的 `k02_pcie_phy_bringup_ila.bit` 来自仓库内 K02 工程，不来自本目录的 `pcie_phy_0_ex.xpr`。K02 结果是 PHY 稳态 Gen3/QPLL1 证据，不能直接作为官方 Demo 的动态 Gen1→Gen3 Golden。

## 已确认基线

| 项目 | 结果 | 证据 |
|---|---|---|
| Vivado | 2021.2 | `pcie_phy_0_ex.xpr` / `vivado.log` |
| Device | `xcku040-ffva1156-2-e` | `pcie_phy_0_ex.xpr` |
| Top | `xilinx_pcie_phy_top` | `sources_1` FileSet |
| IP | `pcie_phy_0`，`xilinx.com:ip:pcie_phy:1.0` | `pcie_phy_0.xci` |
| Lane/Speed | x1 / Gen3（8.0 GT/s） | `pcie_phy_0.xci` |
| GT type/PLL | GTH / QPLL1 | `pcie_phy_0.xci` |
| REFCLK | 100 MHz，`Bank_225_MGTREFCLK0` | `pcie_phy_0.xci` |
| User/Core clock | 125 MHz / 250 MHz | `pcie_phy_0.xci` |
| GT Channel | `GTHE3_CHANNEL_X0Y7` | `pcie_phy_0.xci` |
| XCI SHA-256 | `41b8dcf439629d458256404d7ecefccb4e46a0d01f72bddf2c8fe1eb3d689968` | 当前文件 |
| XPR SHA-256 | `d4efe350084605f0b473ea35a0460852f0a2e4cfd76927728eb6efbaf91e0af5` | 当前文件 |
| XDC SHA-256 | `7808e4d872e9f30684c829cbc4d70672d8816012816242c76f7759ebb232eb96` | 当前文件 |

## 已有通过证据

官方 VCS 真实 PHY/GT/SecureIP 仿真已通过：

```text
Gen1 ON
Gen1 Off
Gen3 ON
PHY Traffic Has Tested @ 8.0 Gbps or Gen-3 Speed...
Test Completed Successfully
```

证据文件：

- `/home/wx/Documents/KCU105/pcie_phy_0_ex/simulation_result.md`
- `/home/wx/Documents/KCU105/pcie_phy_0_ex/vcs_results/vcs_simulation.log`
- `/home/wx/Documents/KCU105/pcie_phy_0_ex/vcs_results/official_trace/`

## 硬件证据缺口

在官方 Demo 目录和本机 `/home/wx/Documents/KCU105` 搜索后，未找到属于该 Demo 的：

- 可下载 `.bit`；
- 对应 `.ltx`；
- Hardware Manager ILA `.csv/.ila`；
- `program_hw_devices`/`write_bitstream` 完成记录；
- KCU105 PCIe Lane/REFCLK package pin 完整约束。

官方工程当前存在综合 DCP，但 `imports/xilinx_pcie_phy.xdc` 只定义 `sys_clk` 周期和复位属性，没有完整板级 PCIe 管脚约束。工程源顶层还把 `gen1_en/gen2_en/gen3_en` 等控制端口置于 `synthesis translate_off` 区域，不能直接作为可下载硬件控制接口。

## 结论

P1-1 的 IP 和工程基线已冻结，但官方 Hardware Golden 仍缺少可复现硬件构建输入。P1-2 不能直接在当前工程上修改并宣称完成，否则会把“官方仿真 Demo”误当成“官方可下载硬件 Demo”。

继续条件是补齐实际使用的官方硬件工程/约束，或提供此前上板 PASS 所用 bit/LTX。补齐后再使用相同 ILA 信号、相同采样时钟和相同 `PHY_RATE: Gen1→Gen3` T0 进入差分验证。
