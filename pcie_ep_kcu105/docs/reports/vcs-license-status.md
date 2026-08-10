# VCS许可证与阶段影响记录

日期：2026-08-09

状态：**许可证服务可用；K02真实PHY动态仿真PASS**

## 当前检查结果

- VCS：`VCS-MX O-2018.09-SP2_Full64`，`linux64`编译器存在；
- 许可证服务器：`27000@wx-linux`，`lmgrd/snpslmd`均为UP；
- `VCSCompiler_Net`：99席，0占用；
- `VCSRuntime_Net`：99席，0占用；
- `VCSMXRunTime_Net`：99席，0占用；
- `make k02-vcs`已完成真实Xilinx PHY/GT Wizard/secureip编译、elaboration和运行；
- 动态结果：Receiver Detect使用Xilinx强制成功模型，切速序列为G1→G2→G3→G1，
  最终输出`K02_VCS_REAL_IP_PASS`。

此前300秒超时不是许可证文件缺少或席位耗尽；执行环境无法访问本机许可证端口时也会
表现为排队超时。后续VCS门禁必须在能访问`27000@wx-linux`的环境中执行。

## 阶段影响

- K00/K01/M02：VCS smoke、原语和FIFO回归；已有脚本，可直接运行，不再受许可证阻塞；
- K02：真实standalone PHY动态门禁已经补齐；只剩实板Receiver Detect；
- K03：仍缺真实PHY Partner/Root Port串行集成平台，属于验证平台工作，不是许可证问题；
- K04～K10：主要由Verilator/Python/Vivado完成，VCS仅作兼容补充，不影响已冻结结果；
- K11-A：纯离线RTL集成已经PASS，不依赖VCS；
- K11-B：必须使用VCS完成真实PHY+LTSSM+DLL/TL串行仿真，许可证现已具备；仍受测试平台
  和未插板影响；
- K12/K13：Gen3 EQ和完整Gen3串行回归需要VCS，当前许可证条件已满足；
- K14：VCS最终回归需要许可证，当前条件已满足。

许可证恢复不等于K03或K11-B自动通过；真实串行Partner、完整Endpoint顶层与实板门禁
仍需分别实施。

## 2026-08-10再次复核

K11-B2重跑曾再次显示`VCSCompiler_Net`排队。非隔离环境执行`lmstat`确认许可证服务、
`snpslmd`及三类VCS Feature均正常，99席、0占用；同一命令在可访问
`27000@wx-linux`的环境立即获得许可证并完成真实PHY枚举/BAR回归。因此此类“0占用
但持续排队”的处理原则固定为：先用`lmstat`区分服务/席位问题，再确认当前执行环境
是否隔离本机网络；不要重启许可证服务，也不要删除工程编译库来碰运气。
