# XDMA Golden / K15 自研 EP 物理数据流 A/B 根因报告（2026-09-03）

## 结论状态

本轮已完成 Golden testbench、统一取证格式、Gen3 L0 双阶段判定和离线统计脚本。
最初的受限环境在 VCS checkout 处报 `(-15,570) Operation not permitted`，但按
license 参考流程切换到可访问 `27000@wx-linux` 的环境后，
`VCSCompiler_Net`/`VCSRuntime_Net` 均成功 checkout，源码编译、elaboration、link
全部完成。因此 license 已排除，不是当前 Golden 的根因。

当前 Golden 在仿真启动后约 `5.4829 ns` 由 SVT
`svt_pcie_pl_proxy::callback_client_exists` 报 `Null object access`，在 Detect/
Polling 之前终止；`XDMA_SVT_FORENSICS_SUMMARY records=0`，两个 L0 marker 均未
产生。故目前不能宣称 XDMA Golden 已稳定 Gen3 L0，也不能用缺失的 Golden 波形
判定 65-beat compensation 属于哪一层。下一步应先修复/隔离这个 Golden
testbench 与 SVT PL callback 的启动时序问题，再进行 Gen3 A/B 取证。

license 诊断依据 `docs/reports/vcs-license-status.md`：该服务器当前复核为 UP、
`VCSCompiler_Net`/`VCSRuntime_Net` 各 99 席且 0 占用；受限环境中的 `-15,570`
只表示网络策略阻断 FlexNet 端口。因此应先在允许访问 `27000@wx-linux` 的环境
用 `lmutil lmstat` 区分 daemon/席位问题，再运行 Golden。
Golden 脚本现在自动设置 `SNPSLMD_LICENSE_FILE`/`LM_LICENSE_FILE`，对 Compiler
和 Runtime 两个 feature 做 10 秒 preflight，并支持 `XILINX_VCS_SIMLIB`、
`VIVADO_SIMLIB` 及本机 compile_simlib fallback。若 preflight 通过而 VCS 仍在
`Doing common elaboration` 排队，按参考记录判定为执行环境网络隔离，不应继续
增加 `-licqueue` timeout 或修改 RTL。

## 已实施的可复现实验

- `make xdma-x1-svt-vcs`：官方 `xdma_x1_demo` EP、官方 GT/secureip 仿真模型、
  同一 Synopsys SVT x4/8G RP，lane 0 串行直连。
- `XDMA_SVT_GEN3_L0_PASS`：RP status 首次报告 Gen3 (8.0 GT/s) x1 L0。
- `XDMA_SVT_L0_STABLE_PASS`：首次 L0 后继续采样 8192 个 Gen3 PIPE 周期，期间
  link/L0/rate 不得退出，且不得出现 invalid sync header、非零 `rxstatus` 或
  electrical-idle code；同时报告观察到的 start-block 次数。
- `+PHY_FORENSICS`（Golden 默认打开，可用 `XDMA_X1_SVT_FORENSICS=0` 关闭）和
  K15 默认打开的同名开关，输出统一的 `PHY_FORENSICS side=...` 行。统计工具：
  `python3 sim/vcs_svt/analyze_phy_forensics.py <simulate.log> ...`。

### license 与当前运行证据

- 受限环境：`lmutil lmstat -c 27000@wx-linux` 返回 `(-15,570) Operation not
  permitted`。
- 可访问环境：server/master 与 `snpslmd` 均 UP，Compiler/Runtime 均为
  `99 issued / 0 in use`；同一 Golden 完成 VCS compile/elab/link。
- 可访问环境的当前失败点：`simulate.log` 在 `5482900 fs` 报
  `svt_pcie_pl_proxy.sv:5280` 空对象，随后 `records=0`。

这三条证据将 license 问题与 SVT 启动 callback 问题明确分层；不要再通过增加
`-licqueue` timeout、重启 license daemon 或修改生产 RTL 来处理当前失败。

## 取证边界

Golden 的 TX 不是从串行 bit 流猜测，而是取官方 PCIe core 的
`pipe_tx_0_sigs`：

| 字段 | 官方 packed bit |
|---|---:|
| TXDATA | `[31:0]` |
| TXDATA_VALID | `[35]` |
| TXSTART_BLOCK | `[36]` |
| TXSYNC_HEADER | `[38:37]` |
| electrical_idle | `[34]` |

层次为 `test_top.EP.xdma_x1_i.inst.pcie3_ip_i.inst.pipe_tx_0_sigs`；LTSSM/rate
取 `pcie3_ip_i.cfg_ltssm_state/cfg_current_speed`。K15 直接取
`DUT.phy_*`，SVT RX 两端均取 `root0.port0.pcs0_rx_*`，所以 A/B 的字段含义和
采样位置一致，且没有修改生产 RTL。

## 已有 K15 基线（Golden 尚未可用时不得外推）

现有记录显示 K15 在首次 Gen3 L0 后约第 4 次结构性补偿处出现
`non-IDL token 0x4a`；此前观察到 `data_valid=0` 的严格约 65-byte 周期，后续
第二帧 SKP_END 在 Xilinx secureip/SVT 组合中被整体删除并报
`SKP_END was not detected before byte 20`。这些是 K15 侧事实，不是 Golden 的
结论；A/B 对齐必须等 Golden `simulate.log` 产生后再填写确切 cycle/timestamp。

## Golden 解锁后的判定表

运行两端并分别执行统计脚本后，报告应填写：

1. Golden 是否有 `XDMA_SVT_L0_STABLE_PASS`；
2. `rxdata_valid` stall run 的长度/间隔（65-beat 是 insertion、deletion 还是
   valid stall）；
3. compensation 是否落在普通 Data Block、SDS→Data、EDS→SKP 或 SKP→Data 边界；
4. SKP/SKP_END 是否仍在 RX，128b/130b sync header 是否保持有效；
5. 首个 `sh=11`、`rxstatus!=0`、`data=0x4a`、SKP_END missing 的 cycle 和时间；
6. 与 K15 的首次不一致是在 MAC 输出、standalone PHY 输入、GT/secureip，还是
   SVT RX。

若 Golden 也在同一 cycle/同一字段呈现 65-beat compensation、SKP_END 丢失或
`sh=11`，则根因应归类为 **Xilinx secureip/GT model + Synopsys O-2018.09
SVT 的组合仿真 artifact**，不再修改生产 RTL。若 Golden 长期稳定而 K15 独有
差异，最小修改范围才是 K15 的 MAC→standalone-PHY PIPE 语义（valid gap、
TXSTART_BLOCK/首 word 同拍、sync header block-start 限定及 EDS→SKP 边界）。

## 本轮明确不做的修改

没有改 EQ P1/P2/P3、Recovery LTSSM、LFSR seed/handoff，也没有把 dense SKP、
65-beat phase workaround 或任何非规范 Data Stream 行为带入生产配置。
