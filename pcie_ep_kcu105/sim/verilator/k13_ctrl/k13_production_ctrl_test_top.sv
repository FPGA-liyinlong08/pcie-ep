module k13_production_ctrl_test_top (
    input wire core_clk, input wire phy_clk,
    input wire core_rst_n, input wire phy_rst_n,
    input wire retrain_pulse, input wire [1:0] target_speed,
    input wire force_cdr_lost, input wire force_ts_bad,
    output wire [1:0] phy_rate, output wire [1:0] negotiated_speed,
    output wire [2:0] speed_state, output wire eq_active, output wire eq_done,
    output wire eq_failed, output wire [2:0] eq_phase,
    output wire traffic_quiesce, output wire [1:0] txeq_ctrl,
    output wire [1:0] rxeq_ctrl, output wire ts_reject,
    output wire cdr_loss_sticky, output wire fallback_sticky
);
    reg link_up;
    reg [1:0] partner_rate;
    reg [1:0] os_count;
    reg phystatus_r, ts_valid_r, ts_complete_r, ts_is_ts1_r, ts_is_ts2_r;
    reg [1:0] ts_rate_r;
    reg tx_done_r, rx_done_r;

    wire [1:0] ctrl_rate;
    wire ctrl_txelecidle;
    wire [1:0] ctrl_txeq_ctrl, ctrl_rxeq_ctrl;
    wire [3:0] ctrl_txeq_preset, ctrl_rxeq_txpreset;
    wire [5:0] ctrl_txeq_coeff;
    wire ctrl_ts_accept;
    wire ctrl_recovery_active;
    wire ctrl_eq_done, ctrl_eq_failed;

    pcie_k13_production_ctrl #(.K13_ENABLE(1), .SPEED_TIMEOUT_CYCLES(8),
                               .EQ_TIMEOUT_CYCLES(8)) dut (
        .core_clk(core_clk), .core_rst_n(core_rst_n),
        .phy_clk(phy_clk), .phy_rst_n(phy_rst_n), .link_up(link_up),
        .retrain_pulse(retrain_pulse), .target_speed(target_speed),
        .phy_phystatus(phystatus_r), .phy_cdr_lost(force_cdr_lost),
        .phy_txeq_done(tx_done_r), .phy_rxeq_done(rx_done_r),
        .ts_valid(ts_valid_r), .ts_complete(ts_complete_r),
        .ts_is_ts1(ts_is_ts1_r), .ts_is_ts2(ts_is_ts2_r),
        .ts_lane(3'd0), .ts_link(8'd0), .ts_rate(ts_rate_r),
        .ts_eq_request(1'b0), .expected_lane(3'd0), .expected_link(8'd0),
        .phy_rate(ctrl_rate), .phy_txelecidle(ctrl_txelecidle),
        .phy_txeq_ctrl(ctrl_txeq_ctrl), .phy_txeq_preset(ctrl_txeq_preset),
        .phy_txeq_coeff(ctrl_txeq_coeff), .phy_rxeq_ctrl(ctrl_rxeq_ctrl),
        .phy_rxeq_txpreset(ctrl_rxeq_txpreset),
        .traffic_quiesce(traffic_quiesce), .recovery_active(ctrl_recovery_active),
        .negotiated_speed(negotiated_speed), .speed_state(speed_state),
        .eq_active(eq_active), .eq_done(ctrl_eq_done), .eq_failed(ctrl_eq_failed),
        .eq_phase(eq_phase), .ts_accept(ctrl_ts_accept), .ts_reject(ts_reject),
        .cdr_loss_sticky(cdr_loss_sticky), .fallback_sticky(fallback_sticky),
        .illegal_ts_sticky()
    );

    always @(posedge phy_clk or negedge phy_rst_n) begin
        if (!phy_rst_n) begin
            link_up <= 1'b0;
            partner_rate <= 2'b00;
            os_count <= 2'd0;
            phystatus_r <= 1'b0;
            ts_valid_r <= 1'b0;
            ts_complete_r <= 1'b0;
            ts_is_ts1_r <= 1'b0;
            ts_is_ts2_r <= 1'b0;
            ts_rate_r <= 2'b00;
            tx_done_r <= 1'b0;
            rx_done_r <= 1'b0;
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
            if ((ctrl_rate != partner_rate) && (os_count == 2'd3)) begin
                partner_rate <= ctrl_rate;
                phystatus_r <= 1'b1;
            end
            if ((speed_state == 3'd3) && (os_count == 2'd3)) begin
                ts_valid_r <= 1'b1;
                ts_complete_r <= 1'b1;
                ts_is_ts1_r <= !force_ts_bad;
                ts_is_ts2_r <= force_ts_bad;
                ts_rate_r <= force_ts_bad ? 2'b11 : ctrl_rate;
            end
            if (ctrl_txeq_ctrl != 2'b00 && os_count == 2'd3)
                tx_done_r <= 1'b1;
            if (ctrl_rxeq_ctrl != 2'b00 && os_count == 2'd3)
                rx_done_r <= 1'b1;
        end
    end

    assign phy_rate = ctrl_rate;
    assign txeq_ctrl = ctrl_txeq_ctrl;
    assign rxeq_ctrl = ctrl_rxeq_ctrl;
    assign eq_done = ctrl_eq_done;
    assign eq_failed = ctrl_eq_failed;
endmodule
