`timescale 1ns/1ps
`default_nettype none

// D3 K02-PHY standalone top using the production PHY command owner.
module kcu105_pcie_phy_command_rate_top #(
    parameter integer ARM_DELAY_CYCLES = 500_000_000
) (
    input wire pcie_refclk_p, input wire pcie_refclk_n,
    input wire pcie_perst_n, input wire pcie_rxp, input wire pcie_rxn,
    output wire pcie_txp, output wire pcie_txn, output wire [7:0] led
);
    wire phy_coreclk, phy_userclk, phy_mcapclk, phy_pclk;
    wire pipe_rst_n, core_rst_n, phy_phystatus_rst;
    wire [31:0] phy_rxdata;
    wire [1:0] phy_rxdatak;
    wire phy_rxdata_valid, phy_rxstart_block, phy_rxvalid;
    wire [1:0] phy_rxsync_header;
    wire phy_phystatus, phy_rxelecidle;
    wire [2:0] phy_rxstatus;
    wire [5:0] phy_txeq_fs, phy_txeq_lf;
    wire [17:0] phy_txeq_new_coeff, phy_rxeq_new_txcoeff;
    wire phy_txeq_done, phy_rxeq_preset_sel;
    wire phy_rxeq_adapt_done, phy_rxeq_done;

    wire [2:0] cmd_profile;
    wire op_valid, op_kind, op_ready, op_done;
    wire [1:0] op_result;
    wire rate_req_valid, rate_req_ready, rate_busy, rate_done;
    wire [1:0] rate_req_target, active_rate;
    wire [2:0] rate_result;
    wire [3:0] rate_state;
    wire [3:0] seq_state;
    wire seq_failed;

    (* mark_debug = "true" *) wire [1:0] phy_powerdown;
    (* mark_debug = "true" *) wire phy_txdetectrx;
    (* mark_debug = "true" *) wire phy_txelecidle;
    (* mark_debug = "true" *) wire [1:0] phy_rate;
    wire [1:0] phy_txeq_ctrl, phy_rxeq_ctrl;
    wire [3:0] phy_txeq_preset, phy_rxeq_txpreset;
    wire [5:0] phy_txeq_coeff;
    wire as_mac_in_detect, as_cdr_hold_req;
    wire phy_txcompliance, phy_rxpolarity;
    wire [2:0] phy_txmargin;
    wire phy_txswing, phy_txdeemph;

    (* KEEP = "TRUE" *) wire qpll1lock_record_in;
    (* KEEP = "TRUE" *) wire qpll1reset_record_in;
    (* mark_debug = "true" *) wire [117:0] k02_event_record_w;

    // Stable aliases let the proven K02 ILA insertion/capture scripts compare
    // Golden and command-controller builds with the same probe schema.
    (* mark_debug = "true" *) wire [1:0] phy_rate_cmd = phy_rate;
    (* mark_debug = "true" *) wire phy_txelecidle_cmd = phy_txelecidle;
    (* mark_debug = "true" *) wire [7:0] phy_ctrl_debug_state_w =
        {4'd0, rate_state};
    (* mark_debug = "true" *) wire as_mac_in_detect_cmd = as_mac_in_detect;
    (* mark_debug = "true" *) wire as_cdr_hold_cmd = as_cdr_hold_req;
    (* mark_debug = "true" *) wire [3:0] seq_state_w = seq_state;
    (* mark_debug = "true" *) wire gen3_request_w = rate_req_valid || rate_busy;
    (* mark_debug = "true" *) wire tx_elec_idle_w = phy_txelecidle;
    (* mark_debug = "true" *) wire phy_ready_en_w = !phy_phystatus_rst;
    (* mark_debug = "true" *) wire gen1_en_w =
        (active_rate == 2'b00) && !rate_busy;
    (* mark_debug = "true" *) wire gen3_en_w =
        (phy_rate == 2'b10) || (active_rate == 2'b10);

    pcie_phy_rate_test_seq #(
        .ARM_DELAY_CYCLES(ARM_DELAY_CYCLES)
    ) u_rate_test_seq (
        .clk(phy_pclk), .rst_n(pipe_rst_n),
        .phy_ready(!phy_phystatus_rst),
        .op_ready(op_ready), .op_done(op_done),
        .rate_req_ready(rate_req_ready), .rate_done(rate_done),
        .rate_result(rate_result), .cmd_profile(cmd_profile),
        .op_valid(op_valid), .op_kind(op_kind),
        .rate_req_valid(rate_req_valid), .rate_req_target(rate_req_target),
        .state(seq_state), .failed(seq_failed)
    );

    pcie_phy_command_ctrl u_phy_command_ctrl (
        .phy_pclk(phy_pclk), .pipe_rst_n(pipe_rst_n),
        .cmd_profile(cmd_profile), .op_valid(op_valid), .op_kind(op_kind),
        .op_ready(op_ready), .op_done(op_done), .op_result(op_result),
        .rate_req_valid(rate_req_valid), .rate_req_target(rate_req_target),
        .rate_abort(1'b0), .rate_req_ready(rate_req_ready),
        .rate_busy(rate_busy), .rate_done(rate_done),
        .rate_result(rate_result), .active_rate(active_rate),
        .rate_state(rate_state),
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

    k02_phy_event_recorder u_k02_event_recorder (
        .clk(phy_pclk), .rst(phy_phystatus_rst),
        .qpll1lock(qpll1lock_record_in), .qpll1reset(qpll1reset_record_in),
        .phy_rate(phy_rate), .phy_phystatus(phy_phystatus),
        .seq_state(seq_state), .record_bus(k02_event_record_w)
    );

    kcu105_pcie_phy_wrapper u_phy_wrapper (
        .pcie_refclk_p(pcie_refclk_p), .pcie_refclk_n(pcie_refclk_n),
        .pcie_perst_n(pcie_perst_n), .pcie_rxp(pcie_rxp), .pcie_rxn(pcie_rxn),
        .pcie_txp(pcie_txp), .pcie_txn(pcie_txn),
        .phy_txdata(32'd0), .phy_txdatak(2'd0), .phy_txdata_valid(1'b1),
        .phy_txstart_block(1'b0), .phy_txsync_header(2'b01),
        .phy_txdetectrx(phy_txdetectrx), .phy_txelecidle(phy_txelecidle),
        .phy_txcompliance(phy_txcompliance), .phy_rxpolarity(phy_rxpolarity),
        .phy_powerdown(phy_powerdown), .phy_rate(phy_rate),
        .phy_txmargin(phy_txmargin), .phy_txswing(phy_txswing),
        .phy_txdeemph(phy_txdeemph), .phy_txeq_ctrl(phy_txeq_ctrl),
        .phy_txeq_preset(phy_txeq_preset), .phy_txeq_coeff(phy_txeq_coeff),
        .phy_rxeq_ctrl(phy_rxeq_ctrl), .phy_rxeq_txpreset(phy_rxeq_txpreset),
        .as_mac_in_detect(as_mac_in_detect), .as_cdr_hold_req(as_cdr_hold_req),
        .phy_coreclk(phy_coreclk), .phy_userclk(phy_userclk),
        .phy_mcapclk(phy_mcapclk), .phy_pclk(phy_pclk),
        .pipe_rst_n(pipe_rst_n), .core_rst_n(core_rst_n),
        .phy_rxdata(phy_rxdata), .phy_rxdatak(phy_rxdatak),
        .phy_rxdata_valid(phy_rxdata_valid),
        .phy_rxstart_block(phy_rxstart_block),
        .phy_rxsync_header(phy_rxsync_header), .phy_rxvalid(phy_rxvalid),
        .phy_phystatus(phy_phystatus),
        .phy_phystatus_rst(phy_phystatus_rst),
        .phy_rxelecidle(phy_rxelecidle), .phy_rxstatus(phy_rxstatus),
        .phy_txeq_fs(phy_txeq_fs), .phy_txeq_lf(phy_txeq_lf),
        .phy_txeq_new_coeff(phy_txeq_new_coeff), .phy_txeq_done(phy_txeq_done),
        .phy_rxeq_preset_sel(phy_rxeq_preset_sel),
        .phy_rxeq_new_txcoeff(phy_rxeq_new_txcoeff),
        .phy_rxeq_adapt_done(phy_rxeq_adapt_done),
        .phy_rxeq_done(phy_rxeq_done)
    );

    assign led = {seq_failed, rate_busy, active_rate == 2'b10,
                  rate_state == 4'd0, seq_state};

    wire _unused = &{1'b0, phy_coreclk, phy_userclk, phy_mcapclk, core_rst_n,
        phy_rxdata, phy_rxdatak, phy_rxdata_valid, phy_rxstart_block,
        phy_rxsync_header, phy_rxvalid, phy_rxelecidle, phy_txeq_fs,
        phy_txeq_lf, phy_txeq_new_coeff, phy_txeq_done,
        phy_rxeq_preset_sel, phy_rxeq_new_txcoeff, phy_rxeq_adapt_done,
        phy_rxeq_done, op_result, rate_req_target, rate_req_valid, rate_done,
        rate_result};
endmodule

`default_nettype wire
