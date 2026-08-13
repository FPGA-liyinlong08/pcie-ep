# K13 Gen3 x1 全集成验证计划

状态：**v0.1，在建；K13-CTRL行为门通过，VCS/Vivado/Gen3实板出口未通过**

## 1. 验证目标与判定原则

K13验证目标是证明`K13_ENABLE=1`的生产Endpoint能够在真实PHY和Root Port下完成
Gen1→Gen3 x1训练、EQ、L0、配置枚举和BAR事务，并能从全部错误路径安全回退。

以下结果不能单独作为K13 PASS：控制器单元测试通过、PHY IP配置为8.0 GT/s、
`K13_ENABLE=0`的Gen1 bit枚举成功，或只通过`/dev/mem`访问物理BAR地址。

## 2. 固定验证分层

| 层级 | 必需内容 | 当前状态 |
|---|---|---|
| Lint/行为仿真 | K13控制器展开、正常Gen3、CDR loss、非法TS、K12回归 | **部分PASS** |
| 生产顶层仿真 | `K13_ENABLE=0/1`、真实LTSSM/TS边界、事务静默、回退 | **未完成** |
| VCS真实PHY | Xilinx PHY + Root Port串行Gen1→Gen3、EQ和错误注入 | **elaboration受license阻塞** |
| Vivado | K13-enabled综合、CDC、DRC、route、非负WNS、bit/LTX | **未完成** |
| KCU105实板 | Gen3 x1枚举、ILA、BAR随机压力、retrain和回退 | **未完成** |

## 3. 已执行的K13-CTRL门

当前入口：

```text
make -C pcie_ep_kcu105 k13
make -C pcie_ep_kcu105 k12-integration
```

已通过：

- `k13-ctrl-lint`：以`K13_ENABLE=1`展开`pcie_k13_production_ctrl`；
- `production_gen3_speed_eq_path`：行为Partner下Speed完成，EQ Phase
  `0→1→2→3→4`，协商速率为Gen3；
- `production_cdr_loss_fallback`：注入CDR loss，sticky和Gen1 fallback成立；
- `production_bad_ts_rejects`：非法TS被拒绝并回退Gen1；
- K12 integration 7项回归继续PASS。

固定标记为：

```text
K13_CTRL_SIM_PASS
K13_CTRL_PASS
```

这些标记只关闭K13-CTRL子阶段，不关闭K13。

## 4. 必需Directed场景

1. `K13_ENABLE=0`：与K11 Gen1 release行为等价，reboot、枚举和BAR不退化。
2. 正常Gen1→Gen3：Retrain命令原子跨域，Speed完成，合法TS被接受，EQ Phase
   0～3严格有序，最终进入Gen3 x1 L0。
3. Gen2中间路径：Root Port或PHY要求Gen2时正确完成，不误进入Gen3 EQ。
4. Speed timeout：撤销Electrical Idle命令并回退Gen1，不无限等待。
5. TX/RX EQ timeout：分别验证命令归零、错误锁存和Gen1回退。
6. 非法Rate、TS类型、Lane、Link、Preset和Coefficient：不得驱动非法PHY操作。
7. CDR loss：在Speed以及每个EQ Phase注入，均中止训练并回退。
8. Ordered Set边界：状态、TX mode和速率只在完整TS结束后切换。
9. Recovery事务静默：`traffic_quiesce=1`期间不提交新TLP/DLLP；回到L0后恢复。
10. PERST#/Hot Reset：在Speed和每个EQ Phase复位，输出回到确定安全状态。
11. Retrain重复/overflow：busy期间第二条命令不能覆盖目标速率，错误可观测。
12. Fallback后再次Retrain：Gen1恢复后能够重新尝试并成功进入Gen3。

## 5. 随机、断言与覆盖

- 随机化core/PHY时钟相位、PHY done延迟、TS间隔、拒绝点和CDR loss时刻；
- 至少覆盖Speed所有状态和合法边、EQ Phase 0～3成功/超时、三类TS拒绝和再次升速；
- 断言PHY命令在done/timeout前保持稳定，TS只在complete边界accept，quiesce期间无事务；
- 断言失败路径有限时间进入Fallback，EQ命令归零，最终恢复Gen1；
- 对关键Checker提供故意错误Stub，证明验证环境能检出提前done、Phase跳跃、TS中途切换、
  quiesce泄漏和CDR loss不回退。

## 6. VCS真实PHY门

必须以`K13_ENABLE=1` elaboration生产顶层、Xilinx standalone `pcie_phy`和Root Port
串行模型。至少完成：

- Gen1初始L0及配置访问；
- Root Port发起Retrain并协商8.0 GT/s x1；
- Recovery.Speed和EQ Phase 0～3波形；
- Gen3 L0后的配置读写和BAR TLP；
- CDR loss、非法TS、Speed/EQ timeout的Gen1回退。

当前VCS编译已到elaboration，但`VCSCompiler_Net` license不可用；许可证阻塞解除并
实际完成仿真前，不得写`K13_VCS_GEN3_PASS`。

## 7. Vivado实现门

K13-enabled构建必须明确传入`K13_ENABLE=1`，并在独立目录输出bit、LTX和报告。
必需条件：

- 综合、opt、place、route和bit生成全部成功；
- DRC为0 Error，CDC新增项逐条关闭或进入固定allowlist；
- 所有相关时钟路径`WNS>=0`且hold通过；
- 报告证明K13控制器未被常量裁剪，PHY速率/EQ输出由K13路径真实驱动；
- 生成物记录参数、Git commit、Vivado版本和SHA256。

允许负WNS生成的诊断bit只能标记`DIAGNOSTIC_ONLY`，不能通过K13实现门。

## 8. KCU105 Gen3 x1实板门

烧写K13-enabled bit后，在Linux Root Port执行并保存：

1. `lspci -vv`确认`LnkSta: Speed 8GT/s, Width x1`，且无降速/降宽；
2. Vendor/Device为`1234:e001`，BAR0为4 KiB且由标准PCI enable/驱动打开Memory Space；
3. ILA证明Speed、合法TS、EQ Phase 0～3和Gen3 L0边界；
4. 至少10万次随机8/16/32-bit BAR读写，数据逐项比对，无Completion/CRC/DLL错误；
5. remove/rescan、retrain、reboot后仍保持Gen3 x1并可访问BAR；
6. 注入或构造失败时能够回到Gen1可枚举状态，再次Retrain可恢复Gen3。

`/dev/mem`直访物理BAR可以作为辅助诊断，但必须另外证明PCI Command的Memory
Space已开启并走标准PCI设备访问路径。

## 9. K13冻结标记

全部门禁通过后固定输出并记录：

```text
K13_CTRL_PASS
K13_VCS_GEN3_PASS
K13_IMPL_PASS
K13_HW_GEN3_X1_PASS
K13_BAR_100K_PASS
K13_FALLBACK_RECOVERY_PASS
K13_PASS
```

当前只有`K13_CTRL_PASS`成立；阶段状态保持`K13-IN-PROGRESS`，不得进入K14。
