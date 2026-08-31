`timescale 1ps/1ps
`default_nettype none

// Direct K14 semantic test using the production KCU105 PCIe PHY model.
// No TS decoder, Root Port task, configuration write, setpci or AUTO request
// participates in this test.
module k14_direct_vcs_tb;
    localparam time REFCLK_HALF_PERIOD = 5_000;

    reg pcie_refclk_p = 1'b0;
    wire pcie_refclk_n = ~pcie_refclk_p;
    reg pcie_perst_n = 1'b0;
    always #REFCLK_HALF_PERIOD pcie_refclk_p = ~pcie_refclk_p;

    wire phy_coreclk, phy_userclk, phy_mcapclk, phy_pclk;
    wire pipe_rst_n, core_rst_n;
    wire phy_phystatus, phy_phystatus_rst;
    wire [2:0] phy_rxstatus;
    wire [1:0] phy_powerdown, phy_rate;
    wire phy_txdetectrx, phy_txelecidle;
    wire [1:0] phy_txeq_ctrl, phy_rxeq_ctrl;
    wire [3:0] phy_txeq_preset, phy_rxeq_txpreset;
    wire [5:0] phy_txeq_coeff;
    wire [5:0] phy_txeq_fs, phy_txeq_lf;
    wire [17:0] phy_txeq_new_coeff, phy_rxeq_new_txcoeff;
    wire phy_txeq_done, phy_rxeq_preset_sel;
    wire phy_rxeq_adapt_done, phy_rxeq_done;
    wire as_mac_in_detect, as_cdr_hold_req;
    wire pcie_txp, pcie_txn;

    wire [2:0] speed_state;
    wire [3:0] rate_state;
    wire [1:0] active_rate, requested_rate, negotiated_speed;
    wire traffic_quiesce, recovery_active, retrain_accept;
    wire rate_req_valid, rate_req_ready, rate_busy, rate_done;
    wire [1:0] rate_req_target;
    wire [2:0] rate_result;
    wire fallback_req;
    wire speed_timeout, fallback_taken;
    wire rate_success = rate_done && (rate_result == 3'd1);
    wire rate_failed = rate_done && (rate_result != 3'd0) &&
                       (rate_result != 3'd1);

    reg partner_request = 1'b0;
    wire partner_pending;
    wire [1:0] partner_target;
    wire partner_armed;
    wire partner_accept = partner_pending && retrain_accept;
    reg ltssm_speed_ready = 1'b0;

    pcie_partner_retrain_pending u_pending (
        .clk(phy_pclk), .rst_n(pipe_rst_n),
        .request_valid(partner_request), .request_target(2'b10),
        .rearm((speed_state == 3'd0) && !recovery_active),
        .accept(partner_accept), .pending(partner_pending),
        .pending_target(partner_target), .armed(partner_armed)
    );

    pcie_recovery_speed_ctrl #(.SPEED_TIMEOUT_CYCLES(5_000)) u_speed (
        .clk(phy_pclk), .rst_n(pipe_rst_n), .link_up(1'b1),
        .reinitialize_gen1(1'b0),
        .retrain_valid(partner_pending),
        .retrain_target_speed(partner_target),
        .ltssm_speed_ready(ltssm_speed_ready),
        .rate_req_valid(rate_req_valid), .rate_req_target(rate_req_target),
        .fallback_req(fallback_req), .rate_req_ready(rate_req_ready),
        .rate_op_done(rate_success), .rate_op_failed(rate_failed),
        .active_rate(active_rate), .requested_rate(requested_rate),
        .retrain_accept(retrain_accept), .phy_cdr_lost(1'b0),
        .peer_speed_ok(1'b0), .peer_speed_reject(1'b0),
        .state(speed_state), .traffic_quiesce(traffic_quiesce),
        .recovery_active(recovery_active),
        .negotiated_speed(negotiated_speed),
        .speed_timeout_sticky(speed_timeout), .peer_reject_sticky(),
        .illegal_speed_sticky(), .cdr_loss_sticky(),
        .fallback_taken_sticky(fallback_taken)
    );

    pcie_phy_command_ctrl #(
        .GOLDEN_RELEASE_GAP_CYCLES(4),
        .RATE_TIMEOUT_CYCLES(200_000),
        .GEN3_TX_SETTLE_CYCLES(2),
        .K15_AB_PRERATE_TXEQ(0), .K15_AB_PRERATE_QUERY(0)
    ) u_command (
        .phy_pclk(phy_pclk), .pipe_rst_n(pipe_rst_n),
        .cmd_profile(recovery_active ? 3'd5 : 3'd4),
        .op_valid(1'b0), .op_kind(1'b0), .op_ready(), .op_done(),
        .op_result(), .rate_req_valid(rate_req_valid),
        .rate_req_target(rate_req_target),
        .prerate_preset_valid(1'b0), .prerate_preset(4'd4),
        .rate_abort(rate_failed), .rate_req_ready(rate_req_ready),
        .rate_busy(rate_busy), .rate_done(rate_done),
        .rate_result(rate_result), .active_rate(active_rate),
        .rate_state(rate_state),
        .prerate_query_valid(), .prerate_query_coeff(),
        .phy_phystatus(phy_phystatus),
        .eq_req_valid(1'b0), .eq_req_kind(3'd0),
        .eq_req_preset(4'd0), .eq_req_coeff(18'd0),
        .eq_req_ready(), .eq_busy(), .eq_done(), .eq_result(),
        .eq_rsp_preset_sel(), .eq_rsp_coeff(),
        .phy_rxstatus(phy_rxstatus),
        .phy_txeq_fs(phy_txeq_fs), .phy_txeq_lf(phy_txeq_lf),
        .phy_txeq_new_coeff(phy_txeq_new_coeff),
        .phy_txeq_done(phy_txeq_done),
        .phy_rxeq_preset_sel(phy_rxeq_preset_sel),
        .phy_rxeq_new_txcoeff(phy_rxeq_new_txcoeff),
        .phy_rxeq_adapt_done(phy_rxeq_adapt_done),
        .phy_rxeq_done(phy_rxeq_done), .phy_powerdown(phy_powerdown),
        .phy_txdetectrx(phy_txdetectrx), .phy_txelecidle(phy_txelecidle),
        .phy_rate(phy_rate), .phy_txeq_ctrl(phy_txeq_ctrl),
        .phy_txeq_preset(phy_txeq_preset),
        .phy_txeq_coeff(phy_txeq_coeff), .phy_rxeq_ctrl(phy_rxeq_ctrl),
        .phy_rxeq_txpreset(phy_rxeq_txpreset),
        .as_mac_in_detect(as_mac_in_detect),
        .as_cdr_hold_req(as_cdr_hold_req), .phy_txcompliance(),
        .phy_rxpolarity(), .phy_txmargin(), .phy_txswing(), .phy_txdeemph()
    );

    kcu105_pcie_phy_wrapper phy (
        .pcie_refclk_p(pcie_refclk_p), .pcie_refclk_n(pcie_refclk_n),
        .pcie_perst_n(pcie_perst_n), .pcie_rxp(1'b0), .pcie_rxn(1'b1),
        .pcie_txp(pcie_txp), .pcie_txn(pcie_txn),
        .phy_txdata(32'd0), .phy_txdatak(2'd0),
        .phy_txdata_valid(1'b0), .phy_txstart_block(1'b0),
        .phy_txsync_header(2'b01), .phy_txdetectrx(phy_txdetectrx),
        .phy_txelecidle(phy_txelecidle), .phy_txcompliance(1'b0),
        .phy_rxpolarity(1'b0), .phy_powerdown(phy_powerdown),
        .phy_rate(phy_rate), .phy_txmargin(3'd0), .phy_txswing(1'b0),
        .phy_txdeemph(1'b0), .phy_txeq_ctrl(phy_txeq_ctrl),
        .phy_txeq_preset(phy_txeq_preset),
        .phy_txeq_coeff(phy_txeq_coeff), .phy_rxeq_ctrl(phy_rxeq_ctrl),
        .phy_rxeq_txpreset(phy_rxeq_txpreset),
        .as_mac_in_detect(as_mac_in_detect),
        .as_cdr_hold_req(as_cdr_hold_req), .phy_coreclk(phy_coreclk),
        .phy_userclk(phy_userclk), .phy_mcapclk(phy_mcapclk),
        .phy_pclk(phy_pclk), .pipe_rst_n(pipe_rst_n),
        .core_rst_n(core_rst_n), .phy_rxdata(), .phy_rxdatak(),
        .phy_rxdata_valid(), .phy_rxstart_block(), .phy_rxsync_header(),
        .phy_rxvalid(), .phy_phystatus(phy_phystatus),
        .phy_phystatus_rst(phy_phystatus_rst), .phy_rxelecidle(),
        .phy_rxstatus(phy_rxstatus), .phy_txeq_fs(phy_txeq_fs),
        .phy_txeq_lf(phy_txeq_lf),
        .phy_txeq_new_coeff(phy_txeq_new_coeff),
        .phy_txeq_done(phy_txeq_done),
        .phy_rxeq_preset_sel(phy_rxeq_preset_sel),
        .phy_rxeq_new_txcoeff(phy_rxeq_new_txcoeff),
        .phy_rxeq_adapt_done(phy_rxeq_adapt_done),
        .phy_rxeq_done(phy_rxeq_done)
    );

    wire qpll1lock = phy.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.qpll1lock_out[0];
    integer gen3_excursions = 0;
    reg seen_gen3_phystatus = 1'b0;
    reg seen_gen1_fallback_phystatus = 1'b0;
    reg seen_qpll_lock = 1'b0;
    reg fallback_window = 1'b0;
    reg [1:0] last_phy_rate = 2'b00;
    reg [3:0] last_rate_state = 4'hf;
    reg [2:0] last_speed_state = 3'h7;

    always @(posedge phy_pclk) begin
        if (pipe_rst_n) begin
            if ((rate_state != last_rate_state) ||
                (speed_state != last_speed_state))
                $display("K14_DIRECT_STATE time_ps=%0t speed=%0d rate_state=%0d rate=%0d active=%0d phystatus=%0d txeq=%0d",
                         $time, speed_state, rate_state, phy_rate, active_rate,
                         phy_phystatus, phy_txeq_ctrl);
            if ((phy_rate == 2'b10) && (last_phy_rate != 2'b10))
                gen3_excursions = gen3_excursions + 1;
            if ((phy_rate == 2'b10) && phy_phystatus)
                seen_gen3_phystatus = 1'b1;
            if ((phy_rate == 2'b10) && qpll1lock)
                seen_qpll_lock = 1'b1;
            if (fallback_taken)
                fallback_window = 1'b1;
            if (fallback_window && (phy_rate == 2'b00) && phy_phystatus)
                seen_gen1_fallback_phystatus = 1'b1;
            last_phy_rate = phy_rate;
            last_rate_state = rate_state;
            last_speed_state = speed_state;
        end
    end

    task automatic pulse_partner_request;
        begin
            @(negedge phy_pclk);
            partner_request = 1'b1;
            @(negedge phy_pclk);
            partner_request = 1'b0;
            @(posedge phy_pclk);
        end
    endtask

    initial begin : watchdog
        #2_000_000_000;
        $fatal(1, "K14_DIRECT_VCS_GLOBAL_TIMEOUT");
    end

    initial begin : test_sequence
        integer cycles;
        #500_000;
        pcie_perst_n = 1'b1;
        wait (pipe_rst_n === 1'b1);
        repeat (16) @(posedge phy_pclk);

        pulse_partner_request();
        if (!partner_pending)
            $fatal(1, "K14_DIRECT_PENDING_NOT_LATCHED");
        wait (retrain_accept === 1'b1);
        $display("K14_DIRECT_PENDING_ACCEPT_VCS_PASS time_ps=%0t", $time);

        // Repeated copies during the accepted transaction are suppressed.
        repeat (2) begin
            pulse_partner_request();
            if (partner_pending)
                $fatal(1, "K14_DIRECT_DUPLICATE_REQUEST_REARMED");
        end

        ltssm_speed_ready = 1'b1;
        @(posedge phy_pclk);
        ltssm_speed_ready = 1'b0;

        cycles = 0;
        while ((active_rate != 2'b10) && (cycles < 250_000)) begin
            @(posedge phy_pclk);
            cycles = cycles + 1;
        end
        if (active_rate != 2'b10)
            $fatal(1, "K14_DIRECT_GEN3_RATE_TIMEOUT");
        if (!seen_gen3_phystatus)
            $fatal(1, "K14_DIRECT_GEN3_PHYSTATUS_MISSING");
        if (!seen_qpll_lock)
            $fatal(1, "K14_DIRECT_QPLL_LOCK_MISSING");
        $display("K14_DIRECT_GEN3_PHY_VCS_PASS time_ps=%0t qpll=%0d",
                 $time, qpll1lock);

        // peer_speed_ok is tied low: exercise the existing natural timeout
        // and real Gen1 PHY fallback transaction.
        cycles = 0;
        while (!((active_rate == 2'b00) && (speed_state == 3'd0)) &&
               (cycles < 300_000)) begin
            @(posedge phy_pclk);
            // Model the production LTSSM returning to Recovery.Speed for the
            // explicit Gen1 fallback request.
            if (speed_state == 3'd5)
                ltssm_speed_ready = 1'b1;
            else if (speed_state == 3'd6)
                ltssm_speed_ready = 1'b0;
            cycles = cycles + 1;
        end
        if (!fallback_taken || !speed_timeout)
            $fatal(1, "K14_DIRECT_FALLBACK_REQUEST_MISSING");
        if (!seen_gen1_fallback_phystatus)
            $fatal(1, "K14_DIRECT_GEN1_PHYSTATUS_MISSING");
        if (gen3_excursions != 1)
            $fatal(1, "K14_DIRECT_DUPLICATE_GEN3_EXCURSION count=%0d",
                   gen3_excursions);

        // No new request: fallback must remain stably at Gen1.
        repeat (256) begin
            @(posedge phy_pclk);
            if ((phy_rate != 2'b00) || (gen3_excursions != 1))
                $fatal(1, "K14_DIRECT_POST_FALLBACK_RETRIGGER");
        end
        $display("K14_DIRECT_GEN1_FALLBACK_VCS_PASS time_ps=%0t", $time);
        $display("K14_DIRECT_VCS_PASS excursions=%0d auto=0 mailbox=0 ts=0",
                 gen3_excursions);
        $finish;
    end
endmodule

`default_nettype wire
