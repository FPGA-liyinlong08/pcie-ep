# K13 Gen3 x1 全集成接口契约

状态：**v0.2，在建；Retrain已接入生产Recovery.Speed边界，真实Gen3数据路径和PHY反馈待闭环**

## 1. 参数与时钟域

| 参数 | 当前默认值 | 语义 |
|---|---:|---|
| `K13_ENABLE` | `0` | `0`为K11 Gen1静态旁路；`1`启用K13生产控制器 |
| `K13_SPEED_TIMEOUT_CYCLES` | `1_000_000` | `phy_pclk`域Recovery/Speed超时，250 MHz时约4 ms |
| `K13_EQ_TIMEOUT_CYCLES` | `1_000_000` | `phy_pclk`域每个EQ阶段超时，250 MHz时约4 ms |
| `K13_RXEQ_BOOTSTRAP` | `1` | Gen3 Rate change完成后是否主动发送PG239 `phy_rxeq_ctrl=2'b10`；用于A/B隔离 |

`core_clk/core_rst_n`对应`phy_coreclk/core_rst_n`，只承载配置空间发出的Retrain
命令；其余Speed、TS、EQ和PHY控制全部位于`phy_pclk/pipe_rst_n`域。跨域命令只能
通过`pcie_retrain_cdc_mailbox`传递。

## 2. `pcie_k13_production_ctrl`输入

| 信号 | 位宽 | 时钟域 | 契约 |
|---|---:|---|---|
| `link_up` | 1 | `phy_pclk` | 生产LTSSM的稳定L0指示；只在L0接受Retrain |
| `retrain_pulse` | 1 | `phy_coreclk` | K08配置空间单拍命令，由mailbox跨域 |
| `target_speed` | 2 | `phy_coreclk` | `00/01/10=Gen1/Gen2/Gen3`，`11`非法 |
| `phy_phystatus` | 1 | `phy_pclk` | PHY速率操作完成脉冲 |
| `phy_cdr_lost` | 1 | `phy_pclk` | 真实CDR失锁；高电平中止训练并触发Gen1回退 |
| `phy_txeq_done` | 1 | `phy_pclk` | 当前TX EQ命令完成 |
| `phy_rxeq_done` | 1 | `phy_pclk` | RX EQ完成指示；必须与`phy_rxeq_adapt_done`同拍有效 |
| `phy_rxeq_adapt_done` | 1 | `phy_pclk` | RX adaptation完成指示；必须与`phy_rxeq_done`同拍有效 |
| `ltssm_speed_ready` | 1 | `phy_pclk` | 生产LTSSM已进入`Recovery.Speed`，是唯一允许改变`phy_rate`的边界 |
| `ts_valid` | 1 | `phy_pclk` | 当前有已解析训练序列候选 |
| `ts_complete` | 1 | `phy_pclk` | 当前TS完整结束；accept只能在此边界产生 |
| `ts_is_ts1/ts_is_ts2` | 各1 | `phy_pclk` | TS类型，必须恰有一个有效 |
| `ts_lane` | 3 | `phy_pclk` | 解析后的Lane编号，x1固定期望0 |
| `ts_link` | 8 | `phy_pclk` | 解析后的Link编号 |
| `ts_rate` | 2 | `phy_pclk` | `00/01/10=Gen1/Gen2/Gen3`，`11`非法 |
| `ts_eq_request` | 1 | `phy_pclk` | 对端训练控制中的EQ请求 |
| `expected_lane/link` | 3/8 | `phy_pclk` | 本端已锁存的Lane/Link编号 |

顶层当前用`os_ts1_valid || os_ts2_valid`形成`ts_valid`，并将同一脉冲作为
`ts_complete`。这要求Ordered Set解析器只在完整TS结束时产生有效脉冲；若未来改为
多拍valid，必须拆分并重新验证`ts_complete`。

Rate ID按能力位图解析，不再要求exact one-hot：bit3优先映射Gen3，否则
bit2映射Gen2，再否则bit1映射Gen1；无任一合法能力位时映射为
非法`2'b11`。K13本端TX TS宣告`8'h0e`，TS guard还必须确认解析速率
与当前Retrain target一致。

## 3. PHY控制输出

| 信号 | 位宽 | 有效期与规则 |
|---|---:|---|
| `phy_rate` | 2 | 速率请求后保持到`phy_phystatus`或timeout；`00/01/10=Gen1/2/3` |
| `phy_txelecidle` | 1 | Speed切换期间置1；退出前必须完成PHY握手 |
| `phy_txeq_ctrl` | 2 | Phase 0/2命令；保持到`phy_txeq_done`或timeout |
| `phy_txeq_preset` | 4 | 当前固定Preset 4；驱动前必须合法 |
| `phy_txeq_coeff` | 6 | 当前固定Coefficient 12；驱动前必须合法 |
| `phy_rxeq_ctrl` | 2 | PG239编码：`00=Idle`、`01=Reserved`（生产逻辑禁止）、`10=RX EQ`、`11=Bypass`；`10`保持到`done && adapt_done`或失败/timeout |
| `phy_rxeq_txpreset` | 4 | 当前固定TX Preset 5；驱动前必须合法 |
| `traffic_quiesce` | 1 | Speed或EQ活动时为1，禁止新的TLP/DLLP提交 |
| `recovery_active` | 1 | Speed Recovery或EQ任一活动时为1 |

顶层mux规则：K13只在Recovery/EQ活动期接管相关PHY输出；K13关闭时全部使用生产
LTSSM输出。`mac_tx_valid`在`traffic_quiesce=1`时必须被抑制，同时不得丢失已经接受
但尚未完成的包。

## 4. 状态与结果输出

| 信号 | 位宽 | 语义 |
|---|---:|---|
| `negotiated_speed` | 2 | 已完成握手的速率；失败回退后为Gen1 |
| `speed_state` | 3 | K12-B局部状态编码，不能当作6位生产LTSSM编码 |
| `eq_active/done/failed` | 各1 | EQ进行、完成和失败状态 |
| `eq_phase` | 3 | `0～3`为Phase，`4`为完成，禁用值为`7` |
| `ts_accept/ts_reject` | 各1 | 完整TS边界上的单拍判定 |
| `cdr_loss_sticky` | 1 | 观察到CDR失锁后保持至复位 |
| `fallback_sticky` | 1 | 任一错误触发安全回退后保持至复位 |
| `speed_timeout_sticky` | 1 | 等待LTSSM Speed边界或PHY `phystatus`超时后保持至复位 |
| `illegal_ts_sticky` | 1 | malformed、非法Rate或Lane/Link不匹配的汇总 |

`speed_state`当前编码沿用K12：`0=L0`、`1=QUIESCE`、`2=SPEED_WAIT`、
`3=RECOVERY_IDLE`、`4=FALLBACK_WAIT`、`5=FALLBACK_IDLE`。

生产LTSSM增加`RECOVERY_SPEED=18`和双向握手：`recovery_speed_ready`授权
K13切速，`recovery_speed_done`通知PHY切速完成。LTSSM在旧速率完成
`RcvrLock→RcvrCfg`后进入Speed，切速后回到`RcvrLock→RcvrCfg→Recovery.Idle`；
K13未释放`force_recovery`前不得提前返回L0。

## 5. 复位和失败语义

- `core_rst_n=0`清空Retrain mailbox；`phy_rst_n=0`清空Speed、TS和EQ状态；
- CDR loss以`phy_rst_n && !speed_cdr_loss`复位EQ控制器，所有EQ命令必须归零；
- RXEQ成功条件固定为`phy_rxeq_done && phy_rxeq_adapt_done`；done-only脉冲不得推进Phase，生产Bootstrap失败后停止命令并进入回退路径；
- timeout、TS reject、非法速率和CDR loss必须最终令`fallback_sticky=1`并回到Gen1；
- sticky状态只在相应复位撤销，不允许自动清零掩盖错误；
- PERST#期间所有PHY控制取K02/K11定义的安全值。

## 6. 当前接口缺口

生产顶层当前以`RXELECIDLE && !RXVALID`的连续周期作为CDR-loss代理，
尚未满足真实GT CDR-loss契约；冻结前必须接入K02 PHY可验证的失锁来源。
生产LTSSM还必须提供真实Gen3 TS发送和128b/130b
收发边界，不能仅用Gen1 Ordered Set接口推断Gen3已经闭环。

K13开发bit必须明确记录`K13_ENABLE=1`。当前诊断bit虽已以
`K13_ENABLE=1`实现和上板，但仅验证了Gen1枚举/BAR及失败Retrain现象，
不属于本接口的Gen3实板验收物。
