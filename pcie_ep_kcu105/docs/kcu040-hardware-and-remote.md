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
