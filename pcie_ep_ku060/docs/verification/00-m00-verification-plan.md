# M00 RTL 前验证计划

状态：**已冻结**

## 目的

M00 用于证明在加入任何 PCIe 功能 RTL 前，项目已经具备可复现的仿真入口。
本阶段不宣称覆盖 PCIe 协议、PHY 或综合实现。

## 验证环境

- Python 3.8.10
- Verilator 5.020
- cocotb 1.9.2
- cocotbext-pcie 0.2.16
- VCS-MX O-2018.09-SP2 Full64
- Vivado/Xilinx 仿真库：`/home/wx/Documents/vcs_compile_simlib`

## 测试项

| 编号 | 测试 | 检查方法 | 通过标准 |
|---|---|---|---|
| M00-VLT-001 | 使用 cocotb/Verilator 编译并仿真可复位的 SystemVerilog 计数器 | cocotb 逐周期断言 | 复位值及连续 32 次计数完全一致 |
| M00-PCIE-001 | 在 cocotb Scheduler 中实例化 `RootComplex`、`Device` 和 `Function` | Python 类型及拓扑断言 | 对象成功创建，Device 连接到 RC Port |
| M00-PCIE-002 | 在仿真内外分别创建、打包、解包和验证 Memory Write TLP | `cocotbext-pcie` TLP 对象相等比较 | 往返转换保留所有 TLP 字段和 Payload |
| M00-VCS-001 | 检查 VCS Full64 可执行文件选择 | 脚本输出和退出状态 | `VCS_ARCH_OVERRIDE=linux` 配合 `-full64` 选择 `linux64` Compiler |
| M00-VCS-002 | 编译并 Elaborate 一个包含 Xilinx `BUFG` 的 Smoke DUT | VCS 和 `unisims_ver` | `BUFG` 成功解析，仿真打印 `M00_VCS_PASS` |

## 失败注入

cocotb Checker 每个周期读取 DUT 计数器。如果把计数器递增修改为保持，
M00-VLT-001 会在第一个有效时钟立即失败，因此可以证明 Checker 确实观察
到了 DUT，而不是产生无条件 PASS。

M00-PCIE-002 会修改一个临时副本中的 Payload 字节，并要求修改后的 TLP 与
原对象比较不相等，以证明比较过程检查了 Payload，而不仅是 Header。

## 输出与生成文件

- Verilator 输出：`sim/verilator/sim_build` 和 `sim/verilator/results.xml`。
- VCS 输出：`sim/vcs/build`。
- 所有生成路径均被忽略，可通过 `make clean` 删除。

## 阶段门标准

`make m00` 必须以退出状态 0 完成。基线报告记录准确工具版本和全部测试结果。
报告标记为 PASS 前，不允许创建 M01 RTL。

