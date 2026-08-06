# K01 `kcu105_refclk_reset` RTL 前仿真计划

状态：**PASS / K01-v1 计划与验证结果已冻结**

## 1. 验证对象与参考模型

- Verilator DUT：无厂商原语的 `kcu105_reset_ctrl`；
- Python 参考模型：两个 `RESET_SYNC_STAGES` 位移位链和组合 `phy_rst_n`；
- cocotb Driver：产生 250 MHz Core 时钟、三种 PIPE 时钟以及随机相位复位；
- cocotb Monitor/Checker：逐边沿检查异步置位、精确释放拍数和域间隔离；
- VCS DUT：完整 `kcu105_refclk_reset`，链接 Vivado 2021.2 `unisims_ver`；
- Vivado：KU040 OOC 综合、原语/管脚属性、时钟、CDC、DRC 和时序检查。

固定随机种子 `20260806`。失败信息必须包含 PIPE 周期、迭代号、复位源、期望拍数
和实际输出。

## 2. 错误 Stub 自检

先编译同端口错误 Stub，Stub 永久释放三个复位输出。`release_and_dependency`
必须在 PERST# 有效期间检测到复位错误。只有 JUnit 确实包含 failure，外层脚本才
报告 `K01_CHECKER_SELFTEST_PASS`。此步骤通过前禁止编写生产 RTL。

## 3. Directed Case

### K01-DIR-001：初始与依赖关系

- PERST# 为低时，`phy_rst_n/core_rst_n/pipe_rst_n` 全部为低；
- PERST# 拉高、`phy_phystatus_rst` 保持高：只允许 PHY 和 Core 释放；
- `phy_phystatus_rst` 拉低后，PIPE 必须等待四个 `phy_pclk` 上升沿；
- `phy_phystatus_rst` 再次拉高：只异步置位 PIPE；
- PERST# 再次拉低：三个复位同时异步置位。

### K01-DIR-002：精确释放拍数

- `RESET_SYNC_STAGES-1` 个上升沿内复位保持低；
- 第 `RESET_SYNC_STAGES` 个上升沿后复位为高；
- 分别在时钟高、低和临近边沿的相位释放异步条件；
- 时钟停止期间不允许复位自行释放。

### K01-DIR-003：短脉冲与域隔离

- 注入短于 Core/PIPE 时钟周期的 PERST# 低脉冲，三个输出都必须捕获；
- 注入短 `phy_phystatus_rst` 高脉冲，PIPE 必须捕获并重新等待四拍；
- Core 和 PHY 复位在 PHY Status 脉冲期间保持释放。

## 4. 约束随机回归

| 组合 | `phy_pclk` 周期 | `phy_coreclk` 周期 | PERST# 序列 | PHY Status 序列 |
|---|---:|---:|---:|---:|
| Gen1 | 16 ns | 4 ns | 1,000 | 250 |
| Gen2 | 8 ns | 4 ns | 1,000 | 250 |
| Gen3 | 4 ns | 4 ns，错相 0.8 ns | 1,000 | 250 |

每次随机化置位相位、脉冲宽度和释放相位。总计 3,000 次 PERST#、750 次
`phy_phystatus_rst`，每次都精确检查两个释放移位链。

## 5. VCS 原语测试

- 输入 100 MHz 差分参考时钟；
- 检查 `phy_gtrefclk` 和 `phy_refclk` 均稳定输出 100 MHz；
- 检查 `IBUFDS_GTE3` 的互补输入行为和 `BUFG_GT` 路径；
- 执行 PERST#、PHY Status、Core/PIPE 四拍释放和异步重新置位；
- 超时前打印 `K01_VCS_PASS`，否则 `$fatal`。

## 6. Vivado 静态检查

- 目标器件必须为 `xcku040-ffva1156-2-e`；
- 网表必须恰好包含 1 个 `IBUFDS_GTE3` 和 1 个参考时钟 `BUFG_GT`；
- `ASYNC_REG` 必须恰好覆盖两个四级复位链，共 8 个寄存器；
- 管脚固定为 AB6/AB5/K22，PERST# 为 LVCMOS18 且上拉；
- 配置属性固定为 `CONFIG_VOLTAGE=1.8`、`CFGBVS=GND`；
- `check_timing` 无 No Clock/Constant Clock/Pulse Width Clock；
- CDC 不得有 Critical；DRC 不得有 Error/Critical Warning；
- Warning 类型必须与 K01 固定 Allowlist 完全一致，新增类型失败。

## 7. 通过标准

- 错误 Stub 被 Checker 检出；
- Directed、3,000 次 PERST#、750 次 PHY Status 全部通过；
- Verilator Lint 和 VCS 原语仿真通过；
- KU040 原语、管脚、复位属性、CDC、DRC 和时序检查通过；
- 保存工具版本、JUnit、Vivado 报告、Warning Allowlist、已知限制和冻结决定。
