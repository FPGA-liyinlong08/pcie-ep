# K00 工程骨架与验证基线报告

状态：**PASS / K00-v1 已冻结**  
执行日期：2026-08-06  
统一命令：`make k00`

## 1. 冻结结论

新工程已在 `/home/wx/Documents/PCIe/pcie_ep_kcu105` 独立建立。KU060 历史工程
仍位于 `/home/wx/Documents/PCIe/pcie_ep_ku060`；Git 差异中没有旧工程改动。
K00 所有门禁通过，允许下一次单独开始 K01，但本次没有创建 K01 RTL。

## 2. 工具版本

| 工具 | 版本 |
|---|---|
| Vivado | 2021.2，Build 3367213 |
| Verilator | 5.020 |
| cocotb | 1.9.2 |
| cocotbext-pcie | 0.2.16 |
| Python | 3.8.10 |
| VCS-MX | O-2018.09-SP2 Full64 |

## 3. 动态验证结果

| 检查 | 结果 |
|---|---|
| Verilator 复位/Counter Smoke | PASS，连续 32 周期 |
| RC/Device/Function 创建与连接 | PASS |
| Memory Write TLP pack/unpack | PASS，TLP 32 Byte |
| VCS `unisims_ver`/`BUFG` Smoke | PASS |
| 故意错误 M02 Stub | 按预期 FAIL，Checker 报告“未完成 Packet 提前可见”；外层自检 PASS |
| M02 Verilator Lint | PASS |
| M02 cocotb | PASS，6 组时钟 × 1,000 Packet；每组 5/5 用例通过 |
| M02 Native C++/Verilator | PASS，6 组 × 1,000,000 Packet，共 6,000,000 Packet |
| M02 VCS | PASS，8 ns 写时钟/4 ns 读时钟 |

Native 回归每组 `committed=received=1,000,000`，无丢包、重复、乱序、字段变化、
Overflow 或 Underflow。固定随机种子为 `20260806`。

## 4. KU040 OOC 结果

目标器件为 `xcku040-ffva1156-2-e`，代表时钟为写侧 62.5 MHz、读侧 250 MHz。

| 项目 | 结果 |
|---|---:|
| 综合 | 0 Error，0 Critical Warning |
| CLB LUT | 252 |
| CLB Register | 415 |
| RAMB36E2 | 2 |
| RAMB18E2 | 2 |
| Block RAM Tile | 3 |
| `ASYNC_REG` Cell | 124 |
| WNS / TNS | 1.561 ns / 0.000 ns |
| WHS / THS | 0.098 ns / 0.000 ns |
| `check_timing` no/constant/pulse-width clock | 0 / 0 / 0 |
| CDC | 2×CDC-3 Info，6×CDC-6 Allowlist，无 Critical |
| DRC | 1×CFGBVS-1 Allowlist，无 Error/Critical |

报告位于 `fpga/kcu105/build_k00_m02/`，该目录由 `.gitignore` 排除。Warning 类型
与 `docs/verification/vivado-warning-allowlist.md` 完全一致；新增类型会使脚本失败。

## 5. 依赖和指纹

外部 `afifo.v` 未复制、未修改：

`e6c8d4731857caf504277dca72967c89dba6e3c83aee95953a0a279ff958cc4c`

导入的通用 RTL：

| 文件 | SHA-256 |
|---|---|
| `pcie_async_pkt_fifo.sv` | `b108eee71d094c588676f7efbc18398f01f85e0f755bd453151810a7c34de635` |
| `pcie_reset_sync.sv` | `89f8d6c2314b41c4d0a5f62350f48dddeb12a3d7d075d655f6771c57a48b6006` |
| `pcie_bit_sync.sv` | `479008b01d2f62120ff7b16d137ccf2cd9aa64826d376aa3690f5406a0e4a450` |
| `pcie_gray_sync.sv` | `1b2b16683f7dff2dffd3afc0a04e4c4eb88d062e2e0f8bea62b7e045cd094b34` |

四个文件与 KU060 历史基线逐字节一致。新工程不存在非构建目录下的 XCI、DCP
或 XPR；没有复制 KU060 的时钟/GT/PCS RTL。

## 6. 已知限制

- K00 只证明通用验证框架和 M02 在 KU040 上成立，不证明 standalone PHY 可行；
- OOC 时序没有最终系统 BUFG 位置，`Timing 38-242` 留待 K11 集成消除；
- `CFGBVS-1` 来自无板级顶层的 OOC 检查，K01 顶层 XDC 必须设置配置电压属性；
- K02 仍是第一可行性门；Receiver Detect、速率切换和真实串行链路尚未验证。
