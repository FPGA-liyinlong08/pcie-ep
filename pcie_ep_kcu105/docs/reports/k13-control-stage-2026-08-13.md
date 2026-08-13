# K13 控制阶段记录（2026-08-13）

状态：**K13控制/生产边界子阶段通过；Root Port Gen3能力已由XDMA同板对照确认；K13全集成未完成**

## 1. 本次完成内容

新增 `rtl/phy/pcie_k13_production_ctrl.sv`，将 K12 已验证的控制单元组合成一个
可关闭的生产接线边界：

- 配置空间 Retrain 命令通过 CDC mailbox 原子跨到 `phy_pclk`；
- Recovery.Speed 驱动 Gen1/Gen2/Gen3 速率请求、PHY `phystatus` 完成和 fallback；
- Ordered Set 只在完整边界、类型、速率、Lane/Link 合法时接受；
- Gen3 EQ Phase 0～3 驱动 Preset/Coefficient，并等待 TX/RX done 或超时；
- CDR loss、非法 TS 和训练失败回到 Gen1 安全路径；
- `K13_ENABLE=0` 时所有 PHY 控制输出保持 K11 Gen1 安全值。

EQ 启动条件使用“Speed 已完成且 TS 合法”这一边界，避免控制器等待 EQ done
而 EQ 又尚未启动的死锁。

## 2. 已执行门禁

命令：

```text
make -C pcie_ep_kcu105 k13
make -C pcie_ep_kcu105 k12-integration
```

结果：

| 门禁 | 结果 | 覆盖 |
|---|---|---|
| K13 Verilator lint | PASS | `K13_ENABLE=1` 控制器展开 |
| K13 production control simulation | PASS | 3/3 |
| Gen3 Speed + EQ | PASS | 速率完成、TS边界、EQ Phase 0～3 |
| CDR loss fallback | PASS | 回退并锁存错误 |
| malformed/illegal TS reject | PASS | 拒绝并进入安全回退 |
| K12 integration regression | PASS | 7/7 |

K13 仿真测试名：

- `production_gen3_speed_eq_path`
- `production_cdr_loss_fallback`
- `production_bad_ts_rejects`

## 3. 生产顶层接线结果

已将控制器接入 `rtl/ep/kcu105_pcie_ep_gen1_top.sv`：

- Retrain 脉冲和目标速率由配置空间经 `k11a_offline_top` 引出；
- 生产 LTSSM 的 TS1/TS2 合法性、Lane/Link、Rate、training-control 和 RX TS 完成边界接入；
- PHY `phystatus`、TX EQ done、RX EQ done 接入；
- `K13_ENABLE=1` 时 K13 控制器驱动速率、TX electrical idle、EQ 和 TX quiesce；
- `K13_ENABLE=0` 使用静态 generate bypass，不实例化控制器，也不保留 K13 mux 逻辑，保持 K11 release 数据路径；
- 当前 K02 PHY wrapper 没有独立 CDR-loss 输出，因此顶层暂以安全默认 `phy_cdr_lost=0` 接入，不能视为真实 CDR loss 已完成。

默认展开和 `-GK13_ENABLE=1` 的 K11-B2 lint 均 PASS；K13 控制器 3/3、K12 集成 7/7 均 PASS。

## 4. 当前边界和未完成项

当前仍不是完整 Gen3 Endpoint：生产 LTSSM/MAC 的 TX Ordered Set 仍是 Gen1 实现，
PHY wrapper 也缺少真实 CDR-loss 端口，因此 K13 目前只能作为控制接线阶段，不能宣称
Gen3 retrain 已闭环。

## 5. VCS / Vivado 门禁结果

- VCS：源文件扩展和编译阶段通过；当时elaboration因执行环境无法访问
  `VCSCompiler_Net`服务而阻塞，后续已按第12节复签解除。
- Vivado 默认 `K13_ENABLE=0`：综合、place、route、DRC 均完成，DRC 为 0 Error；
  最终 timing gate 失败，`txoutclk_out[0]` 为 `WNS=-0.033 ns`、`TNS=-0.054 ns`、
  6 个 setup failing endpoints，hold 为 `WHS=+0.030 ns`。主要失败路径仍在现有
  Gen1 framer/PHY TX 数据路径，不是 K13 控制器逻辑。
- 因 timing gate 失败没有生成 K13-enabled 正式 release bit；本次按要求生成的是
  允许负 WNS 的 K11-B2 ILA 诊断 bit，K11 release 基线未被替换。

## 6. 本次继续执行结果（ILA 诊断 bit）

按要求暂不修复小时序，先生成可用于 ILA 取证的诊断 bit。默认 32768 深度的完整
ILA 因 BRAM 资源不足停止，随后切换到 G12 Ordered-Set 诊断变体：PIPE ILA 深度
4096、不创建 Core ILA，最终生成成功：

```text
bit: /home/wx/Documents/PCIe/pcie_ep_kcu105/fpga/kcu105/build_g12_ordered_set_ila/impl/k11b2_gen1_endpoint_ila.bit
ltx: /home/wx/Documents/PCIe/pcie_ep_kcu105/fpga/kcu105/build_g12_ordered_set_ila/impl/k11b2_gen1_endpoint_ila.ltx
marker: K11B3_ILA_IMPL_PASS
WNS: -0.019 ns
DRC: 0 Error
TIMING_POLICY: DIAGNOSTIC_ONLY_NEGATIVE_ALLOWED
```

该 bit 是 **Gen1 K11-B2 顶层的 ILA 诊断 bit**，不是 K13 Gen3 bit；`K13_ENABLE`
仍为默认 0。外层构建脚本已同步支持 ILA 变体目录、已知 ILA warning 和诊断时序
策略，避免出现 bit 已生成但命令因按正式 release 规则复查而返回失败的情况。

下一步仍需修复现有 250 MHz TX→GTH setup 路径并恢复 `WNS>=0`，然后在真实
Gen3 LTSSM/TS TX、CDR-loss 端口和 VCS license 可用后，重新跑 K13-enabled
Vivado、bit、Gen3 枚举/BAR/reboot 验证。

## 7. 本次烧写、远端 reboot、枚举和 BAR 验证

### 7.1 烧写路径

- 本机 Vivado `hw_server` 访问 KU040 JTAG target：Digilent，序列号
  `210308AC5C97`。
- 成功烧写本节第 6 节的 G12 Ordered-Set ILA bit，并发现 1 个 PIPE ILA
  `u_ila_pipe`；烧写后执行 `program-arm`。
- 远端主机为 `192.168.11.126`，本次执行的是主机 reboot，随后重新 SSH 检查。

### 7.2 reboot 后 PCIe 枚举

远端主机 reboot 后的实际结果：

```text
0000:01:00.0 Unassigned class [ff00]: Device [1234:e001] (rev 01)
Region 0: Memory at 82800000 (32-bit, non-prefetchable) [disabled] [size=4K]
COMMAND=0000
```

因此“设备重新枚举”结论为 **PASS**，但 Linux 此时尚未开启 PCI Memory
Space/Bus Master；这与设备出现在 `lspci` 中是两个独立条件。

### 7.3 BAR 访问

现成 `/home/wx/c_test/pcie_bar_test1 0000:01:00.0 0` 通过动态发现 BAR0
并使用 `/dev/mem` 访问物理地址，reboot 后直接完成：

```text
Write throughput: 37.21 MB/s
Read throughput: 2.97 MB/s
```

随后使用标准 PCI 配置路径临时执行 `setpci -s 01:00.0 COMMAND=0006`，复查为：

```text
Control: I/O- Mem+ BusMaster+ ...
Region 0: Memory at 82800000 (32-bit, non-prefetchable) [size=4K]
Write throughput: 27.12 MB/s
Read throughput: 2.89 MB/s
```

结论：**BAR0 物理访问 PASS；开启 PCI Memory Space/Bus Master 后的标准 BAR
访问 PASS**。后续应由正式驱动或 PCI enable 流程设置 command bits，不能仅以
`/dev/mem` 直访代替标准 PCI 设备访问。

### 7.4 reboot 后 ILA 证据

回读文件：

```text
pcie_ep_kcu105/fpga/kcu105/build_g12_ordered_set_ila/capture/20260813_134422_u_ila_pipe.csv
```

使用 `scripts/decode_k11b3_ila.py` 的结果：

```text
PIPE samples=4096 trigger=[1024]
PIPE link_loss_trigger=[]
PIPE phy_rxidle_conflict=[]
PIPE final ltssm=0x0a link=1 dll_active=1 fc=3 rx_tlp=2 tx_tlp=0
PIPE PHY RX valid_samples=4096 data_valid_samples=0 nonidle_samples=4096
PIPE GT RX resetdone_samples=4096 valid_samples=4096
PIPE errors lcrc=0 sequence=0 duplicate=0 buffer=0 fc=0 bad_dllp_crc=0 malformed_dllp=0
```

`ltssm=0x0a` 对应 `STATE_L0`；G9 为非 active、无 timeout，G10 状态为
`0x39400000`（已见 CFG_COMPLETE/L0），G12 低字段保持 `0x0a`。这证明烧写后
链路在活动状态下接收了 BAR 测试流量，没有观察到 link-loss、RxElecIdle
冲突或 DLL/CRC 错误。

本次 `program-arm` 默认使用 TLP trigger，故 ILA 采样是 **reboot 后链路恢复并
产生 BAR 流量的证据**，不是以 PERST# 边沿为触发点的专用冷启动波形；若要取得
PERST# 低电平到释放的完整波形，下一轮应使用 `program-arm-perst` 或
`program-arm-perst-release` 后再单独 reboot。

## 8. K13_ENABLE=1 诊断实现结果（本次继续执行）

为保持 K13 阶段继续进行，新增了 K13-enabled 的 Vivado 构建入口，并保留
`K13_ENABLE=0` 的 K11 安全旁路。第一次使用完整 32768 深度 ILA 时，综合因
KU040 BRAM 容量不足停止；随后采用 G9+G12 PIPE-only、4096 深度 ILA 重新实现，
实现和 bitgen 均成功：

```text
bit: /home/wx/Documents/PCIe/pcie_ep_kcu105/fpga/kcu105/build_k13_gen3_ila/impl/k11b2_gen1_endpoint_ila.bit
ltx: /home/wx/Documents/PCIe/pcie_ep_kcu105/fpga/kcu105/build_k13_gen3_ila/impl/k11b2_gen1_endpoint_ila.ltx
marker: K13_ILA_IMPL_PASS
K13_ENABLE: 1
PHY_MODULE: pcie_phy_x1_gen3
WNS: -0.113 ns
DRC: 0 Error; unrouted nets: 0
TIMING_POLICY: DIAGNOSTIC_ONLY_NEGATIVE_ALLOWED
```

该 bit 是 **K13 控制器已展开的诊断实现 bit**，不是 K13 正式 release：当前生产
LTSSM/MAC 的 Ordered Set 仍是 Gen1 路径，PHY wrapper 仍没有真实 CDR-loss 输入，
并且 ILA 保留了负 setup 时序。外层 warning allowlist 的换行比对问题也已修复，
可复用检查现有实现目录而不重复跑 Vivado。

下一步是用本机 JTAG 烧写该 K13 诊断 bit，执行远端冷启动/reboot 后核对
`lspci -vv` 的真实速率和 x1 宽度、标准 PCI command/BAR 访问，并用 ILA 观察
Speed/EQ/TS 边界；结果只能用于 K13 集成取证，不能替代正式 Gen3 release 门禁。

## 9. K13 诊断 bit 实板 reboot 结果（2026-08-13）

### 9.1 烧写和 reboot

- 本机 JTAG target：KU040，序列号 `210308AC5C97`；K13 bit 烧写成功，识别到
  1 个 PIPE ILA，并成功 arm。
- 远端 `192.168.11.126` reboot 后设备重新枚举为 `01:00.0 1234:e001`。

### 9.2 真实链路状态

sudo 读取的 PCIe capability：

```text
LnkCap: Speed 8GT/s, Width x1
LnkSta: Speed 2.5GT/s (downgraded), Width x1 (ok)
LnkSta2: EqualizationComplete-, EqualizationPhase1-, EqualizationPhase2-, EqualizationPhase3-
```

结论：**reboot 后枚举 PASS、x1 PASS，但 Gen3 速率 FAIL**。K13 bit 虽然展开了
Gen3 PHY wrapper 和 K13 控制器，但当前生产 LTSSM/MAC 仍走 Gen1 Ordered Set，
因此没有发生真实 Gen3 Recovery/EQ 握手。

### 9.3 标准 BAR 访问

设置 `setpci -s 01:00.0 COMMAND=0006` 后，标准 PCI Memory/BusMaster 位均为 1；
现成 `/home/wx/c_test/pcie_bar_test1 0000:01:00.0 0` 通过：

```text
Write throughput: 39.74 MB/s
Read throughput: 4.19 MB/s
```

结论：**标准 command 开启后的 BAR0 访问 PASS**。

### 9.4 ILA 证据

```text
capture: fpga/kcu105/build_k13_gen3_ila/capture/20260813_151042_u_ila_pipe.csv
samples=4096, trigger_count=1
ltssm=0x0a (L0), link=1, dll_active=1
rx_tlp=1, tx_tlp=0
link_loss_trigger=0, phy_rxidle_conflict=0
rxrate_values=[0], rxresetdone=1, rxvalid=1
lcrc=0, sequence=0, duplicate=0, buffer=0, fc=0, bad_dllp_crc=0
malformed_dllp=1
```

ILA 与 PCI 配置空间结论一致：链路稳定在 Gen1 L0，能够完成 BAR 流量，但没有
进入 Gen3 EQ。`malformed_dllp=1` 保留为下一轮 K13 的独立异常项，需结合原始
波形确认是解码器边界误报还是实际 DLLP 异常。当前新增的 CDR-loss 是
`RXELECIDLE && !RXVALID` 连续 8 个 `phy_pclk` 周期的 PIPE 代理，不是 GT 原生
`rxcdrlock`；本次没有观察到该代理触发 link-loss。

本轮 K13 仍保持“进行中”，不冻结为 K13 release；下一步应把真实 LTSSM/TS TX、
PHY feedback（包括 CDR-loss、phystatus 和 EQ done）接入闭环，再重跑 Gen3 x1
reboot、BAR 和 ILA 验证。

## 10. K13 标准 Retrain 触发结果（2026-08-13）

为区分“未触发 Retrain”和“Retrain 后升速失败”，本轮重新 arm ILA 后，向
PCIe Capability 的 Link Control 写入标准 Retrain 位。结果如下：

- Retrain 写入生效后，设备短暂变为 `rev ff / Unknown header type 7f`，PCIe
  capability 暂不可读，且等待后没有自行恢复；远端 reboot 后恢复枚举。
- ILA：
  `fpga/kcu105/build_k13_gen3_ila/capture/20260813_153447_u_ila_pipe.csv`
- 解码结果：`rxrate=0` 持续到 sample 1924；sample 1925～1927 短暂为
  `rxrate=2`，随后 `rxvalid` 变为 0，sample 1957 后 `rxrate` 回到 0。
  全部采样中的 `ltssm=0x0a`，未形成可观察的 Recovery/EQ Phase 波形。
- ILA 汇总：`rxrate_values=[0,2]`、`rxvalid_samples=1928`、
  `rxresetdone=1`、CRC/sequence/buffer 错误为 0。
- reboot 恢复后：设备重新枚举，`LnkSta=2.5GT/s x1`，BAR 访问恢复，写
  26.89 MB/s、读 4.10 MB/s。

该结果说明 Retrain 并非没有触发：PHY 速率曾短暂切到 Gen3 请求值，但生产
LTSSM 仍保持 `L0` 观测值，Gen3 速率只维持约3个采样周期即失去 `RxValid` 并回到
Gen1。当前 EQ 未完成的直接故障点是 Recovery.Speed、生产 LTSSM 和 PHY 数据有效
切换没有形成闭环；尚不能归因于某个 EQ Phase 的 Preset/Coefficient 或 EQ done
失败，因为训练尚未稳定进入 EQ Phase 0。该现象进一步确认 K13 还不能冻结。

## 11. Retrain/Recovery.Speed生产接线修正（2026-08-13）

针对第10节“LTSSM始终为L0，PHY rate单独短暂变为Gen3”的实板证据，
本轮先修正控制链，不直接生成新bit：

- 生产LTSSM增加`RECOVERY_SPEED=18`，Retrain必须依次经过旧速率
  `RcvrLock→RcvrCfg`、`Recovery.Speed`、PHY切速、新速率
  `RcvrLock→RcvrCfg→Recovery.Idle`，然后才能返回L0。
- `pcie_recovery_speed_ctrl`在`ltssm_speed_ready=1`前保持Gen1 rate，不得在L0
  旁路切速；PHY切速完成通过`recovery_speed_done`回送LTSSM。
- 硬件Speed/EQ超时由32个周期改为1,000,000个`phy_pclk`周期，
  250 MHz时约4 ms；行为测试仍以参数覆盖使用短超时。
- TS Rate ID由exact one-hot改为能力位图解析，K13 TX由`8'h08`改为
  宣告Gen1/2/3的`8'h0e`；TS guard要求解析速率与Retrain target一致。
- 现有64-bit PIPE ILA复用原保留位，加入`speed_state`、`eq_phase`、
  recovery/EQ active、fallback、speed timeout、TS accept/reject和CDR-loss；解码脚本
  同步更新。

执行结果：

```text
make k13                                      PASS，3/3
make k12b-speed                              PASS，6/6
make k12-integration                         PASS，7/7
make k03-lint                                PASS
make k03-verilator                           PASS，12/12 + 100次随机训练
retrain_uses_ltssm_recovery_speed_boundary  PASS，1/1 Directed
make k11b2-lint                              PASS，K13_ENABLE=0/1
```

VCS以`K13_ENABLE=1`首次重试时，全部源文件已编译完成，没有新增RTL语法
或端口错误；elaboration等待`VCSCompiler_Net` 90秒后因执行环境网络隔离超时。
该阻塞后续已按第12节解除，但Gen3动态训练仍未完成，因此不写
`K13_VCS_GEN3_PASS`。

本轮修正关闭了“L0旁路切速”这一已知控制缺陷，但仍未关闭Gen3协议面：
生产收发路径仍是Gen1 8b/10b，尚缺Gen3 TS/EQ字段和128b/130b Sync Header/
Start Block，CDR-loss也仍是PIPE代理而非GT原生反馈。下一个工作项是先在行为
Partner/VCS闭环这些协议路径，通过后再生成包含新ILA字段的K13诊断bit。

## 12. VCS license和配置/BAR基线复签（2026-08-13）

`VCSCompiler_Net`排队的根因已确认为执行环境无法访问本机FlexNet端口；
license server、`snpslmd`均为UP，Compiler/Runtime feature均为99席、0占用。详细
排查和复用命令已记录到`docs/reports/vcs-license-status.md`，运行脚本也增加
license环境自动设置和10秒preflight。

第一次越过elaboration后的`Max Link Speed=0`/`BAR mask=0`并非同一个RTL故障：

- Xilinx XDMA Root Port示例的自检硬编码读取其配套Endpoint的`0xd0`，而本
  Endpoint的Capability Pointer为`0x40`、Link Capability为`0x4c`。
- 示例`pci_exp_usrapp_tx.v`还有一个自动配置initial进程，与本工程的
  `k11b2_transaction_test`同时驱动TX task并共用`DEFAULT_TAG/P_READ_DATA`，导致
  Completion数据被竞争覆盖。

执行脚本现在只屏蔽Xilinx示例的自动initial测试，保留全部公开transaction
task；并按本Endpoint的Capability Pointer检查真实字段。复签结果：

```text
357 modules elaborated and linked
K13_VCS_CFG_CAP_PASS cap_ptr=40 max_speed=3 max_width=1
K11B2_ENUM_PASS bdf=01a0 bar0=80000000
K11B2_BAR_PASS signature=50434945 scratch=a5c37e19
K11B2_VCS_PASS
K11B2_VCS_REAL_PHY_PASS
```

因此VCS elaboration、Gen1串行链路、Gen3/x1能力字段和配置/BAR基线已通过。
该用例尚未发起并完成Gen1→Gen3 Retrain/EQ，所以不得将本节标记为
`K13_VCS_GEN3_PASS`。

## 13. Gen1→Gen3生产动态闭环与串行模型边界（2026-08-13）

本轮新增`sim/verilator/k13_integration`，没有以控制器Stub替代生产路径。联合顶层
实例化真实`pcie_ltssm_mac_gen1`、`pcie_k13_production_ctrl`、Gen1/Gen3
Ordered Set模块，并用一套独立`pcie_gen3_os_tx`作为PIPE行为PHY Partner。测试从
Gen1 L0发出实际core-domain Retrain mailbox，驱动旧速率Recovery TS、PHY
`phystatus`、TX/RX EQ done和新速率Gen3 Ordered Set。第14节修正后，独立TX
前缀断言要求`EIEOS→TS1/TS2`，不再接受旧测试中的训练前SDS。结果为：

```text
production_ltssm_gen1_to_gen3_eq_closed_loop passed
K13_LTSSM_PARTNER_INTEGRATION_PASS
K13_CTRL_AND_LTSSM_INTEGRATION_PASS
```

波形断言确认LTSSM经过`Recovery.RcvrLock→Recovery.RcvrCfg→Recovery.Speed`，
PHY rate只在Speed边界变为`2'b10`；切速后重新训练并独立解析Gen3 TS1/TS2，EQ
Phase严格经过`0→1→2→3→4`，无TS reject、fallback或EQ failure，最终进入
`Recovery.Idle`。K11顶层`K13_ENABLE=1` lint、K12 integration 7/7和K03
Recovery.Speed directed回归也全部PASS。

串行模型方面，VCS和XSIM都出现“双方Rate已切到Gen3、GT TX持续翻转，但
RXVALID/DATA_VALID始终为0”。为避免把模型边界误诊为RTL缺陷，新增双PHY XSIM
纯回环诊断，使用AMD示例相同的P1→P0、Preset apply和Gen3 golden pattern；复签
结果为：

```text
K13_XSIM_PHY_LOOPBACK_RESULT ... rxvalid=0 data_valid=0 ... peer_rxvalid=0 peer_data_valid=0 ... tx_edges=263004
K13_XSIM_PHY_MODEL_LIMIT_OBSERVED
```

临时生成的Vivado 2021.2官方PCIe PHY example同样在两端没有Gen3
`RXVALID/DATA_VALID`；其默认成功提示只表示定时测试流程结束，并不校验RX数据。
因此旧VCS/XSIM安全模型的Gen3无RX结论被重新分类为**仿真模型限制、非RTL失败
证据**。K13控制状态机和行为Partner闭环现已关闭，但角色正确的真实EQ字段、
Gen3 L0事务、真实CDR-loss、
非负WNS实现以及实板8.0 GT/s枚举/BAR仍是冻结门，当前状态继续为
`K13-IN-PROGRESS`。

## 14. Gen3 Ordered Set修正和第二次实板复测（2026-08-13）

### 14.1 已关闭的协议缺陷

源码审计发现原Gen3训练发送器使用了`EIEOS→SDS→TS1/TS2`顺序，并在SDS后
初始化scrambler。该顺序不适用于Recovery训练：训练开始和每32个TS之间应插入
EIEOS，scrambler在EIEOS末尾复位；SDS用于Recovery.Idle开始Data Stream，不能
插在Recovery TS前。行为Partner与生产发送器原先共享同一错误假设，因此旧联合
回归形成了自洽但不独立的假阳性。

本轮完成以下修正：

- `pcie_gen3_os_tx`改为`EIEOS→TS1/TS2`，每32个TS重新发送EIEOS并复位LFSR；
- `pcie_gen3_os_rx`在EIEOS后建立scrambler边界，SDS只推进而不重置LFSR；
- K13集成测试独立检查生产TX前缀为4个EIEOS字后直接进入TS1，且不含SDS；
- `make k13`通过，输出`K13_LTSSM_PARTNER_INTEGRATION_PASS`和
  `K13_CTRL_AND_LTSSM_INTEGRATION_PASS`。

### 14.2 新bit和实板结果

使用`K11B2_ILA_DEBUG=1 K13_ENABLE=1 G9_WAIT_REMOTE_DETECT=1
G12_ORDERED_SET=1`重新完成Vivado实现和bitgen：

```text
K13_ILA_IMPL_PASS
DRC Error = 0
WNS = -0.121 ns
bit = fpga/kcu105/build_k13_gen3_ila/impl/k11b2_gen1_endpoint_ila.bit
SHA256 = eea45005917eafa1e156eba9670dd45e2c005f4ec0d7363f3f16157c71db2664
```

该bit仍有负setup时序，只是诊断bit。经本机JTAG烧写后远端主机reboot，设备没有
重新枚举，故本轮BAR测试不可执行。ILA记录为
`fpga/kcu105/build_k13_gen3_ila/capture/20260813_202324_u_ila_pipe.csv`，关键时序：

```text
sample 512: PhyStatus 0→1，GT RXRATE保持2'b10
sample 513: speed_state 2→3，PhyStatus 1→0
sample 514: LTSSM Recovery.Speed(0x12)→Recovery.RcvrLock(0x0b)
Gen3 RXVALID samples = 0
Gen3 DATA_VALID samples = 0
GT RX valid samples = 0
```

这证明EIEOS/SDS缺陷已修正，但它不是唯一根因。Recovery.Speed命令、GT rate切换
和PhyStatus完成应答已经闭环；失败发生在新速率重新进入RcvrLock后，没有收到任何
可供TS/EQ解析的Gen3 block。

### 14.3 Root Port Gen3能力结论修正

前一版记录曾根据一次远端`00:01.0`能力读取写成“Root Port最高只支持Gen2”，
该结论现撤销。工程中已有同一块KCU105、同一Lane、同一PCIe插槽和同一远端主机的
官方XDMA Gen3 x1对照证据：

```text
Endpoint = 10ee:9031 (official XDMA)
LnkSta = 8GT/s x1
EqualizationComplete = 1
Equalization Phase 1/2/3 = complete
AER = 0
```

该结果证明Root Port、PCIe插槽、Lane 0、REFCLK、PERST#和板级GT通道具备Gen3
建链条件，当前插槽可以作为K13 Gen3实板验收Partner。之前的能力寄存器快照与该
直接实板事实矛盾，现阶段只能判定为错误的BDF/能力偏移/采样上下文或过期状态，不能
继续把它作为Endpoint失败的解释；应在XDMA成功运行状态下重新读取并保存完整Root
Port BDF、PCIe capability offset和`lspci -vv`原文。

仍有一个必须独立关闭的TS矛盾：先前Gen1 ILA解析到对端TS1 Rate ID为`0x8e`，
但尚未用原始symbol和方向标记复核。由于XDMA已经证明对端确实支持Gen3，下一步
不应再检查Root Port是否支持Gen3，而应核对Endpoint的TS字段偏移、解扰边界、RX/TX
方向和速率能力解析是否正确。

### 14.4 结论和后续顺序

K13保持`K13-IN-PROGRESS`，不能冻结或发布。后续按以下顺序执行：

1. 扩充ILA，直接保存Gen1 TS原始16个symbol、RX/TX方向、解析后的Rate ID和
   speed-change位，先关闭`0x8e`与Root Port能力寄存器的矛盾。
2. 在XDMA成功状态下重新采集Root Port完整能力和链路状态，固定正确BDF及capability
   offset，排除上一版能力读取错误。
3. 对Endpoint增加Gen3 TS原始symbol、`RXDATAK`、收发方向和解析结果的ILA观测，
   核对`0x8e`是否确为Root Port TS1而非本端TX或错误字段。
4. 在真实Gen3 Partner上补齐角色正确的EQ Phase 0～3动态字段、
   `phy_rxeq_ctrl=2'b10`自适应流程、RX EQ done，以及Gen3 L0的128b/130b
   Data Stream/SKP/EDS和TLP/DLLP路径。

现有`pcie_equalization_ctrl`的Phase 1仍输出`phy_rxeq_ctrl=2'b01`，而当前PHY
接口中该编码不是接收自适应命令；生产顶层还用`os_rate_id[3]`代替真实TS EQ
Control/Data来启动EQ。行为测试中的Phase `0→1→2→3→4`只能证明状态机推进，
不能证明PCIe Gen3 EQ协议已实现，这两项必须在真实Gen3复测前修正。
