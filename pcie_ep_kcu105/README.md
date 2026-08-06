# KCU105/KU040 自研 PCIe Endpoint

本工程目标是在 KCU105（`xcku040-ffva1156-2-e`）上实现 PCIe Gen3 x1
Endpoint。Xilinx standalone `pcie_phy v1.0` 只负责 GT/PMA/PCS、Receiver
Detect、速率切换和均衡执行；LTSSM、Ordered Set、DLL、TLP、配置空间和 BAR
均由本工程实现。

文字数据路径固定为：

`PCIe 串行口 → Xilinx standalone pcie_phy → PHY32 → 自研 LTSSM/MAC → 自研 DLL → 异步 Packet FIFO → TLP/配置空间 → BAR-to-AXI4-Lite`

## 当前阶段

- K00：**PASS / K00-v1 已冻结**。
- K01：**PASS / K01-v1 已冻结**。
- K02：**执行中、尚未冻结**；架构/接口/仿真计划、错误 Stub、Verilator、XCI
  指纹和 Vivado 完整实现已通过；VCS 动态仿真等待 `VCSCompiler_Net` 许可证，
  KCU105 Receiver Detect 等待接入实板。
- K00 导入通用 Smoke 验证、CDC 同步器和已冻结的 M02 Packet FIFO；不导入
  KU060 的时钟、GT、PCS 或 PCIe 协议 RTL。
- K01 已实现 PCIe REFCLK 缓冲、PERST# 分发和 PIPE/Core 四级复位同步释放。
- K02 已生成 standalone PHY 封装和 bring-up bitstream；K02 未冻结前不开始 K03。
- 历史工程 `/home/wx/Documents/PCIe/pcie_ep_ku060` 保持原位，不移动、不删除、
  不由本工程脚本写入。

## 目录

| 目录 | 用途 |
|---|---|
| `docs/architecture` | 总体和模块架构冻结文档 |
| `docs/interfaces` | 接口、时钟域、复位和握手契约 |
| `docs/verification` | RTL 前仿真计划和阶段门模板 |
| `docs/reports` | 实际执行结果、已知限制和冻结决定 |
| `docs/archive` | KU060 历史基线位置和状态 |
| `docs/implementation-plan.md` | K00～K14 顺序、阶段门和验收目标 |
| `rtl/common` | 可复用同步器和异步 Packet FIFO |
| `rtl/phy` | K01 参考时钟/复位 RTL，以及 K02 后续 PHY 封装 |
| `rtl/dll`、`rtl/tl` | 后续自研协议模块，K00 为空 |
| `sim/verilator` | cocotb/Verilator 与 Native C++ 回归 |
| `sim/vcs` | VCS/Xilinx 库 Smoke 和 FIFO 回归 |
| `fpga/kcu105` | KU040 约束、Tcl 和阶段构建入口 |

## K00 命令

完整回归：

```bash
make k00
```

可独立运行：

```bash
make k00-baseline
make k00-m02-checker-selftest
make k00-m02-lint
make k00-m02-verilator
make k00-m02-verilator-signoff
make k00-m02-vcs
make k00-m02-vivado
```

`k00-m02-verilator-signoff` 对六组时钟组合各发送 1,000,000 个 Packet；
`k00-m02-vivado` 以 KU040 进行 OOC 综合、BRAM/CDC/DRC 检查。

外部 FIFO 依赖固定为：

`/home/wx/Documents/AXI/prj_wb2axip_master/wb2axip-master/rtl/afifo.v`

构建前会核对 SHA-256；该文件不复制、不修改。

## K01 命令

完整回归：

```bash
make k01
```

可独立运行：

```bash
make k01-checker-selftest
make k01-lint
make k01-verilator
make k01-vcs
make k01-vivado
```

`k01-verilator` 覆盖 Gen1/2/3 三种 `phy_pclk`，共执行 3,000 组 PERST# 和
750 组 PHY Status 随机复位；`k01-vcs` 使用 Vivado 2021.2 原语库；
`k01-vivado` 对 KU040 执行 OOC 综合、管脚/原语/CDC/DRC/时序检查。

## K02 命令

自动回归入口：

```bash
make k02
```

可独立运行：

```bash
make k02-checker-selftest
make k02-lint
make k02-verilator
make k02-ip
make k02-vcs
make k02-vivado
make k02-hw-probe
make k02-hw-program
```

`k02-vcs` 使用真实 Xilinx PHY/GTHE3 仿真模型；可通过
`VCS_LICENSE_TIMEOUT=<秒数>` 设置许可证等待上限；仅重试许可证时可同时设置
`K02_SKIP_IP_GENERATION=1` 复用刚验证过的生成目录。上板验收需确认 J74 为 x1，
先执行：

```bash
/home/Xilinx/Vivado/2021.2/bin/hw_server -d -p0 -I60 -stcp::3122
```

随后可用后两个目标探测/下载 bitstream，再观察 Receiver Detect LED。
