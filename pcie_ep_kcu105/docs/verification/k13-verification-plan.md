# K13 Gen3 x1 全集成验证计划

状态：**v0.9，在建；RXEQ合约、Recovery.Speed TXELECIDLE定向检查和PIPE Partner回归通过；实板已定位到GT rate-change/QPLL出口，Gen3尚未通过**

## 1. 验证目标与判定原则

K13验证目标是证明`K13_ENABLE=1`的生产Endpoint能够在真实PHY和Root Port下完成
Gen1→Gen3 x1训练、EQ、L0、配置枚举和BAR事务，并能从全部错误路径安全回退。

以下结果不能单独作为K13 PASS：控制器单元测试通过、PHY IP配置为8.0 GT/s、
`K13_ENABLE=0`的Gen1 bit枚举成功，或只通过`/dev/mem`访问物理BAR地址。

## 2. 固定验证分层

| 层级 | 必需内容 | 当前状态 |
|---|---|---|
| Lint/行为仿真 | K13控制器展开、正常Gen3、CDR loss、非法TS、K12回归 | **PASS** |
| 生产顶层仿真 | `K13_ENABLE=0/1`、真实LTSSM/TS边界、事务静默、回退 | **PIPE Partner动态闭环PASS；Gen3 L0事务路径待完成** |
| VCS真实PHY | Xilinx PHY + Root Port串行Gen1→Gen3、EQ和错误注入 | **elaboration/Gen1配置BAR PASS；Gen3 RX受模型限制** |
| Vivado | K13-enabled综合、CDC、DRC、route、非负WNS、bit/LTX | **诊断实现PASS；正式门未通过** |
| KCU105实板 | Gen3 x1枚举、ILA、BAR随机压力、retrain和回退 | **Gen1基线PASS；最新Gen3诊断bit未枚举；Root Port能力由XDMA对照确认** |

## 3. 已执行的K13-CTRL门

当前入口：

```text
make -C pcie_ep_kcu105 k13
make -C pcie_ep_kcu105 k12-integration
```

已通过：

- `k13-ctrl-lint`：以`K13_ENABLE=1`展开`pcie_k13_production_ctrl`；
- `production_gen3_speed_eq_path`：行为Partner下Speed完成，EQ Phase
  `0→1→2→3→4`，协商速率为Gen3；
- `production_cdr_loss_fallback`：注入CDR loss，sticky和Gen1 fallback成立；
- `production_bad_ts_rejects`：非法TS被拒绝并回退Gen1；
- K12 integration 7项回归继续PASS。
- K03 LTSSM原有12项回归通过，新增
  `retrain_uses_ltssm_recovery_speed_boundary` Directed用例通过；证明只有
  `Recovery.Speed`可授权切速，且K13未释放前`Recovery.Idle`不会提前回L0。
- K12-B Speed回归6/6通过，包含`ltssm_speed_ready=0`时禁止改变rate的用例。
- `k13-integration-sim`以生产`pcie_ltssm_mac_gen1`、生产
  `pcie_k13_production_ctrl`和独立Gen3行为Partner完成Gen1 L0→Retrain→
  `Recovery.RcvrLock/RcvrCfg/Speed`→Gen3 TS1/TS2→EQ Phase `0→1→2→3→4`→
  `Recovery.Idle`动态闭环；无TS reject、fallback或EQ failure。
- K12-C RXEQ回归已覆盖PG239合法编码、保留编码不驱动、`done=1/adapt_done=0`
  失败，以及四阶段成功路径；`K13_CTRL_SIM_PASS`中的behavioral responder也只在
  `phy_rxeq_ctrl=2'b10`下分别产生两个完成指示。
- 生产K13控制器已增加`K13_RXEQ_BOOTSTRAP=0/1` A/B参数。Gen3切速前的
  `TXELECIDLE` NBA交接窗口已由定向检查覆盖：进入Gen3 preset/rate-change
  window后，直到`PhyStatus`完成不允许出现0拍；TXEQ delayed-done、非法TS和
  CDR loss回归仍保持通过。
- 独立`k13_gen3_golden_checker.py`检查Endpoint PIPE观测的EIEOS→TS1顺序、
  block起始、Sync Header、TS1 marker和SDS禁用，判定不依赖partner RX。
- 本地`K13_RXEQ_BOOTSTRAP=0` controller A/B回归通过；完整LTSSM行为Partner的
  OFF分支目前被Verilator报告为测试模型零时间组合环，未将其记为PASS，也未把
  该harness问题外推为硬件结论。上板A/B仍须在真实PHY/Root Port上执行。

固定标记为：

```text
K13_CTRL_SIM_PASS
K13_LTSSM_PARTNER_INTEGRATION_PASS
K13_CTRL_AND_LTSSM_INTEGRATION_PASS
```

这些标记关闭控制器及生产LTSSM/PIPE Partner集成子阶段，不关闭真实串行PHY、
Gen3 L0事务、实现和实板门，因此不关闭K13。

## 3.5 新增 GT rate-change/QPLL 前置门

实板 RXEQ ON/OFF 各一次均在 RXEQ 启动前停于 `Recovery.Speed`，因此在进入
RXEQ Bootstrap A/B 和 Gen3 Ordered-Set 结论前，先完成 GT rate-change 前置门。
该门只判断 PHY/GT 握手和 QPLL 状态，不把诊断 bit 记为正式实现通过。

必须同时观测：

- `PHY_RATE/RXRATE`、`PCIERATEIDLE`、`PCIERATEGEN3`；
- `PCIEUSERGEN3RDY`、`PCIEUSERRATESTART`、`PCIEUSERRATEDONE`；
- `PCIERATEQPLLRESET/PD`、`QPLL1LOCK`、`PhyStatus`；
- 首个 Gen3 `RXVALID/DATA_VALID/START_BLOCK/SYNC_HEADER`。

最小合法时序窗口为：

```text
PHY_RATE=Gen3
→ PCIERATEIDLE进入切速窗口
→ QPLL rate reset/lock
→ PCIERATEGEN3和PCIEUSERGEN3RDY有效
→ PCIEUSERRATESTART/PCIEUSERRATEDONE完成
→ PhyStatus
→ 首个Gen3 block
```

当前硬件结果为：`PCIERATEIDLE` 在 sample 700 由 1 变 0，sample 701
`PCIERATEQPLLRESET` 拉高且 `QPLL1LOCK` 由 1 变 0；`PCIERATEGEN3`、
`PCIEUSERGEN3RDY`、`PCIEUSERRATESTART` 全程为 0，`PhyStatus` 仍为 0。
因此 GT rate-change/QPLL 前置门 **FAIL**，RXEQ、DLL/TLP/BAR 和最终 Gen3
验收必须继续冻结。

`PCIEUSERRATEDONE` 固定拉高的诊断 A/B 已完成但无改善，不能作为修复。随后完成了
`K13_GT_RATE_QPLL_RESET_FORWARD=1` 的诊断 A/B：静态网表确认
`PCIERATEQPLLRESET[0]` 确实进入活动 QPLL1RESET 驱动 LUT 的输入，但实板仍在
sample 701 发生 `QPLL1LOCK: 1→0`，且未恢复；`PCIERATEGEN3`、
`PCIEUSERGEN3RDY`、`PCIEUSERRATESTART` 和 `PhyStatus` 仍为 0。因此“rate reset
未扇出到 QPLL1”已排除为唯一根因，但 GT rate-change/QPLL 前置门仍 **FAIL**。
下一步应继续核对 standalone PHY/IP 生成配置和端口方向，尤其是 GT 内部
`PCIERATEGEN3/IDLE/USERGEN3RDY/USERRATESTART` 的实际驱动来源、QPLL1 lock
恢复条件以及 GT rate-done/START 时序；确认后再决定是否需要修改 PHY wrapper/IP
配置。该诊断 bit 的 WNS 为 `-0.129 ns`，仍只能作为诊断证据。

当前最直接的下一嫌疑是生成的 `pcie_phy_x1_gen3_core_top.v` 将
`GT_PCIEUSERRATEDONE` 固定接为 0，而 `GT_PCIEUSERRATESTART` 只被观测、没有
返回到用户握手逻辑；这与 `PCIEUSERGEN3RDY` 全程为 0 相互吻合。下一版应实现
“看到 `PCIEUSERRATESTART` 后按 GT Wizard 合约产生一次受控 `USERRATEDONE`”的
独立诊断变体，并同时采集 `PCIERATEGEN3/USERGEN3RDY/PhyStatus`。不能用持续拉高
done 代替该握手，也不能在此之前修改生产默认路径。

Gen1→Gen2 隔离仍保留为下一道硬件门，但当前仓库的 `G2_GEN1_ONLY` 入口是
Gen1/CPLL 对照构建，不是可直接代表 Gen2 的实板配置；不能把该入口误报为
Gen1→Gen2 PASS。需要先提供真实 Gen2 rate 选择/Root Port 限速方法，再执行
10 次冷启动和 20 次 Retrain。

## 4. 必需Directed场景

1. `K13_ENABLE=0`：与K11 Gen1 release行为等价，reboot、枚举和BAR不退化。
2. 正常Gen1→Gen3：Retrain命令原子跨域，Speed完成，合法TS被接受，EQ Phase
   0～3严格有序，最终进入Gen3 x1 L0。
3. Gen2中间路径：Root Port或PHY要求Gen2时正确完成，不误进入Gen3 EQ。
4. Speed timeout：撤销Electrical Idle命令并回退Gen1，不无限等待。
5. TX/RX EQ timeout：分别验证命令归零、错误锁存和Gen1回退。
6. 非法Rate、TS类型、Lane、Link、Preset和Coefficient：不得驱动非法PHY操作。
7. CDR loss：在Speed以及每个EQ Phase注入，均中止训练并回退。
8. Ordered Set边界：状态、TX mode和速率只在完整TS结束后切换。
9. Recovery事务静默：`traffic_quiesce=1`期间不提交新TLP/DLLP；回到L0后恢复。
10. PERST#/Hot Reset：在Speed和每个EQ Phase复位，输出回到确定安全状态。
11. Retrain重复/overflow：busy期间第二条命令不能覆盖目标速率，错误可观测。
12. Fallback后再次Retrain：Gen1恢复后能够重新尝试并成功进入Gen3。

## 5. 随机、断言与覆盖

- 随机化core/PHY时钟相位、PHY done延迟、TS间隔、拒绝点和CDR loss时刻；
- 至少覆盖Speed所有状态和合法边、EQ Phase 0～3成功/超时、三类TS拒绝和再次升速；
- 断言PHY命令在done/timeout前保持稳定，TS只在complete边界accept，quiesce期间无事务；
- 断言失败路径有限时间进入Fallback，EQ命令归零，最终恢复Gen1；
- 对关键Checker提供故意错误Stub，证明验证环境能检出提前done、Phase跳跃、TS中途切换、
  quiesce泄漏和CDR loss不回退。

## 6. VCS真实PHY门

必须以`K13_ENABLE=1` elaboration生产顶层、Xilinx standalone `pcie_phy`和Root Port
串行模型。至少完成：

- Gen1初始L0及配置访问；
- Root Port发起Retrain并协商8.0 GT/s x1；
- Recovery.Speed和EQ Phase 0～3波形；
- Gen3 L0后的配置读写和BAR TLP；
- CDR loss、非法TS、Speed/EQ timeout的Gen1回退。

本轮确认原90秒超时是执行环境无法访问`27000@wx-linux`，不是席位耗尽。
在可访问license server的环境中，357个模块完成elaboration/link并生成
`simv`。隔离Xilinx示例自带的自动配置进程后，K13-enabled生产顶层完成：

```text
K13_VCS_CFG_CAP_PASS cap_ptr=40 max_speed=3 max_width=1
K11B2_ENUM_PASS bdf=01a0 bar0=80000000
K11B2_BAR_PASS signature=50434945 scratch=a5c37e19
K11B2_VCS_REAL_PHY_PASS
```

这些标记只证明VCS平台、Gen1 DLL/配置/BAR和Gen3能力字段基线通过。VCS串行
Retrain中双方都完成PIPE Rate切换且GT TX持续翻转，但Endpoint的Gen3
`RXVALID/DATA_VALID`始终为0，因而不能完成串行Gen3训练。

为区分RTL缺陷和仿真模型边界，新增`sim/xsim/run_k13_phy_loopback.sh`，用两套当前
standalone PHY、AMD示例相同的P1→P0初始化、Preset apply和Gen3 golden pattern
进行纯PHY回环。Vivado 2021.2 XSIM仍得到：

```text
K13_XSIM_PHY_LOOPBACK_RESULT ... rxvalid=0 data_valid=0 ... peer_rxvalid=0 peer_data_valid=0 ... tx_edges=263004
K13_XSIM_PHY_MODEL_LIMIT_OBSERVED
```

另外，临时生成并给AMD官方PCIe PHY示例增加真实RX观测后也得到两端
`RXVALID/DATA_VALID=0`；原示例的`Test Completed Successfully`是定时状态结束，
不是Gen3 RX数据自检。故当前VCS/XSIM串行无RX只能判定为Vivado 2021.2安全模型
不具备可用的Gen3串行RX校验能力，不能据此判定Endpoint RTL失败，也不能据此写
`K13_VCS_GEN3_PASS`。动态协议闭环由第3节的PIPE Partner门覆盖，最终结论必须由
更新工具链或实板ILA给出。

## 7. Vivado实现门

K13-enabled构建必须明确传入`K13_ENABLE=1`，并在独立目录输出bit、LTX和报告。
必需条件：

- 综合、opt、place、route和bit生成全部成功；
- DRC为0 Error，CDC新增项逐条关闭或进入固定allowlist；
- 所有相关时钟路径`WNS>=0`且hold通过；
- 报告证明K13控制器未被常量裁剪，PHY速率/EQ输出由K13路径真实驱动；
- 生成物记录参数、Git commit、Vivado版本和SHA256。

允许负WNS生成的诊断bit只能标记`DIAGNOSTIC_ONLY`，不能通过K13实现门。

本轮K13诊断实现结果：`K13_ENABLE=1` 的综合、opt、place、route、DRC和bitgen
均成功，输出 `K13_ILA_IMPL_PASS`；实现目录为
`fpga/kcu105/build_k13_gen3_ila/impl`，WNS=`-0.113 ns`，DRC为0 Error，
unrouted nets为0。由于仍有负setup时序，该结果只作为诊断实现，不写入
`K13_IMPL_PASS`。

## 8. KCU105 Gen3 x1实板门

烧写K13-enabled bit后，在Linux Root Port执行并保存：

1. `lspci -vv`确认`LnkSta: Speed 8GT/s, Width x1`，且无降速/降宽；
2. Vendor/Device为`1234:e001`，BAR0为4 KiB且由标准PCI enable/驱动打开Memory Space；
3. ILA证明Speed、合法TS、EQ Phase 0～3和Gen3 L0边界；
4. 至少10万次随机8/16/32-bit BAR读写，数据逐项比对，无Completion/CRC/DLL错误；
5. remove/rescan、retrain、reboot后仍保持Gen3 x1并可访问BAR；
6. 注入或构造失败时能够回到Gen1可枚举状态，再次Retrain可恢复Gen3。

`/dev/mem`直访物理BAR可以作为辅助诊断，但必须另外证明PCI Command的Memory
Space已开启并走标准PCI设备访问路径。

第一版实板结果（2026-08-13）：K13 bit 已通过本机JTAG烧写到KU040，远端主机
reboot 后重新枚举为`01:00.0 1234:e001`；设置`COMMAND=0006`后标准BAR访问
通过，写吞吐39.74 MB/s、读吞吐4.19 MB/s。但真实链路仅为
`2.5GT/s (downgraded), Width x1`，`EqualizationComplete`及Phase 1～3均未完成。

ILA采样文件为
`fpga/kcu105/build_k13_gen3_ila/capture/20260813_151042_u_ila_pipe.csv`：
最终`ltssm=0x0a (L0)`、`link=1`、`dll_active=1`，未见link-loss或RxIdle冲突，
`rxrate_values=[0]`，说明当前链路仍停留在Gen1。当前CDR-loss检测使用
`RXELECIDLE && !RXVALID`连续8个`phy_pclk`周期的PIPE代理，不是真实GT
`rxcdrlock`，因此不能关闭真实PHY feedback门。

第二版诊断bit修正了Recovery训练中错误的`EIEOS→SDS→TS`顺序，改为开始及每
32个TS插入EIEOS，并在EIEOS末尾复位scrambler。bit SHA256为
`eea45005917eafa1e156eba9670dd45e2c005f4ec0d7363f3f16157c71db2664`，DRC为
0 Error，WNS为`-0.121 ns`。烧写并reboot后Endpoint未枚举，BAR不可访问；ILA
`20260813_202324_u_ila_pipe.csv`证明GT完成Gen3 rate切换和PhyStatus应答，但新
速率下`RXVALID/DATA_VALID`均为0。

前一版根据一次`00:01.0`能力快照误判Root Port最高为5GT/s；该结论已被撤销。官方
XDMA Gen3 x1在同一块KCU105、同一Lane、同一插槽和同一远端主机上枚举为`10ee:9031`，
并稳定报告`8GT/s x1`、Equalization Phase 1～3完成、AER为0。因此当前插槽具备
Gen3验收条件。下一版必须在XDMA成功状态下重新采集Root Port的完整BDF、capability
offset和`lspci -vv`，解释旧快照的读取上下文，不能再把Root Port能力作为当前失败原因。
此前ILA解析出的TS1 Rate ID `0x8e`仍需用原始symbol和方向标记复核。故仍不能标记
`K13_HW_GEN3_X1_PASS`、`K13_BAR_100K_PASS`或`K13_IMPL_PASS`，但原因应归回Endpoint
Gen3训练/接收路径，而不是Root Port不支持Gen3。

此外，当前EQ行为回归还不是协议冻结证据：`pcie_equalization_ctrl`的Phase 1使用
`phy_rxeq_ctrl=2'b01`，生产顶层以`os_rate_id[3]`替代真实TS EQ Control/Data触发
EQ。必须改为PHY接口定义的RX adaptation命令、接入动态TS EQ字段并按端口角色
验证Phase 0～3，才能写入任何真实EQ通过标记。

## 9. K13冻结标记

全部门禁通过后固定输出并记录：

```text
K13_CTRL_PASS
K13_VCS_GEN3_PASS
K13_IMPL_PASS
K13_HW_GEN3_X1_PASS
K13_BAR_100K_PASS
K13_FALLBACK_RECOVERY_PASS
K13_PASS
```

当前成立的标记为`K13_CTRL_AND_LTSSM_INTEGRATION_PASS`和
`K13_ILA_IMPL_PASS`；后者是诊断标记，不等价于`K13_IMPL_PASS`。阶段状态保持
`K13-IN-PROGRESS`，不得冻结为K13 release，也不得进入K14。

本轮新增的ILA probe19为64-bit `dbg_k13_top`，覆盖Recovery.Speed、
`phy_txelecidle`、TXEQ/RXEQ命令及两个done、TX/RX valid/start/header、
`PhyStatus`和LTSSM。实现脚本同时生成`timing_paths_50.rpt`；仍需单独确认
Gen3 TX相关路径无负WNS后，才可把实现结果从诊断门升级。

硬件门尚未执行：Gen1→Gen2的10次冷启动/20次Retrain、Gen3 RXEQ
Bootstrap ON/OFF各10次冷启动/10次Retrain、3次reboot/rescan、100,000次
标准PCI BAR访问和失败注入恢复均待上板。故`K13_VCS_GEN3_PASS`、
`K13_IMPL_PASS`、`K13_HW_GEN3_X1_PASS`、`K13_BAR_100K_PASS`、
`K13_FALLBACK_RECOVERY_PASS`和`K13_PASS`继续保持未置位。
