# K14 reboot Root Port自主Gen3请求 VCS基线

## 基线与约束

- Git基线：`7b6899651ca231d8ecfd1c671d44b4ab70a0bf59`
- 分支：`codex/k14-reboot-gen3`
- 入口：`make k14-reboot-vcs`
- 模型：K11B2真实串行Endpoint PHY与XDMA v4.1 Root Port，Root Port源码来自
  `/home/wx/Documents/XDMA/xdma_dec_250922/imports`
- Endpoint `GEN3_RATE_CHANGE_ENABLE=1`
- Endpoint `GEN3_AUTO_RETRAIN_CYCLES=0`
- 未调用Root Port或Endpoint配置写、Target Link Speed写、retrain task
- 未force TS、Recovery状态或`PHY_RATE`

## 结果

真实串行训练正常完成，双方进入Gen1 L0：

```text
K14_REBOOT_GEN1_L0_PASS epoch=0 time_ps=141691504
```

从Gen1 L0开始继续观察250,000个Endpoint PIPE时钟。测试在Root Port发送端原始
Gen1 PIPE上独立解码TS1，同时观察K14生产接收器；两处均未出现同时满足以下条件的
Root Port TS1：

```text
os_ts1_valid == 1
os_rate_id[7] == 1  # Speed Change
os_rate_id[3] == 1  # Gen3
```

门禁按设计失败：

```text
RP_AUTO_GEN3_REQUEST_MISSING epoch=0 wait_cycles=250000 \
ep_state=10 rp_state=10 rp_speed=1 ep_rate=0 auto=0 mailbox=0
```

失败时Endpoint和Root Port仍处于Gen1 L0，Endpoint AUTO源关闭，mailbox源为空。
原始PIPE证据排除了“K14接收器漏解一个已经发送的TS1”，但不表示该Root Port模型
不支持Gen3。

本次组合不升速的直接边界是K14在初始训练中发送`Rate ID=8'h02`，只向partner声明
2.5 GT/s能力；`8'h0e`仅在K14已经进入本端`speed_retrain_active`后才发送。因此，
在禁止配置写、本端AUTO和人工retrain的条件下，Root Port没有从partner获知Gen3
能力，也不会自行生成Speed Change事务。这与官方Gen3 Endpoint不同：现有
`pcie3_ultrascale_0_ex` VCS日志显示，官方Endpoint/RP先在Gen1 L0后自动进入Recovery，
随后达到8.0 GT/s；该RP进入Recovery发生在usrapp第一次配置写之前。

完整日志位于`sim/vcs/build/k14_reboot_simulate.log`（构建产物，不纳入源码提交）。

## 门禁结论

本基线不满足“保持初始`Rate ID=02`，同时要求不含BIOS/OS策略的Root Port硬件模型
自动发现并请求Gen3”这一组合前提。要继续验证必须先解决该前提冲突；更换同样支持
Gen3的Root Port版本本身不会补出被K14隐藏的partner能力。

## 与直接semantic仿真的关系

上述平台前提失败不阻塞K14内部控制边界验证。`make k14-direct-sim`严格依次执行：

1. `make k14-direct-vcs`：VCS加生产`pcie_phy_x1_gen3`行为模型；
2. `make k14-recovery-speed-test`：Verilator控制器回归；
3. PHY command ownership检查。

该入口不经过TS解码、Root Port task、`setpci`或Endpoint AUTO，直接向partner pending
边界提交Gen3 semantic request；pending/accept、重复请求抑制、reset重新arm、Gen3
PHY rate、fresh PhyStatus、QPLL lock、abort和timeout/fallback回归均已通过。Root Port
自动TS仍由独立的`make k14-reboot-vcs`负责，不与direct semantic PASS混记。
