# K11-B 真实 PHY/VCS RTL 前验证计划

状态：**计划冻结；先执行 K11-B1**

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
