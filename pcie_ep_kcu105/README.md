# KCU105/KU040 自研 PCIe Endpoint

本工程目标是在 KCU105（`xcku040-ffva1156-2-e`）上实现 PCIe Gen3 x1
Endpoint。Xilinx standalone `pcie_phy v1.0` 只负责 GT/PMA/PCS、Receiver
Detect、速率切换和均衡执行；LTSSM、Ordered Set、DLL、TLP、配置空间和 BAR
均由本工程实现。

文字数据路径固定为：

`PCIe 串行口 → Xilinx standalone pcie_phy → PHY32 → 自研 LTSSM/MAC → 自研 DLL → 异步 Packet FIFO → TLP/配置空间 → BAR-to-AXI4-Lite`

## 当前阶段

- K00：**PASS / K00-v1 已冻结**；当前没有开始 K01。
- K00 导入通用 Smoke 验证、CDC 同步器和已冻结的 M02 Packet FIFO；不导入
  KU060 的时钟、GT、PCS 或 PCIe 协议 RTL。
- K01、K02 及后续模块在前一阶段冻结前均不开始。
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
| `rtl/phy` | K01/K02 以后使用，K00 为空 |
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
