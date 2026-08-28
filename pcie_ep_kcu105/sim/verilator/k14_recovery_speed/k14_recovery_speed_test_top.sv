`timescale 1ns/1ps
`default_nettype none

module k14_recovery_speed_test_top (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       retrain_valid,
    input  wire [1:0] retrain_target,
    input  wire       retrain_rearm,
    input  wire       retrain_accept_enable,
    input  wire       ltssm_speed_ready,
    input  wire       phy_phystatus,
    input  wire       peer_speed_ok,
    input  wire       reinitialize_gen1,
    output wire [2:0] speed_state,
    output wire [3:0] rate_state,
    output wire [1:0] active_rate,
    output wire [1:0] requested_rate,
    output wire [1:0] negotiated_speed,
    output wire       traffic_quiesce,
    output wire       recovery_active,
    output wire       retrain_accept,
    output wire       retrain_pending,
    output wire       retrain_armed,
    output wire       rate_done,
    output wire [2:0] rate_result,
    output wire [1:0] phy_rate,
    output wire [1:0] phy_powerdown,
    output wire       phy_txelecidle,
    output wire       phy_txdetectrx,
    output wire       as_mac_in_detect,
    output wire       as_cdr_hold_req,
    output wire       fallback_taken
);
    wire rate_req_valid, rate_req_ready, rate_busy;
    wire [1:0] rate_req_target;
    wire fallback_req;
    wire speed_timeout, peer_reject, illegal_speed, cdr_loss;
    wire rate_success = rate_done && (rate_result == 3'd1);
    wire rate_failed = rate_done && (rate_result != 3'd0) &&
                       (rate_result != 3'd1);
    wire [1:0] pending_target;
    wire controller_retrain_accept;
    wire [1:0] phy_txeq_ctrl_w;
    reg phy_txeq_done_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) phy_txeq_done_q <= 1'b0;
        else phy_txeq_done_q <= (phy_txeq_ctrl_w != 2'b00);
    end

    pcie_partner_retrain_pending u_partner_pending (
        .clk(clk), .rst_n(rst_n),
        .request_valid(retrain_valid), .request_target(retrain_target),
        .rearm(retrain_rearm),
        .accept(controller_retrain_accept),
        .pending(retrain_pending), .pending_target(pending_target),
        .armed(retrain_armed)
    );

    assign retrain_accept = controller_retrain_accept;

    pcie_recovery_speed_ctrl #(.SPEED_TIMEOUT_CYCLES(24)) u_speed (
        .clk(clk), .rst_n(rst_n), .link_up(1'b1),
        .reinitialize_gen1(reinitialize_gen1),
        .retrain_valid(retrain_pending && retrain_accept_enable),
        .retrain_target_speed(pending_target),
        .ltssm_speed_ready(ltssm_speed_ready),
        .rate_req_valid(rate_req_valid), .rate_req_target(rate_req_target),
        .fallback_req(fallback_req), .rate_req_ready(rate_req_ready),
        .rate_op_done(rate_success), .rate_op_failed(rate_failed),
        .active_rate(active_rate), .requested_rate(requested_rate),
        .retrain_accept(controller_retrain_accept), .phy_cdr_lost(1'b0),
        .peer_speed_ok(peer_speed_ok), .peer_speed_reject(1'b0),
        .state(speed_state), .traffic_quiesce(traffic_quiesce),
        .recovery_active(recovery_active),
        .negotiated_speed(negotiated_speed),
        .speed_timeout_sticky(speed_timeout),
        .peer_reject_sticky(peer_reject),
        .illegal_speed_sticky(illegal_speed),
        .cdr_loss_sticky(cdr_loss),
        .fallback_taken_sticky(fallback_taken)
    );

    pcie_phy_command_ctrl #(
        .GOLDEN_RELEASE_GAP_CYCLES(4),
        .RATE_TIMEOUT_CYCLES(12),
        .GEN3_TX_SETTLE_CYCLES(2)
    ) u_command (
        .phy_pclk(clk), .pipe_rst_n(rst_n),
        .cmd_profile(recovery_active ? 3'd5 : 3'd4),
        .op_valid(1'b0), .op_kind(1'b0), .op_ready(), .op_done(),
        .op_result(), .rate_req_valid(rate_req_valid),
        .rate_req_target(rate_req_target),
        .rate_abort(reinitialize_gen1 || rate_failed),
        .rate_req_ready(rate_req_ready), .rate_busy(rate_busy),
        .rate_done(rate_done), .rate_result(rate_result),
        .active_rate(active_rate), .rate_state(rate_state),
        .eq_req_valid(1'b0), .eq_req_kind(3'd0),
        .eq_req_preset(4'd0), .eq_req_coeff(18'd0),
        .eq_req_ready(), .eq_busy(), .eq_done(), .eq_result(),
        .eq_rsp_preset_sel(), .eq_rsp_coeff(),
        .phy_phystatus(phy_phystatus), .phy_rxstatus(3'b000),
        .phy_txeq_fs(6'd0), .phy_txeq_lf(6'd0),
        .phy_txeq_new_coeff(18'd0), .phy_txeq_done(phy_txeq_done_q),
        .phy_rxeq_preset_sel(1'b0), .phy_rxeq_new_txcoeff(18'd0),
        .phy_rxeq_adapt_done(1'b0), .phy_rxeq_done(1'b0),
        .phy_powerdown(phy_powerdown), .phy_txdetectrx(phy_txdetectrx),
        .phy_txelecidle(phy_txelecidle), .phy_rate(phy_rate),
        .phy_txeq_ctrl(phy_txeq_ctrl_w), .phy_txeq_preset(), .phy_txeq_coeff(),
        .phy_rxeq_ctrl(), .phy_rxeq_txpreset(),
        .as_mac_in_detect(as_mac_in_detect),
        .as_cdr_hold_req(as_cdr_hold_req), .phy_txcompliance(),
        .phy_rxpolarity(), .phy_txmargin(), .phy_txswing(), .phy_txdeemph()
    );

    wire _unused = &{1'b0, rate_busy, fallback_req, speed_timeout,
                     peer_reject, illegal_speed, cdr_loss};
endmodule

`default_nettype wire
