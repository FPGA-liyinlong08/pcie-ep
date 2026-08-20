`timescale 1ns/1ps
`default_nettype none

// K13 production-path integration harness.  The DUT is the real LTSSM plus
// the real K13 controller and the same boundary muxes used by the board top.
// Gen1 PIPE input is driven by cocotb; after Rate=Gen3, a separate ordered-set
// transmitter acts as the behavioral PHY partner.
module k13_ltssm_partner_top #(
    parameter integer K13_RXEQ_BOOTSTRAP = 1
) (
    input  wire        phy_pclk,
    input  wire        core_clk,
    input  wire        pipe_rst_n,
    input  wire        core_rst_n,

    input  wire [31:0] phy_rxdata,
    input  wire [1:0]  phy_rxdatak,
    input  wire        phy_rxdata_valid,
    input  wire        phy_rxstart_block,
    input  wire [1:0]  phy_rxsync_header,
    input  wire        phy_rxvalid,
    input  wire        phy_phystatus,
    input  wire        phy_rxelecidle,
    input  wire [2:0]  phy_rxstatus,
    input  wire        phy_cdr_lost,
    input  wire        phy_txeq_done,
    input  wire        phy_rxeq_adapt_done,
    input  wire        phy_rxeq_done,
    input  wire        retrain_pulse,
    input  wire [1:0]  target_speed,
    input  wire        gen3_partner_enable,

    output wire [31:0] phy_txdata,
    output wire [1:0]  phy_txdatak,
    output wire        phy_txdata_valid,
    output wire        phy_txstart_block,
    output wire [1:0]  phy_txsync_header,
    output wire        phy_txdetectrx,
    output wire        phy_txelecidle,
    output wire [1:0]  phy_powerdown,
    output wire [1:0]  phy_rate,
    output wire [1:0]  phy_txeq_ctrl,
    output wire [1:0]  phy_rxeq_ctrl,
    output wire [5:0]  ltssm_state,
    output wire        link_up,
    output wire [2:0]  negotiated_width,
    output wire [1:0]  negotiated_speed,
    output wire [1:0]  phy_rate_cmd,
    output wire [1:0]  active_rate,
    output wire [4:0]  rx_ts_count,
    output wire [31:0] training_error_count,
    output wire [31:0] timeout_count,
    output wire [2:0]  speed_state,
    output wire        recovery_active,
    output wire        as_cdr_hold_req,
    output wire        eq_active,
    output wire        eq_done,
    output wire        eq_failed,
    output wire [2:0]  eq_phase,
    output wire        ts_accept,
    output wire        ts_reject,
    output wire        fallback_sticky,
    output wire        recovery_speed_ready,
    output wire        recovery_speed_done,
    output wire        reinitialize_gen1,
    output wire [3:0]  rate_contract_state,
    output wire        partner_source_active,
    output wire        os_ts1_valid,
    output wire        os_ts2_valid,
    output wire        os_malformed
);
    wire [7:0] link_number, os_link_number, os_lane_number;
    wire [7:0] os_rate_id, os_training_control;
    wire [7:0] os_eq_control;
    wire [23:0] os_eq_data;
    wire os_tx_complete;
    wire [1:0] ltssm_phy_rate;
    wire ltssm_phy_txelecidle;
    wire [1:0] ltssm_txeq_ctrl, ltssm_rxeq_ctrl;
    wire [3:0] ltssm_txeq_preset, ltssm_rxeq_txpreset;
    wire [5:0] ltssm_txeq_coeff;
    wire phy_txcompliance, phy_rxpolarity;
    wire [2:0] phy_txmargin;
    wire phy_txswing, phy_txdeemph;
    wire as_mac_in_detect;
    wire [15:0] rx_pkt_data;
    wire [1:0] rx_pkt_keep;
    wire rx_pkt_valid, rx_pkt_sop, rx_pkt_eop, rx_pkt_is_dllp;
    wire [3:0] rx_pkt_error;
    wire tx_pkt_ready;

    wire [1:0] k13_rate, k13_active_rate, k13_requested_rate,
               k13_txeq_ctrl, k13_rxeq_ctrl;
    wire k13_txelecidle, traffic_quiesce;
    wire [1:0] phy_rate_w, phy_txeq_ctrl_w, phy_rxeq_ctrl_w;
    wire phy_txelecidle_w;
    wire [3:0] k13_txeq_preset, k13_rxeq_txpreset;
    wire [5:0] k13_txeq_coeff;
    wire [1:0] k13_negotiated_speed;
    wire cdr_loss_sticky, speed_timeout_sticky, illegal_ts_sticky;
    wire k13_recovery_speed_done;
    wire [3:0] k13_rate_contract_state;
    wire k13_rate_contract_busy, k13_rate_contract_done,
         k13_rate_contract_failed, k13_rate_contract_illegal;
    // In the OFF A/B harness, EQ begins in the same cycle as Recovery.Idle.
    // Use the registered speed-state indication for LTSSM force-recovery so
    // that this test-only mux does not create a zero-time EQ feedback loop.
    wire harness_recovery_force = (K13_RXEQ_BOOTSTRAP == 0) ?
                                   (speed_state != 3'd0) : recovery_active;
    // The partner source is selected only from registered state.  This keeps
    // the Gen1 cocotb source and the Gen3 ordered-set source from forming a
    // combinational parser/mux loop at the Recovery boundary.
    reg partner_enable_q;
    reg [1:0] partner_mode_q;
    always @(posedge phy_pclk or negedge pipe_rst_n) begin
        if (!pipe_rst_n) begin
            partner_enable_q <= 1'b0;
            partner_mode_q <= 2'd1;
        end else begin
            partner_enable_q <= gen3_partner_enable &&
                                (k13_active_rate == 2'b10);
            if (ltssm_state == 6'd12)
                partner_mode_q <= 2'd2;
            else if (ltssm_state == 6'd11)
                partner_mode_q <= 2'd1;
        end
    end
    wire partner_enable = partner_enable_q;
    wire [31:0] partner_data;
    wire partner_valid, partner_start;
    wire [1:0] partner_header;

    pcie_gen3_os_tx u_partner_tx (
        .clk(phy_pclk), .rst_n(pipe_rst_n), .enable(partner_enable),
        .mode(partner_mode_q), .link_number(link_number), .link_is_pad(1'b0),
        .lane_number(8'd0), .lane_is_pad(1'b0), .n_fts(8'hff),
        .rate_id(8'h0e), .training_control(8'h00),
        .out_data(partner_data), .out_valid(partner_valid),
        .start_block(partner_start), .sync_header(partner_header),
        .os_complete(), .word_index_debug()
    );

    wire [31:0] lt_rxdata = partner_enable ? partner_data : phy_rxdata;
    wire [1:0] lt_rxdatak = partner_enable ? 2'b00 : phy_rxdatak;
    wire lt_rxdata_valid = partner_enable ? partner_valid : phy_rxdata_valid;
    wire lt_rxstart_block = partner_enable ? partner_start : phy_rxstart_block;
    wire [1:0] lt_rxsync_header = partner_enable ? partner_header :
                                                           phy_rxsync_header;
    wire lt_rxvalid = partner_enable ? partner_valid : phy_rxvalid;
    wire lt_rxelecidle = partner_enable ? !partner_valid : phy_rxelecidle;

    function [1:0] decode_ts_rate(input [7:0] raw_rate_id);
        begin
            if (raw_rate_id[3]) decode_ts_rate = 2'b10;
            else if (raw_rate_id[2]) decode_ts_rate = 2'b01;
            else if (raw_rate_id[1]) decode_ts_rate = 2'b00;
            else decode_ts_rate = 2'b11;
        end
    endfunction

    wire partner_retrain_valid = link_up && os_ts1_valid && os_rate_id[7] &&
                                  (decode_ts_rate(os_rate_id) != 2'b11);

    pcie_k13_production_ctrl #(
        .K13_ENABLE(1), .K13_RXEQ_BOOTSTRAP(K13_RXEQ_BOOTSTRAP),
        .SPEED_TIMEOUT_CYCLES(4096),
        .EQ_TIMEOUT_CYCLES(64)
    ) u_k13_ctrl (
        .core_clk(core_clk), .core_rst_n(core_rst_n),
        .phy_clk(phy_pclk), .phy_rst_n(pipe_rst_n), .link_up(link_up),
        .ltssm_speed_ready(recovery_speed_ready),
        .retrain_pulse(retrain_pulse), .target_speed(target_speed),
        .partner_retrain_valid(partner_retrain_valid),
        .partner_target_speed(decode_ts_rate(os_rate_id)),
        .phy_phystatus(phy_phystatus), .phy_cdr_lost(phy_cdr_lost),
        .phy_txeq_done(phy_txeq_done),
        .phy_rxeq_adapt_done(phy_rxeq_adapt_done),
        .phy_rxeq_done(phy_rxeq_done),
        .ts_valid(os_ts1_valid || os_ts2_valid),
        .ts_complete(os_ts1_valid || os_ts2_valid),
        .ts_is_ts1(os_ts1_valid), .ts_is_ts2(os_ts2_valid),
        .ts_lane(os_lane_number[2:0]), .ts_link(os_link_number),
        .ts_rate(decode_ts_rate(os_rate_id)),
        .ts_eq_request((os_ts1_valid || os_ts2_valid) &&
                       ((os_eq_control != 8'd0) || (os_eq_data != 24'd0))),
        .expected_lane(3'd0), .expected_link(link_number),
        .reinitialize_gen1(as_mac_in_detect),
        .phy_rate_cmd(k13_rate), .active_rate(k13_active_rate),
        .requested_rate(k13_requested_rate),
        .phy_txelecidle(k13_txelecidle),
        .phy_txeq_ctrl(k13_txeq_ctrl), .phy_txeq_preset(k13_txeq_preset),
        .phy_txeq_coeff(k13_txeq_coeff), .phy_rxeq_ctrl(k13_rxeq_ctrl),
        .phy_rxeq_txpreset(k13_rxeq_txpreset),
        .traffic_quiesce(traffic_quiesce), .recovery_active(recovery_active),
        .recovery_speed_done(k13_recovery_speed_done),
        .rate_contract_state(k13_rate_contract_state),
        .rate_contract_busy(k13_rate_contract_busy),
        .rate_contract_done(k13_rate_contract_done),
        .rate_contract_failed(k13_rate_contract_failed),
        .rate_contract_illegal(k13_rate_contract_illegal),
        .negotiated_speed(k13_negotiated_speed), .speed_state(speed_state),
        .eq_active(eq_active), .eq_done(eq_done), .eq_failed(eq_failed),
        .eq_phase(eq_phase), .ts_accept(ts_accept), .ts_reject(ts_reject),
        .cdr_loss_sticky(cdr_loss_sticky),
        .speed_timeout_sticky(speed_timeout_sticky),
        .fallback_sticky(fallback_sticky),
        .illegal_ts_sticky(illegal_ts_sticky)
    );

    assign phy_rate_w = k13_rate;
    assign phy_txelecidle_w = recovery_active ? k13_txelecidle :
                                              ltssm_phy_txelecidle;
    assign phy_txeq_ctrl_w = recovery_active ? k13_txeq_ctrl : ltssm_txeq_ctrl;
    assign phy_rxeq_ctrl_w = recovery_active ? k13_rxeq_ctrl : ltssm_rxeq_ctrl;
    assign phy_rate = phy_rate_w;
    assign phy_rate_cmd = phy_rate_w;
    assign active_rate = k13_active_rate;
    assign recovery_speed_done = k13_recovery_speed_done;
    assign reinitialize_gen1 = as_mac_in_detect;
    assign rate_contract_state = k13_rate_contract_state;
    assign partner_source_active = partner_enable;
    assign phy_txelecidle = phy_txelecidle_w;
    assign phy_txeq_ctrl = phy_txeq_ctrl_w;
    assign phy_rxeq_ctrl = phy_rxeq_ctrl_w;
    assign negotiated_speed = (k13_negotiated_speed != 2'b00) ?
                              k13_negotiated_speed : 2'b00;

    pcie_ltssm_mac_gen1 #(
        .DETECT_QUIET_CYCLES(4), .DETECT_TIMEOUT_CYCLES(64),
        .TRAIN_TIMEOUT_CYCLES(10000), .HOT_RESET_CYCLES(8),
        .TX_RATE_ID(8'h0e)
    ) u_ltssm (
        .phy_pclk(phy_pclk), .pipe_rst_n(pipe_rst_n),
        .phy_rxdata(lt_rxdata), .phy_rxdatak(lt_rxdatak),
        .phy_rxdata_valid(lt_rxdata_valid),
        .phy_rxstart_block(lt_rxstart_block),
        .phy_rxsync_header(lt_rxsync_header), .phy_rxvalid(lt_rxvalid),
        .phy_phystatus(phy_phystatus), .phy_rxelecidle(lt_rxelecidle),
        .phy_rxstatus(phy_rxstatus),
        .active_phy_rate(k13_active_rate),
        .recovery_target_rate(k13_requested_rate),
        .phy_txdata(phy_txdata), .phy_txdatak(phy_txdatak),
        .phy_txdata_valid(phy_txdata_valid),
        .phy_txstart_block(phy_txstart_block),
        .phy_txsync_header(phy_txsync_header),
        .phy_txdetectrx(phy_txdetectrx),
        .phy_txelecidle(ltssm_phy_txelecidle),
        .phy_txcompliance(phy_txcompliance), .phy_rxpolarity(phy_rxpolarity),
        .phy_powerdown(phy_powerdown), .phy_rate(ltssm_phy_rate),
        .phy_txmargin(phy_txmargin), .phy_txswing(phy_txswing),
        .phy_txdeemph(phy_txdeemph), .phy_txeq_ctrl(ltssm_txeq_ctrl),
        .phy_txeq_preset(ltssm_txeq_preset),
        .phy_txeq_coeff(ltssm_txeq_coeff), .phy_rxeq_ctrl(ltssm_rxeq_ctrl),
        .phy_rxeq_txpreset(ltssm_rxeq_txpreset),
        .as_mac_in_detect(as_mac_in_detect),
        .as_cdr_hold_req(as_cdr_hold_req), .tx_pkt_valid(1'b0),
        .tx_pkt_ready(tx_pkt_ready), .tx_pkt_data(16'd0),
        .tx_pkt_keep(2'd0), .tx_pkt_sop(1'b0), .tx_pkt_eop(1'b0),
        .tx_pkt_is_dllp(1'b0), .tx_pkt_bad(1'b0),
        .rx_pkt_valid(rx_pkt_valid), .rx_pkt_data(rx_pkt_data),
        .rx_pkt_keep(rx_pkt_keep), .rx_pkt_sop(rx_pkt_sop),
        .rx_pkt_eop(rx_pkt_eop), .rx_pkt_is_dllp(rx_pkt_is_dllp),
        .rx_pkt_error(rx_pkt_error), .link_disable(1'b0),
        .hot_reset_req(1'b0), .force_recovery(harness_recovery_force),
        .speed_retrain_active(harness_recovery_force),
        .recovery_speed_done(k13_recovery_speed_done),
        .recovery_speed_ready(recovery_speed_ready),
        .ltssm_state(ltssm_state), .link_up(link_up),
        .negotiated_width(negotiated_width), .negotiated_speed(),
        .link_number(link_number), .rx_ts_count(rx_ts_count),
        .training_error_count(training_error_count),
        .timeout_count(timeout_count), .frame_error_count(),
        .hot_reset_seen(), .os_ts1_valid(os_ts1_valid),
        .os_ts2_valid(os_ts2_valid), .os_malformed(os_malformed),
        .os_link_number(os_link_number), .os_lane_number(os_lane_number),
        .os_rate_id(os_rate_id),
        .os_training_control(os_training_control),
        .os_tx_complete(os_tx_complete),
        .os_eq_control(os_eq_control), .os_eq_data(os_eq_data)
    );

    wire _unused = &{1'b0, traffic_quiesce, cdr_loss_sticky,
        speed_timeout_sticky, illegal_ts_sticky, phy_txcompliance,
        phy_rxpolarity, phy_txmargin, phy_txswing, phy_txdeemph,
        as_mac_in_detect, as_cdr_hold_req, k13_txeq_preset,
        k13_txeq_coeff, k13_rxeq_txpreset, ltssm_txeq_preset,
        ltssm_txeq_coeff, ltssm_rxeq_txpreset, rx_pkt_valid, rx_pkt_data,
        rx_pkt_keep, rx_pkt_sop, rx_pkt_eop, rx_pkt_is_dllp, rx_pkt_error,
        tx_pkt_ready, os_training_control, os_tx_complete,
        k13_rate_contract_busy, k13_rate_contract_done,
        k13_rate_contract_failed, k13_rate_contract_illegal};
endmodule

`default_nettype wire
