// K12集成行为PHY Partner：连接K12-A mailbox、K12-B Speed和K12-C EQ。
// Partner只在Ordered Set边界产生phystatus/EQ done，供集成Checker验证边界契约。
module k12_behavioral_partner_top (
    input wire core_clk, input wire phy_clk,
    input wire core_rst_n, input wire phy_rst_n,
    input wire link_up,
    input wire core_retrain_pulse, input wire [1:0] core_target_speed,
    input wire eq_start,
    input wire force_peer_reject, input wire force_eq_timeout,
    input wire force_early_done, input wire force_cdr_lost,
    input wire force_ts_malformed, input wire force_ts_lane_mismatch,
    output wire mailbox_busy, output wire mailbox_valid,
    output wire [1:0] mailbox_target_speed,
    output wire [2:0] speed_state, output wire [1:0] phy_rate,
    output wire speed_retrain_accept, output wire [1:0] negotiated_speed,
    output wire speed_fallback_taken, output wire speed_timeout,
    output wire eq_start_accept, output wire eq_active, output wire eq_done,
    output wire eq_failed, output wire [2:0] eq_phase,
    output wire [1:0] txeq_ctrl, output wire [3:0] txeq_preset,
    output wire [5:0] txeq_coeff, output wire [1:0] rxeq_ctrl,
    output wire [3:0] rxeq_txpreset,
    output wire phy_phystatus, output wire phy_txeq_done,
    output wire phy_rxeq_adapt_done, output wire phy_rxeq_done,
    output wire os_tx_complete,
    output wire boundary_violation,
    output wire illegal_speed, output wire illegal_eq_param,
    output wire cdr_loss_seen, output wire ts_accept, output wire ts_reject,
    output wire ts_malformed, output wire ts_illegal_rate,
    output wire ts_lane_link_mismatch
);
    wire mailbox_busy_w, mailbox_valid_w;
    wire [1:0] mailbox_speed_w;
    wire mailbox_accept_w;
    wire [1:0] negotiated_speed_w;
    wire [2:0] speed_state_w;
    wire [1:0] phy_rate_w;
    wire phy_phystatus_w, peer_speed_ok_w, peer_speed_reject_w;
    wire speed_timeout_w, illegal_speed_w, speed_fallback_w, illegal_eq_param_w;
    wire cdr_loss_w;
    wire ts_accept_w, ts_reject_w, ts_malformed_w, ts_illegal_rate_w;
    wire ts_lane_link_mismatch_w;
    wire eq_start_accept_w, eq_active_w, eq_done_w, eq_failed_w;
    wire [2:0] eq_phase_w;
    wire [1:0] txeq_ctrl_w, rxeq_ctrl_w;
    wire [3:0] txeq_preset_w, rxeq_txpreset_w;
    wire [5:0] txeq_coeff_w;
    wire phy_txeq_done_w, phy_rxeq_adapt_done_w, phy_rxeq_done_w;

    pcie_retrain_cdc_mailbox u_mailbox (
        .s_clk(core_clk), .s_rst_n(core_rst_n),
        .s_retrain_pulse(core_retrain_pulse),
        .s_target_speed(core_target_speed), .s_busy(mailbox_busy_w),
        .s_overflow_sticky(),
        .d_clk(phy_clk), .d_rst_n(phy_rst_n),
        .d_retrain_valid(mailbox_valid_w),
        .d_target_speed(mailbox_speed_w),
        .d_retrain_accept(mailbox_accept_w)
    );

    pcie_recovery_speed_ctrl #(.SPEED_TIMEOUT_CYCLES(8)) u_speed (
        .clk(phy_clk), .rst_n(phy_rst_n), .link_up(link_up),
        .retrain_valid(mailbox_valid_w),
        .retrain_target_speed(mailbox_speed_w),
        .ltssm_speed_ready(os_tx_complete_r),
        .retrain_accept(mailbox_accept_w),
        .phy_phystatus(phy_phystatus_w),
        .phy_cdr_lost(force_cdr_lost), .peer_speed_ok(peer_speed_ok_w),
        .peer_speed_reject(peer_speed_reject_w),
        .state(speed_state_w), .phy_rate(phy_rate_w),
        .phy_txelecidle(), .traffic_quiesce(), .recovery_active(),
        .negotiated_speed(negotiated_speed_w),
        .speed_timeout_sticky(speed_timeout_w),
        .peer_reject_sticky(), .illegal_speed_sticky(illegal_speed_w),
        .cdr_loss_sticky(cdr_loss_w), .fallback_taken_sticky(speed_fallback_w)
    );

    pcie_equalization_ctrl #(.EQ_TIMEOUT_CYCLES(8)) u_eq (
        .clk(phy_clk), .rst_n(phy_rst_n && !force_cdr_lost), .eq_start(eq_start),
        .target_speed(negotiated_speed_w), .tx_preset(4'd4),
        .tx_coeff(6'd12), .tx_coeff_valid(1'b1),
        .rx_txpreset(4'd5), .rx_preset_valid(1'b1),
        .phy_txeq_done(phy_txeq_done_w),
        .phy_rxeq_adapt_done(phy_rxeq_adapt_done_w),
        .phy_rxeq_done(phy_rxeq_done_w),
        .eq_start_accept(eq_start_accept_w), .eq_active(eq_active_w),
        .eq_done(eq_done_w), .eq_failed(eq_failed_w), .phase(eq_phase_w),
        .phy_txeq_ctrl(txeq_ctrl_w), .phy_txeq_preset(txeq_preset_w),
        .phy_txeq_coeff(txeq_coeff_w), .phy_rxeq_ctrl(rxeq_ctrl_w),
        .phy_rxeq_txpreset(rxeq_txpreset_w),
        .illegal_param_sticky(illegal_eq_param_w),
        .phase_timeout_sticky()
    );

    reg [1:0] partner_rate;
    reg rate_pending;
    reg [2:0] rate_delay;
    reg [1:0] os_count;
    reg os_tx_complete_r;
    reg phy_phystatus_r;
    reg phy_txeq_done_r, phy_rxeq_adapt_done_r, phy_rxeq_done_r;
    reg boundary_violation_r;
    reg peer_ts_valid_r, peer_ts_complete_r, peer_ts_is_ts1_r, peer_ts_is_ts2_r;
    reg [2:0] peer_ts_lane_r;
    reg [7:0] peer_ts_link_r;
    reg [1:0] peer_ts_rate_r;
    reg peer_ts_eq_request_r;

    assign phy_phystatus_w = phy_phystatus_r;
    assign phy_txeq_done_w = phy_txeq_done_r;
    assign phy_rxeq_adapt_done_w = phy_rxeq_adapt_done_r;
    assign phy_rxeq_done_w = phy_rxeq_done_r;

    pcie_recovery_ts_guard u_ts_guard (
        .clk(phy_clk), .rst_n(phy_rst_n),
        .ts_valid(peer_ts_valid_r), .ts_complete(peer_ts_complete_r),
        .ts_is_ts1(peer_ts_is_ts1_r), .ts_is_ts2(peer_ts_is_ts2_r),
        .ts_lane(peer_ts_lane_r), .ts_link(peer_ts_link_r),
        .ts_rate(peer_ts_rate_r), .expected_rate(mailbox_speed_w),
        .ts_eq_request(peer_ts_eq_request_r),
        .expected_lane(3'd0), .expected_link(8'd0),
        .ts_accept(ts_accept_w), .ts_reject(ts_reject_w),
        .malformed_sticky(ts_malformed_w),
        .illegal_rate_sticky(ts_illegal_rate_w),
        .lane_link_mismatch_sticky(ts_lane_link_mismatch_w)
    );
    assign peer_speed_ok_w = ts_accept_w;
    assign peer_speed_reject_w = ts_reject_w;

    always @(posedge phy_clk or negedge phy_rst_n) begin
        if (!phy_rst_n) begin
            partner_rate <= 2'b00;
            rate_pending <= 1'b0;
            rate_delay <= 3'd0;
            os_count <= 2'd0;
            os_tx_complete_r <= 1'b0;
            phy_phystatus_r <= 1'b0;
            phy_txeq_done_r <= 1'b0;
            phy_rxeq_adapt_done_r <= 1'b0;
            phy_rxeq_done_r <= 1'b0;
            boundary_violation_r <= 1'b0;
            peer_ts_valid_r <= 1'b0;
            peer_ts_complete_r <= 1'b0;
            peer_ts_is_ts1_r <= 1'b0;
            peer_ts_is_ts2_r <= 1'b0;
            peer_ts_lane_r <= 3'd0;
            peer_ts_link_r <= 8'd0;
            peer_ts_rate_r <= 2'd0;
            peer_ts_eq_request_r <= 1'b0;
        end else begin
            os_tx_complete_r <= (os_count == 2'd3);
            os_count <= os_count + 1'b1;
            phy_phystatus_r <= 1'b0;
            phy_txeq_done_r <= 1'b0;
            phy_rxeq_adapt_done_r <= 1'b0;
            phy_rxeq_done_r <= 1'b0;
            peer_ts_valid_r <= 1'b0;
            peer_ts_complete_r <= 1'b0;
            peer_ts_is_ts1_r <= 1'b0;
            peer_ts_is_ts2_r <= 1'b0;

            if (phy_rate_w != partner_rate) begin
                rate_pending <= 1'b1;
                if ((rate_pending && os_tx_complete_r) || force_early_done) begin
                    partner_rate <= phy_rate_w;
                    phy_phystatus_r <= 1'b1;
                    rate_pending <= 1'b0;
                    if (!os_tx_complete_r && force_early_done)
                        boundary_violation_r <= 1'b1;
                end else if (rate_delay != 3'd7) begin
                    rate_delay <= rate_delay + 1'b1;
                end
            end else begin
                rate_pending <= 1'b0;
                rate_delay <= 3'd0;
            end

            if (speed_state_w == 3'd3 && os_tx_complete_r) begin
                peer_ts_valid_r <= 1'b1;
                peer_ts_complete_r <= 1'b1;
                peer_ts_is_ts1_r <= 1'b1;
                peer_ts_is_ts2_r <= force_peer_reject || force_ts_malformed;
                peer_ts_lane_r <= force_ts_lane_mismatch ? 3'd1 : 3'd0;
                peer_ts_link_r <= 8'd0;
                peer_ts_rate_r <= force_ts_malformed ? 2'b11 : phy_rate_w;
                peer_ts_eq_request_r <= 1'b0;
            end

            if (txeq_ctrl_w != 2'b00) begin
                if (force_early_done || (!force_eq_timeout && os_tx_complete_r)) begin
                    phy_txeq_done_r <= 1'b1;
                    if (!os_tx_complete_r && force_early_done)
                        boundary_violation_r <= 1'b1;
                end
            end
            if (rxeq_ctrl_w != 2'b00) begin
                if (force_early_done || (!force_eq_timeout && os_tx_complete_r)) begin
                    phy_rxeq_done_r <= 1'b1;
                    phy_rxeq_adapt_done_r <= 1'b1;
                    if (!os_tx_complete_r && force_early_done)
                        boundary_violation_r <= 1'b1;
                end
            end

            // 负向测试开关的语义是强制 Partner 越过 Ordered Set 边界完成。
            // 独立置位 sticky，避免测试结果依赖故障注入恰好落在哪个采样相位。
            if (force_early_done && ((phy_rate_w != partner_rate) ||
                                     (txeq_ctrl_w != 2'b00) ||
                                     (rxeq_ctrl_w != 2'b00)))
                boundary_violation_r <= 1'b1;
        end
    end

    assign mailbox_busy = mailbox_busy_w;
    assign mailbox_valid = mailbox_valid_w;
    assign mailbox_target_speed = mailbox_speed_w;
    assign speed_state = speed_state_w;
    assign phy_rate = phy_rate_w;
    assign speed_retrain_accept = mailbox_accept_w;
    assign negotiated_speed = negotiated_speed_w;
    assign speed_fallback_taken = speed_fallback_w;
    assign speed_timeout = speed_timeout_w;
    assign eq_start_accept = eq_start_accept_w;
    assign eq_active = eq_active_w;
    assign eq_done = eq_done_w;
    assign eq_failed = eq_failed_w;
    assign eq_phase = eq_phase_w;
    assign txeq_ctrl = txeq_ctrl_w;
    assign txeq_preset = txeq_preset_w;
    assign txeq_coeff = txeq_coeff_w;
    assign rxeq_ctrl = rxeq_ctrl_w;
    assign rxeq_txpreset = rxeq_txpreset_w;
    assign phy_phystatus = phy_phystatus_w;
    assign phy_txeq_done = phy_txeq_done_w;
    assign phy_rxeq_adapt_done = phy_rxeq_adapt_done_w;
    assign phy_rxeq_done = phy_rxeq_done_w;
    assign os_tx_complete = os_tx_complete_r;
    assign boundary_violation = boundary_violation_r;
    assign illegal_speed = illegal_speed_w;
    assign illegal_eq_param = illegal_eq_param_w;
    assign cdr_loss_seen = cdr_loss_w;
    assign ts_accept = ts_accept_w;
    assign ts_reject = ts_reject_w;
    assign ts_malformed = ts_malformed_w;
    assign ts_illegal_rate = ts_illegal_rate_w;
    assign ts_lane_link_mismatch = ts_lane_link_mismatch_w;
endmodule
