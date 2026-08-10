# K11-B 真实 PHY/VCS RTL 前验证计划

状态：**K11-B1 PASS；K11-B2 D001～D008、修改后VCS及KU040实现PASS**

## 1. 参考对象和 Checker

- Root Port：XDMA 示例工程导出的 Xilinx UltraScale Root Port Core 和用户应用；
- Endpoint：真实 K02 standalone PHY、K03 LTSSM/MAC；
- Checker：B1同时观察双方 LTSSM L0、协商速率/宽度和错误计数；Root
  `user_lnk_up` 在B2接入InitFC/DLL后才作为门禁；
- 日志：VCS 编译、展开、运行分别保存，任何 Error、Fatal 或固定 FAIL 标记均失败。

## 2. 错误 Stub 自检（先于正常用例）

同一测试平台在 `K11B_DISCONNECT_LANE0` 模式下断开 Lane 0。Checker 必须在限定时间
内确认 Endpoint 不能进入 L0，并输出 `K11B_VCS_CHECKER_SELFTEST_PASS`。若断线仍被
判定为正常，或测试未结束，门禁失败且不得运行正常用例。

## 3. K11-B1 Directed Case

| 编号 | 用例 | 检查点 |
|---|---|---|
| B1-D001 | 编译与展开 | Endpoint PHY、Root Port GT、secureip 均使用真实模型 |
| B1-D002 | 同步复位 | 两端 reset 释放后时钟持续，Endpoint 不提前离开复位 |
| B1-D003 | Receiver Detect | Endpoint Detect.Active 获得 present，进入 Polling |
| B1-D004 | Gen1 降速/降宽 | Gen3 x8 RP 与 Gen1 x1 EP 最终协商 Gen1 x1 |
| B1-D005 | L0 稳定 | 双方LTSSM=L0同时保持至少1,024个Endpoint `phy_pclk` |
| B1-D006 | 串行断线 | 不得假阳性进入 L0，错误 Stub 自检必须通过 |

## 4. 断言、覆盖和通过标准

- Endpoint `link_up` 前不得出现 L0；协商宽度只能为 x1、速率只能为 Gen1；
- 覆盖 Detect、Polling、Configuration、L0 四大状态组；
- 正常用例要求双方LTSSM保持L0且稳定窗口无掉链；
- 断线用例要求 Checker 明确识别未训练成功；
- 展开日志必须证明同时装入 Root Port Core、K02 PHY 和 GTHE3/secureip；
- VCS 许可证等待超过可配置超时时间时报告为环境阻塞，不伪造成设计失败。

K11-B1 通过后才开始 B2 的 InitFC、配置枚举和 BAR 测试。实板仍按延期记录执行，
VCS 结果不能替代 KCU105 上板门禁。

## 5. K11-B2 测试平台结构

- Driver：复用Root Port `tx_usrapp`的Type-0、Memory Read/Write task；
- Monitor：同时采集双方LTSSM、`user_lnk_up`、Endpoint `dll_active`、BDF/BAR/MSE、
  DLL/TL计数器和CDC sticky状态；
- Scoreboard：逐事务比较DW0、BAR mask、Demo签名及Scratch读回值；
- 超时：分成DLL Active、每个Completion和全局三个超时，超时日志必须给出最末状态；
- 日志：B1和B2使用不同固定PASS/FAIL标记，禁止B1的L0标记误判为B2成功。

## 6. K11-B2 错误Stub自检

在编写`kcu105_pcie_ep_gen1_top`前，测试平台先以已经通过的K03-only B1 Endpoint作为
负向Stub。该Stub可以进入L0，但没有InitFC、Completion和BAR。Checker必须在DLL
Active超时后输出`K11B2_CHECKER_SELFTEST_PASS`，并且不得出现任何B2 PASS标记。
这样可证明B2门禁不是只检查物理L0。

## 7. K11-B2 Directed Case

| 编号 | 用例 | 检查点 |
|---|---|---|
| B2-D001 | K03-only负向Stub | L0可成立，但DLL/枚举门禁必须失败 |
| B2-D002 | InitFC | EP `dll_active`与RP `user_lnk_up`均为1，信用不下溢 |
| B2-D003 | Vendor/Device | Type-0 DW0返回`E001_1234`且BDF被捕获 |
| B2-D004 | BAR probing | BAR0 mask为`FFFF_F000`，BAR1～5保持未实现 |
| B2-D005 | BAR配置 | BAR0=`8000_0000`，Command.MSE=1 |
| B2-D006 | Demo签名 | MRd32 BAR0+0返回`5043_4945` |
| B2-D007 | Scratch写读 | MWr32/MRd32 BAR0+0x40返回`A5C3_7E19` |
| B2-D008 | 稳定性 | 全过程双方保持L0，CDC错误为0，无Fatal/FAIL |

## 8. 随机、错误注入、断言和通过标准

B2基础串行路径通过后增加100组随机Scratch地址/数据/BE；注入坏LCRC、ACK丢失和一次
PERST#，检查Replay或重新训练后可继续配置访问。基础实现阶段至少断言：DLL Active前
不发送TLP、Posted Write无Completion、同Tag Completion字段匹配、CDC错误恒为0、
MSE关闭时BAR请求不命中。正式通过要求D001确实失败且D002～D008全部通过；之后运行
K03、K06、K08～K11-A离线回归、VCS串行回归和KU040完整实现。实板验收继续延期。

## 9. 当前执行记录

- K03-only负向Stub已输出`K11B2_CHECKER_SELFTEST_PASS`；
- 真实PHY串行基础路径已完成InitFC、`01:14.0`枚举、BAR probing/分配、MSE、Demo
  签名和Scratch读写，D002～D008全部通过；
- 完整KU040实现首次暴露TX FIFO到Replay RAM的250 MHz长组合路径，增加一拍弹性级后
  `WNS=+0.020 ns`、`WHS=+0.014 ns`，DRC/CDC通过并成功生成bitstream；
- 弹性级修改后的Verilator双向随机桥回归通过；真实PHY VCS在可访问本机许可证服务
  的非隔离环境重跑通过，输出全部K11-B2固定PASS标记；
- 100组串行随机BAR、坏LCRC、ACK丢失和PERST#注入尚未执行，实板继续延期。
