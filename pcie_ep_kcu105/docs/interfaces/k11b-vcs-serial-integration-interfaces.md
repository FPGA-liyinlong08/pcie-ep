# K11-B VCS 串行集成接口冻结

状态：**v1.1 已冻结（增加K11-B2生产顶层状态）**

## 1. 板级仿真接口

| 信号 | 方向（相对 Endpoint） | 宽度 | 规则 |
|---|---:|---:|---|
| `pcie_refclk_p/n` | 输入 | 1 | 100 MHz 差分，P/N 互补 |
| `pcie_perst_n` | 输入 | 1 | 异步有效低，与 RP `sys_rst_n` 同源 |
| `pcie_rxp/n` | 输入 | 1 | 连接 RP TX Lane 0 |
| `pcie_txp/n` | 输出 | 1 | 连接 RP RX Lane 0 |

Root Port Lane 1～7 不与 Endpoint 相连，其 RXP/RXN 分别固定为 `0/0`，表示没有有效
差分接收端。测试平台不得短接或交换 Lane 0 的 P/N 来制造正常用例。

## 2. Endpoint 内部接口

K02 与 K03 继续使用 `K02-PHY32-v1.1`：Gen1 下每拍有效 Symbol 位于低 16 bit，
线路最先出现的 Symbol 位于 `[7:0]`。K03 与后续 DLL 继续使用 `K03-MAC16-v1`。
本阶段不新增协议接口。

K11-B2生产顶层名称固定为`kcu105_pcie_ep_gen1_top`。板级串行端口保持第1节不变，
另外提供以下只读状态输出用于仿真、ILA和上板定位：

| 信号 | 位宽 | 时钟语义 | 复位值/含义 |
|---|---:|---|---|
| `link_up` | 1 | `phy_pclk` | 0；K03处于L0 |
| `dll_active` | 1 | `phy_pclk` | 0；InitFC完成 |
| `ltssm_state` | 6 | `phy_pclk` | 0；沿用K03状态编码 |
| `dll_fc_state` | 2 | `phy_pclk` | 0；沿用K05编码 |
| `negotiated_speed` | 2 | `phy_pclk` | 0=Gen1 |
| `negotiated_width` | 3 | `phy_pclk` | 1=x1，仅L0/Recovery有效 |
| `captured_bdf` | 16 | `phy_coreclk` | 0；K08捕获的本地BDF |
| `bdf_valid` | 1 | `phy_coreclk` | 0；BDF已捕获 |
| `bar0_base` | 32 | `phy_coreclk` | 0；4 KiB对齐BAR0基址 |
| `memory_space_enable` | 1 | `phy_coreclk` | 0；Command.MSE |
| `cdc_errors` | 8 | 混合sticky状态 | 0；任一位为1均失败 |

这些输出只用于状态观测，不允许反向控制协议逻辑。跨域状态只能在各自所属时钟域采样；
测试平台若组合判断多个域，必须要求条件连续稳定，不依赖同拍原子性。

为 VCS 缩短运行时间，`kcu105_pcie_gen1_top` 新增以下**参数**，端口不变：

| 参数 | 硬件默认值 | VCS 覆盖原则 |
|---|---:|---|
| `DETECT_QUIET_CYCLES` | 1,500,000 | 不小于 PHY 初始化完成后的稳定窗口 |
| `DETECT_TIMEOUT_CYCLES` | 3,000,000 | 覆盖一次真实 Receiver Detect |
| `TRAIN_TIMEOUT_CYCLES` | 6,000,000 | 覆盖 Root Port 最慢训练状态 |
| `HOT_RESET_CYCLES` | 250,000 | K11-B1 不主动触发 Hot Reset |

参数只改变超时计数，不得改变 LTSSM 状态图、Ordered Set 内容或综合顶层默认行为。

## 3. 测试结果接口

VCS 日志使用固定机器可读标记：

- `K11B_VCS_CHECKER_SELFTEST_PASS`：断开的串行 Stub 被 Checker 正确判失败；
- `K11B_VCS_GEN1_L0_PASS`：真实串行 B1 门通过；
- `K11B_VCS_GEN1_L0_FAIL`：超时并打印双方状态；
- `K11B_VCS_REAL_PHY_PASS`：脚本确认编译、展开、运行和日志检查全部成功。
- `K11B2_CHECKER_SELFTEST_PASS`：K03-only负向Stub被枚举门禁检出；
- `K11B2_DLL_ACTIVE_PASS`：双方用户/Data Link链路已就绪；
- `K11B2_ENUM_PASS`：Vendor/Device、BAR探测/分配和MSE正确；
- `K11B2_BAR_PASS`：Demo签名及Scratch写读正确；
- `K11B2_RANDOM_MMIO_PASS`：100组随机Scratch地址、数据和Byte Enable通过；
- `K11B2_BAD_LCRC_PASS`：坏LCRC触发NAK且重放后事务完成；
- `K11B2_ACK_LOSS_PASS`：ACK丢失触发Replay且延迟ACK清空窗口；
- `K11B2_PERST_RECOVERY_PASS`：PERST#后重训、重新配置与MMIO通过；
- `K11B2_STRESS_PASS`：全部非实板串行加固门禁通过；
- `K11B2_VCS_PASS`：B2全部门禁通过。
