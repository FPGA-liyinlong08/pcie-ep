# PCIe/Xilinx Demo 的 VCS 仿真流程与问题复盘

本文以 `pcie3_ultrascale_0_ex` 为例，记录 Vivado 生成的 PCIe Gen3 UltraScale demo 使用 VCS 仿真的完整流程。后续类似的 Xilinx PCIe、GT 或 IP demo 可以按本文的检查顺序复用。

## 1. 当前验证结果

当前 demo 已完成 VCS 编译、elaboration、链接和运行，默认测试通过：

- 仿真 top：`board` 与 `glbl`
- 测试：`pio_writeReadBack_test0`
- 链路速率：`8.0GT/s`
- 协商位宽：`x1`
- Device/Vendor ID：检查通过
- CMPS ID：检查通过
- BAR0：MEM32 映射检查通过
- PIO 写回读：`01020304` 正确收到
- 结束标志：`Test Completed Successfully`、`VCS Simulation Report`
- 仿真返回码：`0`

## 2. 工程和工具环境

工程目录：

```text
/home/wx/Documents/PCIe/pcie3_ultrascale_0_ex
```

本次验证使用的工具和路径：

| 项目 | 当前配置 |
|---|---|
| Vivado | `/home/Xilinx/Vivado/2023.1` |
| VCS | `/home/synopsys/vcs-mx/O-2018.09-SP2` |
| VCS 架构兼容设置 | `VCS_ARCH_OVERRIDE=linux` |
| Xilinx VCS 仿真库 | `/home/wx/Documents/vcs_compile_simlib` |
| License Server | `27000@wx-linux` |
| VCS 运行脚本 | `vcs/run_vcs.sh` |
| 仿真输出目录 | `vcs/build` |

旧版本 VCS 在当前 Linux 环境中需要显式使用 `-full64`，并设置：

```bash
export VCS_ARCH_OVERRIDE=linux
```

如果没有设置，VCS wrapper 可能会错误地寻找 `linux/bin/vcs1`，而实际安装目录使用的是 `linux64/bin/vcs1`。

## 3. 标准运行方法

首次运行或需要重新编译时：

```bash
cd /home/wx/Documents/PCIe/pcie3_ultrascale_0_ex
./vcs/run_vcs.sh clean
```

只修改测试参数、希望复用已有编译结果时，可以直接运行已有的 `board_simv`：

```bash
cd /home/wx/Documents/PCIe/pcie3_ultrascale_0_ex/vcs/build

export VCS_HOME=/home/synopsys/vcs-mx/O-2018.09-SP2
export VCS_ARCH_OVERRIDE=linux
export SNPSLMD_LICENSE_FILE=27000@wx-linux
export LM_LICENSE_FILE=27000@wx-linux:/home/questasim/mentor.dat
export PATH="$VCS_HOME/bin:$PATH"

./board_simv -licqueue -l simulate_rerun.log \
  +TESTNAME=pio_writeReadBack_test0
```

`run_vcs.sh` 支持通过环境变量覆盖默认配置，例如：

```bash
TESTNAME=其他测试名 ./vcs/run_vcs.sh clean
VCS_LICENSE_SERVER=27000@其他服务器 ./vcs/run_vcs.sh clean
```

脚本中的默认变量包括 `VCS_ROOT`、`VIVADO_ROOT`、`SIMLIB_DIR`、`LICENSE_SERVER`、`BUILD_DIR` 和 `TESTNAME`。换到其他 demo 时，优先修改这些变量或通过环境变量传入，不要把工具路径散落在多个命令中。

## 4. 仿真文件组成

一个 Vivado PCIe demo 的 VCS 仿真通常至少需要以下几类文件：

1. 测试平台顶层，例如 `board.v`。
2. 测试平台的 `imports/*.v` 文件，例如 PCIe transaction、配置空间和 host model 相关代码。
3. Vivado IP 的 RTL/source 文件。
4. IP 的仿真 wrapper。当前 demo 的 `pcie3_ultrascale_0.v` 位于 IP 的 `sim/` 目录，不一定位于 `ip_0/sim/` 目录。
5. `glbl.v`。
6. Xilinx XPM、GT Wizard 等公共仿真源。
7. Xilinx 预编译仿真库：`secureip`、`unisims_ver`、`xpm` 等。

当前 `vcs/run_vcs.sh` 已将上述文件组织起来，并使用本机预编译的 Xilinx VCS 仿真库进行 elaboration。

## 5. 本次遇到的问题和解决方法

| 问题 | 典型现象 | 根因 | 解决方法 |
|---|---|---|---|
| VCS 架构识别失败 | 提示找不到 compiler，或寻找 `linux/bin/vcs1` | VCS-MX 旧版本的 wrapper 与当前架构目录不一致 | 设置 `VCS_ARCH_OVERRIDE=linux`，编译和 elaboration 使用 `-full64` |
| Vivado 默认 VCS 脚本不能直接跑完整 demo | 只编译 IP，找不到 `board` | Vivado 生成的脚本面向 IP 单元仿真，不包含完整 example testbench | 自己维护顶层 testbench、`imports/*.v` 和 `glbl.v` 的 source list |
| 找不到 PCIe IP wrapper | `pcie3_ultrascale_0` unresolved | wrapper 位于 IP 的 `sim/` 目录，默认搜索路径没有覆盖 | 显式加入 `.../pcie3_ultrascale_0/sim/pcie3_ultrascale_0.v` |
| Xilinx 原语 unresolved | `IBUF`、`BUFG_GT`、`RAMB36E1` 等 unresolved | 直接编译部分 Vivado 原语源并不能替代完整仿真库 | 使用 `compile_simlib` 生成的 VCS 库，并在 VCS 中加入 `-Lsecureip -Lunisims_ver -Lxpm` |
| PCIe/GT 加密模型 unresolved | `SIP_PCIE_3_1`、`SIP_GTHE3_CHANNEL` 等 unresolved | 这些模型依赖 Xilinx precompiled secureip/仿真库 | 配置本地 `synopsys_sim.setup`，指向预编译库；不要只依赖 raw UNISIM source |
| License 不可用 | `VCSCompiler_Net does not exist` 或进入 license queue | VCS license 环境变量未统一，或当前 shell 无法访问 license server | 设置 `SNPSLMD_LICENSE_FILE` 和 `LM_LICENSE_FILE`，并用 `lmutil lmstat` 预检查 |
| 链接阶段大量 undefined reference | `snpsOutOfMem`、`vfs_get_sdb...`、`snps_mem...` 等链接错误 | 旧 VCS 与系统 linker 的库按需链接行为不兼容 | 在 VCS 命令中加入 `-LDFLAGS "-Wl,--no-as-needed"` |
| 仿真 warning | `board.v` 中 `3'hx2` 位宽提示，或 RP model 端口位宽不一致 | Vivado 示例/旧模型中的遗留代码问题 | 当前不影响本 demo 的 PASS 结果；后续若改 testbench，再单独清理并回归 |

其中最重要的经验是：

> 对包含 PCIe hard IP、GT 和 secure model 的 Xilinx demo，VCS 仿真库不是可选项。先准备好与 Vivado 版本匹配的 precompiled simlib，再处理 testbench source list，通常比直接编译 `UNISIM` 源码稳定得多。

## 6. 结果判定标准

不能只看 VCS 进程是否返回 `0`。建议同时检查以下内容：

```text
SYSTEM CHECK PASSED
Check Max Link Speed = 8.0GT/s - PASSED
Check Negotiated Link Width = 1 - PASSED
Check Device/Vendor ID - PASSED
Check CMPS ID - PASSED
Test PASSED --- Write Data: 01020304 successfully received
Test Completed Successfully
VCS Simulation Report
```

失败时重点搜索：

```bash
rg -n "Error-|ERROR|FATAL|Fatal|unresolved|license|common elaboration failed|Test FAILED" \
  /home/wx/Documents/PCIe/pcie3_ultrascale_0_ex/vcs/build/*.log
```

## 7. 日志和生成物位置

当前 demo 的关键文件：

- 编译日志：`vcs/build/vlogan.log`
- elaboration 日志：`vcs/build/elaborate.log`
- 仿真日志：`vcs/build/simulate.log`
- 重跑日志：`vcs/build/simulate_rerun.log`
- 可执行仿真器：`vcs/build/board_simv`
- 可复用脚本：`vcs/run_vcs.sh`

建议保留 `run_vcs.sh` 和日志命名规则；`vcs/build` 下的目标文件、`csrc` 和可执行文件属于生成物，后续可以加入 `.gitignore`，避免把约百 MB 的编译结果提交到版本库。

## 8. 新 demo 的复用清单

复制或改造脚本时，按下面顺序确认：

- [ ] 确认 Vivado 版本、VCS 版本和 simlib 版本匹配。
- [ ] 确认 VCS 可以运行：`vcs -full64 -ID`。
- [ ] 确认 License 可见：`lmutil lmstat -f VCSCompiler_Net -c 27000@wx-linux`。
- [ ] 找到真正的 testbench top，而不是只使用 Vivado IP 单元 top。
- [ ] 收集 `imports/*.v`、testbench、`glbl.v` 和所有 generated IP wrapper。
- [ ] 特别检查 IP wrapper 是否位于 IP 根目录的 `sim/`，不要只搜索 `ip_0/sim/`。
- [ ] 生成或复用本地 Xilinx VCS simlib。
- [ ] 配置 `synopsys_sim.setup` 和 `-Lsecureip -Lunisims_ver -Lxpm`。
- [ ] 保留 `-LDFLAGS "-Wl,--no-as-needed"`，直到确认当前 VCS/系统 linker 不再需要它。
- [ ] 先跑最小 smoke test，再跑完整 PCIe PIO/DMA 测试。
- [ ] 同时检查进程返回码、关键 PASS 文本和日志中的 error。

## 9. 常用排错命令

检查 VCS 版本和架构：

```bash
VCS_HOME=/home/synopsys/vcs-mx/O-2018.09-SP2 \
VCS_ARCH_OVERRIDE=linux \
PATH="/home/synopsys/vcs-mx/O-2018.09-SP2/bin:$PATH" \
vcs -full64 -ID
```

检查 License：

```bash
/home/questasim/linux_x86_64/lmutil lmstat \
  -f VCSCompiler_Net -c 27000@wx-linux
```

如果该路径不存在，也可以查找其他安装位置的 `lmutil`，例如 `/home/synopsys/scl/2018.06/linux64/bin/lmutil`。

检查顶层、wrapper 和仿真源：

```bash
rg --files /home/wx/Documents/PCIe/pcie3_ultrascale_0_ex \
  | rg '/(board|glbl|imports|sim|source)/|pcie3_ultrascale_0\.v$'
```

## 10. 后续建议

如果后续会有较多类似仿真，建议逐步抽出一个公共模板，至少统一以下内容：

- 工具路径和 license 变量命名。
- `preflight` 检查：VCS、simlib、license、top 和 source list。
- 编译、elaboration、运行三个阶段的独立日志。
- 统一的 `clean`、`compile`、`run` 和 `all` 入口。
- 统一的 PASS/FAIL 关键字检查。
- 每个 demo 只维护自己的 top、source list 和测试名。

当前 demo 可以作为第一个模板，入口脚本为：

```text
/home/wx/Documents/PCIe/pcie3_ultrascale_0_ex/vcs/run_vcs.sh
```
