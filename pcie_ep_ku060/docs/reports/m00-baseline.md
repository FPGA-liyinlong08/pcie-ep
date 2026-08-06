# M00 基线报告

状态：**PASS / 已冻结**  
执行日期：2026-08-06（Asia/Shanghai）

## 冻结产物

- 系统架构：`docs/architecture/00-system-architecture.md`
- 接口契约版本 1：`docs/interfaces/00-interface-contracts.md`
- 验证计划：`docs/verification/00-m00-verification-plan.md`
- 后续模块阶段门：`docs/verification/module-gate-template.md`

## 回归命令

```sh
make m00
```

## 测试结果

| 测试 | 结果 | 证据 |
|---|---|---|
| M00-VLT-001 | PASS | cocotb 完成复位和连续 32 周期计数检查，仿真时间 350 ns |
| M00-PCIE-001 | PASS | 在 cocotb Scheduler 中成功创建并连接 `RootComplex`、`Device` 和 `Function` |
| M00-PCIE-002 | PASS | 32 Byte Memory Write TLP 打包/解包往返及 Payload 破坏负向比较通过 |
| M00-VCS-001 | PASS | VCS 选择 `linux64`，Compiler 为 `VCS-MX O-2018.09-SP2_Full64` |
| M00-VCS-002 | PASS | VCS 成功编译、Elaborate 和仿真包含 `BUFG` 的 Smoke Design，日志包含 `M00_VCS_PASS` |

完整回归从已清理的仿真环境开始执行：

```text
make clean  -> PASS
make m00    -> PASS
```

## 工具基线

- Python 3.8.10
- Verilator 5.020
- cocotb 1.9.2
- cocotbext-pcie 0.2.16
- VCS-MX O-2018.09-SP2 Full64
- Xilinx 编译库：`/home/wx/Documents/vcs_compile_simlib`

## 环境约定

- 本机 VCS 必须使用 `VCS_ARCH_OVERRIDE=linux` 和 `-full64`；缺少
  `-full64` 时会错误选择不存在的 32 位 `linux` Compiler。
- 当前系统 Linker 下，VCS Elaborate 必须使用 `-Wl,--no-as-needed`；该配置
  与现有 XDMA VCS 环境一致。
- `RootComplex` 会启动 cocotb Coroutine，因此必须在运行中的 cocotb
  Scheduler 内创建。独立 Python 检查只负责 TLP 对象创建和序列化。

## 阶段门决定

M00 以接口契约版本 1 冻结。本阶段没有实现 PCIe 功能 RTL。M01 尚未开始；
下一项允许开展的工作是编写并冻结 M01 的架构、端口契约和验证计划。

