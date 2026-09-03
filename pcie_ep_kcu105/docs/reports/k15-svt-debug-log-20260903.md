# K15 SVT 调试记录（2026-09-01 ~ 09-03）

任务：EP（KCU105 设计）对 Synopsys SVT VIP 跑通 Gen3 链路训练与数据交换，
判定门 `K15_SVT_X1_PASS epochs=2`（`sim/vcs_svt/run_k15_svt_x1.sh`）。

前置已解决（见早前报告与 git log）：valid-gap 采集节奏（9af5c66）、
Gen3 SKP OS 格式 AA×12+E1（2252e15）、EQ 相位语义重写（b30a515，
P1 不 apply / P2 EC=11 收尾 / P3 EC=11 apply+reflect）。

## 一、修复时间线与有效性

| 改动 | 内容 | 有效性 |
|---|---|---|
| EQ 相位语义 (b30a515, 已提交) | 见上 | ✅ VIP EQ 三相握手通过 |
| SKP OS 格式 (2252e15, 已提交) | AA×12 + E1 tail；1C 是 Gen1/2 符号勿用 | ✅ |
| `eieos_suppress`（0c/0d 抑制周期 EIEOS） | VIP 把"EIEOS 后跟数据"当电空闲进入并关接收机；MAC 在 RcvrCfg(0c)/Recovery.Idle(0d) 屏蔽周期 EIEOS，流变成 VIP 验证过的 TS2→SDS→idle | ✅ |
| `K15_L0_GAP_OFF` (l0fix30i) | 去掉 L0 idle 流 1 拍 gap（GT 泄漏成 4 字节无帧残留，VIP 插入型 comp 消化不了） | ⚠️ 部分有效（idle 流 12 块验证干净，后续仍败） |
| l0fix31k：gap 拍内容改 aa | 假设泄漏的是 gap 拍自己的 TXDATA | ❌ 无效已回退（泄漏=前一字节重复，与内容无关） |
| `K15_SVT_RCVR_GAP_OFF` (l0fix32) | 去掉 Recovery 流全部 MAC gap | ❌ EQ P1 回归（详见三）；但 0x4a 失败点过关 |

## 二、关键取证事实（SVT 环境特有）

1. **孤儿字节 = 65 拍结构性 comp 插入，与 MAC gap 无关**。l0fix32 去掉全部
   gap 后 VIP RX 流仍有 +1"前一字节重复"孤儿，严格 65 拍周期（107 个孤儿
   全为重复）。"每 gap +1 → +27 累积漂移"理论作废。
2. **VIP 能消化孤儿**：l0fix31k EQ 流含 ~90 孤儿仍通过。
3. **GT secureip 要求 EIEOS 槽前紧跟 1 拍 valid=0 gap**（l0fix32 反例）：
   缺失则 EIEOS 槽后跟 00 00 + ~268 拍电空闲，VIP"连续 8 TS1"计数被打断。
   与 RP 侧"gap 与 EIEOS 相邻是必要条件"实测一致。
4. **gap_run bug 教训**：`pcie_gen3_os_tx.sv` SEND_EIEOS 完成分支
   （word_index==3）清 `gap_run`；依赖 gap_run 保存状态的触发必须避开。
   l0fix32 v1 因此一个 SKP OS 都没发（273.87µs 起 max_rx_skp_interval）。
5. VIP PIPE 字节流提取：
   `awk '$8 ~ /^data=/ {split($3,a,"="); t=a[2]/1e6; printf "%s %s %s %s\n", t, $6, $7, substr($8,6)}'`
   （probe 行 `K15_SVT_RP_PIPE_RX n= t_ps= valid= data_valid= start= sh= data= ei= status=`，字节在 data 低 8 位）。

## 三、当前失败状态（l0fix32，`K15_SVT_X1_FAIL epoch=0 reason=link_timeout`）

时间线：EP 正常走 EQ P1→P2（260.65µs，状态 29）→ 自认完成 →
Configuration(状态 12, rate=Gen3, 326µs)；VIP 222µs 进 EQ P1 后**再未出来**
（两次 100µs 超时：292.97/322.2µs）→ Recovery.Speed → EI 推断 →
**自己掉回 Gen1**（324µs）→ 双方速率失配 → DLLP CRC 错误 → link_timeout。
直接原因 = 缺 EIEOS 前 gap（事实 3）+ gap_run bug（事实 4）。

对比 l0fix31k（有 gap）：EQ 三相完整通过（~6µs），败在更后的
Recovery.Idle(0d)：`non-IDL token 0x4a` 成帧崩坏，发生在 idle 块 ~13，
属**局部破坏事件**（疑似 0d 交接后第一次未消化的插入），非累积漂移。

### 怀疑点与排查方向

- **怀疑点 A（主）**：0d 交接后 GT/comp 结构性插入的消化在 LFSR 相位上
  有一个例外情形。排查：重放 l0fix31k 日志（build/simulate.log 已被覆盖；
  /tmp/l0fix31k_svt.log 若仍在）看 267042µs 附近 idle 块 12→13 的
  start/sh/data，确认破坏点与孤儿位置的关系。
- **怀疑点 B**：0c→0d 过渡区（SDS 前）孤儿数与 VIP 期望不符。
  备选杠杆：SDS 前发一帧 EIEOS 双方重置 LFSR（需先验证 VIP 接受
  EIEOS→TS2→SDS，eieos_pending 机制）。
- **下一步（v2，已设计）**：`pcie_gen3_os_tx.sv` RCVR_GAP_OFF 触发改为
  `ts_interval_count==30 → SEND_GAP`（恢复 EIEOS 前 gap，只去 mid-run
  gap）；gap 分支改
  `stream_state <= ((RCVR_GAP_OFF || gap_run) && !eieos_suppress) ? SEND_EIEOS : SEND_TS;`
  RP 路径（RCVR_GAP_OFF=0）不变。预期 EQ 恢复 l0fix31k 通过态，再看 0d。

## 四、战略结论（2026-09-03 确认）：对端是真实主机

**上板测试对端是真实主机（非本仓库的 Xilinx RP 设计）**。由此：

- 真主机 = 任意规范实现接收端 → **SVT VIP 是最贴近上板的仿真**（它对
  EIEOS/SKP/EI 的严格行为都是规范语义）；Xilinx RP 仿真降级为回归工具。
- **K15_L0_SKP_OFF 上板禁忌**：真主机与 EP 各自独立 refclk（SRIS 类），
  ±300ppm 量级速率失配必须靠流内 SKP OS 补偿；关 SKP 链路必崩。
- `K15_L0_GAP_PHASE=4` 对齐的是 RP 仿真模型的结构性删除节拍，真主机无此
  节拍，不要指望它上板起保护作用。
- **收敛路线（上板版本的定义）**：v2 → SVT 过 → SKP 机制规范化（显式
  SKP OS 替代 1 拍 gap 作速率匹配手段，修 l0fix29 的 SKP 发射问题）→
  退役全部环境 define（GAP_OFF×2 / SKP_OFF / GAP_PHASE）→ 单一零 define
  配置两个仿真都过 → 上板。黄金参照：Xilinx demo EP 与真主机工作正常，
  其流形态（显式 SKP OS、65 拍 gap、EIEOS 用法）即"真主机接受什么"。

## 五、RP 影响评估与归档（2026-09-03）

- 当前工作区（含 eieos_suppress、`RECOVERY_IDLE: tx_os_mode=2'd0` 等
  无条件改动）跑 RP 回归：`K15_GEN3_L0_PASS epoch=0 rp_speed=4` ✅，
  确认不影响 Xilinx RP 仿真。
- 归档：commit `64c5187` + tag `rp-ok-pre-svt-l0fix32`（11 文件，
  排除 ucli.key——已被 .gitignore 覆盖——与仿真临时文件）。
- pcie3_ultrascale_0_ex/imports 三文件的 K15_PG3_OUT 调试端口与
  k11b_serial_board.sv 耦合，必须同进同出，不再单独 restore。
- RP 回归命令：`cd sim/vcs && K15_L0FIX=1 K15_L0_GAP_PHASE=4
  K15_L0_SKP_OFF=1 ./run_k15_gen3.sh`（900s 墙钟收尾属正常）。

## 六、2026-09-03 后续收敛与已实施修复（l0fix33~40）

### 6.1 Recovery gap 与周期 SKP 计数

`K15_SVT_RCVR_GAP_OFF` 的进一步 A/B 证明：仅保留 EIEOS 前 gap、或只在
RcvrCfg/Idle 去 gap，都会分别卡住 EQ Phase1 或 0c。最终结论是 **Recovery
训练期必须保留官方 15/16 双 gap**，该 define 已从 RTL 与默认 SVT 脚本退役。

同时修复 `pcie_gen3_os_tx.sv` 两个真实计数错误：

1. `skp_period_count` 原来只在 SKP 结束时递增，第一帧后永远停在 1，无法再次
   达到触发值；现改为每个完整 cadence 周期递增。
2. SKP 原被当作额外块，导致后续 gap 网格整体漂移 4 拍；现改为替换第 9 个
   block slot（`ts_interval_count=9`），保持 16-block run 总长度。

定向测试已从“看到一帧 SKP”加强为“连续看到两帧，间隔不超过 375 blocks”，
结果 `K15_DYNAMIC_SKP_END_PASS recurring=2`。

### 6.2 0d 根因分解

l0fix33（Recovery 双 gap + 周期 SKP 修复）完整通过 EQ P1/P2/P3 与 RcvrCfg：

```
260.651 us  29 (EQ P1)
261.759 us  2a (EQ P2)
266.063 us  2b (EQ P3)
266.323 us  0c (RcvrCfg)
266.743 us  0d (Recovery.Idle)
```

`K15_SVT_HANDOFF` 显示 `os_lfsr=os_lfsr_after=idle_lfsr=01b102`，排除 TX
LFSR 交接错误。VIP PIPE 的 `data_valid=0` 仍严格每 65 byte clocks 出现，
在约第 4 次结构性补偿后报 `non-IDL token 0x4a`，所以 370/371-block 的首帧
SKP 对该组合模型来得太晚。

密集 SKP A/B 给出三个新事实：

- 直接在 SDS 后的数据流插 SKP 会报 `phy_data_stream_without_eds`；
  [PCI-SIG Gen3 FAQ](https://pcisig.com/section-4273-pcie-30-base-spec-section-4274-states-receivers-shall-be-tolerant-receive-and-process)
  也明确要求先完成当前数据块并发送 EDS。
- 加入 `EDS data block -> SKP OS -> Data block` 后，VIP 正确接受 EDS 边界。
- SKP_END 的 Data Parity 不能沿用训练期的 `~LFSR[22]`。对 SDS/SKP 之间
  所有扰码后 Data Block payload 做 XOR reduction 后，VIP 的
  `bad_skp_8g_parity` 消失。

因此已在生产 RTL 实施：

- `pcie_gen3_idle_tx.sv`：新增 EDS 状态、规范化 EDS→SKP→Data 序列、真实
  Data Parity 累加器，并在 SDS/SKP 边界清零；默认上板 cadence 仍为
  370/371 blocks。
- `pcie_gen3_os_rx.sv`：接收 EDS 尾块，并按 Data Stream 状态校验动态 parity；
  Recovery 训练期 SKP 仍使用既有 golden parity 规则。
- `pcie_ltssm_mac_gen1.sv`：Gen3 `os_idle_pair_valid` 已表示完整 16-Symbol
  Idle Data Block，足以满足 8 个连续 IDL Symbol；不再错误地等待 8 个块。
  l0fix39 中 EP 首次从 0d 进入 L0：`266.939504 us state=0a`。

### 6.3 当前剩余阻塞与下一优化方向

完整 strict gate 尚未通过。启用诊断变量
`K15_SVT_L0_SKP_DENSE=1 ./run_k15_svt_x1.sh` 后，第一帧带正确 EDS/parity
的 SKP 被 VIP 接受；第二帧的 12×AA 到达，但 Xilinx secureip/SVT 组合把
4-byte SKP_END 整体删除，VIP 报：

```
pcs_skp_end_not_detected_0(): SKP_END was not detected before byte 20
```

尝试增加额外 AA 保护组无效，已回退，不留在生产路径。默认 SVT 脚本也不
强制密集 cadence，只保留显式诊断开关。

下一步不应再改 LTSSM/EQ 或 LFSR，而应聚焦 **GT TX 对第二帧 SKP_END 的
结构性删除**：在 EP GT 串行输出与 VIP PMA 输入之间对齐第二帧 SKP 的
`TXSTART_BLOCK/TXSYNC_HEADER/TXDATA_VALID`，确认删除发生在 secureip TX
侧还是 VIP elastic-buffer 侧；随后根据位置修正 GT clock-correction 控制或
SKP 调度相位。真实主机版本保持规范 370/371 cadence、EDS framing 与动态
parity，禁止携带 SVT 的 64-byte 诊断密度。

### 6.4 验证状态

- 默认 `make k15-directed-test`：通过。
- `make k15-directed-dense-test`：通过 EDS、动态 parity、重复 SKP，
  `K15_GEN3_IDLE_STREAM_PASS`。
- 完整 SVT：EQ 三相、RcvrCfg、EP 首次 Gen3 L0 已通过；仍因第二帧
  SKP_END 被模型删除而回 Recovery，未出现 `K15_SVT_X1_PASS epochs=2`。

最终默认配置复核（l0fix41，不带 `K15_SVT_L0_SKP_DENSE`）同样在
`266.939504 us` 进入 Gen3 L0，随后于 `267.026483 us` 复现结构性补偿后的
`non-IDL token 0x4a`。因此“进入 L0”修复不是密集模式的偶然结果；默认路径
和密集诊断路径只是同一 65-byte 模型问题的两种表现（前者首帧规范 SKP 尚未
到期，后者第二帧 SKP_END 被模型删除）。

## 七、官方 XDMA Golden A/B（2026-09-03，本轮）

已建立 `xdma_x1_demo` 官方 Endpoint + 同一 SVT RP 的串行 Golden，并加入
`XDMA_SVT_GEN3_L0_PASS`（首次进入）和 `XDMA_SVT_L0_STABLE_PASS`（随后
8192 个 Gen3 PIPE 周期）两级判定。Golden 与 K15 均输出统一
`PHY_FORENSICS side=...` 字段，可由
`sim/vcs_svt/analyze_phy_forensics.py` 统计 stall、header、status、0x4a 和
start-block 间隔。

受限环境中的 `27000@wx-linux` 报错为 `(-15,570) Operation not permitted`，但
在可访问 license server 的环境中，Golden 已完成 compile/elab/link，证明不是
席位不足或 license feature 缺失。当前真正阻塞点是仿真启动 `5482900 fs` 的
`svt_pcie_pl_proxy.sv:5280` `Null object access`；因此尚未生成 Golden 的
Gen3 `PHY_FORENSICS`，不能把 K15 的 65-byte/`0x4a` 事实外推到 XDMA，也暂不
修改生产 RTL。下一步应先修复 Golden/SVT PL callback 启动时序，再按
`docs/reports/xdma-svt-k15-ab-root-cause-20260903.md` 的判定表做 A/B。
