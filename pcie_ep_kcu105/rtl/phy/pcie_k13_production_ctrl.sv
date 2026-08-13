`timescale 1ns/1ps
`default_nettype none

// K13生产接线层：把K12-A/B/C/D控制器组合成一个可关闭的PHY控制单元。
// K13_ENABLE=0时，所有控制输出保持K11 Gen1安全值；启用后才接受Retrain。
module pcie_k13_production_ctrl #(
    parameter integer K13_ENABLE = 0,
    // 250 MHz PIPE下分别为4 ms；行为仿真继续通过参数覆盖缩短。
    parameter integer SPEED_TIMEOUT_CYCLES = 1_000_000,
    parameter integer EQ_TIMEOUT_CYCLES = 1_000_000
) (
    input wire       core_clk,
    input wire       core_rst_n,
    input wire       phy_clk,
    input wire       phy_rst_n,
    input wire       link_up,
    input wire       ltssm_speed_ready,
    input wire       retrain_pulse,
    input wire [1:0] target_speed,
    input wire       phy_phystatus,
    input wire       phy_cdr_lost,
    input wire       phy_txeq_done,
    input wire       phy_rxeq_done,
    input wire       ts_valid,
    input wire       ts_complete,
    input wire       ts_is_ts1,
    input wire       ts_is_ts2,
    input wire [2:0] ts_lane,
    input wire [7:0] ts_link,
    input wire [1:0] ts_rate,
    input wire       ts_eq_request,
    input wire [2:0] expected_lane,
    input wire [7:0] expected_link,
    output wire [1:0] phy_rate,
    output wire       phy_txelecidle,
    output wire [1:0] phy_txeq_ctrl,
    output wire [3:0] phy_txeq_preset,
    output wire [5:0] phy_txeq_coeff,
    output wire [1:0] phy_rxeq_ctrl,
    output wire [3:0] phy_rxeq_txpreset,
    output wire       traffic_quiesce,
    output wire       recovery_active,
    output wire [1:0] negotiated_speed,
    output wire [2:0] speed_state,
    output wire       eq_active,
    output wire       eq_done,
    output wire       eq_failed,
    output wire [2:0] eq_phase,
    output wire       ts_accept,
    output wire       ts_reject,
    output wire       cdr_loss_sticky,
    output wire       speed_timeout_sticky,
    output wire       fallback_sticky,
    output wire       illegal_ts_sticky
);
    wire mailbox_busy, mailbox_valid, mailbox_accept;
    wire [1:0] mailbox_target;
    wire speed_timeout, peer_reject, illegal_speed, speed_cdr_loss;
    wire speed_fallback;
    wire ts_malformed, ts_illegal_rate, ts_lane_link_mismatch;
    wire eq_start_accept, eq_illegal_param, eq_phase_timeout;
    wire [1:0] speed_phy_rate;
    wire speed_txelecidle, speed_quiesce, speed_recovery_active;
    wire [1:0] speed_negotiated;
    wire [2:0] speed_state_w;
    wire ts_accept_w, ts_reject_w;
    reg eq_start_q;

    generate if (K13_ENABLE != 0) begin : g_k13_enabled
        pcie_retrain_cdc_mailbox u_mailbox (
            .s_clk(core_clk), .s_rst_n(core_rst_n),
            .s_retrain_pulse(retrain_pulse), .s_target_speed(target_speed),
            .s_busy(mailbox_busy), .s_overflow_sticky(),
            .d_clk(phy_clk), .d_rst_n(phy_rst_n),
            .d_retrain_valid(mailbox_valid), .d_target_speed(mailbox_target),
            .d_retrain_accept(mailbox_accept)
        );

        pcie_recovery_ts_guard u_ts_guard (
            .clk(phy_clk), .rst_n(phy_rst_n),
            .ts_valid(ts_valid), .ts_complete(ts_complete),
            .ts_is_ts1(ts_is_ts1), .ts_is_ts2(ts_is_ts2),
            .ts_lane(ts_lane), .ts_link(ts_link), .ts_rate(ts_rate),
            .expected_rate(mailbox_target),
            .ts_eq_request(ts_eq_request), .expected_lane(expected_lane),
            .expected_link(expected_link), .ts_accept(ts_accept_w),
            .ts_reject(ts_reject_w), .malformed_sticky(ts_malformed),
            .illegal_rate_sticky(ts_illegal_rate),
            .lane_link_mismatch_sticky(ts_lane_link_mismatch)
        );

        pcie_recovery_speed_ctrl #(
            .SPEED_TIMEOUT_CYCLES(SPEED_TIMEOUT_CYCLES)
        ) u_speed (
            .clk(phy_clk), .rst_n(phy_rst_n), .link_up(link_up),
            .retrain_valid(mailbox_valid), .retrain_target_speed(mailbox_target),
            .ltssm_speed_ready(ltssm_speed_ready),
            .retrain_accept(mailbox_accept), .phy_phystatus(phy_phystatus),
            .phy_cdr_lost(phy_cdr_lost), .peer_speed_ok(ts_accept_w),
            .peer_speed_reject(ts_reject_w), .state(speed_state_w),
            .phy_rate(speed_phy_rate), .phy_txelecidle(speed_txelecidle),
            .traffic_quiesce(speed_quiesce),
            .recovery_active(speed_recovery_active),
            .negotiated_speed(speed_negotiated),
            .speed_timeout_sticky(speed_timeout),
            .peer_reject_sticky(peer_reject),
            .illegal_speed_sticky(illegal_speed),
            .cdr_loss_sticky(speed_cdr_loss),
            .fallback_taken_sticky(speed_fallback)
        );

        always @(posedge phy_clk or negedge phy_rst_n) begin
            if (!phy_rst_n)
                eq_start_q <= 1'b0;
            else begin
                eq_start_q <= 1'b0;
                if ((speed_state_w == 3'd3) && (mailbox_target == 2'b10) &&
                    ts_accept_w && !eq_active && !eq_done && !eq_failed)
                    eq_start_q <= 1'b1;
            end
        end

        pcie_equalization_ctrl #(
            .EQ_TIMEOUT_CYCLES(EQ_TIMEOUT_CYCLES)
        ) u_eq (
            .clk(phy_clk), .rst_n(phy_rst_n && !speed_cdr_loss),
            .eq_start(eq_start_q), .target_speed(mailbox_target),
            .tx_preset(4'd4), .tx_coeff(6'd12), .tx_coeff_valid(1'b1),
            .rx_txpreset(4'd5), .rx_preset_valid(1'b1),
            .phy_txeq_done(phy_txeq_done), .phy_rxeq_done(phy_rxeq_done),
            .eq_start_accept(eq_start_accept), .eq_active(eq_active),
            .eq_done(eq_done), .eq_failed(eq_failed), .phase(eq_phase),
            .phy_txeq_ctrl(phy_txeq_ctrl), .phy_txeq_preset(phy_txeq_preset),
            .phy_txeq_coeff(phy_txeq_coeff), .phy_rxeq_ctrl(phy_rxeq_ctrl),
            .phy_rxeq_txpreset(phy_rxeq_txpreset),
            .illegal_param_sticky(eq_illegal_param),
            .phase_timeout_sticky(eq_phase_timeout)
        );
    end else begin : g_k13_disabled
        assign mailbox_busy = 1'b0;
        assign mailbox_valid = 1'b0;
        assign mailbox_accept = 1'b0;
        assign mailbox_target = 2'b00;
        assign speed_phy_rate = 2'b00;
        assign speed_txelecidle = 1'b0;
        assign speed_quiesce = 1'b0;
        assign speed_recovery_active = 1'b0;
        assign speed_negotiated = 2'b00;
        assign speed_state_w = 3'd0;
        assign ts_accept_w = 1'b0;
        assign ts_reject_w = 1'b0;
        assign ts_malformed = 1'b0;
        assign ts_illegal_rate = 1'b0;
        assign ts_lane_link_mismatch = 1'b0;
        assign speed_timeout = 1'b0;
        assign peer_reject = 1'b0;
        assign illegal_speed = 1'b0;
        assign speed_cdr_loss = 1'b0;
        assign speed_fallback = 1'b0;
        assign eq_start_q = 1'b0;
        assign eq_start_accept = 1'b0;
        assign eq_active = 1'b0;
        assign eq_done = 1'b0;
        assign eq_failed = 1'b0;
        assign eq_phase = 3'd7;
        assign phy_txeq_ctrl = 2'b00;
        assign phy_txeq_preset = 4'd0;
        assign phy_txeq_coeff = 6'd0;
        assign phy_rxeq_ctrl = 2'b00;
        assign phy_rxeq_txpreset = 4'd0;
        assign eq_illegal_param = 1'b0;
        assign eq_phase_timeout = 1'b0;
    end endgenerate

    assign phy_rate = speed_phy_rate;
    assign phy_txelecidle = speed_txelecidle;
    assign traffic_quiesce = speed_quiesce || eq_active;
    assign recovery_active = speed_recovery_active || eq_active;
    assign negotiated_speed = speed_negotiated;
    assign speed_state = speed_state_w;
    assign ts_accept = ts_accept_w;
    assign ts_reject = ts_reject_w;
    assign cdr_loss_sticky = speed_cdr_loss;
    assign speed_timeout_sticky = speed_timeout;
    assign fallback_sticky = speed_fallback;
    assign illegal_ts_sticky = ts_malformed || ts_illegal_rate ||
                                ts_lane_link_mismatch;
endmodule

`default_nettype wire
