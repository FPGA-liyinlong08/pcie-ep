# KU060 自研 PCIe Endpoint

本目录用于开发面向 `xcku060-ffva1156-2-i` 的单功能 PCIe Gen3 x1
Endpoint，包括独立自研的 RTL 和验证环境。

项目严格采用阶段门管理：每次只开发一个编号模块。开始编写 RTL 前，必须先
冻结该模块的架构、端口契约和仿真计划；当前模块未通过验收前，不得进入下一
模块。

当前状态：**M01 已通过——`pcie_clk_reset` 时钟复位模块已经冻结**。

M02 尚未开始。开始异步 Packet FIFO 前，必须先完成并评审 M02 的架构、接口
和 RTL 前仿真计划。

## M00 快速回归

```sh
make m00
```

也可以分别执行：

```sh
make m00-verilator
make m00-pcie-model
make m00-vcs
```

VCS 检查会强制使用本机已安装的 64 位工具，并从本地 Vivado 2021.2
`unisims_ver` 仿真库中链接一个 Xilinx `BUFG`。生成文件只保存在已忽略的
`build/` 或仿真工作目录中。

## M01 快速回归

```sh
make m01
```

该命令依次执行错误 Stub 自检、Verilator Lint、三种 PIPE 时钟下的 3000 组
随机 PERST# 和 300 组随机状态撤销、VCS Xilinx 原语仿真，以及 KU060 Vivado
OOC 综合/CDC/DRC 检查。
也可以分别执行：

```sh
make m01-checker-selftest
make m01-lint
make m01-verilator
make m01-vcs
make m01-vivado
```

## 目录职责

- `docs/architecture`：总体架构和各模块冻结后的架构说明。
- `docs/interfaces`：RTL 与测试平台共同遵守的信号级接口契约。
- `docs/verification`：RTL 编写前的仿真计划和阶段门模板。
- `docs/reports`：完成后的阶段门报告与可复现证据。
- `rtl`：独立自研的可综合 SystemVerilog；当前包含 M01 时钟复位模块。
- `sim/verilator`：cocotb/Verilator 单元及集成测试。
- `sim/vcs`：Xilinx 原语及后续串行链路 VCS 仿真。
- `fpga/ku060`：Vivado 脚本、约束和 KU060 板级集成。
- `sw/bar_test`：M12/M13 阶段加入的 Linux BAR 测试程序。

本目录之外的 PLDA 和 XDMA 源码只用于参考和独立交叉验证，不复制到本项目
RTL 中。
