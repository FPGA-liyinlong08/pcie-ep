# K11-B1 VCS真实Gen1串行链路报告

状态：**PASS**

日期：2026-08-10

## 验证对象

- Endpoint：K02 standalone `pcie_phy`、GTHE3/secureip、K03 Gen1 x1 LTSSM/MAC；
- Root Port：本机XDMA工程导出的Xilinx UltraScale Gen3 x8 Root Port；
- 串行连接：只连接Lane 0，其余Root Port Lane保持静默；
- 仿真器：VCS-MX O-2018.09-SP2，Xilinx Vivado 2021.2预编译库。

## 本次补齐内容

- 新增`pcie_gen12_scrambler`，训练期间旁路数据异或但维持LFSR推进；
- TS使用原始PHY字符解析，Logical Idle和Packet使用解扰字符；
- Configuration.Idle与L0发送加扰后的D0.0，不再把K28.3作为Logical Idle；
- K03 Rate ID固定为`8'h02`，B1只宣告Gen1，避免Root Port自动升速；
- Hot Reset仅由本拍有效TS的Training Control触发，不使用陈旧锁存值。

## 结果

- 错误Stub：断开Lane 0后无法进入L0，输出`K11B_VCS_CHECKER_SELFTEST_PASS`；
- 正常链路：Endpoint依次覆盖Detect、Polling、Configuration和L0；
- Root Port `cfg_ltssm_state=6'h10`，Endpoint `ltssm_state=6'd10`；
- 协商结果：Gen1 x1；
- 双方L0连续保持1024个Endpoint `phy_pclk`；
- 输出`K11B_VCS_GEN1_L0_PASS`和`K11B_VCS_REAL_PHY_PASS`。

## 回归与静态签核

- K03独立加扰器：错误Stub可被检测，2个正式用例通过，随机往返20,000拍；
- K03 Verilator：7/7用例通过，包含100次训练和2,000个随机Packet；
- K03 OOC：`WNS=4.709 ns`；
- standalone PHY + K03完整布局布线：`WNS=0.212 ns`、`TNS=0`、未布线网络0；
- DRC违规0，CDC只有4条`CDC-3 Info`和5条`CDC-9 Info`，无Warning/Critical；
- 成功生成`fpga/kcu105/build_k03/impl/k03_gen1_ltssm_mac.bit`；
- XCI SHA-256保持`33c7bc66cdf1414ee0ca4f78a2dc32ed73dac8a150e2dd154698f4d6c2ecb345`。

## 边界与下一步

K11-B1只验收真实串行PHY与LTSSM。Root `user_lnk_up`包含Data Link用户接口就绪
语义，本阶段尚未接入InitFC/DLL，因此只记录、不作为B1门禁。下一步K11-B2接入
K04～K11-A完整数据链路与事务路径，届时以`user_lnk_up`、枚举和BAR访问为门禁。

KCU105实板仍按用户批准延期，VCS结果不替代上板验收。
