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

关键对比信号显示 RP 在切到 Gen3 后曾有 `rp_qplllock=1`，随后变为 `0`；同时
RP 仍为 `rp_state=c`、`rp_gt_txidle=1`、`rp_gt_txdata=00000000`，EP 未收到
有效 Gen3 RX block。因此本轮不能把问题归因于“license”或简单的 4.1/4.4
RP 源码版本差异；下一步应在同一可访问 license 环境中继续检查 RP Gen3 TX
reset/QPLL 复位时序以及 EP 侧收到的 PIPE/串行数据。

## 判定标准

许可证恢复后，对比以下两组日志：

1. 4.4 RP + 自研 EP：`run_k13_rp44_ab.sh`
2. 4.1 RP + 自研 EP：`run_k11b_serial.sh`

重点比较 `K13_RATE_EVENT`、`K13_RP_TX_CONTRACT`、`K13_RP_RX_EVENT` 和最终
`K13_VCS_GEN3_RETRAIN_*`。若只有 4.4 RP 通过，问题优先归类为 RP 版本/PIPE
兼容性；若两组均在同一 RP RX block-lock 窗口失败，则继续定位自研 EP 的串行
Gen3 TX/PIPE 映射。
