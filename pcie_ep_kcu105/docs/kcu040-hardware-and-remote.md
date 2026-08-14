# KU040/KCU105 烧写与远程主机操作

## 1. 硬件和连接

- FPGA：`xcku040-ffva1156-2-e`，KCU105 开发板。
- PCIe：Gen3 x1；`J74` 设置为 x1。
- PCIe REFCLK：100 MHz，`AB6/AB5`。
- PERST#：`K22`。
- PCIe Lane 0：GT Quad 225，`GTHE3_CHANNEL_X0Y7`。
- 本地 JTAG 通过 Vivado `hw_server` 的 `localhost:3122` 访问。

更完整的管脚、时钟和复位说明见
`docs/architecture/00-system-architecture.md`。

## 2. 启动 hw_server

在连接 KCU105 的机器上执行：

```bash
/home/Xilinx/Vivado/2021.2/bin/hw_server -d -p0 -I60 -stcp::3122
```

然后使用公共 Tcl：

```bash
# 探测唯一的 xcku040
make ku040-hw-probe

# 下载 bit 到 FPGA SRAM；KU040_BIT 可替换为任意 bit 文件
make ku040-hw-program \
  KU040_BIT=fpga/kcu105/build_k11b2/impl/k11b2_gen1_endpoint.bit

# 直接调用 Vivado/Tcl
/home/Xilinx/Vivado/2021.2/bin/vivado -mode batch \
  -source scripts/program_ku040.tcl \
  -tclargs localhost:3122 path/to/image.bit program
```

公共实现位于 `scripts/program_ku040.tcl`。它会检查 JTAG target，要求发现且只发现
一个 `xcku040*` 器件，然后执行 `program_hw_devices`。这里是 FPGA SRAM 下载，
不是断电保持的 QSPI/Flash 固化。

原有的 `make k02-hw-program`、`make k11b2-hw-program` 和
`make xdma-x1-hw-program` 仍然保留，并复用同一公共下载逻辑。

## 3. 远程 Linux Root Port

当前硬件记录中的默认主机是：

```text
用户：wx
主机：192.168.11.126
主机名：wx-ubuntu
PCIe Endpoint BDF：01:00.0
```

工程不保存 SSH 密码。脚本使用 `BatchMode=yes`，适合已配置 SSH key 的环境。
默认值可以覆盖：

```bash
export PCIE_REMOTE_HOST=192.168.11.126
export PCIE_REMOTE_USER=wx
export PCIE_REMOTE_BDF=01:00.0
```

公共脚本为 `scripts/remote_pcie_host.sh`，支持：

```bash
# 检查 SSH、主机名和 PCIe 状态
make remote-check

# 只发起远端 reboot；要求 sudo 无密码执行
make remote-reboot

# 等待 SSH 恢复
make remote-wait

# 读取 Endpoint 的 lspci -vvv
make remote-lspci

# reboot -> 等待 SSH 恢复 -> 读取 lspci
make remote-cycle
```

也可以覆盖目标和等待时间：

```bash
PCIE_REMOTE_HOST=192.168.11.126 \
PCIE_REMOTE_USER=wx \
PCIE_REMOTE_BDF=01:00.0 \
PCIE_SSH_REBOOT_TIMEOUT=240 \
make remote-cycle
```

脚本首先尝试 `sudo -n reboot`。如果远端 sudo 需要密码，它会明确失败并打印人工
执行命令，不会把密码写入脚本、环境输出或日志。此时可人工执行：

```bash
ssh wx@192.168.11.126 'sudo reboot'
make remote-wait
make remote-lspci
```

`192.168.11.126` 是远程 Linux Root Port 主机，不是 JTAG `hw_server` 地址；两者
可以位于不同机器上。

## 4. K13 Recovery.Speed CDR-hold 验证归档（2026-08-14）

### 4.1 修改内容

依据 PG239 PHY assist contract，生产 LTSSM 在 `Recovery.Speed` 拉高
`as_cdr_hold_req`，离开该状态后拉低：

```verilog
assign as_cdr_hold_req = (ltssm_state == RECOVERY_SPEED);
```

当前 MAC 尚未实现 L1/Loopback 状态，因此本轮只覆盖 `Recovery.Speed`。
该信号同时加入 K13 诊断总线；集成仿真在进入 `Recovery.Speed` 时断言为 1，
回到 `Recovery.Idle` 后断言为 0。

涉及文件：

- `rtl/phy/pcie_ltssm_mac_gen1.sv`
- `rtl/ep/kcu105_pcie_ep_gen1_top.sv`
- `sim/verilator/k13_integration/k13_ltssm_partner_top.sv`
- `sim/verilator/k13_integration/test_k13_integration.py`
- `fpga/kcu105/run_k11b2_impl.{sh,tcl}`
- `fpga/kcu105/run_k11b2_ila_hw.tcl`

### 4.2 验证结果

- K13 集成 lint 通过。
- K13 集成仿真两条测试均通过：`2/2 PASS`。
- 诊断实现通过：`K13_ILA_IMPL_PASS`。
- 器件：`xcku040-ffva1156-2-e`。
- GT：`GTHE3_CHANNEL_X0Y7` / `GTHE3_COMMON_X0Y1`。
- 诊断 WNS：`-0.053 ns`；该 bit/LTX 只能作为诊断证据，不能作为正式实现版本。

诊断 bit/LTX SHA256：

```text
bit  e31eccff25b8c5a4366841273d25dbacec33978c18cf8983d91d532690b96b0e
ltx  cdb4eee983c5854a8cf5fd27dcdc2aa5d9212cba195bceaf3fac0c7cdf2b60d4
```

实板采样文件：

`fpga/kcu105/build_k13_gen3_ila_cdr_hold_gt_primitive/capture/20260814_114555_u_ila_pipe.csv`

关键采样点：

| Sample | 事件 |
|---:|---|
| 680 | `as_cdr_hold_req: 0 -> 1`，LTSSM 进入 `Recovery.Speed` |
| 692 | `phy_rate: 0 -> 2`，`rxrate: 0 -> 2` |
| 702 | `QPLL1LOCK: 1 -> 0`，实际 `QPLL1RESET: 0 -> 1` |
| 707 | 实际 `QPLL1RESET: 1 -> 0` |
| 4095 | `QPLL1LOCK` 仍为 0，`as_cdr_hold_req` 仍为 1 |

`QPLL1PD` 全程为 0，`PCIERATEQPLLRESET` 仍按预期产生脉冲；但 QPLL1LOCK
没有在采样窗口内恢复。因此，CDR hold 已正确接入并生效，但没有阻止 QPLL1
在 Gen3 rate change 时失锁。

### 4.3 结论与门禁状态

本 A/B 关闭“`as_cdr_hold_req=0` 是 QPLL1 失锁根因”的假设，但该信号修正仍应
保留，作为 PG239 合约要求。当前不能输出任何 Gen3 PASS 标记；Gen1 x1 基线和
Gen3 QPLL1/rate-change 路径必须分开判断。

本轮后续优先级回到：

1. `PCIEUSERRATESTART`、`PCIEUSERRATEDONE`、`PCIEUSERGEN3RDY` 的真实
   rate-handshake 时序；
2. 生成 PHY 内部 rate FSM/pipeline 与 `GTHE3_CHANNEL` rate 端口的对应关系；
3. `QPLL1RESET` 脉冲后 QPLL1 参考时钟、复位释放和 lock-detector 的恢复条件。

此前 Gen1 x1 枚举成功只证明 Gen1/CPLL 基线可用，不能证明 Gen3/QPLL1 路径
正常。

## 5. Git 归档

本轮源码、脚本和仿真断言已提交并推送：

```text
commit 5cbac7f K13: hold RX CDR during Recovery.Speed
remote: origin/main
```

本节文档补充需在后续提交中单独归档；仿真生成的 `error.dat`、`rx.dat`、`tx.dat`、
`ucli.key`、`xelab.pb` 和 `xvlog.pb` 不属于源码归档。
