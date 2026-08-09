# K08 Type-0 配置空间接口契约

状态：**K08-CFG-SPACE-v1 接口冻结**

除低有效`rst_n`外，全部端口属于`clk=phy_coreclk`（250 MHz）域，使用普通
SystemVerilog端口。输入状态的CDC由K11集成层完成，K08内部没有异步跨时钟逻辑。

## 1. 时钟、复位与链路状态

| 端口 | 方向 | 位宽 | 复位/规则 |
|---|---:|---:|---|
| `clk` | 输入 | 1 | `phy_coreclk`，目标周期4.000 ns |
| `rst_n` | 输入 | 1 | 异步低有效；系统保证同步释放 |
| `hot_reset` | 输入 | 1 | Core域单周期事件；与PERST#相同地清除配置状态 |
| `link_up` | 输入 | 1 | 已同步状态；只影响Link Status |
| `link_training` | 输入 | 1 | 已同步状态；映射Link Status.Training |
| `dll_active` | 输入 | 1 | 已同步状态；映射Link Status.DLL Active |
| `link_speed` | 输入 | 2 | `0/1/2=Gen1/Gen2/Gen3`；`3`按Gen1报告 |
| `link_width` | 输入 | 3 | 当前协商宽度；只有值1且Link Up时报告x1，其他值报告0 |

`hot_reset=1`期间禁止接受新请求，并在上升沿清除可写配置状态与BDF。已经产生且正在
反压的响应不得撤销，仍保持到握手；若同拍`cfg_rsp_ready=1`，该既有响应正常握手并
清空。普通链路Down、Recovery、Retrain和`link_speed`改变都不得修改任何配置寄存器。

## 2. K07配置请求接口

| 端口 | 方向 | 位宽 | 说明 |
|---|---:|---:|---|
| `cfg_req_valid` | 输入 | 1 | 请求有效 |
| `cfg_req_ready` | 输出 | 1 | 仅响应槽空闲且`hot_reset=0`时为1 |
| `cfg_req_write` | 输入 | 1 | 0=读，1=写 |
| `cfg_req_dw_addr` | 输入 | 10 | 4 KiB空间DWORD地址 |
| `cfg_req_be` | 输入 | 4 | 每bit控制对应Byte；允许任意16种组合 |
| `cfg_req_wdata` | 输入 | 32 | 小端数值；Byte 0在`[7:0]` |
| `cfg_req_requester_id` | 输入 | 16 | 保留用于诊断；K08响应上下文由K07保存 |
| `cfg_req_tag` | 输入 | 8 | 保留用于诊断；K08不排序Tag |
| `cfg_req_target_bdf` | 输入 | 16 | `{Bus[7:0],Device[4:0],Function[2:0]}` |

`cfg_req_valid && cfg_req_ready`的上升沿接收请求。请求反压时K07必须保持所有字段稳定。
K08不组合依赖`cfg_rsp_ready`产生`cfg_req_ready`，因此没有Ready/Valid组合环。

Byte Enable写语义：

```text
merged[8*i +: 8] = cfg_req_be[i] ? cfg_req_wdata[8*i +: 8]
                                      : old_value[8*i +: 8]
```

随后再应用寄存器可写位掩码。`cfg_req_be=0`是合法无副作用写，仍返回SC。配置读忽略
`cfg_req_be`并返回完整DWORD；K07-v1固定生成1 DW、Byte Count=4的Completion。

## 3. K07配置响应接口

| 端口 | 方向 | 位宽 | 说明 |
|---|---:|---:|---|
| `cfg_rsp_valid` | 输出 | 1 | 请求握手后最早下一拍置位 |
| `cfg_rsp_ready` | 输入 | 1 | K07接受响应 |
| `cfg_rsp_status` | 输出 | 3 | `000=SC`、`001=UR`；其他值K08不生成 |
| `cfg_rsp_rdata` | 输出 | 32 | SC读数据；写及UR固定0 |
| `cfg_rsp_completer_id` | 输出 | 16 | 首次命中用目标BDF，其后用捕获BDF |

`cfg_rsp_valid && !cfg_rsp_ready`期间三个响应字段保持逐位稳定。响应握手后下一拍
`cfg_rsp_valid`清零，K08才重新接受请求。PERST#取消待响应事务；Hot Reset不得取消
已产生的响应，但会立即阻止新请求并复位配置状态。

## 4. BDF与配置状态输出

| 端口 | 方向 | 位宽 | 复位值/说明 |
|---|---:|---:|---|
| `captured_bdf` | 输出 | 16 | 0；首次合法Function 0请求捕获 |
| `bdf_valid` | 输出 | 1 | 0；BDF已捕获 |
| `local_completer_id` | 输出 | 16 | `bdf_valid ? captured_bdf : 0` |
| `bar0_base` | 输出 | 32 | 0；低12位固定0，探测时保持真实基址 |
| `bar0_probe_active` | 输出 | 1 | 0；全DWORD写全1后置1 |
| `memory_space_enable` | 输出 | 1 | Command bit1 |
| `bus_master_enable` | 输出 | 1 | Command bit2；当前无主动请求 |
| `max_payload_size` | 输出 | 3 | 固定0，即128 B |
| `max_read_request_size` | 输出 | 3 | Device Control `[14:12]`，复位2 |
| `rcb_128b` | 输出 | 1 | Link Control bit3；0=64 B、1=128 B |
| `link_disable` | 输出 | 1 | Link Control bit4 |
| `retrain_link_pulse` | 输出 | 1 | 写Link Control bit5时单周期脉冲 |
| `target_link_speed` | 输出 | 2 | `0/1/2=Gen1/Gen2/Gen3`，复位2 |

`retrain_link_pulse`不受下游Ready控制，K11必须在同一Core域捕获并可靠跨到Link域。

## 5. BDF响应规则

按以下优先级处理每个已握手请求：

| 条件 | 动作 | 响应 |
|---|---|---|
| `target_bdf.device/function != 0` | 不捕获、不读写 | UR，Completer ID为0或已捕获BDF |
| `!bdf_valid && device/function==0` | 捕获完整目标BDF并执行访问 | SC，Completer ID为目标BDF |
| `bdf_valid && target==captured` | 正常执行 | SC，Completer ID为捕获BDF |
| `bdf_valid && target!=captured` | 不读写 | UR，Completer ID为捕获BDF |

K08不返回CRS或CA。Malformed、Poisoned CfgWr和不支持的Cfg Type已经由K07处理。

## 6. 逐位寄存器属性

属性缩写：`RO`只读、`RW`普通读写、`R0`读0、`WI`写忽略、`PULSE`写1脉冲。

### 6.1 Type-0 Header

| 地址 | Bit | 属性 | 定义 |
|---:|---:|---|---|
| `004` | `[2:0]` | RW | I/O Space、Memory Space、Bus Master |
| `004` | `6` | RW | Parity Error Response Enable，仅保存 |
| `004` | `8` | RW | SERR Enable，仅保存 |
| `004` | `10` | RW | Interrupt Disable，仅保存 |
| `004` | 其余Command | R0/WI | 未实现 |
| `004` | Status bit4 | RO=1 | Capabilities List，位于DWORD bit20 |
| `004` | 其余Status | R0/WI | 当前无错误状态 |
| `010` | `[31:12]` | RW | BAR0基址；探测读回Size Mask |
| `010` | `[11:0]` | RO=0 | 4 KiB、32-bit、non-prefetchable |
| 其他Header | 全部 | RO或R0/WI | 见架构固定表 |

Command可写掩码固定为`16'h0547`。

### 6.2 PCIe Capability

| 地址 | Bit | 属性 | 定义 |
|---:|---:|---|---|
| `048` | `[4:0]` | RW | Error Reporting及Relaxed Ordering，仅保存 |
| `048` | `[7:5]` | RO=0 | MPS固定128 B |
| `048` | `[14:12]` | RW受限 | MRRS，复位2；仅0～5有效，6/7保持旧值 |
| `048` | 其他 | R0/WI | Extended Tag、No Snoop、FLR等不支持 |
| `050` | `3` | RW | RCB |
| `050` | `4` | RW | Link Disable |
| `050` | `5` | PULSE | Retrain Link，不存储 |
| `050` | `6` | RW | Common Clock Configuration，仅保存 |
| `050` | `7` | RW | Extended Sync，仅保存 |
| `050` | `9` | RW | Hardware Autonomous Width Disable，仅保存 |
| `050` | `[31:16]` | RO动态 | Current Speed/Width、Training、DLL Active |
| `070` | `[3:0]` | RW受限 | 仅1、2、3有效；复位3 |
| `070` | 其他 | R0/WI | Gen3 EQ状态在K12需要时另行升级 |

Device Control可写掩码固定为`16'h701f`；Link Control持久位掩码为`16'h02d8`，
其中Retrain bit5单独按PULSE处理。

## 7. BAR0探测细则

1. 只有`cfg_req_dw_addr=4`、`cfg_req_be=4'hf`且`wdata=32'hffff_ffff`被识别为探测；
2. 探测不修改真实`bar0_base`，只置`bar0_probe_active`；
3. 探测状态读BAR0返回`32'hffff_f000`；
4. 下一次任意非探测BAR0写按Byte Enable更新真实基址并清除探测状态；
5. BAR0读出的低12位恒0，所有属性位恒0；
6. BAR1～5、ROM BAR写全1仍读0；
7. Hot Reset/PERST#将真实基址和探测状态都清零。

## 8. 延迟与时序

- 请求握手到响应`valid`：1拍；
- 响应反压：无限期允许，字段稳定；
- Hot Reset输入到所有可写状态复位：同一上升沿；
- `retrain_link_pulse`：与相应配置写握手后的下一周期有效1拍；
- 组合读Mux只能驱动请求捕获寄存器，不得直接形成顶层长组合响应路径；
- 目标4.000 ns；OOC同步输入边界延迟冻结为`0.25～1.00 ns`，输出给下游保留
  `1.00 ns`setup预算，K11集成不得放宽；
- K08内部无CDC、无BRAM、无DSP和无PCIe Hard Block。
