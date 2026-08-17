# pcie_phy_0_ex：KCU105 Gen1→Gen3 上板诊断

本目录是从 `pcie_ep_kcu105` 的 KCU105 约束和远程调试流程整理出的
`pcie_phy_0_ex` 板级诊断工程。当前 bitstream 的流程是：

1. 释放复位并执行一次 Receiver Detect；
2. PHY 进入 Gen1，执行 TXEQ preset；
3. 关闭 Gen1 rate-change 请求，等待 PHY 状态返回；
4. 请求 Gen3，等待 `phy_phystatus`，并通过 ILA 观察 QPLL1 lock。

它是 standalone PHY/GT 诊断，不包含 LTSSM、TS1/TS2、DLLP/TLP 或完整 PCIe
链路训练。因此 ILA 能确认 PHY 的 Gen1→Gen3 速率切换和 QPLL 行为，但不能
单独证明操作系统已经枚举出 PCIe endpoint；后者需要配合完整 endpoint 工程。

## KCU105 引脚

约束文件 `pcie_phy_0_kcu105.xdc` 已补齐参考时钟、PERST#、x1 收发器和 8 个
板载 LED：

| 信号 | KCU105 引脚 |
|---|---|
| PCIe refclk P/N | AB6 / AB5 |
| PCIe PERST# | K22 |
| PCIe RX P/N | AB2 / AB1 |
| PCIe TX P/N | AC4 / AC3 |
| LED[0..7] | AP8, H23, P20, P21, N22, M22, R23, P23 |

GT 位置应为 `GTHE3_COMMON_X0Y1`、`GTHE3_CHANNEL_X0Y7`，对应参考工程中
使用的 QPLL1 和 KCU105 PCIe lane 0。

LED 含义：LED0=复位/PHY 状态，LED1=receiver present，LED2=detect done，
LED3=PIPE reset release，LED4=core reset release，LED5=detect timeout，
LED6=unexpected status，LED7=heartbeat。

## 已生成文件

当前实现已经通过 Vivado 2021.2 的综合、布局布线和 DRC，bitstream 位于：

```text
build_k02_dynamic/pcie_phy_0_ex_gen1_to_gen3_ila.bit
build_k02_dynamic/pcie_phy_0_ex_gen1_to_gen3_ila.ltx
```

实现摘要和报告：

```text
build_k02_dynamic/impl_summary.txt
build_k02_dynamic/timing_summary.rpt
build_k02_dynamic/drc.rpt
build_k02_dynamic/check_timing.rpt
build_k02_dynamic/cdc.rpt
```

重新生成 bitstream：

```bash
cd /home/wx/Documents/PCIe
XILINX_LOCAL_USER_DATA=no /home/Xilinx/Vivado/2021.2/bin/vivado \
  -mode batch \
  -source pcie_phy_0_ex/board_kcu105/build_dynamic_ila.tcl \
  -nojournal \
  -log pcie_phy_0_ex/board_kcu105/build_k02_dynamic/build.log
```

## 远程 ILA 调试

物理连接 JTAG 的机器按 `pcie_ep_kcu105/docs/kcu040-hardware-and-remote.md` 启动
`hw_server`，默认端口为 3122：

```bash
/home/Xilinx/Vivado/2021.2/bin/hw_server -d -p0 -I60 -stcp::3122
```

启动后建议先在 `pcie_ep_kcu105` 目录执行 `make ku040-hw-probe`；必须看到唯一
的 `xcku040` target 后再执行下面的 ILA 下载命令。JTAG 序列号应对应已连接的
KCU105，而不是只有 USB-UART/FTDI 设备。

在启动 `hw_server` 的本机 Vivado 环境执行：

```bash
cd /home/wx/Documents/PCIe/pcie_phy_0_ex/board_kcu105

# 下载 bitstream、加载 .ltx，并在 TXEQ 活动处布置 ILA 触发器
/home/Xilinx/Vivado/2021.2/bin/vivado -mode batch \
  -source run_ila_hw.tcl \
  -tclargs localhost:3122 program-arm

# 可选：以 dynamic_rate_fail 为触发器，覆盖完整 Gen3 timeout
/home/Xilinx/Vivado/2021.2/bin/vivado -mode batch \
  -source run_ila_hw.tcl \
  -tclargs localhost:3122 program-arm-fail

# 等待触发并保存 CSV/ILA
/home/Xilinx/Vivado/2021.2/bin/vivado -mode batch \
  -source run_ila_hw.tcl \
  -tclargs localhost:3122 capture-wait
```

如果 hw_server 位于另一台 JTAG 主机，将 `localhost:3122` 换成对应的
`<jtag-host>:3122`。也可以使用
`status` 检查设备和 ILA，使用 `upload` 在已采集后再次导出数据。

2026-08-17 的实际上板采样记录见
`hardware_capture_20260817.md`。

ILA `probe0` 的前五位依次是 `QPLL1LOCK`、`QPLL1RESET`、`QPLL1PD`、
`QPLL1REFCLKLOST`、`QPLL1FBCLKLOST`，并同时包含 GT power-good、rate-change
握手、PIPE `phy_rate`、`phy_phystatus` 和 TXEQ 信号。`probe1` 包含动态状态、
TXEQ 活动、pass/fail、Gen3 active、detect 结果和 PHY status reset。

判定 Gen1→Gen3 是否正常时重点检查：

- `phy_rate` 从 `2'b00` 变为 `2'b10`；
- QPLL1 在切换前后保持 `LOCK=1`，且 `REFCLKLOST/FBCLKLOST=0`；
- `QPLL1RESET/QPLL1PD` 没有异常长时间保持有效；
- `PCIERATEIDLE`、`PCIEUSERRATESTART` 和 `phy_phystatus` 在切换期间出现合理握手；
- `dynamic_rate_fail=0`、`dynamic_rate_pass=1`，并且 `detect_timeout=0`。

## 配合远程 Linux root port

完整 endpoint 的远程枚举/复位流程仍按上级目录
`../../pcie_ep_kcu105/README.md` 执行，例如：

```bash
cd /home/wx/Documents/PCIe/pcie_ep_kcu105
make remote-check
make remote-cycle
```

本 standalone PHY 镜像没有 PCIe 配置空间，因此 `remote-check` 只有在下载
完整 endpoint 镜像后才会出现 `01:00.0` 等枚举结果；本镜像的主要结果应以
ILA capture 和 LED 状态为准。
