`timescale 1ps/1ps
`default_nettype none

// K12-E真实PHY影子适配器：只观测K11生产顶层的PHY反馈，不驱动生产控制线。
// 目的：确认K12控制器可在真实PHY时钟/反馈接口下展开，并保证Gen1 release时
// 所有升速/EQ命令保持关闭。真正的Gen3 retrain/EQ驱动留给生产LTSSM接线门。
module k12e_phy_monitor (
    input wire       clk,
    input wire       rst_n,
    input wire       link_up,
    input wire [1:0] phy_rate,
    input wire       phy_phystatus,
    input wire       phy_txeq_done,
    input wire       phy_rxeq_done,
    input wire [1:0] phy_txeq_ctrl,
    input wire [1:0] phy_rxeq_ctrl
);
    wire [2:0] speed_state;
    wire [1:0] shadow_rate_cmd, shadow_active_rate;
    wire shadow_rate_req_valid, shadow_fallback_req, shadow_rate_req_ready;
    wire [1:0] shadow_rate_req_target;
    wire shadow_rate_done, shadow_rate_failed;
    wire shadow_retrain_accept, shadow_quiesce, shadow_active;
    wire [1:0] shadow_negotiated_speed;
    wire shadow_speed_timeout, shadow_peer_reject, shadow_illegal_speed;
    wire shadow_cdr_loss, shadow_fallback;
    wire shadow_eq_start_accept, shadow_eq_active, shadow_eq_done, shadow_eq_failed;
    wire [2:0] shadow_eq_phase;
    wire [1:0] shadow_txeq_ctrl, shadow_rxeq_ctrl;
    wire [3:0] shadow_txeq_preset, shadow_rxeq_txpreset;
    wire [5:0] shadow_txeq_coeff;
    wire shadow_illegal_param, shadow_phase_timeout;
    reg [4:0] stable_count;
    reg reported;

    pcie_recovery_speed_ctrl u_shadow_speed (
        .clk(clk), .rst_n(rst_n), .link_up(link_up),
        .reinitialize_gen1(1'b0),
        .retrain_valid(1'b0), .retrain_target_speed(2'b00),
        .ltssm_speed_ready(1'b1),
        .rate_req_valid(shadow_rate_req_valid),
        .rate_req_target(shadow_rate_req_target),
        .fallback_req(shadow_fallback_req),
        .rate_req_ready(shadow_rate_req_ready),
        .rate_op_done(shadow_rate_done), .rate_op_failed(shadow_rate_failed),
        .active_rate(shadow_active_rate),
        .retrain_accept(shadow_retrain_accept),
        .phy_cdr_lost(1'b0), .peer_speed_ok(1'b0), .peer_speed_reject(1'b0),
        .state(speed_state),
        .traffic_quiesce(shadow_quiesce), .recovery_active(shadow_active),
        .negotiated_speed(shadow_negotiated_speed),
        .speed_timeout_sticky(shadow_speed_timeout),
        .peer_reject_sticky(shadow_peer_reject),
        .illegal_speed_sticky(shadow_illegal_speed),
        .cdr_loss_sticky(shadow_cdr_loss),
        .fallback_taken_sticky(shadow_fallback)
    );

    pcie_phy_rate_contract u_shadow_rate_contract (
        .clk(clk), .rst_n(rst_n), .link_ready(link_up),
        .reinitialize_gen1(1'b0),
        .rate_req_valid(shadow_rate_req_valid),
        .rate_req_target(shadow_rate_req_target),
        .fallback_req(shadow_fallback_req),
        .rate_req_ready(shadow_rate_req_ready),
        .phy_phystatus(phy_phystatus),
        .phy_rate_cmd(shadow_rate_cmd), .force_txelecidle(),
        .active_rate(shadow_active_rate), .rate_busy(),
        .rate_done(shadow_rate_done), .rate_failed(shadow_rate_failed),
        .dbg_state(), .phystatus_seen(), .timeout_sticky()
    );

    pcie_equalization_ctrl u_shadow_eq (
        .clk(clk), .rst_n(rst_n), .eq_start(1'b0), .target_speed(2'b00),
        .tx_preset(4'd0), .tx_coeff(6'd0), .tx_coeff_valid(1'b0),
        .rx_txpreset(4'd0), .rx_preset_valid(1'b0),
        .phy_txeq_done(phy_txeq_done),
        .phy_rxeq_adapt_done(1'b0), .phy_rxeq_done(phy_rxeq_done),
        .eq_start_accept(shadow_eq_start_accept), .eq_active(shadow_eq_active),
        .eq_done(shadow_eq_done), .eq_failed(shadow_eq_failed),
        .phase(shadow_eq_phase), .phy_txeq_ctrl(shadow_txeq_ctrl),
        .phy_txeq_preset(shadow_txeq_preset), .phy_txeq_coeff(shadow_txeq_coeff),
        .phy_rxeq_ctrl(shadow_rxeq_ctrl),
        .phy_rxeq_txpreset(shadow_rxeq_txpreset),
        .illegal_param_sticky(shadow_illegal_param),
        .phase_timeout_sticky(shadow_phase_timeout)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stable_count <= 5'd0;
            reported <= 1'b0;
        end else if (!reported) begin
            if (link_up && (phy_rate == 2'b00) &&
                (phy_txeq_ctrl == 2'b00) && (phy_rxeq_ctrl == 2'b00) &&
                (phy_phystatus === 1'b0 || phy_phystatus === 1'b1) &&
                (phy_txeq_done === 1'b0 || phy_txeq_done === 1'b1) &&
                (phy_rxeq_done === 1'b0 || phy_rxeq_done === 1'b1) &&
                (shadow_rate_cmd == 2'b00) &&
                (shadow_active_rate == 2'b00) && !shadow_eq_active) begin
                if (stable_count == 5'd15) begin
                    reported <= 1'b1;
                    $display("K12E_REAL_PHY_ADAPTER_PASS gen1_phy_feedback=known eq_controls=zero");
                end else begin
                    stable_count <= stable_count + 1'b1;
                end
            end else begin
                stable_count <= 5'd0;
            end
        end
    end
endmodule

`default_nettype wire
