# K13 Gate C 阻塞 — os_rx 按数据源 mux 未解 (2026-08-20)

## 状态
- Gate C (LTSSM 集成验证) 阻塞中
- 分支: `k13_phy_rate_contract`
- 提交: `a21bc9f modify: k13 fast-fallback + Gate B wrapper, 8+4+9 验证全过` 之后

## 已落地 (此 commit 范围内)
1. `pcie_ltssm_mac_gen1.sv` 新增 parameter `K13_TEST_GEN1_OS_ONLY=0`
   - 加在 parameter list (line 25),port list 干净
   - 控制 `os_ts1_valid / os_ts2_valid / os_link_number / os_lane_number / os_rate_id / os_malformed` 全部走 Gen1 os_rx 旁路 Gen3
2. `k13_ltssm_partner_top.sv` 用 `.K13_TEST_GEN1_OS_ONLY(1)` parameter override
3. Verilator 编译通过,组合环路 ("Active region did not converge") 消除
4. Gate C 两条测试 `production_ltssm_gen1_to_gen3_eq_closed_loop` 与
   `partner_initiated_speed_change_closes_recovery_and_eq` 仍在跑,但断言挂在
   `assert int(dut.phy_rate.value) == 2` (实际 0)

## 阻塞根因
| 数据源 | 格式 | Gen1 os_rx 能否解析 |
|--------|------|---------------------|
| testbench `phy_rxdata` | 16-bit Gen1 symbols,无 sync_header | ✅ |
| partner `partner_data` (RECOVERY_SPEED/RECOVERY_IDLE) | 32-bit 块 + sync_header + 加扰 | ❌ |

`K13_TEST_GEN1_OS_ONLY=1` 让两种数据源都走 Gen1 os_rx → partner 那侧
`rx_ts_count=0` → `speed contract rate_done` 不拉高 → `active_phy_rate` 卡 0
→ `phy_rate` 永远 0。

之前尝试的方案:
- 按 `ltssm_state` mux Gen1/Gen3 os_rx → 组合环路 (`ltssm_state → partner_enable
  → os_rx 选择 → ltssm_state`) — 弃
- 寄存器化 `ltssm_state_d` 选择 os_rx — 仍报告环路 — 弃
- 当前用全局 parameter `K13_TEST_GEN1_OS_ONLY` — 解决了环路但留下数据源不匹配

## 解决方向 (待用户选)
- (A) 寄存器化 `ltssm_state_d` 决定 os_rx mux (低风险,多寄存器)
- (B) partner top 内 `pcie_gen3_os_rx` 解 partner → `pcie_gen1_os_tx` 重编喂 DUT
  (解耦干净,需确认 rx_status 反馈链路)
- (C) 改测试:partner 也发 Gen1 格式 (放弃混源,简单但偏离 Gate C 目的)

## 上板前约束
- `K13_TEST_GEN1_OS_ONLY` 必须保持 0 (生产路径)
- parameter 只是为了 K13 集成测试期闭环验证,RTL 不污染生产配置
