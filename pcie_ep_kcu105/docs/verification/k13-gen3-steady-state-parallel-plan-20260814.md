# Gen3 steady-state 与协议并行开发计划

日期：2026-08-14

状态：**direct Gen3 bit/LTX 和上板 ILA 验证 PASS；VCS 已完成真实 PHY 编译/链接，运行阶段时钟断言失败**

## 1. 决策和边界

当前阶段不把 Gen1/CPLL → Gen3/QPLL1 dynamic transition 作为 Gen3 协议开发的前置条件。
新增 `DIRECT_GEN3_MODE` 作为独立诊断入口：复位释放后直接请求 `P0 + phy_rate=2'b10`
并保持 TX Electrical Idle，不执行 Receiver Detect，也不执行 Gen1→Gen3 rate transition。

这只证明 Gen3 PHY steady-state，不等同于完整 PCIe Gen3 链路；LTSSM、TS1/TS2、128b/130b、
Equalization、DLL、TLP 和枚举仍需分别验证。

原有模式保持不变：

| 模式 | 入口 | 用途 |
|---|---|---|
| 原 K02 steady | `make k02-vcs` / `make k02-vivado` | Receiver Detect 后进入 Gen3 |
| direct Gen3 | `make k02-gen3-vcs` / `make k02-gen3-vivado` | 跳过 Detect 和动态切速，验证 Gen3 steady-state |
| dynamic 诊断 | `K02_DYNAMIC_GEN1_TO_GEN3=1` | 单独定位 QPLL dynamic transition，不阻塞协议开发 |

## 2. 已执行记录

### 2.1 VCS

- 新增真实 Xilinx PHY/GT Wizard testbench：`sim/vcs/k02_gen3_steady_tb.sv`；
- 测试期间 `phy_rate` 固定为 `2'b10`，仅执行 P1→P0 上电；
- 本轮复用本地 `27000@wx-linux` license 方法，`VCSCompiler_Net` preflight 通过；
- `vlogan`、真实 PHY/GT Wizard elaboration 和 link 均完成；
- 运行阶段在时钟检查处停止：`phy_pclk_gen3=8000 ps`，TB 当前期望 `4000 ps`；
- 因此当前结论是 `VCS FAIL_CLOCK_ASSERTION`，不能标记
  `K02_VCS_GEN3_STEADY_PASS`；这不是 license 阻塞。

实际运行输出：

```text
M00_VCS_ENV_PASS simlib=/home/wx/Documents/vcs_compile_simlib
Fatal: k02_gen3_steady_tb: phy_pclk_gen3 period=8000 expected=4000
```

下一步需先确认 direct steady-state 下 behavioral model 的 `BUFG_GT DIV`/PHY clock
配置是否应当输出 125 MHz，或 TB 是否需要等待一次 PHY rate/clock reconfiguration；
不能仅修改期望值来掩盖该差异。

重试命令：

```bash
cd /home/wx/Documents/PCIe/pcie_ep_kcu105
K02_VCS_GEN3_STEADY=1 VCS_LICENSE_TIMEOUT=300 ./sim/vcs/run_k02.sh
```

许可证恢复后，必须看到：

```text
K02_VCS_GEN3_CLOCK clock=phy_pclk_gen3 period_ps=4000
K02_VCS_GEN3_CLOCK clock=phy_coreclk_gen3 period_ps=4000
K02_VCS_GEN3_CLOCK clock=phy_userclk_gen3 period_ps=8000
K02_VCS_GEN3_STEADY_PASS rate=Gen3 powerdown=P0 receiver_detect=skipped
```

### 2.2 Vivado bit/LTX

执行：

```bash
cd /home/wx/Documents/PCIe/pcie_ep_kcu105
K02_DIRECT_GEN3=1 ./fpga/kcu105/run_k02_impl.sh
```

结果：

- ILA 插入：PASS，probe0=`49`、probe1=`10`、depth=`8192`；
- GT Channel：`GTHE3_CHANNEL_X0Y7`；GT Common：`GTHE3_COMMON_X0Y1`；
- PCIe Hard Block：`0`；
- DRC/CDC：PASS；
- Route WNS：`+0.702 ns`；
- bitgen：PASS；
- bit：`fpga/kcu105/build_k02_gen3/k02_pcie_phy_bringup_gen3_ila.bit`；
- LTX：`fpga/kcu105/build_k02_gen3/k02_pcie_phy_bringup_gen3_ila.ltx`；
- bit SHA-256：`523dda55b3ff3481c405673c9e0e5feb9c347e468f6e4cc1c2654faae2c5c112`；
- LTX SHA-256：`cb354b1e48d8ffc2de4b33ed8b00142e81925718944cbef0adf04520f1ab4495`。

### 2.3 上板门禁

- [x] `make k02-gen3-hw-probe` 确认 JTAG target：`xcku040_0`，Digilent target 可见；
- [x] 下载 direct Gen3 bit 并配置 ILA；
- [x] 用 Hardware Manager 载入同名 LTX；
- [x] 采集 `QPLL1LOCK`、`QPLL1RESET`、`QPLL1PD`、`phy_rate`、`PCIERATEGEN3`、
  `PCIEUSERGEN3RDY`、`RXRESETDONE`、`PhyStatus`；
- [x] steady-state 结果：`phy_rate=2`、`QPLL1LOCK=1`、`QPLL1RESET=0`、
  `QPLL1PD=0`、`PCIERATEGEN3=1`、`PCIEUSERGEN3RDY=1`、`RXRESETDONE=1`；
- [x] 保存 CSV/ILA 和 bit/LTX SHA-256；
- [x] 明确记录 `RXVALID=0` 不代表失败，因为当前 direct demo 仍未发送 TS/Ordered Set。

实板采样文件：

```text
fpga/kcu105/build_k02_gen3/capture/20260814_230545_k02_phy.csv
fpga/kcu105/build_k02_gen3/capture/20260814_230545_k02_phy.ila
```

关键稳态值（8192 点窗口内保持不变）：

| 信号 | 实测值 |
|---|---:|
| direct QPLL1LOCK probe | `1` |
| `qpll1lock_out` | `1` |
| `QPLL1RESET` | `0` |
| `QPLL1PD` | `0` |
| `phy_rate` | `2` |
| `phy_powerdown` | `0`（P0） |
| `PCIERATEGEN3` | `1` |
| `PCIERATEQPLLRESET` | `0` |
| `PCIERATEQPLLPD` | `0` |
| `PCIEUSERGEN3RDY` | `1` |
| `RXRESETDONE` | `1` |
| `RXVALID` | `0` |
| `PhyStatus` | `0`（无 rate transition，符合 direct 模式） |

## 2.4 并行协议基线回归

在 direct Gen3 硬件验证之后，已运行现有 K13 Verilator 基线：

- `make k13-ctrl-sim`：4/4 PASS，覆盖 Gen3 speed/EQ path、CDR loss fallback、坏 TS 拒绝、
  RXEQ done-only fallback；
- `make k13-integration-sim`：2/2 PASS，覆盖 Gen1→Gen3 EQ closed-loop 和 partner-initiated
  speed change；
- 该回归证明现有控制器、TS/Ordered Set partner loopback 和 Gen3 scrambler 路径可继续
  并行推进，但它不是 VCS real PHY，也不是 direct bit 的完整 Gen3 枚举/协议 PASS。

## 3. 并行协议开发主线

### Lane A：Gen3 steady-state PHY

1. VCS real-IP steady-state PASS；
2. Vivado direct Gen3 bit/LTX PASS；
3. 上板确认 QPLL1 lock 和 Gen3 ready；
4. 把 direct 模式作为后续协议层实验的固定 PHY 起点。

### Lane B：128b/130b

1. 固定 Gen3 PIPE 输入为 32-bit data + `phy_txstart_block` + 2-bit sync header；
2. 完成 block sync/header 编解码和 bit-order 断言；
3. 加入 scrambler/descrambler 联合回环；
4. 用固定向量、随机向量和错误 header 向量验证；
5. 接入 Gen3 Ordered Set 发送/接收边界，不等待 QPLL dynamic transition。

### Lane C：TS1/TS2

1. 固定 Gen3 训练字段、Link/Lane Number、速度字段和 PAD/无效字段；
2. 完成 TS1/TS2 发送器、接收器和字段 checker；
3. 先在 Verilator partner loopback 中闭环；
4. 再在 VCS real PHY 中确认 PIPE 侧出现正确 block/header；
5. 将 TS 接收结果接到 LTSSM，不把 TX Electrical Idle 误判为训练完成。

### Lane D：EQ

1. 先完成 EQ Phase 0/1/2/3 的控制器状态和超时；
2. 独立验证 `TXEQ_CTRL/PRESET/DONE`、`RXEQ_CTRL/DONE`；
3. 在 direct Gen3 PHY 上验证 EQ command 不触发错误的速率切换；
4. 再接入 TS/EQ closed-loop；
5. 最后才把 dynamic transition 作为可选 Recovery.Speed 场景重新接回。

## 4. 通过标准

只有同时满足下列条件，才把“Gen3 链路开发阶段”标为 PASS：

- direct Gen3 PHY 的 VCS、bitgen、上板 ILA 均 PASS；
- 128b/130b checker 无错误；
- TS1/TS2 partner loopback 闭环 PASS；
- EQ Phase 0–3 正常完成；
- Gen3 `PhyStatus`、`PCIEUSERGEN3RDY`、`RXRESETDONE` 和协议训练状态一致；
- 至少完成一次不依赖 dynamic transition 的 Gen3 training/l0 验证。

dynamic QPLL transition 单独保留为诊断门禁；它失败时，只阻塞 Recovery.Speed 专项，不阻塞上述
direct Gen3 协议开发阶段。
