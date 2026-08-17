# KCU105 PCIe PHY Gen1→Gen3 VCS仿真结果

- 仿真日期：2026-08-14
- 工程目录：`/home/wx/Documents/KCU105/pcie_phy_0_ex`
- 仿真器：Synopsys VCS-MX O-2018.09-SP2_Full64
- 仿真模型：AMD/Xilinx PCIe PHY + GT Wizard + SecureIP
- license：`SNPSLMD_LICENSE_FILE=27000@wx-linux`

## 结论

真实 VCS + GT/SecureIP 仿真通过，demo完成了 Gen1 启动、关闭并切换到 Gen3，最终输出：

```text
[            43443529] : Gen1 ON
[            93443529] : Gen1 Off
[           103443529] : Gen3 ON
[           204951505] : PHY Traffic Has Tested @ 8.0 Gbps or Gen-3 Speed...
[           205951505] : Test Completed Successfully
```

结论标志：`PASS`

仿真结束时间：`205951505 ps`，约 `205.95 us`。

## 验证内容

1. 系统复位拉低并释放。
2. Gen1 PHY启动并产生流量。
3. Gen1关闭。
4. Gen3速率请求生效。
5. Gen3 PHY流量运行，达到8.0 Gbps速率。
6. Testbench正常 `$finish`，未发生license timeout或仿真超时。

## 仿真方法（源文件加载与执行步骤）

### 1. 仿真层次关系

VCS的顶层不是直接把一个PHY文件“跑起来”，而是从 `board` 顶层向下展开整个层次：

```text
board
├─ xilinx_pcie_phy_top PCIE_PHY       (RP侧)
│  └─ pcie_phy_0
│     └─ pcie_phy_0_core_top
│        └─ pcie_phy_0_gtwizard_top
│           ├─ GTHE3_CHANNEL / SIP_GTHE3_CHANNEL
│           └─ GTHE3_COMMON / SIP_GTHE3_COMMON
└─ xilinx_pcie_phy_model PHY_MODEL    (EP侧)
   ├─ phy_ctrl
   └─ pcie_phy_0
      └─ pcie_phy_0_core_top
         └─ pcie_phy_0_gtwizard_top
```

因此，RP和EP各有一个 `pcie_phy_0`，两端通过 `board.v` 中的 PCIe TX/RX 差分信号连接，构成速率切换测试链路。

### 2. 输入文件分组

`vlogan` 编译的输入分为四组：

1. **Testbench和辅助逻辑**：`imports/board.v`、`xilinx_pcie_phy_top.v`、`xilinx_pcie_phy_model.v`、`phy_ctrl*.v`、`sys_clk_gen*.v`。
2. **Vivado生成的PHY仿真包装**：`pcie_phy_0_ex.gen/sources_1/ip/pcie_phy_0/sim/pcie_phy_0.v`。
3. **Vivado生成的GT Wizard/PHY内部源文件**：同一IP目录下 `source/*.v`。
4. **仿真库和全局模块**：Vivado `glbl.v`、Unisim库、SecureIP库。

其中 `board.v` 是顶层；`xilinx_pcie_phy_top.v` 和 `xilinx_pcie_phy_model.v` 负责连接两侧；生成的 `pcie_phy_0.v` 再向下连接GT Wizard；GTHE3的行为模型由SecureIP提供。

### 3. license和仿真库准备

先设置并检查VCS license：

```bash
export SNPSLMD_LICENSE_FILE=27000@wx-linux
export LM_LICENSE_FILE=27000@wx-linux:/home/questasim/mentor.dat
/home/questasim/linux_x86_64/lmutil lmstat -f VCSCompiler_Net -c 27000@wx-linux
/home/questasim/linux_x86_64/lmutil lmstat -f VCSRuntime_Net -c 27000@wx-linux
```

然后用Vivado `compile_simlib` 生成并在 `synopsys_sim.setup` 中映射：

- `secureip`：GTHE3 SecureIP行为模型；
- `unisims_ver`：`IBUF`、`OBUF`、`IBUFDS_GTE3`、`BUFG_GT`等基础原语；
- `unifast_ver`、`unimacro_ver`：VCS库解析所需的其他Xilinx仿真库。

### 4. 第一次 `vlogan`：把源文件加载到work library

这一步是真正“加载工程生成的 `pcie_phy_0` 仿真源文件和GT Wizard源文件”的地方。`vlogan`读取Verilog源文件，解析module/interface，并把编译结果写入VCS work library；此时还没有生成 `simv`。

先加载SecureIP加密模型：

```bash
vlogan -full64 +v2k -sverilog -work xil_defaultlib \
  /home/Xilinx/Vivado/2021.2/data/secureip/gthe3_channel/gthe3_channel_001.vp \
  /home/Xilinx/Vivado/2021.2/data/secureip/gthe3_common/gthe3_common_001.vp
```

再加载demo、IP包装、GT Wizard源文件和 `glbl.v`：

```bash
vlogan -full64 +v2k -sverilog -work xil_defaultlib \
  +incdir+/home/wx/Documents/KCU105/pcie_phy_0_ex/imports \
  /home/wx/Documents/KCU105/pcie_phy_0_ex/imports/board.v \
  /home/wx/Documents/KCU105/pcie_phy_0_ex/imports/xilinx_pcie_phy_top.v \
  /home/wx/Documents/KCU105/pcie_phy_0_ex/imports/xilinx_pcie_phy_model.v \
  /home/wx/Documents/KCU105/pcie_phy_0_ex/imports/phy_ctrl.v \
  /home/wx/Documents/KCU105/pcie_phy_0_ex/imports/phy_ctrl_pat_gen.v \
  /home/wx/Documents/KCU105/pcie_phy_0_ex/imports/phy_ctrl_pat_gen_lane.v \
  /home/wx/Documents/KCU105/pcie_phy_0_ex/imports/sys_clk_gen.v \
  /home/wx/Documents/KCU105/pcie_phy_0_ex/imports/sys_clk_gen_ds.v \
  /home/wx/Documents/KCU105/pcie_phy_0_ex/pcie_phy_0_ex.gen/sources_1/ip/pcie_phy_0/sim/pcie_phy_0.v \
  /home/wx/Documents/KCU105/pcie_phy_0_ex/pcie_phy_0_ex.gen/sources_1/ip/pcie_phy_0/source/*.v \
  /home/Xilinx/Vivado/2021.2/data/verilog/src/glbl.v
```

### 5. `vcs`：从work library展开并链接

`vcs`不再重新读取上述所有源文件，而是以 `board` 和 `glbl` 为top，从work library中解析实例层次，并通过 `-L...` 连接Xilinx仿真库：

```bash
vcs -full64 -debug_access+all \
  -top board -top glbl \
  -Lsecureip -Lunisims_ver -Lunifast_ver -Lunimacro_ver \
  -LDFLAGS '-Wl,--no-as-needed' \
  -Mdir=/home/wx/Documents/KCU105/pcie_phy_0_ex/vcs_results/csrc5 \
  -o /home/wx/Documents/KCU105/pcie_phy_0_ex/vcs_results/simv5 \
  -l /home/wx/Documents/KCU105/pcie_phy_0_ex/vcs_results/vcs_elaboration.log
```

这一阶段检查并连接：`board → RP/EP wrapper → pcie_phy_0 → GT Wizard → GTHE3 SecureIP`。成功标志是日志出现 `Top Level Modules: board, glbl`，完成elaboration/link并生成 `simv5`。

### 6. 运行 `simv5`

```bash
timeout --foreground 300 \
  /home/wx/Documents/KCU105/pcie_phy_0_ex/vcs_results/simv5 -licqueue \
  -l /home/wx/Documents/KCU105/pcie_phy_0_ex/vcs_results/vcs_simulation.log
```

运行后，`board.v`执行复位、等待PHY ready、打开Gen1、关闭Gen1、打开Gen3并检查Gen3流量。

### 7. 结果判定

检查 `vcs_simulation.log` 同时满足：

- 出现 `Gen1 ON`、`Gen1 Off`、`Gen3 ON`；
- 出现 `PHY Traffic Has Tested @ 8.0 Gbps or Gen-3 Speed...`；
- 出现 `Test Completed Successfully`；
- VCS返回码为 `0`；
- 没有license timeout或仿真timeout。

本次执行的最终输出文件位于 demo目录下的 `vcs_results/`。

## 日志文件

- `vcs_results/vcs_elaboration.log`：VCS编译、展开和link日志。
- `vcs_results/vcs_simulation.log`：VCS运行日志。
- `vcs_results/simv5`：本次通过验证的VCS仿真可执行文件。

## 注意事项

VCS展开阶段报告了若干原始demo中的端口位宽和未驱动TXEQ信号warning，包括 `phy_rxstart_block` 位宽不一致以及 `PHY_TXEQ_FS/LF/NEW_COEFF/DONE` 无驱动。这些warning未阻止本次 Gen1→Gen3 demo通过，但后续若验证完整均衡流程，建议单独修正并复测。
