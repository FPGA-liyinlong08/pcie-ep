# K12 Recovery.Speed / Equalization 接口启动基线

状态：**v0.1；K12-A CDC mailbox、K12-B Recovery.Speed骨架已实现，完整接口冻结中**

## 1. 约束和时钟域

K12不改变K02 PHY接口的编码和K08配置空间语义。K08在
`phy_coreclk`域输出单拍`retrain_link_pulse`和两位`target_link_speed`；
Recovery状态机和K02 PHY控制位于`phy_pclk`域。

这两个信号必须作为一个原子命令跨域，禁止对脉冲和payload分别打两拍后
直接使用。K12-A采用单深度request/ack mailbox：源域锁存payload并翻转request，
目标域同步request后一次性采样稳定payload，接收后翻转ack。ack返回前源域
不得覆盖payload。

## 2. Retrain CDC mailbox

| 信号 | 方向 | 域 | 语义 |
|---|---:|---|---|
| `core_retrain_pulse` | 输入 | `phy_coreclk` | K08 Link Control.Retrain Link写脉冲 |
| `core_target_speed[1:0]` | 输入 | `phy_coreclk` | `0/1/2=Gen1/Gen2/Gen3`，`3`非法 |
| `core_retrain_busy` | 输出 | `phy_coreclk` | mailbox有未应答命令 |
| `link_retrain_valid` | 输出 | `phy_pclk` | 新命令到达，保持至accept |
| `link_target_speed[1:0]` | 输出 | `phy_pclk` | 与valid原子对应的稳定payload |
| `link_retrain_accept` | 输入 | `phy_pclk` | Recovery控制器接收命令 |
| `cdc_overflow_sticky` | 输出 | `phy_coreclk` | busy时再来命令；黏滞为1 |

复位后mailbox为empty，busy/valid/error为0。对非法速率`2'b11`不产生PHY命令，
由Recovery控制器记录拒绝并继续Gen1。

## 3. Recovery/EQ控制边界

K12控制器的生产边界全部位于`phy_pclk`域：

| 类别 | 信号 | 规则 |
|---|---|---|
| 触发 | `link_retrain_valid`, `link_target_speed` | 仅在L0且命令合法时accept |
| 对端训练 | RX TS1/TS2有效及Rate/EQ字段 | 只在完整Ordered Set验证后提交 |
| 速率控制 | `phy_rate[1:0]` | 改变后保持，直到`phy_phystatus`完成或超时 |
| TX EQ命令 | `phy_txeq_ctrl/preset/coeff` | 先校验参数，再保持至`phy_txeq_done`或超时 |
| RX EQ命令 | `phy_rxeq_ctrl/txpreset` | 保持至`phy_rxeq_done`或超时 |
| EQ反馈 | FS/LF、new coefficient、adapt done | 仅在对应命令活动期采样 |
| 事务门控 | `recovery_active`, `traffic_quiesce` | Speed/EQ期间禁止新TLP/DLLP提交 |
| 结果 | `negotiated_speed[1:0]` | 只在新速率L0稳定后更新 |
| 错误 | timeout/illegal/reject/CDR-loss sticky | 饱和计数，不得回绕为0 |

`phy_phystatus`是K02既有速率完成应答；K12不新增一个与之竞争的
`rate_done`信号。`phy_txeq_done`/`phy_rxeq_done`也继续沿用K02语义。

## 4. 状态和Ordered Set契约

- 进入Recovery后先置`traffic_quiesce`，再开始TS交换或PHY命令。
- RcvrLock/RcvrCfg/Speed/EQ/Idle之间的发送模式切换只能在`os_tx_complete=1`后生效。
- 超时、拒绝、非法参数或CDR失锁必须撤销所有PHY命令，进入显式Fallback路径。
- Fallback将`phy_rate`恢复为Gen1，等待`phy_phystatus`，重新训练并执行DLL InitFC。
- K12默认禁用时，所有新控制信号保持K11 release值，逐拍回归必须通过。

## 5. K12-A冻结出口

K12-A只在以下条件全部满足后修改生产LTSSM：CDC mailbox定向和随机验证通过，
错误Stub能被验证计划中的6类Checker检出，默认禁用配置与K11逐拍等价，并且
接口、状态编码和超时默认值在文档中冻结。

## 6. K12-B骨架状态编码

独立控制器`pcie_recovery_speed_ctrl`当前使用以下局部编码，接入生产LTSSM前不得
与K03/K11已有6位LTSSM编码直接混用：

| 编码 | 状态 | 关键输出 |
|---:|---|---|
| 0 | `ST_L0` | Gen1/已协商速率，允许事务 |
| 1 | `ST_QUIESCE` | `traffic_quiesce=1`，禁止新事务 |
| 2 | `ST_SPEED_WAIT` | `phy_txelecidle=1`，驱动目标`phy_rate`，等待`phy_phystatus` |
| 3 | `ST_RECOVERY_IDLE` | 目标速率保持，等待对端确认 |
| 4 | `ST_FALLBACK_WAIT` | 驱动Gen1并等待PHY完成 |
| 5 | `ST_FALLBACK_IDLE` | Gen1保持，等待对端确认 |

K12-B只证明状态和错误出口；真正的Recovery状态、TS边界以及PHY端口接线必须在
K12-C之前由行为PHY和真实串行环境再次确认。
