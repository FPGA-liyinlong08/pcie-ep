`timescale 1ps/1ps
`default_nettype none

// K13 文档 Test B 的窄场景：
//   - 直接使用 KCU105 官方 demo 生成的 pcie_phy_0 行为模型；
//   - 用生产 pcie_k13_production_ctrl 驱动 PIPE 控制口；
//   - 测试边界到 Gen1->Gen3 的 PhyStatus，不把 TS/EQ/DLL/TLP 混入本项。
module k13_phy_rate_change_tb;
    reg refclk = 1'b0;
    reg phy_rst_n = 1'b0;
    always #5000 refclk = ~refclk; // 100 MHz, 10 ns

    wire phy_coreclk, phy_userclk, phy_mcapclk, phy_pclk;
    wire phy_phystatus, phy_phystatus_rst;
    wire phy_txeq_done, phy_rxeq_adapt_done, phy_rxeq_done;
    wire [5:0] phy_txeq_fs, phy_txeq_lf;
    wire [17:0] phy_txeq_new_coeff, phy_rxeq_new_txcoeff;
    wire phy_rxeq_preset_sel;
    wire [31:0] phy_rxdata;
    wire [1:0] phy_rxdatak, phy_rxsync_header, phy_rxstatus;
    wire phy_rxdata_valid, phy_rxstart_block, phy_rxvalid, phy_rxelecidle;
    wire [2:0] phy_rxstatus3;
    wire phy_txp, phy_txn;

    wire [1:0] ctrl_rate, ctrl_txeq_ctrl, ctrl_rxeq_ctrl;
    wire [3:0] ctrl_txeq_preset, ctrl_rxeq_txpreset;
    wire [5:0] ctrl_txeq_coeff;
    wire ctrl_txelecidle, ctrl_traffic_quiesce, ctrl_recovery_active;
    wire [1:0] ctrl_negotiated_speed;
    wire [2:0] ctrl_speed_state, ctrl_eq_phase;
    wire ctrl_eq_active, ctrl_eq_done, ctrl_eq_failed;
    wire ctrl_ts_accept, ctrl_ts_reject, ctrl_cdr_loss;
    wire ctrl_speed_timeout, ctrl_fallback, ctrl_illegal_ts;
    wire ctrl_phy_rst_n = phy_rst_n && !phy_phystatus_rst;

    reg [31:0] phy_txdata = 32'd0;
    reg [1:0] phy_txdatak = 2'b00;
    reg phy_txdata_valid = 1'b0;
    reg phy_txstart_block = 1'b0;
    reg [1:0] phy_txsync_header = 2'b01;
    reg phy_txdetectrx = 1'b0;
    reg phy_txcompliance = 1'b0;
    reg phy_rxpolarity = 1'b0;
    reg [1:0] phy_powerdown = 2'b00;
    reg [2:0] phy_txmargin = 3'd0;
    reg phy_txswing = 1'b0;
    reg phy_txdeemph = 1'b0;
    reg retrain_pulse = 1'b0;

    wire [3:0] phy_rxeq_txpreset = ctrl_rxeq_txpreset;
    // The new contract uses this only to rebuild Gen1 context after Detect;
    // this narrow PHY boundary test starts after initial link bring-up.
    wire as_mac_in_detect = 1'b0;
    // K13 的 Recovery 活跃窗口对应 LTSSM 的 CDR hold 请求。
    wire as_cdr_hold_req = ctrl_recovery_active;
    wire ltssm_speed_ready = (ctrl_speed_state == 3'd1);

    // Test B 的输入在窄场景中保持无 TS；验证边界是 PHY rate/PhyStatus。
    wire partner_retrain_valid = 1'b0;
    wire [1:0] partner_target_speed = 2'b00;
    wire phy_cdr_lost = 1'b0;
    wire ts_valid = 1'b0;
    wire ts_complete = 1'b0;
    wire ts_is_ts1 = 1'b0;
    wire ts_is_ts2 = 1'b0;
    wire [2:0] ts_lane = 3'd0;
    wire [7:0] ts_link = 8'd0;
    wire [1:0] ts_rate = 2'b00;
    wire ts_eq_request = 1'b0;

    // 这四个 0/1 信号使用官方 pcie_phy_0 的真实模型输出，不做 force。
    pcie_phy_0 phy (
        .phy_refclk(refclk), .phy_gtrefclk(refclk), .phy_rst_n(phy_rst_n),
        .phy_txdata(phy_txdata), .phy_txdatak(phy_txdatak),
        .phy_txdata_valid(phy_txdata_valid), .phy_txstart_block(phy_txstart_block),
        .phy_txsync_header(phy_txsync_header), .phy_rxp(1'b0), .phy_rxn(1'b1),
        .phy_txdetectrx(phy_txdetectrx), .phy_txelecidle(ctrl_txelecidle),
        .phy_txcompliance(phy_txcompliance), .phy_rxpolarity(phy_rxpolarity),
        .phy_powerdown(phy_powerdown), .phy_rate(ctrl_rate),
        .phy_txmargin(phy_txmargin), .phy_txswing(phy_txswing),
        .phy_txdeemph(phy_txdeemph), .phy_txeq_ctrl(ctrl_txeq_ctrl),
        .phy_txeq_preset(ctrl_txeq_preset), .phy_txeq_coeff(ctrl_txeq_coeff),
        .phy_rxeq_ctrl(ctrl_rxeq_ctrl), .phy_rxeq_txpreset(phy_rxeq_txpreset),
        .as_mac_in_detect(as_mac_in_detect), .as_cdr_hold_req(as_cdr_hold_req),
        .phy_coreclk(phy_coreclk), .phy_userclk(phy_userclk),
        .phy_mcapclk(phy_mcapclk), .phy_pclk(phy_pclk),
        .phy_txp(phy_txp), .phy_txn(phy_txn), .phy_rxdata(phy_rxdata),
        .phy_rxdatak(phy_rxdatak), .phy_rxdata_valid(phy_rxdata_valid),
        .phy_rxstart_block(phy_rxstart_block), .phy_rxsync_header(phy_rxsync_header),
        .phy_rxvalid(phy_rxvalid), .phy_phystatus(phy_phystatus),
        .phy_phystatus_rst(phy_phystatus_rst), .phy_rxelecidle(phy_rxelecidle),
        .phy_rxstatus(phy_rxstatus3), .phy_txeq_fs(phy_txeq_fs),
        .phy_txeq_lf(phy_txeq_lf), .phy_txeq_new_coeff(phy_txeq_new_coeff),
        .phy_txeq_done(phy_txeq_done), .phy_rxeq_preset_sel(phy_rxeq_preset_sel),
        .phy_rxeq_new_txcoeff(phy_rxeq_new_txcoeff),
        .phy_rxeq_adapt_done(phy_rxeq_adapt_done), .phy_rxeq_done(phy_rxeq_done)
    );

    pcie_k13_production_ctrl #(
        .K13_ENABLE(1), .K13_RXEQ_BOOTSTRAP(0),
        .SPEED_TIMEOUT_CYCLES(500000), .EQ_TIMEOUT_CYCLES(500000)
    ) ctrl (
        .core_clk(phy_coreclk), .core_rst_n(ctrl_phy_rst_n),
        .phy_clk(phy_pclk), .phy_rst_n(ctrl_phy_rst_n), .link_up(1'b1),
        .reinitialize_gen1(as_mac_in_detect),
        .ltssm_speed_ready(ltssm_speed_ready),
        .retrain_pulse(retrain_pulse), .target_speed(2'b10),
        .partner_retrain_valid(partner_retrain_valid),
        .partner_target_speed(partner_target_speed),
        .phy_phystatus(phy_phystatus), .phy_cdr_lost(phy_cdr_lost),
        .phy_txeq_done(phy_txeq_done),
        .phy_rxeq_adapt_done(phy_rxeq_adapt_done), .phy_rxeq_done(phy_rxeq_done),
        .ts_valid(ts_valid), .ts_complete(ts_complete), .ts_is_ts1(ts_is_ts1),
        .ts_is_ts2(ts_is_ts2), .ts_lane(ts_lane), .ts_link(ts_link),
        .ts_rate(ts_rate), .ts_eq_request(ts_eq_request),
        .expected_lane(3'd0), .expected_link(8'd0),
        .phy_rate_cmd(ctrl_rate), .active_rate(),
        .phy_txelecidle(ctrl_txelecidle),
        .phy_txeq_ctrl(ctrl_txeq_ctrl), .phy_txeq_preset(ctrl_txeq_preset),
        .phy_txeq_coeff(ctrl_txeq_coeff), .phy_rxeq_ctrl(ctrl_rxeq_ctrl),
        .phy_rxeq_txpreset(ctrl_rxeq_txpreset),
        .traffic_quiesce(ctrl_traffic_quiesce),
        .recovery_active(ctrl_recovery_active),
        .rate_contract_illegal(),
        .negotiated_speed(ctrl_negotiated_speed), .speed_state(ctrl_speed_state),
        .eq_active(ctrl_eq_active), .eq_done(ctrl_eq_done),
        .eq_failed(ctrl_eq_failed), .eq_phase(ctrl_eq_phase),
        .ts_accept(ctrl_ts_accept), .ts_reject(ctrl_ts_reject),
        .cdr_loss_sticky(ctrl_cdr_loss), .speed_timeout_sticky(ctrl_speed_timeout),
        .fallback_sticky(ctrl_fallback), .illegal_ts_sticky(ctrl_illegal_ts)
    );

    integer trace_fd;
    integer cycle;
    integer timeout_cycles;
    reg seen_rate_gen3;
    reg seen_phystatus;
    reg seen_txeq_preset;
    reg rate_change_window;
    reg retrain_issued;
    reg failed;

    initial begin
        trace_fd = $fopen("k13_phy_rate_change_trace.csv", "w");
        $fdisplay(trace_fd, "cycle,time_ps,rate,powerdown,txelecidle,txeq_ctrl,txeq_preset,txeq_done,phystatus,cdr_hold,speed_state,recovery_active");
        cycle = 0; seen_rate_gen3 = 1'b0; seen_phystatus = 1'b0;
        seen_txeq_preset = 1'b0;
        rate_change_window = 1'b0;
        retrain_issued = 1'b0; failed = 1'b0;
        repeat (500) @(posedge refclk);
        phy_rst_n = 1'b1;
        wait (phy_phystatus_rst === 1'b0);
        repeat (128) @(posedge phy_pclk);
        if (ctrl_rate !== 2'b00) begin
            $display("K13_PHY_RATE_CHANGE_VCS_FAIL reason=gen1_not_stable rate=%02b", ctrl_rate);
            failed = 1'b1;
        end
        @(posedge phy_coreclk);
        retrain_pulse <= 1'b1;
        retrain_issued = 1'b1;
        $display("K13_PHY_RATE_CHANGE_RETRAIN_ISSUED time_ps=%0t", $time);
        @(posedge phy_coreclk);
        retrain_pulse <= 1'b0;

        timeout_cycles = 0;
        while (!seen_phystatus && (timeout_cycles < 500000)) begin
            @(posedge phy_pclk);
            timeout_cycles = timeout_cycles + 1;
        end
        if (!seen_rate_gen3)
            $display("K13_PHY_RATE_CHANGE_VCS_FAIL reason=no_gen3_rate");
        if (!seen_txeq_preset)
            $display("K13_PHY_RATE_CHANGE_VCS_FAIL reason=no_pre_rate_txeq_preset");
        if (!seen_phystatus)
            $display("K13_PHY_RATE_CHANGE_VCS_FAIL reason=phystatus_timeout cycles=%0d", timeout_cycles);
        if (seen_rate_gen3 && seen_txeq_preset && seen_phystatus && !failed) begin
            $display("K13_PRODUCTION_PHY_RATE_CHANGE_VCS_PASS rate=gen1_to_gen3 pre_rate_txeq=1 phystatus=1");
        end else begin
            $display("K13_PRODUCTION_PHY_RATE_CHANGE_VCS_FAIL rate_gen3=%0d phystatus=%0d", seen_rate_gen3, seen_phystatus);
            failed = 1'b1;
        end
        $fclose(trace_fd);
        if (failed) $fatal(1, "K13 narrow PHY rate-change test failed");
        $finish;
    end

    always @(posedge phy_pclk) begin
        if (ctrl_phy_rst_n === 1'b1) begin
            $fdisplay(trace_fd, "%0d,%0t,%02b,%02b,%0d,%02b,%0d,%0d,%0d,%0d,%0d,%0d",
                      cycle, $time, ctrl_rate, phy_powerdown, ctrl_txelecidle,
                      ctrl_txeq_ctrl, ctrl_txeq_preset, phy_txeq_done,
                      phy_phystatus, as_cdr_hold_req, ctrl_speed_state,
                      ctrl_recovery_active);
            if ((ctrl_txeq_ctrl == 2'b01) && (ctrl_txeq_preset == 4'd4))
                seen_txeq_preset = 1'b1;
            if ((ctrl_rate == 2'b10) && !seen_txeq_preset) begin
                $display("K13_PHY_RATE_CHANGE_VCS_FAIL reason=rate_before_txeq_preset cycle=%0d", cycle);
                failed = 1'b1;
            end
            if (ctrl_rate == 2'b10) seen_rate_gen3 = 1'b1;
            if (ctrl_rate == 2'b10) rate_change_window = 1'b1;
            if (rate_change_window && (phy_phystatus === 1'b1))
                seen_phystatus = 1'b1;
            if (retrain_issued && rate_change_window && !seen_phystatus &&
                (ctrl_txelecidle !== 1'b1)) begin
                $display("K13_PHY_RATE_CHANGE_VCS_FAIL reason=txelecidle_gap cycle=%0d rate=%02b state=%0d",
                         cycle, ctrl_rate, ctrl_speed_state);
                failed = 1'b1;
            end
            cycle = cycle + 1;
        end
    end

    always @(ctrl_speed_state) begin
        if (ctrl_phy_rst_n === 1'b1)
            $display("K13_PHY_RATE_CHANGE_STATE time_ps=%0t state=%0d rate=%02b txei=%0d",
                     $time, ctrl_speed_state, ctrl_rate, ctrl_txelecidle);
    end

    initial begin
        #2_000_000_000;
        $fatal(1, "K13 narrow PHY rate-change global timeout");
    end
endmodule

`default_nettype wire
