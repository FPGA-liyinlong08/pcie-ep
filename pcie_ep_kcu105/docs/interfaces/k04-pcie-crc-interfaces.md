# K04 PCIe CRC 流接口契约

状态：**K04-CRC32S-v1 接口与 RTL 已冻结**

## 1. 模块

对外提供两个普通 SystemVerilog 模块：

- `pcie_crc16_dllp`：`crc_result[15:0]`；
- `pcie_crc32_lcrc`：`crc_result[31:0]`。

除结果宽度外，两个模块端口和时序完全一致。内部参数化引擎
`pcie_crc_stream` 不属于跨模块接口契约。

## 2. 输入端口

| 端口 | 方向 | 位宽 | 时钟域 | 复位值/规则 |
|---|---:|---:|---|---|
| `clk` | 输入 | 1 | 本域 | K05/K06 连接 `phy_pclk`，最高 250 MHz |
| `rst_n` | 输入 | 1 | 异步低有效 | 异步置位，外部保证同步释放 |
| `start` | 输入 | 1 | `clk` | 与 Packet 第一拍 `valid` 同时为 1 |
| `data` | 输入 | 32 | `clk` | 线路先到 Byte 位于 `[7:0]` |
| `keep` | 输入 | 4 | `clk` | bit n 对应 `data[8*n +: 8]` |
| `last` | 输入 | 1 | `clk` | Packet 最后一拍，与 `valid` 同时采样 |
| `valid` | 输入 | 1 | `clk` | 为 1 且 `ready=1` 时接受一拍 |

握手与长度规则：

- `ready=0` 时 Driver 必须保持 `start/data/keep/last/valid`；
- 本版本没有内部结果队列，正常运行时 `ready=1`；复位期间 `ready=0`；
- 非末拍 `keep=1111`；末拍允许 `0001`～`1111` 的全部非零组合；
- 有效 Byte 按 lane 0、1、2、3 的升序送入 CRC，`keep=1010` 表示只处理
  `data[15:8]`，再处理 `data[31:24]`；
- 最小 Packet 为 1 Byte；模块没有硬件最大长度计数，系统使用上限为 4096 Byte。

## 3. 输出端口

| 端口 | 方向 | 位宽 | 复位值 | 规则 |
|---|---:|---:|---:|---|
| `ready` | 输出 | 1 | 0 | 离开复位后为 1 |
| `crc_result` | 输出 | 16/32 | 0 | `crc_valid=1` 时有效；Byte 0 位于最低 8 bit |
| `crc_valid` | 输出 | 1 | 0 | 接受末拍后的单周期脉冲 |
| `crc_match` | 输出 | 1 | 0 | 与 `crc_valid` 同拍；包含正确 CRC 的完整输入流为 1 |
| `protocol_error` | 输出 | 1 | 0 | 输入 Packet 规则违例的单周期脉冲 |
| `busy` | 输出 | 1 | 0 | 已接受首拍但尚未接受末拍 |

`crc_result` 的生成用法：输入受保护数据但不输入 CRC 字段，在 `crc_valid` 拍取得
结果，并按 `[7:0]`、`[15:8]`……顺序追加到线路。

`crc_match` 的检查用法：输入受保护数据以及线路收到的 CRC Byte，在最后一个 CRC
Byte 所在拍置 `last=1`。`crc_match=1` 表示余数正确；此时 `crc_result` 不用于生成。

## 4. 延迟与连续事务

- 接受非末拍后，CRC 状态在该时钟沿更新；
- 接受末拍后，`crc_valid/crc_match/crc_result` 在紧随该沿的周期有效；
- 结果没有 `ready`，使用者必须在 `crc_valid` 当拍采样；
- 末拍后一周期可接受新 Packet 首拍；
- `protocol_error` 与 `crc_valid` 不会在同一周期为 1。

## 5. 固定常量

| 模块 | 反射多项式 | 初值 | 正常输出 | 检查 residue |
|---|---:|---:|---|---:|
| `pcie_crc16_dllp` | `16'hD008` | `16'hFFFF` | `~raw_crc` | `16'h556F` |
| `pcie_crc32_lcrc` | `32'hEDB88320` | `32'hFFFFFFFF` | `~raw_crc` | `32'hDEBB20E3` |

接口版本变更条件：端口、Byte 顺序、keep 语义、结果编码、residue、延迟或错误恢复
语义发生任何变化，都必须升级 `K04-CRC32S-v1` 并重跑完整 K04 回归。
