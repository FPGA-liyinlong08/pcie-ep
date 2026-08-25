# K14 Phase D2–D4：Golden方式 Recovery.Speed PHY切速

## 结论

已在不改动K04～K10的前提下，把K02 Golden实测的Gen1→Gen3 raw-command
contract收敛到唯一owner `pcie_phy_command_ctrl`，并接入Endpoint的
`Recovery.Speed`语义边界。当前阶段只证明PHY动态切速闭环，不宣称Gen3协议已完成：
切速成功后由于尚无128b/130b、EIEOS和Gen3 Recovery/EQ，Endpoint会按超时策略安全
回退到Gen1。

同一块KCU105上的独立controller顶层和Endpoint集成都已通过实现、时序与实板验证。
Endpoint获得10次有效的Gen3语义成功事件；最终3轮连续重复测试全部PASS。

## D2：controller事务

`pcie_phy_command_ctrl`新增语义rate transaction，同时继续是全部raw PHY命令的唯一
owner：

- 仅接受Gen1和Gen3目标；非法速度立即返回错误；
- 保持P0、TX Electrical Idle、Detect Assist=0、CDR Hold=0、TXEQ/RXEQ=0；
- 先保持Gen1恰好2500拍（10 us），再只把`PHY_RATE`改为Gen3；
- 只接受请求后的fresh PHYSTATUS，支持timeout、abort和复位；
- 成功后提交active rate，失败/abort后恢复Gen1；
- `valid/ready/done/result`语义不向LTSSM暴露QPLL或GT私有命令。

controller回归覆盖正常完成、早到/旧PhyStatus、超时、abort、非法目标、复位、重复事务
和逐拍Golden raw-command envelope。`make phy-command-ctrl-test`与
`make k14-recovery-speed-test`均PASS。

## D3：独立controller实板

独立路径为：

`pcie_phy_rate_test_seq → pcie_phy_command_ctrl → K02 PHY wrapper`

实现结果：

```text
top=kcu105_pcie_phy_command_rate_top
GTHE3_CHANNEL_LOC=GTHE3_CHANNEL_X0Y7
GTHE3_COMMON_LOC=GTHE3_COMMON_X0Y1
PCIE_HARD_BLOCK_COUNT=0
WNS=+0.501 ns
WHS=+0.004 ns
DRC_ERROR_COUNT=0
bitstream_sha256=b3791a86b033594e4e3f2e4edff9c814e82f69ee68c23b027c2f038f5b708b6d
```

10次连续有效采样中，QPLL1LOCK相对事务起点在87.768～88.168 us恢复，首个有效
PHYSTATUS在112.736～125.220 us出现；全部满足100 us/130 us签署窗口及最终
`PHY_RATE=2`、`QPLL1LOCK=1`、`PCIERATEGEN3=1`、`PCIEUSERGEN3RDY=1`。

## D4：Endpoint Recovery.Speed集成

生产顶层增加的功能由默认关闭参数隔离：

```text
GEN3_RATE_CHANGE_ENABLE=0   # canonical Gen1 release默认值
K14_RATE_DEBUG=0            # canonical Gen1 release默认值
```

实验构建中，配置空间Retrain请求、partner speed-change请求或定时测试请求经语义mailbox
进入`pcie_recovery_speed_ctrl`。controller只在LTSSM的`Recovery.Speed`边界发起切速，
期间quiesce Packet/DLL traffic；完成/失败由语义结果驱动后续状态，不新增raw owner。

实验实现结果：

```text
top=kcu105_pcie_ep_gen1_board_top
G9_WAIT_REMOTE_DETECT=1
PHY_COMMAND_CTRL_COUNT=1
GEN3_RATE_CHANGE_ENABLE=1
WNS=+0.006 ns
WHS=+0.004 ns
DRC_ERROR_COUNT=0
DEBUG_CORE_COUNT=2  # 1 x ILA + dbg_hub
bitstream_sha256=fb549c0e839cff8156449441b6eea1a72648c4b8cacffb2bf46e730945c5b4cf
```

首个fresh成功样本`20260825_190541_k14_recovery_speed.csv`在115.632 us看到
PHYSTATUS，复合触发拍直接观测到`PHY_RATE=2`、`QPLL1LOCK=1`、
`PCIERATEGEN3=1`、`PCIEUSERGEN3RDY=1`。该次紧凑事件记录器没有锁存QPLL rise
时间戳，但原始QPLL pin已为1；另一有效记录给出QPLL rise=87.812 us、
PHYSTATUS=114.224 us。

重复测试使用`event_state==success AND PHY_RATE==Gen3`复合触发。为避免Root Port对
同值Target Link Speed不产生新事务，每轮先稳定回到Gen1，再由Endpoint Retrain写入
产生确定的mailbox请求，最后由Root Port请求Gen3。共取得10次有效成功事件，其中最后
3轮为：

```text
20260825_192500_k14_recovery_speed.csv PASS
20260825_192510_k14_recovery_speed.csv PASS
20260825_192522_k14_recovery_speed.csv PASS
K14_RECOVERY_REPEAT_PASS cycles=3
```

事件记录器只在bitstream下载后fresh arm一次；后续无重烧重复事务的compact record会
保留首次时间戳并标记`recorder_fresh=0`。因此重复轮次只用于证明当前事务在复合触发拍
达到语义成功与四个raw最终条件，不把旧时间戳当作新的独立时延样本。时延签署依据是
fresh样本以及独立D3的10次测量。

## 门禁与边界

- `phy-command-ownership`正向门禁PASS，额外raw driver负向fixture正确失败；
- K03 13/13、100次训练、2000 Packet PASS；
- K11-B2真实PHY VCS serial/stress PASS，覆盖枚举、BAR、100次随机MMIO、坏LCRC/NAK、
  ACK丢失/Replay和PERST恢复；
- K04～K10相对Phase C基线无源文件差异；
- canonical Gen1 release仍固定Gen1且无debug core，D4实验入口不改变其默认行为。

下一里程碑Phase E才加入Gen3 EIEOS、128b/130b、Recovery.RcvrLock/RcvrCfg、
Equalization Phase 0～3及Gen3 L0/枚举/BAR压力。在Phase E完成前，D4 bitstream只作为
PHY切速实验基线，不能作为Gen3 Endpoint release。
