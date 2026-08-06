# KU060 历史工程归档记录

## 归档位置与状态

- 位置：`/home/wx/Documents/PCIe/pcie_ep_ku060`
- 最后冻结阶段：M02 `pcie_async_pkt_fifo`
- 用途：保存原 KU060 方案、M00～M02 的架构、接口、验证与报告证据。
- 管理规则：原目录不移动、不删除、不继续加入 KCU105 RTL；新工程脚本不得向
  该目录写入构建结果。

## K00 允许复用的内容

KCU105 工程只复用了与器件、PHY 和板卡无关的已审查内容：

- `pcie_reset_sync.sv`、`pcie_bit_sync.sv`、`pcie_gray_sync.sv`；
- `pcie_async_pkt_fifo.sv`；
- M00 Smoke 测试和 `cocotbext-pcie` 对象自检；
- M02 cocotb、Native C++、VCS 测试平台；
- M02 架构、接口和 RTL 前验证计划。

新工程没有复用 KU060 的 `pcie_clk_reset_ctrl`、GT/PCS 设计、管脚约束、器件
配置或 Vivado 生成物。复用后的 M02 必须在 KU040 上重新执行六组时钟、600 万
Packet 和 OOC 综合，旧报告不能代替 K00 复核报告。
