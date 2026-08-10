# K11-A Gen1 Endpoint 离线集成架构

## 1. 范围

K11-A把K02～K10冻结模块连接为可综合的Gen1 x1 Endpoint层次，并完成不依赖真实
Xilinx串行模型和板卡的验证。真实`pcie_phy`串行仿真、Receiver Detect、Linux枚举和
板卡BAR访问属于K11-B，不作为K11-A通过条件。

数据路径保持为：

`PHY32 → LTSSM/MAC → DLL → RX异步Packet FIFO → TLP/CFG/BAR → Demo AXI-Lite`

返回路径为：

`Demo AXI-Lite → BAR Completion → TLP Codec → TX异步Packet FIFO → DLL → MAC`

## 2. 层次划分

- `pcie_tlp_async_bridge`：两个M02 Packet FIFO、一个TX元数据FIFO和一个RX信用归还
  FIFO；只负责CDC和Packet原子对齐。
- `k09_tlp_test_top`：名称保留自K09验证基线，内部使用生产K07 Codec、K08配置空间
  和K09 BAR Master；K11-A把它作为可综合TL子层，不包含行为模型。
- `k11a_offline_top`：位于`rtl/ep/k11a_offline_top.sv`，集成生产K06 DLL、异步桥、
  上述TL子层和生产K10 Demo Slave；上边界为K03的16-bit MAC Packet接口。模块名为
  保持K11-A冻结接口不变而保留，K11-B直接复用该生产RTL。
- K02 PHY、K03 LTSSM/MAC和板级管脚不进入该顶层；真正的
  `kcu105_pcie_ep_gen1_top`留到K11-B完成，动态串行验证也延期到K11-B。

## 3. CDC与原子性

M02-v1接口不增加侧带。TX TLP的`type/data_credits`在Core域SOP握手时写入独立15-bit
异步FIFO。PIPE域只有在Packet和元数据同时可用时才放行首拍，元数据保持到EOP握手
后再弹出。因此Packet与信用信息不会错配。

K07在完整RX Packet消费后产生的`release_type/data_credits`通过14-bit事件FIFO返回
PIPE域。事件FIFO满时向K07反压，不允许静默丢失信用归还。

PIPE域的链路状态、DLL状态和32-bit诊断计数器通过请求/应答握手形成143-bit原子快照，
源域在目标域确认前保持快照总线稳定；Core域只在同步后的请求翻转到达后更新状态。
Hot Reset使用独立toggle事件同步器，转换为Core域单拍。相邻Hot Reset事件必须至少
间隔两个`core_clk`周期，PCIe训练流程天然满足此限制。

任一时钟域复位都会异步清空Packet和元数据FIFO。配置状态只受PERST#同步复位或
Hot Reset事件控制；PIPE速率切换复位不得直接清空配置空间。

## 4. 缓冲与错误处理

- RX/TX Packet FIFO沿用M02 `LGFIFO=9`，最多512个128-bit beat；
- TX元数据和RX信用事件FIFO各16项；
- Packet FIFO overflow/underflow、元数据overflow/underflow均为sticky诊断；
- 元数据未到达时Packet首拍保持，不允许先进入DLL；
- DLL replay fatal请求K03进入Recovery；K11-A不实现Gen3升速；
- BAR/Codec/DLL的既有错误动作保持冻结，不在集成层改写。

## 5. K11-B边界

K11-B必须补齐真实VCS `pcie_phy`串行环境、许可证与操作系统兼容性、KCU105 Gen1 L0、
Linux枚举/BAR、20次冷启动和100次PERST#/重训。K11-A通过不等于K11整体冻结。
