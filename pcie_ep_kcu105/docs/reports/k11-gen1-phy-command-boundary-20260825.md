# K11 Gen1 PHY Command边界重构签署（2026-08-25）

## 结论

Phase A–C已实现。生产路径固定为：

`pcie_ltssm_mac_gen1 → pcie_phy_command_ctrl → K02 pcie_phy wrapper`

K04～K10 RTL及接口未修改。K13代码和实验资料保留为reference-only，但生产顶层、
lint、真实PHY VCS和canonical release源清单均不再包含K13控制/MUX/tap。

## 结构与验证

- controller唯一拥有PowerDown、DetectRx、TX Electrical Idle、Rate、TXEQ/RXEQ、
  Detect Assist、CDR Hold以及固定电气控制；
- K03只输出语义profile和`valid/kind`，消费`ready/done/result`；Detect与P0 PowerUp
  的PhyStatus由controller在当前拍完成，不增加流水；
- Phase C固定Gen1，rate、TXEQ和RXEQ为零；
- controller逐拍映射/两次独立PhyStatus测试PASS；
- ownership结构门禁PASS，额外`phy_rate` driver负向fixture被正确拒绝；
- K03行为回归13/13、100次随机训练、2000 Packet PASS；
- K11-B2 lint、真实PHY VCS serial/stress PASS。stress覆盖100次随机MMIO、坏LCRC/NAK、
  ACK丢失/Replay和PERST恢复。

VCS所用加密Root Port模型在G9窗口启用时会自行循环Detect，因此VCS board harness
固定G9=0；G9活动/超时由定向测试覆盖，canonical硬件release固定G9=1。

## Canonical release

构建目录：`fpga/kcu105/build_k11_gen1_release/impl`

```text
G9_WAIT_REMOTE_DETECT=1
G9_WAIT_REMOTE_DETECT_CYCLES=6250000
GEN3_RATE_CHANGE=0
EQ_ENABLE=0
PHY_COMMAND_CTRL_COUNT=1
WNS=+0.035 ns
WHS=+0.015 ns
DRC_ERROR_COUNT=0
DEBUG_CORE_COUNT=0
SHA256=4006e1a008ac462bbf3a98cf61733b7a2871ed74f575685ba892f921519d068d
```

`make k11b2-vivado`与`make k11b2-hw-program`使用同一canonical bitstream路径。

## KCU105实板

下载canonical bit后曾在首个压力尝试中复现历史偶发现象：第一次MMIO PASS、第二次
读回全`ffffffff`，Root Port记录Corrected Data Link `Rollover + Timeout`。按门禁
立即停止并保存Root Port/Endpoint/AER现场；未执行remove/rescan，也未修改K04～K10。
静态逐状态差分确认旧/新raw PHY command映射一致。该样本与既有K11报告中的偶发
DLL/事务生命周期现象相同，不能归因于PHY command重构。

随后仅通过Root Port reboot清场，完整重跑并获得连续3轮干净结果：

```text
reboot/enumeration: 3/3 PASS
vendor/device: 1234:e001
LnkSta: 2.5 GT/s x1, DLActive+
BAR0: 4 KiB, Memory Space Enable
MMIO: 15/15 PASS
signature=50434945
scratch=a5c37e19
UR=0, CA=0, AXI=0
new AER per boot: 0/0/0
```

失败样本未被删除或表述成PASS；Phase C签署依据是失败现场保存后整套连续3轮重跑
全部通过。Gen3 Recovery.Speed、128b/130b、EIEOS及EQ仍明确延期到Phase D/E。
