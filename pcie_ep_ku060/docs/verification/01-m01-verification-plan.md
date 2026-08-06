# M01 `pcie_clk_reset` RTL 前仿真计划

状态：**PASS / 已执行并冻结**

## 1. 验证对象与分层

- Verilator DUT：不含厂商原语的 `pcie_clk_reset_ctrl`。
- VCS DUT：完整 `pcie_clk_reset`，包含 `IBUFDS_GTE3`、`MMCME3_BASE`、
  `BUFG` 和 `BUFG_GT`。
- Vivado：针对 `xcku060-ffva1156-2-i` 的综合、时钟约束和 CDC 检查。

## 2. Checker 预期失败自检

在编写生产 RTL 前，先编译同端口的错误 Stub。Stub 将三个输出永久保持为 0。
`release_and_dependency` 必须失败；外层脚本把“测试确实失败”判定为
`M01_CHECKER_SELFTEST_PASS`。如果错误 Stub 也能通过，则禁止编写 RTL。

## 3. Verilator/cocotb 测试

### M01-VLT-001：释放顺序与依赖关系

- Core lock 有效且 GT 未就绪时，只允许释放 `core_rst_n`。
- GT 三个 ready 信号全部有效后，连续四个 PIPE 时钟释放 `pipe_rst_n`。
- `clock_ready` 必须晚于 `core_rst_n` 和 `pipe_rst_n`。
- 分别撤销 GT ready、Core lock 和 PERST#，检查各自影响范围。

### M01-VLT-002：异步置位

- 在 Core/PIPE 时钟周期的随机相位拉低 PERST#、Core lock 或 GT ready。
- 相关复位必须在下一个时钟边沿之前拉低。
- 不相关时钟域不得被错误复位。

### M01-VLT-003：随机复位压力

- PIPE 周期分别使用 16 ns、8 ns、4 ns，对应 Gen1/Gen2/Gen3 PIPE 时钟。
- 每种 PIPE 周期执行 1000 次随机相位 PERST# 脉冲。
- 每次复位后检查四级同步释放和 `clock_ready` 恢复。
- 固定并记录随机种子；发生错误时输出轮次和信号状态。

## 4. VCS/Xilinx 原语测试

### M01-VCS-001：时钟原语与 MMCM

- 差分输入产生 100 MHz PCIe Refclk。
- `sys_clk_100` 驱动 `MMCME3_BASE`，检查 `core_mmcm_locked` 在超时前拉高。
- 测量 20 个 `core_clk_250` 周期，平均周期必须在 3.98～4.02 ns。
- 检查 `gt_refclk` 能跟随正确的差分参考时钟输入。

### M01-VCS-002：完整复位流程

- 依次释放 PERST#、MMCM、GT PLL 和 TX/RX reset-done。
- 检查 `core_rst_n`、`pipe_rst_n` 和 `clock_ready` 的顺序。
- 拉低 PERST#，两个复位必须异步置位。

## 5. Vivado 检查

- `synth_design -top pcie_clk_reset -part xcku060-ffva1156-2-i` 必须通过。
- 综合后必须存在一个 `IBUFDS_GTE3`、一个 `MMCME3_BASE`、至少两个
  `BUFG_GT` 和 Core Clock `BUFG`。
- `report_cdc` 不得出现 Critical CDC。
- 所有异步同步寄存器必须保留 `ASYNC_REG` 属性。
- 输入时钟和异步 Clock Group 约束必须无未解析对象。

## 6. 通过标准

- 错误 Stub 被 Checker 检出。
- 三种 PIPE 周期下的全部 Directed 和 1000 次随机复位均通过。
- VCS 完整原语仿真通过并打印 `M01_VCS_PASS`。
- Vivado 综合、DRC 和 CDC 检查通过；若只剩工具可解释的 Warning，必须在
  冻结报告中逐项记录。
