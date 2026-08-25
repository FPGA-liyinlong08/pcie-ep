# Phase E1：Gen3 128-bit Block与Ordered Set架构

状态：**E1已冻结；E2 RTL、仿真与K14实现复验PASS，实板门禁待实施**

## 1. 生产边界

Phase E继续使用Phase D冻结的唯一PHY命令owner：

`K03 LTSSM/MAC → pcie_phy_command_ctrl → K02 PHY wrapper`

Gen3数据面位于同一个`phy_pclk`域。AMD PCIe PHY完成串行侧128b/130b编码/解码，
MAC侧按PG239提供的32-bit PIPE接口每四个有效传输组成一个128-bit Block。MAC不得把
`RxDataValid=0`解释为block终止；该拍必须被忽略。

## 2. RX分层

`pcie_gen3_block_rx`先完成纯结构处理：

1. 忽略首个`RxStartBlock`之前的任意数据；
2. 仅在`RxDataValid=1`时接收一个32-bit word；
3. `RxDataValid=0`允许出现在block内部且不推进word index；
4. 在一个未完成block中再次看到`RxStartBlock`时报告`boundary_error`，并以新word
   作为下一候选block的word 0；
5. 在第四个有效word后提交一次`block_valid`、128-bit数据和word 0拍锁存的
   `SyncHeader`。

`pcie_gen3_os_rx`再完成语义处理。精确EIEOS建立`block_locked`并把lane-0扰码器重置为
`23'h1DBFBC`。锁定前的TS1/TS2一律不提交给LTSSM。非法Sync Header或中途新
StartBlock会丢锁，只有后续新EIEOS可以重获。

## 3. TX与Recovery序列

Recovery.RcvrLock发送序列冻结为：

`EIEOS → 32 × TS1 → EIEOS → 32 × TS1 → ...`

RcvrCfg切换到TS2时仍保持同一block和扰码上下文。SDS用于开始Data Stream，不属于
Recovery.RcvrLock前缀，因此删除K13实验代码中的自动
`EIEOS → SDS → TS`序列。SDS的完整Data Stream行为留到E5；E1 RX仅识别其固定
12个`AA` Symbol和`E1`标识，不固定比较状态相关的最后3个Symbol。

## 4. 扰码与字段边界

Gen3 lane-0使用23-bit additive scrambler，初值`23'h1DBFBC`。每个TS Block的第一个
byte是明文`1E/2D` Block标识；该byte不做XOR，但LFSR仍跨全部128 bit推进。EIEOS为
明文并重新初始化LFSR。

TS字段沿用已冻结的16-byte语义映射，但由独立Python bit-serial参考模型逐bit生成
期望PIPE word。RX只有在完整block结束且字段标识检查通过时产生单拍`ts1_valid`或
`ts2_valid`。

## 5. Parser所有权

`pcie_ltssm_mac_gen1`只允许一个parser活动：

- `gen3_mode=0`：启用Gen1/2 8b/10b parser，禁用Gen3 parser；
- `gen3_mode=1`：禁用Gen1/2 parser，启用Gen3 block/OS parser。

该互斥避免Gen3原始word在Gen1 parser中形成伪COM/TS状态，并避免fallback后消费旧
半包。

## 6. E2 Recovery.RcvrLock语义门

`pcie_gen3_rcvrlock_ctrl`位于E1 parser与K03 LTSSM之间，只消费解码后的
`block_locked/lock_lost/TS/malformed`事件。它不观察也不驱动`PHY_RATE`、
PowerDown、TXEI、Detect Assist、CDR Hold或PhyStatus握手。

Gen3 `Recovery.RcvrLock`冻结为以下顺序：

1. block lock前的TS1不计数；
2. EIEOS建立lock后累计8个Link/Lane字段匹配的TS1；
3. 第8个TS1产生单拍`complete`并进入`Recovery.RcvrCfg`；
4. 失锁、malformed、TS2或字段不匹配产生单拍`failed`；
5. E2 error或LTSSM timeout都回到`Recovery.Speed`，由K14协调器请求Gen1 fallback；
6. `complete/failed`进入terminal hold，离开RcvrLock后由`enable=0`清除，避免重复脉冲。

Gen1 RcvrLock的既有TS规则保持不变。生产顶层仅在请求速率为Gen3时把
`gen3_rcvrlock_complete`作为`peer_speed_ok`；Gen1 fallback仍使用原TS1/TS2条件。

## 7. 非目标

E2不宣称RcvrCfg、Equalization、Gen3 Data Stream/TLP、Linux Gen3枚举或实板8 GT/s
已经通过。E2实板连续20次RcvrLock门禁也仍待完成；这些分别属于E2硬件门与E3～E6。
