# K13 RP 4.4 A/B 仿真入口

日期：2026-08-21

## 目的

在不改变当前 XDMA 4.1 基线的前提下，用今天新建立并已通过的官方
`pcie3_ultrascale_0_ex` 4.4 RP 源码，连接自研 K13 EP，隔离 RP 版本差异。

## 入口

```bash
VCS_LICENSE_PREFLIGHT=0 \
K13_RP44_DEMO=/home/wx/Documents/PCIe/pcie3_ultrascale_0_ex \
./sim/vcs/run_k13_rp44_ab.sh
```

脚本会把官方 4.4 的三个 RP 文件放入临时目录：

- `pcie3_uscale_rp_core_top.v`
- `pcie3_uscale_rp_top.v`
- `xilinx_pcie_uscale_rp.v`

用户应用和 include 文件仍取自当前 XDMA 仿真环境，避免把 RP 版本差异和测试激励
差异混在一起。默认 `run_k11b_serial.sh` 仍使用 XDMA 4.1，不受本脚本影响。

## 当前验证结果

本轮已完成 VCS 编译和 common elaboration 前的源码/接口检查，日志确认：

```text
K13_RP44_AB_VERSION=4.4
```

4.4 源码能够进入 VCS elaboration；同时出现预期的版本接口告警（AXI ready 位宽、
DRP 端口宽度、startup 端口宽度），没有出现混用 4.1/4.4 文件时的 `cfg_ext_*`
未定义错误。

许可证问题已排除。按 `docs/reports/vcs-license-status.md` 在可访问 license
server 的环境中运行 `lmutil lmstat -c 27000@wx-linux`，结果为 server/daemon
均 UP，`VCSCompiler_Net` 为 99 issued、0 in use。此前的 `(-15,570
"Operation not permitted")` 是当前受限执行环境的网络限制，不是 license seat
耗尽。

完整仿真已完成编译、elaboration、link，并通过初始 Gen1、DLL active、枚举和
BAR 读写检查；但官方 4.4 RP + 自研 EP 的 Gen3 retrain 仍失败：

```text
K13_VCS_GEN3_RETRAIN_FAIL wait=20000 ep_state=12 speed_state=0 rate=2 negotiated=2
  eq_active=0 eq_phase=4 eq_done=1 fallback=0 speed_timeout=0 ts_accept=0
  ts_reject=0 rp_state=c rp_speed=1 rp_link=1 seen_rp_recovery=1
  seen_states=1110 seen_rate=1 seen_phystatus=1 seen_eq=11111
```

早期日志曾显示 RP 在切到 Gen3 后 `rp_qplllock` 有过 `1 -> 0`，但后续完整
链路仍能观察到 RP 的 Gen3 RX 数据和 EQ 活动；因此目前没有证据把失败归因于
QPLL 本身。许可证和简单的 4.1/4.4 RP 源码差异也已排除，下一步转向 EP 侧
Gen3 ordered-set 解码。

## SDS 解码证据（2026-08-21）

在同一有效 license 环境下对完整 VCS 链路做诊断采样，RP 发出的 SDS 开头为
`AAAA AAAA AAAA BCBF9DE1`，随后 SDS 的第四个原始 PIPE word 会出现
`E64670E1`、`6A66A9E1`、`432F68E1`、`D26A6DE1` 等变化值。当前
`rtl/phy/pcie_gen3_os_rx.sv` 仍把 SDS 末字按原始整字固定比较为
`32'hBCBF_9DE1`；在 `197768000 ps` 诊断点因此产生：

```text
K13_OSRX_BAD_SDS word=3 parse_error=0 data=e64670e1 lfsr_ready=1
```

随后 `lfsr_ready` 被清零，TS1/TS2 被连续拒绝，最终表现为 Gen3 EQ 未完成。
若干候选的 SDS/LFSR 修改已做过完整仿真但均未通过，均已撤回；本提交不包含
未经验证的生产 RTL 修复。下一步是先建立聚焦的 SDS/LFSR 单元测试，确认每个
byte 的 descramble、跳过和 LFSR 状态推进规则，再回到完整 VCS 回归。

## 判定标准

许可证恢复后，对比以下两组日志：

1. 4.4 RP + 自研 EP：`run_k13_rp44_ab.sh`
2. 4.1 RP + 自研 EP：`run_k11b_serial.sh`

重点比较 `K13_RATE_EVENT`、`K13_RP_TX_CONTRACT`、`K13_RP_RX_EVENT` 和最终
`K13_VCS_GEN3_RETRAIN_*`。若只有 4.4 RP 通过，问题优先归类为 RP 版本/PIPE
兼容性；若两组均在同一 RP RX block-lock 窗口失败，则继续定位自研 EP 的串行
Gen3 TX/PIPE 映射。
