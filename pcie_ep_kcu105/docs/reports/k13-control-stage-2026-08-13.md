# K13 控制阶段记录（2026-08-13）

状态：**K13-CTRL PASS；K13 全集成未完成**

## 1. 本次完成内容

新增 `rtl/phy/pcie_k13_production_ctrl.sv`，将 K12 已验证的控制单元组合成一个
可关闭的生产接线边界：

- 配置空间 Retrain 命令通过 CDC mailbox 原子跨到 `phy_pclk`；
- Recovery.Speed 驱动 Gen1/Gen2/Gen3 速率请求、PHY `phystatus` 完成和 fallback；
- Ordered Set 只在完整边界、类型、速率、Lane/Link 合法时接受；
- Gen3 EQ Phase 0～3 驱动 Preset/Coefficient，并等待 TX/RX done 或超时；
- CDR loss、非法 TS 和训练失败回到 Gen1 安全路径；
- `K13_ENABLE=0` 时所有 PHY 控制输出保持 K11 Gen1 安全值。

EQ 启动条件使用“Speed 已完成且 TS 合法”这一边界，避免控制器等待 EQ done
而 EQ 又尚未启动的死锁。

## 2. 已执行门禁

命令：

```text
make -C pcie_ep_kcu105 k13
make -C pcie_ep_kcu105 k12-integration
```

结果：

| 门禁 | 结果 | 覆盖 |
|---|---|---|
| K13 Verilator lint | PASS | `K13_ENABLE=1` 控制器展开 |
| K13 production control simulation | PASS | 3/3 |
| Gen3 Speed + EQ | PASS | 速率完成、TS边界、EQ Phase 0～3 |
| CDR loss fallback | PASS | 回退并锁存错误 |
| malformed/illegal TS reject | PASS | 拒绝并进入安全回退 |
| K12 integration regression | PASS | 7/7 |

K13 仿真测试名：

- `production_gen3_speed_eq_path`
- `production_cdr_loss_fallback`
- `production_bad_ts_rejects`

## 3. 当前边界和未完成项

当前验证的是生产控制器本身，不是完整 Gen3 Endpoint。生产顶层
`kcu105_pcie_ep_gen1_top` 仍需完成以下接线后，才可生成 K13 bit：

1. 将 `k09_tlp_test_top` / `k11a_offline_top` 的 Retrain 脉冲和目标速率引出；
2. 从生产 LTSSM 引出完整 Ordered Set 检查所需的 TS1/TS2、Lane/Link、Rate 和完成边界；
3. 将 K13 输出与现有 Gen1 PHY 控制线做参数化 mux，确认 `K13_ENABLE=0` 与 K11 逐拍等价；
4. 接入真实 PHY 的 CDR loss、`phystatus`、TX/RX EQ done 反馈；
5. 运行真实 PHY VCS Gen1→Gen3、Vivado 综合/实现，再进行 KCU105 Gen3 枚举、BAR 和 reboot 验证。

因此本记录不产生 bit、不烧写远端设备，也不改变 K11 release 基线。
