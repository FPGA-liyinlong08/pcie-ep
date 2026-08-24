//-----------------------------------------------------------------------------
// K13 production_ctrl 集成 testbench wrapper (针对新 rate contract 架构)
//
// 简化 PHY / partner LTSSM 应答模型：
//   - 检测 phy_rate_cmd 变化 → 1 cycle 之后驱动 phy_phystatus=1 (PHY 完成)
//   - 检测 speed_state 进入 ST_RECOVERY_IDLE (3'd4) → 驱动 TS accept
//   - 检测 phy_txeq_ctrl / phy_rxeq_ctrl 变化 → 驱动对应 done
//
// 与 K12 旧版 wrapper 的差异 (vs k13_production_ctrl_test_top.sv):
//   1. .phy_rate(.) → .phy_rate_cmd(.) + .active_rate(.) (新 contract 接口)
//   2. TS 触发从 state==3 (ST_SPEED_WAIT) 改为 state==4 (ST_RECOVERY_IDLE)
//      新架构下 RATE_WAIT 只等 contract 内部 completion；TS 只在
//      RECOVERY_IDLE 才语义上有意义
//-----------------------------------------------------------------------------
module k13_production_ctrl_test_top #(
    parameter integer K13_RXEQ_BOOTSTRAP = 1,
    parameter integer K13_RXEQ_TWO_PASS = 0,
    parameter integer GEN1_RELEASE_GAP_CYCLES = 4,
    parameter integer TS_HOLD_CYCLES = 16
) (
    input wire core_clk, input wire phy_clk,
    input wire core_rst_n, input wire phy_rst_n,
    input wire retrain_pulse, input wire [1:0] target_speed,
    input wire force_cdr_lost, input wire force_ts_bad,
    input wire force_rx_done_without_adapt,
    // 暴露给 cocotb 的观察信号 (新接口)
    output wire [1:0] phy_rate_cmd, output wire [1:0] active_rate,
    output wire [1:0] requested_rate,
    output wire [1:0] negotiated_speed,
    output wire phy_txelecidle,
    output wire [2:0] speed_state, output wire eq_active, output wire eq_done,
    output wire eq_failed, output wire [2:0] eq_phase,
    output wire traffic_quiesce, output wire [1:0] txeq_ctrl,
    output wire [1:0] rxeq_ctrl, output wire ts_reject,
    output wire rxeq_bootstrap_enabled,
    output wire cdr_loss_sticky, output wire fallback_sticky,
    output wire recovery_speed_done,
    // 新增 contract 调试信号
    output wire [3:0] rate_contract_state,
    output wire       rate_contract_busy,
    output wire       rate_contract_done,
    output wire       rate_contract_failed,
    output wire       rate_contract_illegal
);
    reg link_up;
    reg [1:0] partner_rate;
    reg [1:0] os_count;
    reg [1:0] phystatus_hold;   // 2-cycle 计数器，匹配 contract 的 2-cycle 上升沿检测
    // TS 应答延迟：state==4 进入后等待 TS_HOLD_CYCLES 拍再驱动 TS，
    // 给 post_rate_rxeq (4 cycle) + EQ start 留时间
    reg [3:0] ts_hold;
    reg ts_ready;               // ts_hold 计数到 0 后才允许驱动 TS
    reg phystatus_r, ts_valid_r, ts_complete_r, ts_is_ts1_r, ts_is_ts2_r;
    reg [1:0] ts_rate_r;
    reg tx_done_r, rx_done_r, rx_adapt_done_r;

    wire [1:0] ctrl_phy_rate_cmd, ctrl_active_rate, ctrl_requested_rate;
    wire ctrl_txelecidle;
    wire [1:0] ctrl_txeq_ctrl, ctrl_rxeq_ctrl;
    wire [3:0] ctrl_txeq_preset, ctrl_rxeq_txpreset;
    wire [5:0] ctrl_txeq_coeff;
    wire ctrl_ts_accept;
    wire ctrl_recovery_active;
    wire ctrl_eq_done, ctrl_eq_failed;
    wire ctrl_rate_busy, ctrl_rate_done, ctrl_rate_failed;
    wire [3:0] ctrl_rate_state;
    // LTSSM 准备好条件：speed ctrl 处于 ST_QUIESCE (3'd1) 且 PHY 已 settle
    wire ltssm_speed_ready = ctrl_recovery_active &&
                             (speed_state == 3'd1) && (os_count == 2'd3);

    pcie_k13_production_ctrl #(.K13_ENABLE(1),
                               .K13_RXEQ_BOOTSTRAP(K13_RXEQ_BOOTSTRAP),
                               .K13_RXEQ_TWO_PASS(K13_RXEQ_TWO_PASS),
                               .K13_PROTOCOL_EQ_ENABLE(0),
                               .GEN3_TX_SETTLE_CYCLES(1),
                               // EQ phases are deliberately serialized after
                               // the rate operation; leave the semantic
                               // Recovery.Speed wait window long enough for
                               // all four PHY acknowledgements in this model.
                               .SPEED_TIMEOUT_CYCLES(128),
                               .EQ_TIMEOUT_CYCLES(16),
                               .GEN1_RELEASE_GAP_CYCLES(GEN1_RELEASE_GAP_CYCLES)) dut (
        .core_clk(core_clk), .core_rst_n(core_rst_n),
        .phy_clk(phy_clk), .phy_rst_n(phy_rst_n), .link_up(link_up),
        .reinitialize_gen1(1'b0),
        .ltssm_speed_ready(ltssm_speed_ready),
        .retrain_pulse(retrain_pulse), .target_speed(target_speed),
        .partner_retrain_valid(1'b0), .partner_target_speed(2'b00),
        .phy_phystatus(phystatus_r), .phy_cdr_lost(force_cdr_lost),
        .phy_txeq_done(tx_done_r),
        .phy_rxeq_adapt_done(rx_adapt_done_r), .phy_rxeq_done(rx_done_r),
        .ts_valid(ts_valid_r), .ts_complete(ts_complete_r),
        .ts_is_ts1(ts_is_ts1_r), .ts_is_ts2(ts_is_ts2_r),
        .ts_lane(3'd0), .ts_link(8'd0), .ts_rate(ts_rate_r),
        .ts_eq_request(1'b0), .ts_eq_control(8'd0), .ts_eq_data(24'd0),
        .tx_eq_ts_complete(1'b0),
        .expected_lane(3'd0), .expected_link(8'd0),
        // === 新 contract 接口 ===
        .phy_rate_cmd(ctrl_phy_rate_cmd),
        .active_rate(ctrl_active_rate),
        .requested_rate(ctrl_requested_rate),
        .phy_txelecidle(ctrl_txelecidle),
        .phy_txeq_ctrl(ctrl_txeq_ctrl), .phy_txeq_preset(ctrl_txeq_preset),
        .phy_txeq_coeff(ctrl_txeq_coeff), .phy_rxeq_ctrl(ctrl_rxeq_ctrl),
        .phy_rxeq_txpreset(ctrl_rxeq_txpreset),
        .traffic_quiesce(traffic_quiesce), .recovery_active(ctrl_recovery_active),
        .negotiated_speed(negotiated_speed), .speed_state(speed_state),
        .eq_active(eq_active), .eq_done(ctrl_eq_done), .eq_failed(ctrl_eq_failed),
        .eq_phase(eq_phase), .ts_accept(ctrl_ts_accept), .ts_reject(ts_reject),
        .cdr_loss_sticky(cdr_loss_sticky), .speed_timeout_sticky(),
        .fallback_sticky(fallback_sticky),
        .illegal_ts_sticky(),
        .recovery_speed_done(recovery_speed_done),
        // === contract 调试信号 ===
        .rate_contract_state(ctrl_rate_state),
        .rate_contract_busy(ctrl_rate_busy),
        .rate_contract_done(ctrl_rate_done),
        .rate_contract_failed(ctrl_rate_failed),
        .rate_contract_illegal(rate_contract_illegal)
    );

    assign requested_rate = ctrl_requested_rate;

    always @(posedge phy_clk or negedge phy_rst_n) begin
        if (!phy_rst_n) begin
            link_up <= 1'b0;
            partner_rate <= 2'b00;
            os_count <= 2'd0;
            phystatus_hold <= 2'd0;
            ts_hold <= 4'd0;
            ts_ready <= 1'b0;
            phystatus_r <= 1'b0;
            ts_valid_r <= 1'b0;
            ts_complete_r <= 1'b0;
            ts_is_ts1_r <= 1'b0;
            ts_is_ts2_r <= 1'b0;
            ts_rate_r <= 2'b00;
            tx_done_r <= 1'b0;
            rx_done_r <= 1'b0;
            rx_adapt_done_r <= 1'b0;
        end else begin
            link_up <= 1'b1;
            os_count <= os_count + 1'b1;
            phystatus_r <= 1'b0;
            ts_valid_r <= 1'b0;
            ts_complete_r <= 1'b0;
            ts_is_ts1_r <= 1'b0;
            ts_is_ts2_r <= 1'b0;
            tx_done_r <= 1'b0;
            rx_done_r <= 1'b0;
            // PHY 完成应答：raw phy_rate_cmd 变化 → 拉 phystatus 2 拍
            // (匹配 contract 的 2-cycle 上升沿检测 phy_phystatus & ~prev)
            if ((ctrl_phy_rate_cmd != partner_rate) && (os_count == 2'd3)) begin
                partner_rate <= ctrl_phy_rate_cmd;
                phystatus_r <= 1'b1;
                phystatus_hold <= 2'd2;
            end else if (phystatus_hold != 2'd0) begin
                phystatus_r <= 1'b1;
                phystatus_hold <= phystatus_hold - 1'b1;
            end
            // TS 应答：state==4 进入后等 TS_HOLD_CYCLES 拍再驱动 TS
            // (给 post_rate_rxeq 4 cycle + EQ start 留时间)
            if (speed_state == 3'd4) begin
                if (ts_hold < TS_HOLD_CYCLES[3:0])
                    ts_hold <= ts_hold + 1'b1;
                if (ts_hold == TS_HOLD_CYCLES[3:0])
                    ts_ready <= 1'b1;
            end else begin
                ts_hold  <= 4'd0;
                ts_ready <= 1'b0;
            end
            if (ts_ready && (os_count == 2'd3)) begin
                ts_valid_r <= 1'b1;
                ts_complete_r <= 1'b1;
                ts_is_ts1_r <= !force_ts_bad;
                ts_is_ts2_r <= force_ts_bad;
                ts_rate_r <= force_ts_bad ? 2'b11 : ctrl_phy_rate_cmd;
            end
            if (ctrl_txeq_ctrl != 2'b00 && os_count == 2'd3)
                tx_done_r <= 1'b1;
            // PG239 RXEQ=10 requires both indications.  This responder
            // intentionally models them independently so a done-only pulse
            // cannot create a false EQ pass.
            // Keep the PHY completion indication asserted while the command
            // is active.  This models a sampled PG239 completion level and
            // avoids losing a one-cycle pulse at the phase hand-off edge.
            if (ctrl_rxeq_ctrl == 2'b10) begin
                rx_done_r <= 1'b1;
                rx_adapt_done_r <= !force_rx_done_without_adapt;
            end
        end
    end

    assign phy_rate_cmd = ctrl_phy_rate_cmd;
    assign active_rate  = ctrl_active_rate;
    assign phy_txelecidle = ctrl_txelecidle;
    assign txeq_ctrl = ctrl_txeq_ctrl;
    assign rxeq_ctrl = ctrl_rxeq_ctrl;
    assign rxeq_bootstrap_enabled = (K13_RXEQ_BOOTSTRAP != 0);
    assign eq_done = ctrl_eq_done;
    assign eq_failed = ctrl_eq_failed;
    assign rate_contract_state = ctrl_rate_state;
    assign rate_contract_busy = ctrl_rate_busy;
    assign rate_contract_done = ctrl_rate_done;
    assign rate_contract_failed = ctrl_rate_failed;
endmodule
