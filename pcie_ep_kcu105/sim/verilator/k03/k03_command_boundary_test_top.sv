`timescale 1ns/1ps
`default_nettype none

// Legacy raw-command view for K03 regression only.  Production K03 uses the
// semantic command interface instantiated below.
module k03_command_boundary_test_top #(
    parameter integer DETECT_QUIET_CYCLES = 4,
    parameter integer DETECT_TIMEOUT_CYCLES = 64,
    parameter integer TRAIN_TIMEOUT_CYCLES = 10000,
    parameter integer HOT_RESET_CYCLES = 8,
    parameter integer G9_WAIT_REMOTE_DETECT = 0,
    parameter integer G9_WAIT_REMOTE_DETECT_CYCLES = 32
) (
    input wire phy_pclk, input wire pipe_rst_n,
    input wire [31:0] phy_rxdata, input wire [1:0] phy_rxdatak,
    input wire phy_rxdata_valid, input wire phy_rxstart_block,
    input wire [1:0] phy_rxsync_header, input wire phy_rxvalid,
    input wire phy_phystatus, input wire phy_rxelecidle,
    input wire [2:0] phy_rxstatus, input wire [1:0] active_phy_rate,
    output wire [31:0] phy_txdata, output wire [1:0] phy_txdatak,
    output wire phy_txdata_valid, output wire phy_txstart_block,
    output wire [1:0] phy_txsync_header,
    output wire phy_txdetectrx, output wire phy_txelecidle,
    output wire phy_txcompliance, output wire phy_rxpolarity,
    output wire [1:0] phy_powerdown, output wire [1:0] phy_rate,
    output wire [2:0] phy_txmargin, output wire phy_txswing,
    output wire phy_txdeemph, output wire [1:0] phy_txeq_ctrl,
    output wire [3:0] phy_txeq_preset, output wire [5:0] phy_txeq_coeff,
    output wire [1:0] phy_rxeq_ctrl, output wire [3:0] phy_rxeq_txpreset,
    output wire as_mac_in_detect, output wire as_cdr_hold_req,
    input wire tx_pkt_valid, output wire tx_pkt_ready,
    input wire [15:0] tx_pkt_data, input wire [1:0] tx_pkt_keep,
    input wire tx_pkt_sop, input wire tx_pkt_eop,
    input wire tx_pkt_is_dllp, input wire tx_pkt_bad,
    output wire rx_pkt_valid, output wire [15:0] rx_pkt_data,
    output wire [1:0] rx_pkt_keep, output wire rx_pkt_sop,
    output wire rx_pkt_eop, output wire rx_pkt_is_dllp,
    output wire [3:0] rx_pkt_error,
    input wire link_disable, input wire hot_reset_req,
    input wire force_recovery, input wire speed_retrain_active,
    input wire recovery_speed_done, output wire recovery_speed_ready,
    output wire [5:0] ltssm_state, output wire link_up,
    output wire [2:0] negotiated_width, output wire [1:0] negotiated_speed,
    output wire [7:0] link_number, output wire [4:0] rx_ts_count,
    output wire [31:0] training_error_count,
    output wire [31:0] timeout_count, output wire [31:0] frame_error_count,
    output wire hot_reset_seen
);
    wire [2:0] cmd_profile;
    wire cmd_valid, cmd_kind, cmd_ready, cmd_done;
    wire [1:0] cmd_result;

    pcie_phy_command_ctrl u_phy_command_ctrl (
        .phy_pclk(phy_pclk), .pipe_rst_n(pipe_rst_n),
        .cmd_profile(cmd_profile), .op_valid(cmd_valid), .op_kind(cmd_kind),
        .op_ready(cmd_ready), .op_done(cmd_done), .op_result(cmd_result),
        .rate_req_valid(1'b0), .rate_req_target(2'b00),
        .rate_abort(1'b0), .rate_req_ready(), .rate_busy(),
        .rate_done(), .rate_result(), .active_rate(), .rate_state(),
        .phy_phystatus(phy_phystatus), .phy_rxstatus(phy_rxstatus),
        .phy_powerdown(phy_powerdown), .phy_txdetectrx(phy_txdetectrx),
        .phy_txelecidle(phy_txelecidle), .phy_rate(phy_rate),
        .phy_txeq_ctrl(phy_txeq_ctrl), .phy_txeq_preset(phy_txeq_preset),
        .phy_txeq_coeff(phy_txeq_coeff), .phy_rxeq_ctrl(phy_rxeq_ctrl),
        .phy_rxeq_txpreset(phy_rxeq_txpreset),
        .as_mac_in_detect(as_mac_in_detect),
        .as_cdr_hold_req(as_cdr_hold_req),
        .phy_txcompliance(phy_txcompliance), .phy_rxpolarity(phy_rxpolarity),
        .phy_txmargin(phy_txmargin), .phy_txswing(phy_txswing),
        .phy_txdeemph(phy_txdeemph)
    );

    pcie_ltssm_mac_gen1 #(
        .DETECT_QUIET_CYCLES(DETECT_QUIET_CYCLES),
        .DETECT_TIMEOUT_CYCLES(DETECT_TIMEOUT_CYCLES),
        .TRAIN_TIMEOUT_CYCLES(TRAIN_TIMEOUT_CYCLES),
        .HOT_RESET_CYCLES(HOT_RESET_CYCLES),
        .G9_WAIT_REMOTE_DETECT(G9_WAIT_REMOTE_DETECT),
        .G9_WAIT_REMOTE_DETECT_CYCLES(G9_WAIT_REMOTE_DETECT_CYCLES)
    ) u_ltssm_mac (
        .phy_pclk(phy_pclk), .pipe_rst_n(pipe_rst_n),
        .phy_rxdata(phy_rxdata), .phy_rxdatak(phy_rxdatak),
        .phy_rxdata_valid(phy_rxdata_valid), .phy_rxstart_block(phy_rxstart_block),
        .phy_rxsync_header(phy_rxsync_header), .phy_rxvalid(phy_rxvalid),
        .phy_rxelecidle(phy_rxelecidle),
        .phy_cmd_profile(cmd_profile), .phy_cmd_valid(cmd_valid),
        .phy_cmd_kind(cmd_kind), .phy_cmd_ready(cmd_ready),
        .phy_cmd_done(cmd_done), .phy_cmd_result(cmd_result),
        .active_phy_rate(active_phy_rate), .recovery_target_rate(2'b00),
        .recovery_fallback_active(1'b0), .gen3_tx_eq_control(8'h01),
        .gen3_tx_eq_data(24'h8a0c28), .gen3_protocol_eq_complete(1'b0),
        .phy_txdata(phy_txdata), .phy_txdatak(phy_txdatak),
        .phy_txdata_valid(phy_txdata_valid), .phy_txstart_block(phy_txstart_block),
        .phy_txsync_header(phy_txsync_header),
        .tx_pkt_valid(tx_pkt_valid), .tx_pkt_ready(tx_pkt_ready),
        .tx_pkt_data(tx_pkt_data), .tx_pkt_keep(tx_pkt_keep),
        .tx_pkt_sop(tx_pkt_sop), .tx_pkt_eop(tx_pkt_eop),
        .tx_pkt_is_dllp(tx_pkt_is_dllp), .tx_pkt_bad(tx_pkt_bad),
        .rx_pkt_valid(rx_pkt_valid), .rx_pkt_data(rx_pkt_data),
        .rx_pkt_keep(rx_pkt_keep), .rx_pkt_sop(rx_pkt_sop),
        .rx_pkt_eop(rx_pkt_eop), .rx_pkt_is_dllp(rx_pkt_is_dllp),
        .rx_pkt_error(rx_pkt_error), .link_disable(link_disable),
        .hot_reset_req(hot_reset_req), .force_recovery(force_recovery),
        .speed_retrain_active(speed_retrain_active),
        .recovery_speed_done(recovery_speed_done),
        .recovery_speed_ready(recovery_speed_ready),
        .ltssm_state(ltssm_state), .link_up(link_up),
        .negotiated_width(negotiated_width), .negotiated_speed(negotiated_speed),
        .link_number(link_number), .rx_ts_count(rx_ts_count),
        .training_error_count(training_error_count), .timeout_count(timeout_count),
        .frame_error_count(frame_error_count), .hot_reset_seen(hot_reset_seen),
        .os_ts1_valid(), .os_ts2_valid(), .os_malformed(), .os_link_number(),
        .os_lane_number(), .os_rate_id(), .os_training_control(),
        .os_tx_complete(), .os_eq_control(), .os_eq_data()
    );
endmodule

`default_nettype wire
