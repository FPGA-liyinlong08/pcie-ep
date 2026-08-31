`timescale 1ns/1ps
`default_nettype none

// Small controller-only harness for the reversible K15 PHY-envelope matrix.
// The PHY's TXEQ_DONE is modeled as a fresh edge after TXEQ_CTRL becomes 01;
// no LTSSM, GT or Root-Port behavior is included in this Gate-A test.
module k15_ab_test_top #(
    parameter integer K15_AB_CDR_HOLD = 0,
    parameter integer K15_AB_PRERATE_TXEQ = 1,
    parameter integer K15_AB_PRERATE_QUERY = 1,
    parameter integer K15_AB_PRERATE_DWELL_CYCLES = 4,
    parameter integer K15_AB_PRERATE_PRESET = 4
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rate_req_valid,
    input  wire [1:0] rate_req_target,
    input  wire       phy_phystatus,
    output wire [1:0] phy_rate,
    output wire [3:0] rate_state,
    output wire       rate_busy,
    output wire       rate_done,
    output wire [2:0] rate_result,
    output wire       as_cdr_hold_req,
    output wire       phy_txelecidle,
    output wire [1:0] phy_txeq_ctrl,
    output wire [3:0] phy_txeq_preset,
    output wire [31:0] variant_dwell,
    output wire       variant_cdr_hold,
    output wire       variant_prerate_txeq,
    output wire       variant_prerate_query,
    output wire       prerate_query_valid,
    output wire [17:0] prerate_query_coeff
);
    wire rate_req_ready;
    wire phy_txeq_done = (phy_txeq_ctrl != 2'b00);

    assign variant_dwell = K15_AB_PRERATE_DWELL_CYCLES;
    assign variant_cdr_hold = (K15_AB_CDR_HOLD != 0);
    assign variant_prerate_txeq = (K15_AB_PRERATE_TXEQ != 0);
    assign variant_prerate_query = (K15_AB_PRERATE_QUERY != 0);

    pcie_phy_command_ctrl #(
        .GOLDEN_RELEASE_GAP_CYCLES(4),
        .RATE_TIMEOUT_CYCLES(32),
        .GEN3_TX_SETTLE_CYCLES(2),
        .K15_AB_CDR_HOLD(K15_AB_CDR_HOLD),
        .K15_AB_PRERATE_TXEQ(K15_AB_PRERATE_TXEQ),
        .K15_AB_PRERATE_QUERY(K15_AB_PRERATE_QUERY),
        .K15_AB_PRERATE_DWELL_CYCLES(K15_AB_PRERATE_DWELL_CYCLES),
        .K15_AB_PRERATE_PRESET(K15_AB_PRERATE_PRESET)
    ) u_command (
        .phy_pclk(clk), .pipe_rst_n(rst_n),
        .cmd_profile(3'd5), .op_valid(1'b0), .op_kind(1'b0),
        .op_ready(), .op_done(), .op_result(),
        .rate_req_valid(rate_req_valid), .rate_req_target(rate_req_target),
        .prerate_preset_valid(1'b1), .prerate_preset(4'd7),
        .rate_abort(1'b0), .rate_req_ready(rate_req_ready),
        .rate_busy(rate_busy), .rate_done(rate_done), .rate_result(rate_result),
        .active_rate(), .rate_state(rate_state),
        .prerate_query_valid(prerate_query_valid),
        .prerate_query_coeff(prerate_query_coeff),
        .eq_req_valid(1'b0), .eq_req_kind(3'd0), .eq_req_preset(4'd0),
        .eq_req_coeff(18'd0), .eq_req_ready(), .eq_busy(), .eq_done(),
        .eq_result(), .eq_rsp_preset_sel(), .eq_rsp_coeff(),
        .phy_phystatus(phy_phystatus), .phy_rxstatus(3'd0),
        .phy_txeq_fs(6'd0), .phy_txeq_lf(6'd0),
        .phy_txeq_new_coeff(18'h03941), .phy_txeq_done(phy_txeq_done),
        .phy_rxeq_preset_sel(1'b0), .phy_rxeq_new_txcoeff(18'd0),
        .phy_rxeq_adapt_done(1'b0), .phy_rxeq_done(1'b0),
        .phy_powerdown(), .phy_txdetectrx(), .phy_txelecidle(phy_txelecidle),
        .phy_rate(phy_rate), .phy_txeq_ctrl(phy_txeq_ctrl),
        .phy_txeq_preset(phy_txeq_preset), .phy_txeq_coeff(),
        .phy_rxeq_ctrl(), .phy_rxeq_txpreset(),
        .as_mac_in_detect(), .as_cdr_hold_req(as_cdr_hold_req),
        .phy_txcompliance(), .phy_rxpolarity(), .phy_txmargin(),
        .phy_txswing(), .phy_txdeemph()
    );

    wire _unused = &{1'b0, rate_req_ready};
endmodule

`default_nettype wire
