# K13 控制阶段记录（2026-08-13）

状态：**K13-CTRL PASS；生产顶层边界接线完成；K13 全集成未完成**

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

- VCS：源文件扩展和编译阶段通过；真实 VCS 在 elaboration 阶段因环境没有
  `VCSCompiler_Net` license seat 阻塞，未宣称 VCS PASS。
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
WNS: -0.270 ns
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
