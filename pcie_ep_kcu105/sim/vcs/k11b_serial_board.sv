`timescale 1ps/1ps
`default_nettype none

// K11-B1 真实串行联合仿真顶层。
// 模块名 board、Root Port 实例名 RP 是 Xilinx usrapp 层次引用的固定契约。
module board;
    parameter integer C_DATA_WIDTH = 256;
    localparam integer EP_DETECT_QUIET_CYCLES   = 128;
    localparam integer EP_DETECT_TIMEOUT_CYCLES = 1_000_000;
    localparam integer EP_TRAIN_TIMEOUT_CYCLES  = 2_000_000;
    localparam integer EP_HOT_RESET_CYCLES      = 16_384;
    localparam integer STABLE_PCLK_CYCLES       = 1_024;
    localparam integer K14_PERST_HOLD_REFCLK_CYCLES = 10_000;
    localparam integer K14_RP_RELEASE_DELAY_REFCLK_CYCLES = 10_000;

    reg  refclk_p;
    wire refclk_n = ~refclk_p;
    reg  sys_rst_n;
    reg  rp_sys_rst_n;
    reg  disconnect_lane0;
    reg  b2_negative_stub;
    reg  b2_active;
    reg  b2_stress;
    reg  k14_reboot_active;
    reg  k14_rate_ab_active;
    reg  k13_retrain_active;
    reg  k13_retrain_monitor_armed;
    reg  k13_retry_sent;
    reg  k13_pipe_compare_enabled;
    reg  k13_initial_gen1_l0_seen;
    reg  k13_do_rp_retrain;
    reg  k13_do_ep_retrain;
    wire rp_reset_n = k14_reboot_active ? rp_sys_rst_n : sys_rst_n;

    integer b2_iter;
    integer b2_byte;
    integer b2_wait_cycles;
    reg [31:0] b2_lfsr;
    reg [31:0] b2_expected [0:47];
    reg [31:0] b2_random_data;
    reg [31:0] b2_random_addr;
    reg [31:0] b2_old_lcrc_count;
    reg [31:0] b2_old_nak_count;
    reg [31:0] b2_old_replay_count;
    reg [11:0] b2_delayed_ack_seq;
    reg [3:0]  b2_random_be;
    integer k13_wait_cycles;
    integer k13_fallback_wait_limit;
    reg k13_seen_rp_recovery;
    reg k13_seen_rcvrlock;
    reg k13_seen_rcvrcfg;
    reg k13_seen_recovery_speed;
    reg k13_seen_recovery_idle;
    reg k13_seen_rate_gen3;
    reg k13_seen_phystatus;
    reg [4:0] k13_seen_eq_phase;
    integer k13_gen3_pipe_samples;
    integer k13_recovery_ts_samples;
    integer k13_eqts_raw_words;
    integer k13_gen3_rx_samples;
    integer k13_rp_tx_edges_at_retrain;
    integer k13_ep_tx_edges_at_retrain;
    integer k13_gen1_l0_stable;
    integer k13_rp_pipe_samples;
    integer k13_rp_fallback_pipe_samples;
    integer k13_rp_recovery_ts_samples;
    integer k13_ep_recovery_rx_samples;
    integer k13_ep_recovery_tx_samples;
    integer k13_ep_gen3_tx_samples;
    integer k13_rp_recovery_rx_samples;
    integer k13_ep_fallback_pipe_samples;
    integer k13_ep_rx_contract_samples;
    integer k13_rp_tx_contract_samples;
    reg [1:0] k13_last_rxeq_ctrl;
    reg       k13_last_rxeq_done;
    reg       k13_last_rxeq_adapt_done;
    reg [2:0] k13_last_rxeq_fsm;

    wire       ep_txp;
    wire       ep_txn;
    wire       ep_rxp;
    wire       ep_rxn;
    wire [7:0] ep_led;
    wire [7:0] rp_txp;
    wire [7:0] rp_txn;
    wire [7:0] rp_rxp;
    wire [7:0] rp_rxn;

`ifdef K13_DUT
    // Scalar trace aliases mirror the useful part of the Xilinx demo board
    // trace.  Keeping these aliases at board scope makes the VCD portable
    // across VCS versions and avoids dumping the full encrypted RP/GT model.
    wire [5:0] trace_rp_ltssm_state = RP.cfg_ltssm_state;
    // The demo top leaves pl_eq_phase unconnected, but the core output remains
    // available hierarchically.  Trace it so the endpoint's transmitted EQ
    // tuple can be correlated with the Root Port's real protocol phase.
    wire [1:0] trace_rp_eq_phase =
        RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pl_eq_phase;
    wire [1:0] trace_rp_current_speed = RP.cfg_current_speed;
    wire [3:0] trace_rp_negotiated_width = RP.cfg_negotiated_width;
    wire       trace_rp_phy_link_status = RP.cfg_phy_link_status;
    wire       trace_rp_phy_link_down = RP.cfg_phy_link_down;
    wire       trace_rp_user_lnk_up = RP.user_lnk_up;
    wire [5:0] trace_ep_ltssm_state = EP.DUT.ltssm_state;
    wire       trace_ep_link_up = EP.DUT.link_up;
    wire       trace_ep_dll_active = EP.DUT.dll_active;
    // phy_rate is the selected command presented at the public PIPE boundary.
    // active_rate is the committed Rate Contract value after PhyStatus.
    wire [1:0] trace_ep_pipe_rate_cmd = EP.DUT.phy_rate;
    wire [1:0] trace_ep_active_rate = EP.DUT.k13_active_rate;
    wire [1:0] trace_ep_negotiated_speed = EP.DUT.negotiated_speed;
    wire [2:0] trace_ep_speed_state = EP.DUT.k13_speed_state;
    wire [2:0] trace_ep_eq_phase = EP.DUT.k13_eq_phase;
    wire       trace_ep_eq_active = EP.DUT.k13_eq_active;
    wire       trace_ep_eq_done = EP.DUT.k13_eq_done;
    wire       trace_ep_eq_failed = EP.DUT.k13_eq_failed;
    wire       trace_ep_fallback = EP.DUT.k13_fallback_sticky;
    wire       trace_ep_speed_timeout = EP.DUT.k13_speed_timeout_sticky;
    wire       trace_ep_phystatus = EP.DUT.phy_phystatus;
    wire       trace_ep_txei = EP.DUT.phy_txelecidle;
    wire [1:0] trace_ep_txeq_ctrl = EP.DUT.phy_txeq_ctrl;
    wire [1:0] trace_ep_rxeq_ctrl = EP.DUT.phy_rxeq_ctrl;
    wire [3:0] trace_ep_rxeq_txpreset = EP.DUT.phy_rxeq_txpreset;
    wire       trace_ep_rxeq_preset_sel = EP.DUT.phy_rxeq_preset_sel;
    wire [17:0] trace_ep_rxeq_new_txcoeff = EP.DUT.phy_rxeq_new_txcoeff;
    wire       trace_ep_rxeq_done = EP.DUT.phy_rxeq_done;
    wire       trace_ep_rxeq_adapt_done = EP.DUT.phy_rxeq_adapt_done;
    wire       trace_ep_tx_ts1;
    wire       trace_ep_tx_ts2;
    wire       trace_ep_tx_malformed;
    wire [7:0] trace_ep_tx_link;
    wire [7:0] trace_ep_tx_lane;
    wire [7:0] trace_ep_tx_rate;
    wire [7:0] trace_ep_tx_control;
    wire [7:0] trace_ep_tx_eq_control;
    wire [23:0] trace_ep_tx_eq_data;
    wire       trace_rp_rx_ts1;
    wire       trace_rp_rx_ts2;
    wire       trace_rp_rx_malformed;
    wire [7:0] trace_rp_rx_link;
    wire [7:0] trace_rp_rx_lane;
    wire [7:0] trace_rp_rx_rate;
    wire [7:0] trace_rp_rx_control;
    wire [7:0] trace_rp_rx_eq_control;
    wire [23:0] trace_rp_rx_eq_data;

    // Decode the actual Endpoint PIPE transmit stream.  This checks the
    // serialized/scrambled Ordered Set rather than trusting controller intent.
    pcie_gen3_os_rx trace_ep_tx_os_rx (
        .clk(EP.DUT.phy_pclk), .rst_n(EP.DUT.pipe_rst_n),
        .enable(EP.DUT.k13_active_rate == 2'b10),
        .in_valid(EP.DUT.phy_txdata_valid),
        .start_block(EP.DUT.phy_txstart_block),
        .sync_header(EP.DUT.phy_txsync_header), .in_data(EP.DUT.phy_txdata),
        .ts1_valid(trace_ep_tx_ts1), .ts2_valid(trace_ep_tx_ts2),
        .malformed(trace_ep_tx_malformed), .idle_valid(),
        .link_number(trace_ep_tx_link), .link_is_pad(),
        .lane_number(trace_ep_tx_lane), .lane_is_pad(), .n_fts(),
        .rate_id(trace_ep_tx_rate), .training_control(trace_ep_tx_control),
        .eq_control(trace_ep_tx_eq_control), .eq_data(trace_ep_tx_eq_data)
    );

    pcie_gen3_os_rx trace_rp_rx_os_rx (
        .clk(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_clk),
        .rst_n(sys_rst_n), .enable(1'b1),
        .in_valid(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_data_valid[0]),
        .start_block(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_start_block[0]),
        .sync_header(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_syncheader[1:0]),
        .in_data(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_data[31:0]),
        .ts1_valid(trace_rp_rx_ts1), .ts2_valid(trace_rp_rx_ts2),
        .malformed(trace_rp_rx_malformed), .idle_valid(),
        .link_number(trace_rp_rx_link), .link_is_pad(),
        .lane_number(trace_rp_rx_lane), .lane_is_pad(), .n_fts(),
        .rate_id(trace_rp_rx_rate), .training_control(trace_rp_rx_control),
        .eq_control(trace_rp_rx_eq_control), .eq_data(trace_rp_rx_eq_data)
    );

    always @(posedge EP.DUT.phy_pclk) begin
        if ($test$plusargs("K13_TRACE") &&
            (trace_ep_tx_ts1 || trace_ep_tx_ts2))
            $display("K13_EP_TX_TS time_ps=%0t ts1=%0d ts2=%0d rp_state=%0h rp_phase=%0d ep_state=%0d link=%02x lane=%02x rate=%02x ctrl=%02x eq_ctrl=%02x eq_data=%06x ready=%0d peer_exit=%0d",
                     $time, trace_ep_tx_ts1, trace_ep_tx_ts2,
                     RP.cfg_ltssm_state, trace_rp_eq_phase,
                     EP.DUT.ltssm_state, trace_ep_tx_link,
                     trace_ep_tx_lane, trace_ep_tx_rate,
                     trace_ep_tx_control, trace_ep_tx_eq_control,
                     trace_ep_tx_eq_data,
                     EP.DUT.g_k13_enabled_top.u_k13_production_ctrl.phase1_response_ready,
                     EP.DUT.g_k13_enabled_top.u_k13_production_ctrl.peer_eq_exit_seen);
    end

    integer trace_ep_gt_status_count = 0;
    always @(posedge EP.DUT.phy_pclk) begin
        if ($test$plusargs("K13_TRACE") && EP.DUT.phy_txstart_block &&
            (EP.DUT.phy_rate == 2'b10) &&
            (trace_ep_gt_status_count < 32)) begin
            $display("K13_EP_GT_STATUS time_ps=%0t n=%0d rate_gen3=%0d user_gen3_rdy=%0d txresetdone=%0d txuserrdy=%0d gttxreset=%0d txelecidle=%0d syncstart=%0d pcs_syncdone=%0d txphalign=%0d txsyncdone=%0d gt_data=%08x gt_ctrl=%04x",
                     $time, trace_ep_gt_status_count,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.GT_PCIERATEGEN3,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.GT_PCIEUSERGEN3RDY,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.GT_TXRESETDONE,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.txuserrdy_in,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.gttxreset_in,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.txelecidle_in,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.GT_PCIERSTTXSYNCSTART,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.GT_PCIESYNCTXSYNCDONE,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.GT_TXPHALIGNDONE,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.txsyncdone_out,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.txdata_in[31:0],
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.txctrl0_in[15:0]);
            trace_ep_gt_status_count <= trace_ep_gt_status_count + 1;
        end
    end

    always @(posedge RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_clk) begin
        if ($test$plusargs("K13_TRACE") &&
            (trace_rp_rx_ts1 || trace_rp_rx_ts2))
            $display("K13_RP_RX_TS time_ps=%0t ts1=%0d ts2=%0d rp_state=%0h rp_phase=%0d ep_state=%0d link=%02x lane=%02x rate=%02x ctrl=%02x eq_ctrl=%02x eq_data=%06x",
                     $time, trace_rp_rx_ts1, trace_rp_rx_ts2,
                     RP.cfg_ltssm_state, trace_rp_eq_phase,
                     EP.DUT.ltssm_state, trace_rp_rx_link,
                     trace_rp_rx_lane, trace_rp_rx_rate,
                     trace_rp_rx_control, trace_rp_rx_eq_control,
                     trace_rp_rx_eq_data);
    end

    // The demo's text trace is intentionally opt-in: normal regressions keep
    // their existing log volume, while a failing retrain can be compared
    // event-for-event with the demo's EP/RP trace.
    wire [46:0] trace_event_snapshot = {
        trace_rp_ltssm_state, trace_rp_eq_phase, trace_rp_current_speed,
        trace_rp_negotiated_width, trace_rp_phy_link_status,
        trace_rp_phy_link_down, trace_rp_user_lnk_up,
        trace_ep_ltssm_state, trace_ep_link_up, trace_ep_dll_active,
        trace_ep_pipe_rate_cmd, trace_ep_active_rate,
        trace_ep_negotiated_speed, trace_ep_speed_state, trace_ep_eq_phase,
        trace_ep_eq_active, trace_ep_eq_done, trace_ep_eq_failed,
        trace_ep_fallback, trace_ep_speed_timeout, trace_ep_phystatus,
        trace_ep_txei, trace_ep_txeq_ctrl, trace_ep_rxeq_ctrl
    };

    always @(trace_event_snapshot) begin
        if (sys_rst_n && $test$plusargs("K13_TRACE"))
            $display("K13_TRACE time_ps=%0t rp_state=%0h rp_eq_phase=%0d rp_speed=%0d rp_width=%0d rp_phy_link=%0d rp_link_down=%0d rp_user_link=%0d ep_state=%0d ep_link=%0d ep_dll=%0d pipe_rate_cmd=%0d active_rate=%0d negotiated=%0d speed_state=%0d eq_active=%0d eq_phase=%0d eq_done=%0d eq_failed=%0d fallback=%0d speed_timeout=%0d phystatus=%0d txei=%0d txeq=%02b rxeq=%02b",
                     $time, trace_rp_ltssm_state, trace_rp_eq_phase,
                     trace_rp_current_speed,
                     trace_rp_negotiated_width, trace_rp_phy_link_status,
                     trace_rp_phy_link_down, trace_rp_user_lnk_up,
                     trace_ep_ltssm_state, trace_ep_link_up,
                     trace_ep_dll_active, trace_ep_pipe_rate_cmd,
                     trace_ep_active_rate,
                     trace_ep_negotiated_speed, trace_ep_speed_state,
                     trace_ep_eq_active, trace_ep_eq_phase, trace_ep_eq_done,
                     trace_ep_eq_failed, trace_ep_fallback,
                     trace_ep_speed_timeout, trace_ep_phystatus,
                     trace_ep_txei, trace_ep_txeq_ctrl, trace_ep_rxeq_ctrl);
    end

    // Optional VCD equivalent to the demo's +DUMP_WAVEFORM mode.  The dump
    // contains only scalar contract/LTSSM/PHY observables; raw PIPE words are
    // already bounded and printed by the existing K13 diagnostic monitor.
    initial begin : k13_demo_style_waveform
        if ($test$plusargs("K13_DUMP_WAVEFORM")) begin
            $dumpfile("build/k13_vcs_training.vcd");
            $dumpvars(0, trace_rp_ltssm_state);
            $dumpvars(0, trace_rp_current_speed);
            $dumpvars(0, trace_rp_negotiated_width);
            $dumpvars(0, trace_rp_phy_link_status);
            $dumpvars(0, trace_rp_phy_link_down);
            $dumpvars(0, trace_rp_user_lnk_up);
            $dumpvars(0, trace_ep_ltssm_state);
            $dumpvars(0, trace_ep_link_up);
            $dumpvars(0, trace_ep_dll_active);
            $dumpvars(0, trace_ep_pipe_rate_cmd);
            $dumpvars(0, trace_ep_active_rate);
            $dumpvars(0, trace_ep_negotiated_speed);
            $dumpvars(0, trace_ep_speed_state);
            $dumpvars(0, trace_ep_eq_phase);
            $dumpvars(0, trace_ep_eq_active);
            $dumpvars(0, trace_ep_eq_done);
            $dumpvars(0, trace_ep_eq_failed);
            $dumpvars(0, trace_ep_fallback);
            $dumpvars(0, trace_ep_speed_timeout);
            $dumpvars(0, trace_ep_phystatus);
            $dumpvars(0, trace_ep_txei);
            $dumpvars(0, trace_ep_txeq_ctrl);
            $dumpvars(0, trace_ep_rxeq_ctrl);
            $display("K13_VCS_WAVEFORM_ENABLE file=build/k13_vcs_training.vcd");
        end
    end
`endif

    reg [5:0] last_ep_state;
    integer stable_count;
    reg seen_detect;
    reg seen_phy_powerup;
    reg seen_polling;
    reg seen_configuration;
    integer rp_tx_edge_count [0:7];
    integer ep_tx_edge_count;
    integer edge_index;

    initial begin
        refclk_p = 1'b0;
        forever #5000 refclk_p = ~refclk_p;
    end

    initial begin
        sys_rst_n = 1'b0;
        rp_sys_rst_n = 1'b0;
        disconnect_lane0 = $test$plusargs("K11B_DISCONNECT_LANE0");
        b2_negative_stub = $test$plusargs("K11B2_NEGATIVE_STUB");
        b2_active = $test$plusargs("K11B2_RUN");
        b2_stress = $test$plusargs("K11B2_STRESS");
        k14_reboot_active = $test$plusargs("K14_REBOOT") ||
                            $test$plusargs("K15_GEN3") ||
                            $test$plusargs("K14_RATE_AB");
        k14_rate_ab_active = $test$plusargs("K14_RATE_AB");
        k13_retrain_active = $test$plusargs("K13_RETRAIN");
        k13_retrain_monitor_armed = 1'b0;
        k13_retry_sent = 1'b0;
        k13_pipe_compare_enabled = $test$plusargs("K13_PIPE_COMPARE");
        k13_initial_gen1_l0_seen = 1'b0;
        if ($test$plusargs("K13_RETRAIN_SOURCE_RP")) begin
            k13_do_rp_retrain = 1'b1;
            k13_do_ep_retrain = 1'b0;
        end else if ($test$plusargs("K13_RETRAIN_SOURCE_EP")) begin
            k13_do_rp_retrain = 1'b0;
            k13_do_ep_retrain = 1'b1;
        end else begin
            k13_do_rp_retrain = 1'b1;
            k13_do_ep_retrain = 1'b1;
        end
        // A real PERST# assertion is held long enough for both the endpoint
        // GT and the encrypted Root Port model to leave any prior link epoch.
        // Keep the historical short reset for unrelated K11-B checks, but
        // use a PCIe-style 100 us hold for the K14 reboot experiment.
        if (k14_reboot_active)
            repeat (K14_PERST_HOLD_REFCLK_CYCLES) @(posedge refclk_p);
        else
            repeat (500) @(posedge refclk_p);
        sys_rst_n = 1'b1;
        if (k14_reboot_active) begin
            $display("K14_EP_PERST_RELEASE time_ps=%0t", $time);
            // Release the RP only after the Endpoint PHY has had a complete
            // reset-release interval, so the RP's first Detect window cannot
            // precede Endpoint readiness on a warm reboot.
            repeat (K14_RP_RELEASE_DELAY_REFCLK_CYCLES) @(posedge refclk_p);
        end
        rp_sys_rst_n = 1'b1;
        if (k14_reboot_active)
            $display("K14_RP_RESET_RELEASE time_ps=%0t", $time);
        $display("K11B_RESET_RELEASE time_ps=%0t disconnect=%0d", $time,
                 disconnect_lane0);
        if (k13_retrain_active)
            $display("K13_VCS_RETRAIN_SOURCE rp=%0d ep=%0d",
                     k13_do_rp_retrain, k13_do_ep_retrain);
    end

    // 正常模式仅连接 Lane 0。断线 Stub 把双方 RX 固定为差分静默值。
    assign ep_rxp = disconnect_lane0 ? 1'b0 : rp_txp[0];
    assign ep_rxn = disconnect_lane0 ? 1'b0 : rp_txn[0];
    assign rp_rxp = {7'b0, (disconnect_lane0 ? 1'b0 : ep_txp)};
    assign rp_rxn = {7'b0, (disconnect_lane0 ? 1'b0 : ep_txn)};

    k11b_endpoint_compat #(
        .DETECT_QUIET_CYCLES   (EP_DETECT_QUIET_CYCLES),
        .DETECT_TIMEOUT_CYCLES (EP_DETECT_TIMEOUT_CYCLES),
        .TRAIN_TIMEOUT_CYCLES  (EP_TRAIN_TIMEOUT_CYCLES),
        .HOT_RESET_CYCLES      (EP_HOT_RESET_CYCLES)
    ) EP (
        .pcie_refclk_p (refclk_p),
        .pcie_refclk_n (refclk_n),
        .pcie_perst_n  (sys_rst_n),
        .pcie_rxp      (ep_rxp),
        .pcie_rxn      (ep_rxn),
        .pcie_txp      (ep_txp),
        .pcie_txn      (ep_txn),
        .led           (ep_led)
    );

    xilinx_pcie3_uscale_rp #(
        .C_DATA_WIDTH                       (256),
        .PL_LINK_CAP_MAX_LINK_SPEED         (3'h4),
        .PL_LINK_CAP_MAX_LINK_WIDTH         (4'h8),
        .PF0_DEV_CAP_MAX_PAYLOAD_SIZE       (3'h2),
        .REF_CLK_FREQ                       (0)
    ) RP (
        .pci_exp_txp (rp_txp),
        .pci_exp_txn (rp_txn),
        .pci_exp_rxp (rp_rxp),
        .pci_exp_rxn (rp_rxn),
        .sys_clk_p   (refclk_p),
        .sys_clk_n   (refclk_n),
        .sys_rst_n   (rp_reset_n)
    );

`ifdef K11B2_DUT
    // Standalone-PHY-only diagnostic for K15.  Wait until the normal K14
    // rate transaction commits Gen3, then loop the Endpoint serial output
    // back into its own RX pins.  The Root Port remains connected, so this
    // isolates the Endpoint GT/PCS receive path without changing any PHY IP.
    initial begin : k15_local_phy_loopback
        integer wait_cycles;
        integer rx_cycles;
        reg gen3_rx_seen;
        reg gt_loopback_forced;
        if ($test$plusargs("K15_LOCAL_PHY_LOOPBACK")) begin
            wait_cycles = 0;
            rx_cycles = 0;
            gen3_rx_seen = 1'b0;
            gt_loopback_forced = 1'b0;
            wait (sys_rst_n === 1'b1);
            while ((EP.DUT.phy_active_rate != 2'b10) &&
                   (wait_cycles < 1_500_000)) begin
                @(posedge EP.DUT.phy_pclk);
                wait_cycles = wait_cycles + 1;
            end
            if (EP.DUT.phy_active_rate != 2'b10) begin
                $display("K15_LOCAL_PHY_LOOPBACK_BLOCKED wait=%0d rate=%02b phystatus=%0d",
                         wait_cycles, EP.DUT.phy_active_rate,
                         EP.DUT.phy_phystatus);
                $finish;
            end

            if ($test$plusargs("K15_GT_LOOPBACK")) begin
                // Ultrascale loopback encoding: 001 is near-end PCS, which
                // keeps the test at the Gen3 PCS boundary without requiring
                // an external serial channel model.
                force EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.GT_LOOPBACK = 3'b001;
                gt_loopback_forced = 1'b1;
                $display("K15_LOCAL_PHY_LOOPBACK_ENABLE mode=gt_internal time_ps=%0t rate=%02b",
                         $time, EP.DUT.phy_active_rate);
            end else begin
                force ep_rxp = ep_txp;
                force ep_rxn = ep_txn;
                $display("K15_LOCAL_PHY_LOOPBACK_ENABLE mode=serial_pins time_ps=%0t rate=%02b",
                         $time, EP.DUT.phy_active_rate);
            end
            while ((EP.DUT.phy_active_rate == 2'b10) &&
                   !gen3_rx_seen && (rx_cycles < 100_000)) begin
                @(posedge EP.DUT.phy_pclk);
                rx_cycles = rx_cycles + 1;
                if ((EP.DUT.phy_active_rate == 2'b10) &&
                    (EP.DUT.phy_rxvalid || EP.DUT.phy_rxdata_valid ||
                     EP.DUT.phy_rxstart_block))
                    gen3_rx_seen = 1'b1;
            end
            $display("K15_LOCAL_PHY_LOOPBACK_RESULT wait=%0d rx_cycles=%0d gen3_rx_seen=%0d active_rate=%02b rxvalid=%0d data_valid=%0d start=%0d header=%02b data=%08x rxstatus=%03b rxelecidle=%0d rxsyncedone=%0d rst_fsm=%0d rst_idle=%0d prst_n=%0d rrst_n=%0d cdrlock=%0d rxresetdone=%0d rate_gen3=%0d user_gen3_rdy=%0d rate_idle=%0d",
                     wait_cycles, rx_cycles, gen3_rx_seen,
                     EP.DUT.phy_active_rate, EP.DUT.phy_rxvalid,
                     EP.DUT.phy_rxdata_valid, EP.DUT.phy_rxstart_block,
                     EP.DUT.phy_rxsync_header, EP.DUT.phy_rxdata,
                     EP.DUT.phy_rxstatus, EP.DUT.phy_rxelecidle,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_pciesynctxsyncdone,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.phy_rst_i.fsm,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.rst_idle,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.prst_n,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.rrst_n,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_rxcdrlock,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_rxresetdone,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_pcierategen3,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_pcieusergen3rdy,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_pcierateidle);
            if (gen3_rx_seen)
                $display("K15_LOCAL_PHY_LOOPBACK_PASS");
            else
                $display("K15_LOCAL_PHY_LOOPBACK_FAIL");
            if (gt_loopback_forced)
                release EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.GT_LOOPBACK;
            else begin
                release ep_rxp;
                release ep_rxn;
            end
            $finish;
        end
    end
`endif

`ifdef K13_DUT
    wire k13_pipe_compare_active = k13_pipe_compare_enabled &&
        ((!k13_initial_gen1_l0_seen || EP.DUT.k13_fallback_sticky) &&
         (EP.DUT.phy_rate == 2'b00) &&
         (RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_rate == 2'b00));
    wire k13_compare_epoch = EP.DUT.k13_fallback_sticky;

    wire rp_os_event_valid, gt_os_event_valid, pipe_os_event_valid;
    wire [1:0] rp_os_event_kind, gt_os_event_kind, pipe_os_event_kind;
    wire [11:0] rp_os_event_seq, gt_os_event_seq, pipe_os_event_seq;
    wire [63:0] rp_os_start_ps, rp_os_end_ps;
    wire [63:0] gt_os_start_ps, gt_os_end_ps;
    wire [63:0] pipe_os_start_ps, pipe_os_end_ps;

    k13_gen1_os_boundary_monitor #(.BOUNDARY_ID(0)) RP_PIPE_OS_MON (
        .clk(EP.DUT.phy_pclk), .rst_n(EP.DUT.pipe_rst_n),
        .enable(k13_pipe_compare_active), .epoch(k13_compare_epoch),
        .sample_valid(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data_valid &&
                      !RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_elec_idle),
        .sample_data(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data[15:0]),
        .sample_datak(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_char_is_k),
        .ltssm_state(RP.cfg_ltssm_state),
        .event_valid(rp_os_event_valid), .event_kind(rp_os_event_kind),
        .event_seq(rp_os_event_seq), .event_start_ps(rp_os_start_ps),
        .event_end_ps(rp_os_end_ps)
    );

    k13_gen1_os_boundary_monitor #(.BOUNDARY_ID(1)) EP_GT_OS_MON (
        .clk(EP.DUT.phy_pclk), .rst_n(EP.DUT.pipe_rst_n),
        .enable(k13_pipe_compare_active), .epoch(k13_compare_epoch),
        .sample_valid(EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.rxvalid_out[0]),
        .sample_data(EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.rxdata_out[15:0]),
        .sample_datak(EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.rxctrl0_out[1:0]),
        .ltssm_state(EP.DUT.ltssm_state),
        .event_valid(gt_os_event_valid), .event_kind(gt_os_event_kind),
        .event_seq(gt_os_event_seq), .event_start_ps(gt_os_start_ps),
        .event_end_ps(gt_os_end_ps)
    );

    k13_gen1_os_boundary_monitor #(.BOUNDARY_ID(2)) EP_PIPE_OS_MON (
        .clk(EP.DUT.phy_pclk), .rst_n(EP.DUT.pipe_rst_n),
        .enable(k13_pipe_compare_active), .epoch(k13_compare_epoch),
        .sample_valid(EP.DUT.phy_rxvalid),
        .sample_data(EP.DUT.phy_rxdata[15:0]),
        .sample_datak(EP.DUT.phy_rxdatak),
        .ltssm_state(EP.DUT.ltssm_state),
        .event_valid(pipe_os_event_valid), .event_kind(pipe_os_event_kind),
        .event_seq(pipe_os_event_seq), .event_start_ps(pipe_os_start_ps),
        .event_end_ps(pipe_os_end_ps)
    );

    reg [1:0] rp_compare_kind [0:4095];
    reg [1:0] gt_compare_kind [0:4095];
    reg [63:0] rp_compare_start [0:4095];
    reg [63:0] rp_compare_end [0:4095];
    reg [63:0] gt_compare_start [0:4095];
    reg [63:0] gt_compare_end [0:4095];
    integer rp_compare_count;
    integer gt_compare_count;
    integer pipe_compare_count;
    integer rp_compare_cursor;
    integer gt_compare_cursor;
    integer compare_index;
    integer compare_match;

    always @(posedge EP.DUT.phy_pclk) begin
        if (!EP.DUT.pipe_rst_n || !k13_pipe_compare_active) begin
            rp_compare_count = 0;
            gt_compare_count = 0;
            pipe_compare_count = 0;
            rp_compare_cursor = 0;
            gt_compare_cursor = 0;
        end else begin
            if (rp_os_event_valid && (rp_os_event_seq < 4096)) begin
                rp_compare_kind[rp_os_event_seq] = rp_os_event_kind;
                rp_compare_start[rp_os_event_seq] = rp_os_start_ps;
                rp_compare_end[rp_os_event_seq] = rp_os_end_ps;
                rp_compare_count = rp_os_event_seq + 1;
            end
            if (gt_os_event_valid && (gt_os_event_seq < 4096)) begin
                gt_compare_kind[gt_os_event_seq] = gt_os_event_kind;
                gt_compare_start[gt_os_event_seq] = gt_os_start_ps;
                gt_compare_end[gt_os_event_seq] = gt_os_end_ps;
                gt_compare_count = gt_os_event_seq + 1;
                compare_match = -1;
                for (compare_index = rp_compare_cursor;
                     compare_index < rp_compare_count;
                     compare_index = compare_index + 1)
                    if ((compare_match < 0) &&
                        (rp_compare_kind[compare_index] == gt_os_event_kind))
                        compare_match = compare_index;
                if (gt_os_event_seq < 128) begin
                    if (compare_match >= 0)
                        $display("K13_PIPE_COMPARE epoch=%0d boundary=RP_TO_GT dst_seq=%0d kind=%0d src_seq=%0d skipped=%0d start_delay_ps=%0d end_delay_ps=%0d",
                                 k13_compare_epoch, gt_os_event_seq,
                                 gt_os_event_kind, compare_match,
                                 compare_match - rp_compare_cursor,
                                 gt_os_start_ps - rp_compare_start[compare_match],
                                 gt_os_end_ps - rp_compare_end[compare_match]);
                    else
                        $display("K13_PIPE_COMPARE_UNMATCHED epoch=%0d boundary=RP_TO_GT dst_seq=%0d kind=%0d available_src=%0d",
                                 k13_compare_epoch, gt_os_event_seq,
                                 gt_os_event_kind, rp_compare_count);
                end
                if (compare_match >= 0)
                    rp_compare_cursor = compare_match + 1;
            end
            if (pipe_os_event_valid && (pipe_os_event_seq < 4096)) begin
                pipe_compare_count = pipe_os_event_seq + 1;
                compare_match = -1;
                for (compare_index = gt_compare_cursor;
                     compare_index < gt_compare_count;
                     compare_index = compare_index + 1)
                    if ((compare_match < 0) &&
                        (gt_compare_kind[compare_index] == pipe_os_event_kind))
                        compare_match = compare_index;
                if (pipe_os_event_seq < 128) begin
                    if (compare_match >= 0)
                        $display("K13_PIPE_COMPARE epoch=%0d boundary=GT_TO_PIPE dst_seq=%0d kind=%0d src_seq=%0d skipped=%0d start_delay_ps=%0d end_delay_ps=%0d",
                                 k13_compare_epoch, pipe_os_event_seq,
                                 pipe_os_event_kind, compare_match,
                                 compare_match - gt_compare_cursor,
                                 pipe_os_start_ps - gt_compare_start[compare_match],
                                 pipe_os_end_ps - gt_compare_end[compare_match]);
                    else
                        $display("K13_PIPE_COMPARE_UNMATCHED epoch=%0d boundary=GT_TO_PIPE dst_seq=%0d kind=%0d available_src=%0d",
                                 k13_compare_epoch, pipe_os_event_seq,
                                 pipe_os_event_kind, gt_compare_count);
                end
                if (compare_match >= 0)
                    gt_compare_cursor = compare_match + 1;
            end
        end
    end

    always @(posedge EP.DUT.phy_pclk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            k13_initial_gen1_l0_seen <= 1'b0;
        else if (EP.DUT.link_up && EP.DUT.dll_active && RP.user_lnk_up)
            k13_initial_gen1_l0_seen <= 1'b1;
    end
`endif

`ifdef K12E_VCS
    k12e_phy_monitor K12E_PHY_MONITOR (
        .clk             (EP.DUT.phy_pclk),
        .rst_n           (EP.DUT.pipe_rst_n),
        .link_up         (EP.DUT.link_up),
        .phy_rate       (EP.DUT.phy_rate),
        .phy_phystatus  (EP.DUT.phy_phystatus),
        .phy_txeq_done  (EP.DUT.phy_txeq_done),
        .phy_rxeq_done  (EP.DUT.phy_rxeq_done),
        .phy_txeq_ctrl  (EP.DUT.phy_txeq_ctrl),
        .phy_rxeq_ctrl  (EP.DUT.phy_rxeq_ctrl)
    );
`endif

    initial begin
        last_ep_state = 6'h3f;
        stable_count = 0;
        seen_detect = 1'b0;
        seen_phy_powerup = 1'b0;
        seen_polling = 1'b0;
        seen_configuration = 1'b0;
        ep_tx_edge_count = 0;
        for (edge_index = 0; edge_index < 8; edge_index = edge_index + 1)
            rp_tx_edge_count[edge_index] = 0;
    end

    always @(ep_txp) ep_tx_edge_count = ep_tx_edge_count + 1;
    always @(rp_txp[0]) rp_tx_edge_count[0] = rp_tx_edge_count[0] + 1;
    always @(rp_txp[1]) rp_tx_edge_count[1] = rp_tx_edge_count[1] + 1;
    always @(rp_txp[2]) rp_tx_edge_count[2] = rp_tx_edge_count[2] + 1;
    always @(rp_txp[3]) rp_tx_edge_count[3] = rp_tx_edge_count[3] + 1;
    always @(rp_txp[4]) rp_tx_edge_count[4] = rp_tx_edge_count[4] + 1;
    always @(rp_txp[5]) rp_tx_edge_count[5] = rp_tx_edge_count[5] + 1;
    always @(rp_txp[6]) rp_tx_edge_count[6] = rp_tx_edge_count[6] + 1;
    always @(rp_txp[7]) rp_tx_edge_count[7] = rp_tx_edge_count[7] + 1;

    always @(RP.cfg_ltssm_state) begin
        if (sys_rst_n)
            $display("K11B_RP_STATE time_ps=%0t state=%0h link=%0d phy_status=%0d speed=%0d width=%0d",
                     $time, RP.cfg_ltssm_state, RP.user_lnk_up,
                     RP.cfg_phy_link_status, RP.cfg_current_speed,
                     RP.cfg_negotiated_width);
    end

`ifdef K13_DUT
    initial begin : k13_gen3_cold_phy_diagnostic
        integer cold_wait;
        integer cold_tx_start_seen;
        integer cold_rx_valid_seen;
        if ($test$plusargs("K13_GEN3_COLD_PHY")) begin
            force EP.DUT.phy_rate = 2'b10;
            force EP.DUT.k13_active_rate = 2'b10;
            force EP.DUT.u_ltssm_mac.active_phy_rate = 2'b10;
            force EP.DUT.u_ltssm_mac.ltssm_state = 6'd11;
            force ep_rxp = ep_txp;
            force ep_rxn = ep_txn;
            wait (EP.DUT.pipe_rst_n === 1'b1);
            cold_wait = 0;
            cold_tx_start_seen = 0;
            cold_rx_valid_seen = 0;
            while (!EP.DUT.phy_rxdata_valid && (cold_wait < 25000)) begin
                @(posedge EP.DUT.phy_pclk);
                if (EP.DUT.phy_txstart_block)
                    cold_tx_start_seen = cold_tx_start_seen + 1;
                if (EP.DUT.phy_rxdata_valid || EP.DUT.phy_rxstart_block)
                    cold_rx_valid_seen = cold_rx_valid_seen + 1;
                cold_wait = cold_wait + 1;
            end
            $display("K13_GEN3_COLD_PHY_RESULT wait=%0d rxvalid=%0d data_valid=%0d start=%0d header=%02b data=%08x tx_edges=%0d txp=%0d txn=%0d txvalid=%0d txstart=%0d txidle=%0d txrate=%02b active_rate=%02b gen3_mode=%0d tx_os_enable=%0d tx_os_mode=%0d gen3_start=%0d tx_start_seen=%0d rx_valid_seen=%0d gt_cdr=%0d gt_rxresetdone=%0d gt_rategen3=%0d gt_gen3rdy=%0d gt_rateidle=%0d rxelecidle=%0d rxctrl0=%04x rawdata=%08x",
                     cold_wait, EP.DUT.phy_rxvalid,
                     EP.DUT.phy_rxdata_valid, EP.DUT.phy_rxstart_block,
                     EP.DUT.phy_rxsync_header, EP.DUT.phy_rxdata,
                     ep_tx_edge_count, ep_txp, EP.DUT.pcie_txn,
                     EP.DUT.phy_txdata_valid, EP.DUT.phy_txstart_block,
                     EP.DUT.phy_txelecidle, EP.DUT.phy_rate,
                     EP.DUT.u_ltssm_mac.active_phy_rate,
                     EP.DUT.u_ltssm_mac.gen3_mode,
                     EP.DUT.u_ltssm_mac.tx_os_enable,
                     EP.DUT.u_ltssm_mac.tx_os_mode,
                     EP.DUT.u_ltssm_mac.gen3_os_tx_start_block,
                     cold_tx_start_seen, cold_rx_valid_seen,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_rxcdrlock,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_rxresetdone,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_pcierategen3,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_pcieusergen3rdy,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_pcierateidle,
                     EP.DUT.phy_rxelecidle,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.rxctrl0_out,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.rxdata_out[31:0]);
            $finish;
        end
    end

    // Diagnostic only: serial loopback distinguishes a local GT/PCS receive
    // problem from cross-device serial interoperability.  Normal regressions
    // never enable this plusarg.
    initial begin : k13_local_loopback_diagnostic
        if ($test$plusargs("K13_LOCAL_LOOPBACK")) begin
            wait (EP.DUT.phy_rate == 2'b10);
            wait (EP.DUT.phy_phystatus == 1'b1);
            @(negedge EP.DUT.phy_phystatus);
            force ep_rxp = ep_txp;
            force ep_rxn = ep_txn;
            $display("K13_LOCAL_LOOPBACK_ENABLE time_ps=%0t mode=external_serial", $time);
        end
    end

    initial begin
        k13_seen_rp_recovery = 1'b0;
        k13_seen_rcvrlock = 1'b0;
        k13_seen_rcvrcfg = 1'b0;
        k13_seen_recovery_speed = 1'b0;
        k13_seen_recovery_idle = 1'b0;
        k13_seen_rate_gen3 = 1'b0;
        k13_seen_phystatus = 1'b0;
        k13_seen_eq_phase = 5'd0;
        k13_gen3_pipe_samples = 0;
        k13_recovery_ts_samples = 0;
        k13_eqts_raw_words = 0;
        k13_gen3_rx_samples = 0;
        k13_rp_pipe_samples = 0;
        k13_rp_fallback_pipe_samples = 0;
        k13_rp_recovery_ts_samples = 0;
        k13_ep_recovery_rx_samples = 0;
        k13_ep_recovery_tx_samples = 0;
        k13_ep_gen3_tx_samples = 0;
        k13_rp_recovery_rx_samples = 0;
        k13_ep_fallback_pipe_samples = 0;
        k13_ep_rx_contract_samples = 0;
        k13_rp_tx_contract_samples = 0;
        k13_rp_tx_edges_at_retrain = 0;
        k13_ep_tx_edges_at_retrain = 0;
        k13_last_rxeq_ctrl = 2'b00;
        k13_last_rxeq_done = 1'b0;
        k13_last_rxeq_adapt_done = 1'b0;
        k13_last_rxeq_fsm = 3'd0;
    end

    always @(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_rate or
             EP.DUT.phy_rate or EP.DUT.phy_phystatus) begin
        if (k13_retrain_monitor_armed)
            $display("K13_RATE_EVENT time_ps=%0t rp_rate=%02b ep_rate=%02b ep_phystatus=%0d rp_state=%0h ep_state=%0d speed_state=%0d rp_rxvalid=%0d rp_rxdata_valid=%0d rp_rxidle=%0d rp_cdr=%0d rp_rxreset=%0d rp_rateidle=%0d rp_rate_start=%0d",
                     $time,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_rate,
                     EP.DUT.phy_rate, EP.DUT.phy_phystatus,
                     RP.cfg_ltssm_state, EP.DUT.ltssm_state,
                     EP.DUT.k13_speed_state,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_valid[0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_data_valid[0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_elec_idle[0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_rxcdrlock[0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_rxresetdone[0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_pcierateidle[0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_pcieuserratestart[0]);
    end

    // Record the first RP-side receive transition after the endpoint starts
    // transmitting Gen3 TS blocks.  This separates a lane that remains
    // electrically idle from a lane that has data but fails PCS/LTSSM decode.
    always @(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_elec_idle[0] or
             RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_valid[0] or
             RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_data_valid[0]) begin
        if (k13_retrain_monitor_armed)
            $display("K13_RP_RX_EVENT time_ps=%0t rp_state=%0h ep_state=%0d ep_rate=%02b ep_txvalid=%0d ep_txidle=%0d ep_txstart=%0d ep_txheader=%02b ep_txdatak=%02b ep_txdata=%08x rp_gt_rate=%02b rp_rategen3=%0d rp_gen3rdy=%0d rp_rxstatus=%03b rp_rxvalid=%0d rp_rxdata_valid=%0d rp_rxidle=%0d rp_cdr=%0d rp_rxresetdone=%0d rp_rateidle=%0d rp_rate_start=%0d rp_gt_data=%08x rp_gt_ctrl=%04x rp_gt_valid=%0d rp_gt_start=%0d rp_gt_header=%02b",
                     $time, RP.cfg_ltssm_state, EP.DUT.ltssm_state,
                     EP.DUT.phy_rate, EP.DUT.phy_txdata_valid,
                     EP.DUT.phy_txelecidle, EP.DUT.phy_txstart_block,
                     EP.DUT.phy_txsync_header, EP.DUT.phy_txdatak,
                     EP.DUT.phy_txdata,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_rate,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.gt_pcierategen3[0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.gt_pcieusergen3rdy[0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_status[2:0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_valid[0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_data_valid[0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_elec_idle[0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_rxcdrlock[0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_rxresetdone[0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_pcierateidle[0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_pcieuserratestart[0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.phy_lane[0].gt_channel_int.gt_channel_i.GT_RXDATA,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.phy_lane[0].gt_channel_int.gt_channel_i.GT_RXDATAK,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.phy_lane[0].gt_channel_int.gt_channel_i.GT_RXDATA_VALID,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.phy_lane[0].gt_channel_int.gt_channel_i.GT_RXSTART_BLOCK,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.phy_lane[0].gt_channel_int.gt_channel_i.GT_RXSYNC_HEADER);
    end

    always @(posedge EP.DUT.phy_pclk) begin
        if (k13_retrain_monitor_armed && EP.DUT.pipe_rst_n) begin
            // Capture Root-Port PIPE words before Endpoint parsing.  The
            // capability Rate ID and directed speed-change indication must
            // be distinguished from this raw source evidence.
            if ((RP.cfg_ltssm_state != 6'h10) &&
                RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data_valid &&
                (k13_rp_pipe_samples < 128)) begin
                $display("K13_RP_PIPE_RAW n=%0d time_ps=%0t state=%0h rate=%02b idle=%0d valid=%0d start=%0d data=%08x ep_state=%0d",
                         k13_rp_pipe_samples, $time, RP.cfg_ltssm_state,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_rate,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_elec_idle,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data_valid,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_start_block,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data,
                         EP.DUT.ltssm_state);
                k13_rp_pipe_samples = k13_rp_pipe_samples + 1;
            end
            if (EP.DUT.k13_fallback_sticky &&
                (EP.DUT.phy_rate == 2'b00) &&
                (RP.cfg_ltssm_state != 6'h10) &&
                (RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_rate == 2'b00) &&
                RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data_valid &&
                (k13_rp_fallback_pipe_samples < 128)) begin
                $display("K13_RP_FALLBACK_PIPE_RAW n=%0d time_ps=%0t state=%0h rate=%02b idle=%0d valid=%0d start=%0d data=%08x ep_state=%0d speed_state=%0d",
                         k13_rp_fallback_pipe_samples, $time,
                         RP.cfg_ltssm_state,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_rate,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_elec_idle,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data_valid,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_start_block,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data,
                         EP.DUT.ltssm_state, EP.DUT.k13_speed_state);
                k13_rp_fallback_pipe_samples =
                    k13_rp_fallback_pipe_samples + 1;
            end
            if (EP.DUT.k13_fallback_sticky &&
                (RP.cfg_ltssm_state == 6'h0b ||
                 RP.cfg_ltssm_state == 6'h0d) &&
                (RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_rate == 2'b00) &&
                !RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_elec_idle &&
                RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data_valid &&
                (k13_rp_recovery_ts_samples < 128)) begin
                $display("K13_RP_RECOVERY_TS_RAW n=%0d time_ps=%0t state=%0h rate=%02b idle=%0d valid=%0d start=%0d data=%08x ep_state=%0d rx_ts=%0d",
                         k13_rp_recovery_ts_samples, $time,
                         RP.cfg_ltssm_state,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_rate,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_elec_idle,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data_valid,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_start_block,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data,
                         EP.DUT.ltssm_state, EP.DUT.rx_ts_count);
                k13_rp_recovery_ts_samples =
                    k13_rp_recovery_ts_samples + 1;
            end
            if (EP.DUT.k13_fallback_sticky &&
                (EP.DUT.ltssm_state == 6'd11 ||
                 EP.DUT.ltssm_state == 6'd12) &&
                EP.DUT.phy_rxvalid &&
                (k13_ep_recovery_rx_samples < 128)) begin
                $display("K13_EP_RECOVERY_RX_RAW n=%0d time_ps=%0t state=%0d rxvalid=%0d data_valid=%0d start=%0d datak=%02b data=%08x rp_state=%0h rp_rate=%02b rp_idle=%0d rp_valid=%0d",
                         k13_ep_recovery_rx_samples, $time,
                         EP.DUT.ltssm_state, EP.DUT.phy_rxvalid,
                         EP.DUT.phy_rxdata_valid, EP.DUT.phy_rxstart_block,
                         EP.DUT.phy_rxdatak, EP.DUT.phy_rxdata,
                         RP.cfg_ltssm_state,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_rate,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_elec_idle,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data_valid);
                k13_ep_recovery_rx_samples =
                    k13_ep_recovery_rx_samples + 1;
            end
            if (EP.DUT.k13_fallback_sticky &&
                (EP.DUT.phy_rate == 2'b00) &&
                !EP.DUT.phy_txelecidle &&
                EP.DUT.phy_txdata_valid &&
                (k13_ep_fallback_pipe_samples < 128)) begin
                $display("K13_EP_FALLBACK_PIPE_RAW n=%0d time_ps=%0t ep_state=%0d speed_state=%0d txidle=%0d valid=%0d start=%0d datak=%02b data=%08x rp_state=%0h",
                         k13_ep_fallback_pipe_samples, $time,
                         EP.DUT.ltssm_state, EP.DUT.k13_speed_state,
                         EP.DUT.phy_txelecidle, EP.DUT.phy_txdata_valid,
                         EP.DUT.phy_txstart_block, EP.DUT.phy_txdatak,
                         EP.DUT.phy_txdata, RP.cfg_ltssm_state);
                k13_ep_fallback_pipe_samples =
                    k13_ep_fallback_pipe_samples + 1;
            end
            if ((EP.DUT.phy_rxeq_ctrl != k13_last_rxeq_ctrl) ||
                (EP.DUT.phy_rxeq_done != k13_last_rxeq_done) ||
                (EP.DUT.phy_rxeq_adapt_done != k13_last_rxeq_adapt_done) ||
                (EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.phy_lane[0].phy_rxeq_i.fsm != k13_last_rxeq_fsm)) begin
                $display("K13_RXEQ_EVENT time_ps=%0t ctrl=%02b txpreset=%0d done=%0d adapt_done=%0d preset_sel=%0d new_txcoeff=%05x fsm=%0d post_active=%0d post_ready=%0d gtreset=%0d userrdy=%0d progreset=%0d progdone=%0d",
                         $time, EP.DUT.phy_rxeq_ctrl,
                         EP.DUT.phy_rxeq_txpreset,
                         EP.DUT.phy_rxeq_done,
                         EP.DUT.phy_rxeq_adapt_done,
                         EP.DUT.phy_rxeq_preset_sel,
                         EP.DUT.phy_rxeq_new_txcoeff,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.phy_lane[0].phy_rxeq_i.fsm,
                         EP.DUT.g_k13_enabled_top.u_k13_production_ctrl.post_rate_rxeq_active,
                         EP.DUT.g_k13_enabled_top.u_k13_production_ctrl.post_rate_rxeq_ready,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.gtrxreset_in,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.rxuserrdy_in,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.rxprogdivreset_in,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.rxprgdivresetdone_out[0]);
                k13_last_rxeq_ctrl <= EP.DUT.phy_rxeq_ctrl;
                k13_last_rxeq_done <= EP.DUT.phy_rxeq_done;
                k13_last_rxeq_adapt_done <= EP.DUT.phy_rxeq_adapt_done;
                k13_last_rxeq_fsm <= EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.phy_lane[0].phy_rxeq_i.fsm;
            end
            if (RP.cfg_ltssm_state != 6'h10)
                k13_seen_rp_recovery <= 1'b1;
            if (EP.DUT.ltssm_state == 6'd11)
                k13_seen_rcvrlock <= 1'b1;
            if (EP.DUT.ltssm_state == 6'd12)
                k13_seen_rcvrcfg <= 1'b1;
            if (EP.DUT.ltssm_state == 6'd18)
                k13_seen_recovery_speed <= 1'b1;
            if (EP.DUT.ltssm_state == 6'd13)
                k13_seen_recovery_idle <= 1'b1;
            if (EP.DUT.phy_rate == 2'b10)
                k13_seen_rate_gen3 <= 1'b1;
            if (EP.DUT.phy_phystatus)
                k13_seen_phystatus <= 1'b1;
            if (EP.DUT.k13_eq_active && (EP.DUT.k13_eq_phase <= 3'd3))
                k13_seen_eq_phase[EP.DUT.k13_eq_phase] <= 1'b1;
            if (EP.DUT.k13_eq_done)
                k13_seen_eq_phase[4] <= 1'b1;
            if ((EP.DUT.os_ts1_valid || EP.DUT.os_ts2_valid ||
                 EP.DUT.os_malformed) &&
                (k13_recovery_ts_samples < 512)) begin
                $display("K13_RECOVERY_TS n=%0d ep_state=%0d ts1=%0d ts2=%0d malformed=%0d link=%02x lane=%02x rate=%02x ctrl=%02x eq_ctrl=%02x eq_data=%06x rx_count=%0d",
                         k13_recovery_ts_samples, EP.DUT.ltssm_state,
                         EP.DUT.os_ts1_valid, EP.DUT.os_ts2_valid,
                         EP.DUT.os_malformed, EP.DUT.os_link_number,
                         EP.DUT.os_lane_number, EP.DUT.os_rate_id,
                         EP.DUT.os_training_control, EP.DUT.os_eq_control,
                         EP.DUT.os_eq_data, EP.DUT.rx_ts_count);
                if (EP.DUT.os_malformed)
                    $display("K13_GEN3_RX_MALFORMED_DETAIL block=%0d word=%0d parse_error=%0d lfsr_ready=%0d start=%0d valid=%0d header=%02b data=%08x",
                             EP.DUT.u_ltssm_mac.u_gen3_os_rx.block_kind,
                             EP.DUT.u_ltssm_mac.u_gen3_os_rx.word_index,
                             EP.DUT.u_ltssm_mac.u_gen3_os_rx.parse_error,
                             EP.DUT.u_ltssm_mac.u_gen3_os_rx.lfsr_ready,
                             EP.DUT.phy_rxstart_block, EP.DUT.phy_rxdata_valid,
                             EP.DUT.phy_rxsync_header, EP.DUT.phy_rxdata);
                k13_recovery_ts_samples <= k13_recovery_ts_samples + 1;
            end
            if ((EP.DUT.ltssm_state == 6'd12) &&
                EP.DUT.u_ltssm_mac.rx_raw_aligned_valid &&
                (k13_eqts_raw_words < 96)) begin
                $display("K13_EQTS_RAW n=%0d parser_active=%0d word_index=%0d datak=%02b data=%04x",
                         k13_eqts_raw_words,
                         EP.DUT.u_ltssm_mac.u_os_rx.active,
                         EP.DUT.u_ltssm_mac.u_os_rx.word_index,
                         EP.DUT.u_ltssm_mac.rx_raw_aligned_datak,
                         EP.DUT.u_ltssm_mac.rx_raw_aligned_data);
                k13_eqts_raw_words <= k13_eqts_raw_words + 1;
            end
            if ((EP.DUT.phy_rate == 2'b10) &&
                (k13_gen3_pipe_samples < 256) &&
                (EP.DUT.phy_rxdata_valid || EP.DUT.phy_rxstart_block ||
                 EP.DUT.phy_txdata_valid || EP.DUT.phy_txstart_block)) begin
                $display("K13_GEN3_PIPE_SAMPLE n=%0d time_ps=%0t rp_rate=%02b rp_txidle=%0d rp_txvalid=%0d rp_txstart=%0d rp_txheader=%02b rp_txdata=%08x rxvalid=%0d rx_data_valid=%0d rx_start=%0d rx_header=%02b rx_data=%08x tx_valid=%0d tx_start=%0d tx_header=%02b tx_data=%08x",
                         k13_gen3_pipe_samples, $time,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_rate,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_elec_idle,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data_valid,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_start_block,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_syncheader,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data,
                         EP.DUT.phy_rxvalid,
                         EP.DUT.phy_rxdata_valid,
                         EP.DUT.phy_rxstart_block,
                         EP.DUT.phy_rxsync_header,
                         EP.DUT.phy_rxdata,
                         EP.DUT.phy_txdata_valid,
                         EP.DUT.phy_txstart_block,
                         EP.DUT.phy_txsync_header,
                         EP.DUT.phy_txdata);
                k13_gen3_pipe_samples <= k13_gen3_pipe_samples + 1;
            end
            if ((EP.DUT.ltssm_state == 6'd12) && EP.DUT.k13_eq_done &&
                EP.DUT.phy_txdata_valid && (k13_ep_recovery_tx_samples < 256)) begin
                $display("K13_EP_RECOVERY_TX_RAW n=%0d time_ps=%0t state=%0d rate_cmd=%02b active_rate=%02b valid=%0d start=%0d header=%02b data=%08x mode=%02b gen3_mode=%0d",
                         k13_ep_recovery_tx_samples, $time,
                         EP.DUT.ltssm_state, EP.DUT.phy_rate,
                         EP.DUT.g_k13_enabled_top.u_k13_production_ctrl.active_rate,
                         EP.DUT.phy_txdata_valid, EP.DUT.phy_txstart_block,
                         EP.DUT.phy_txsync_header, EP.DUT.phy_txdata,
                         EP.DUT.u_ltssm_mac.tx_os_mode,
                         EP.DUT.u_ltssm_mac.gen3_mode);
                k13_ep_recovery_tx_samples <= k13_ep_recovery_tx_samples + 1;
            end
            if ((EP.DUT.phy_rate == 2'b10) && EP.DUT.phy_txdata_valid &&
                (k13_ep_gen3_tx_samples < 64)) begin
                $display("K13_EP_GEN3_TX_RAW n=%0d time_ps=%0t state=%0d rate=%02b idle=%0d valid=%0d start=%0d header=%02b datak=%02b data=%08x mode=%02b gen3_mode=%0d",
                         k13_ep_gen3_tx_samples, $time,
                         EP.DUT.ltssm_state, EP.DUT.phy_rate,
                         EP.DUT.phy_txelecidle, EP.DUT.phy_txdata_valid,
                         EP.DUT.phy_txstart_block, EP.DUT.phy_txsync_header,
                         EP.DUT.phy_txdatak, EP.DUT.phy_txdata,
                         EP.DUT.u_ltssm_mac.tx_os_mode,
                         EP.DUT.u_ltssm_mac.gen3_mode);
                k13_ep_gen3_tx_samples <= k13_ep_gen3_tx_samples + 1;
            end
            // Capture RP's incoming Gen3 stream during the normal retrain
            // epoch as well as fallback.  The previous fallback-only gate
            // left the decisive EP->RP TS2 direction unobserved on the
            // normal (no-fallback) failure path.
            if (k13_retrain_monitor_armed &&
                (RP.cfg_ltssm_state == 6'h0c) &&
                RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_data_valid &&
                (k13_rp_recovery_rx_samples < 256)) begin
                $display("K13_RP_RECOVERY_RX_RAW n=%0d time_ps=%0t state=%0h valid=%0d start=%0d header=%02b data=%08x ep_state=%0d",
                         k13_rp_recovery_rx_samples, $time,
                         RP.cfg_ltssm_state,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_data_valid,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_start_block,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_syncheader,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_data,
                         EP.DUT.ltssm_state);
                k13_rp_recovery_rx_samples <= k13_rp_recovery_rx_samples + 1;
            end
            if ((EP.DUT.phy_rate == 2'b10) &&
                (RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_rate == 2'b10) &&
                (k13_gen3_rx_samples < 256) &&
                (!RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_elec_idle ||
                 EP.DUT.phy_rxdata_valid || EP.DUT.phy_rxstart_block)) begin
                $display("K13_GEN3_RX_SAMPLE n=%0d time_ps=%0t rp_state=%0h rp_idle=%0d rp_valid=%0d rp_start=%0d rp_header=%02b rp_data=%08x ep_rxvalid=%0d ep_data_valid=%0d ep_start=%0d ep_header=%02b ep_data=%08x cdr=%0d rxreset=%0d rategen3=%0d gen3rdy=%0d rateidle=%0d rxctrl0=%04x rawdata=%08x",
                         k13_gen3_rx_samples, $time, RP.cfg_ltssm_state,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_elec_idle,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data_valid,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_start_block,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_syncheader,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data,
                         EP.DUT.phy_rxvalid, EP.DUT.phy_rxdata_valid,
                         EP.DUT.phy_rxstart_block, EP.DUT.phy_rxsync_header,
                         EP.DUT.phy_rxdata,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_rxcdrlock,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_rxresetdone,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_pcierategen3,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_pcieusergen3rdy,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_pcierateidle,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.rxctrl0_out,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.rxdata_out[31:0]);
                k13_gen3_rx_samples <= k13_gen3_rx_samples + 1;
            end
            // Capture the full Gen3 RX contract even when the GT has not yet
            // asserted PIPE RxDataValid.  This distinguishes "no serial
            // recovery" from a PCS decode problem and records the GT rate,
            // CDR, reset-done and Gen3-ready indications at the first
            // divergence.
            if ((EP.DUT.phy_rate == 2'b10) &&
                (k13_ep_rx_contract_samples < 64)) begin
                $display("K13_EP_RX_CONTRACT n=%0d time_ps=%0t ep_state=%0d rate=%02b txei=%0d rxelecidle=%0d rxvalid=%0d rxstatus=%03b data_valid=%0d start=%0d header=%02b data=%08x gt_cdr=%0d gt_rxresetdone=%0d gt_rategen3=%0d gt_gen3rdy=%0d gt_rateidle=%0d rxctrl0=%04x rawdata=%08x rp_state=%0h rp_txrate=%02b rp_txidle=%0d rp_txvalid=%0d",
                         k13_ep_rx_contract_samples, $time,
                         EP.DUT.ltssm_state, EP.DUT.phy_rate,
                         EP.DUT.phy_txelecidle, EP.DUT.phy_rxelecidle,
                         EP.DUT.phy_rxvalid, EP.DUT.phy_rxstatus,
                         EP.DUT.phy_rxdata_valid, EP.DUT.phy_rxstart_block,
                         EP.DUT.phy_rxsync_header, EP.DUT.phy_rxdata,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_rxcdrlock,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_rxresetdone,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_pcierategen3,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_pcieusergen3rdy,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_pcierateidle,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.rxctrl0_out,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.rxdata_out[31:0],
                         RP.cfg_ltssm_state,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_rate,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_elec_idle,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data_valid);
                k13_ep_rx_contract_samples = k13_ep_rx_contract_samples + 1;
            end
            // Capture Root Port's Gen3 transmit contract independently of
            // Endpoint state; the endpoint may switch rate before the RP
            // commits its own directed speed change.
            if ((RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_rate == 2'b10) &&
                (k13_rp_tx_contract_samples < 64)) begin
                $display("K13_RP_TX_CONTRACT n=%0d time_ps=%0t rp_state=%0h rate=%02b idle=%0d valid=%0d start=%0d header=%02b data=%08x ep_state=%0d ep_rate=%02b ep_rxvalid=%0d ep_rxdata_valid=%0d rp_rxvalid=%0d rp_rxdata_valid=%0d rp_rxidle=%0d rp_cdr=%0d rp_rxreset=%0d rp_rateidle=%0d rp_rate_start=%0d rp_txreset=%0d rp_qplllock=%0d rp_gtpower=%0d rp_gt_txidle=%0d rp_gt_txvalid=%0d rp_gt_txstart=%0d rp_gt_txheader=%02b rp_gt_txdata=%08x",
                         k13_rp_tx_contract_samples, $time,
                         RP.cfg_ltssm_state,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_rate,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_elec_idle,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data_valid,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_start_block,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_syncheader,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data,
                         EP.DUT.ltssm_state, EP.DUT.phy_rate,
                         EP.DUT.phy_rxvalid, EP.DUT.phy_rxdata_valid,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_valid[0],
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_data_valid[0],
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_elec_idle[0],
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_rxcdrlock[0],
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_rxresetdone[0],
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_pcierateidle[0],
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_pcieuserratestart[0],
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_txresetdone[0],
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_qpll1lock[0],
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_gtpowergood[0],
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.phy_lane[0].gt_channel_int.gt_channel_i.GT_TXELECIDLE,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.phy_lane[0].gt_channel_int.gt_channel_i.GT_TXDATA_VALID,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.phy_lane[0].gt_channel_int.gt_channel_i.GT_TXSTART_BLOCK,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.phy_lane[0].gt_channel_int.gt_channel_i.GT_TXSYNC_HEADER,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.phy_lane[0].gt_channel_int.gt_channel_i.GT_TXDATA);
                k13_rp_tx_contract_samples = k13_rp_tx_contract_samples + 1;
            end
        end
    end
`endif

    always @(posedge EP.DUT.phy_pclk) begin
        if (!EP.DUT.pipe_rst_n) begin
            last_ep_state <= 6'h3f;
            stable_count <= 0;
        end else begin
            if (EP.DUT.ltssm_state != last_ep_state) begin
                $display("K11B_EP_STATE time_ps=%0t state=%0d rx_ts=%0d train_err=%0d timeout=%0d ep_pipe_rate=%0d ep_txvalid=%0d ep_txidle=%0d rp_pipe_rate=%0d rp_txvalid=%0d rp_txidle=%0d",
                         $time, EP.DUT.ltssm_state, EP.DUT.rx_ts_count,
                         EP.DUT.training_error_count, EP.DUT.timeout_count,
                         EP.DUT.phy_rate, EP.DUT.phy_txdata_valid,
                         EP.DUT.phy_txelecidle,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_rate,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data_valid,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_elec_idle);
                last_ep_state <= EP.DUT.ltssm_state;
            end

            if (EP.DUT.ltssm_state <= 6'd1)
                seen_detect <= 1'b1;
            if (EP.DUT.ltssm_state == 6'd15) begin
                seen_phy_powerup <= 1'b1;
                if ((EP.DUT.phy_powerdown !== 2'b00) ||
                    (EP.DUT.phy_txdetectrx !== 1'b0) ||
                    (EP.DUT.phy_txelecidle !== 1'b1) ||
                    (EP.DUT.phy_txdata_valid !== 1'b0)) begin
                    $display("K11B_VCS_PHY_CONTRACT_FAIL reason=bad_p0_wait powerdown=%0b txdetect=%0d txidle=%0d txvalid=%0d",
                             EP.DUT.phy_powerdown, EP.DUT.phy_txdetectrx,
                             EP.DUT.phy_txelecidle, EP.DUT.phy_txdata_valid);
                    $fatal(1);
                end
            end
            if ((EP.DUT.ltssm_state == 6'd2) || (EP.DUT.ltssm_state == 6'd3))
                seen_polling <= 1'b1;
            if ((EP.DUT.ltssm_state >= 6'd4) && (EP.DUT.ltssm_state <= 6'd9))
                seen_configuration <= 1'b1;

            // B1只验证物理层/LTSSM。Root user_lnk_up还包含Data Link用户接口
            // 就绪语义，必须等B2接入InitFC/DLL后才作为门禁。
            if ((EP.DUT.link_up === 1'b1) &&
                (RP.cfg_ltssm_state === 6'h10))
                stable_count <= stable_count + 1;
            else
                stable_count <= 0;

            if (!disconnect_lane0 && !b2_active && !k14_reboot_active &&
                (stable_count == STABLE_PCLK_CYCLES-1)) begin
                if (!seen_detect || !seen_phy_powerup || !seen_polling ||
                    !seen_configuration) begin
                    $display("K11B_VCS_GEN1_L0_FAIL reason=missing_state_coverage detect=%0d powerup=%0d polling=%0d config=%0d",
                             seen_detect, seen_phy_powerup, seen_polling,
                             seen_configuration);
                    $fatal(1);
                end
                if ((EP.DUT.negotiated_width !== 3'd1) ||
                    (EP.DUT.negotiated_speed !== 2'b00)) begin
                    $display("K11B_VCS_GEN1_L0_FAIL reason=bad_negotiation width=%0d speed=%0d",
                             EP.DUT.negotiated_width, EP.DUT.negotiated_speed);
                    $fatal(1);
                end
                if (b2_negative_stub) begin
                    if (RP.user_lnk_up !== 1'b0) begin
                        $display("K11B2_CHECKER_SELFTEST_FAIL reason=k03_only_user_link_up");
                        $fatal(1);
                    end
                    $display("K11B2_CHECKER_SELFTEST_PASS reason=k03_only_has_no_dll ep_l0=1 rp_l0=1 rp_user_link=0");
                end else begin
                    $display("K11B_VCS_GEN1_L0_PASS stable_pclk=%0d ep_state=%0d rp_state=%0h rp_user_link=%0d",
                             STABLE_PCLK_CYCLES, EP.DUT.ltssm_state,
                             RP.cfg_ltssm_state, RP.user_lnk_up);
                end
                $finish;
            end
        end
    end

`ifdef K11B2_DUT
`ifdef K14_REBOOT_VCS
    localparam integer K14_AUTO_REQUEST_WAIT_CYCLES = 250_000;
    localparam integer K14_EPOCH_TIMEOUT_CYCLES = 1_500_000;
    integer k14_epoch;
    integer k14_wait_cycles;
    integer k14_final_gen1_stable;
    reg k14_seen_rp_raw_gen3_ts;
    reg k14_seen_partner_gen3_ts;
    reg k14_seen_partner_accept;
    reg k14_seen_gen3_rate;
    reg k14_seen_gen3_phystatus;
    reg k14_seen_qpll_lock;
    reg k14_seen_timeout_fallback;
    reg k14_seen_gen1_rate;
    reg k14_ab_seen_l0;
    reg k14_ab_seen_ep_ts1;
    reg k14_ab_seen_ep_ts2;
    reg k14_ab_seen_rp_ts1;
    reg k14_ab_seen_rp_ts2;
    reg [7:0] k14_ab_ep_rate_or;
    reg [7:0] k14_ab_rp_rate_or;
    integer k14_ab_ep_ts_count;
    integer k14_ab_rp_ts_count;

    wire k14_qpll1lock =
        EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.qpll1lock_out[0];

    // Decode the Root Port's Gen1 PIPE transmitter directly.  This is the
    // source-side proof that a Speed Change TS1 was actually emitted; the
    // Endpoint's os_ts1_valid below is a separate receive/decode observation.
    wire k14_rp_raw_ts1;
    wire k14_rp_raw_ts2;
    wire [7:0] k14_rp_raw_rate_id;
    pcie_gen1_os_rx K14_RP_RAW_TX_OS_RX (
        .clk(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_clk),
        .rst_n(sys_rst_n),
        .enable(k14_reboot_active &&
                (RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_rate == 2'b00) &&
                !RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_elec_idle),
        .in_valid(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data_valid),
        .in_data(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data[15:0]),
        .in_datak(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_char_is_k),
        .ts1_valid(k14_rp_raw_ts1), .ts2_valid(k14_rp_raw_ts2),
        .malformed(), .idle_pair_valid(), .link_number(), .link_is_pad(),
        .lane_number(), .lane_is_pad(), .n_fts(),
        .rate_id(k14_rp_raw_rate_id), .training_control()
    );

    // Decode the Endpoint's actual Gen1 PIPE transmitter independently of
    // u_ltssm_mac.  The A/B result therefore proves which Rate ID reached the
    // Xilinx Root Port model rather than merely reporting controller intent.
    wire k14_ep_raw_ts1;
    wire k14_ep_raw_ts2;
    wire [7:0] k14_ep_raw_rate_id;
    pcie_gen1_os_rx K14_EP_RAW_TX_OS_RX (
        .clk(EP.DUT.phy_pclk), .rst_n(EP.DUT.pipe_rst_n),
        .enable(k14_reboot_active && (EP.DUT.phy_rate == 2'b00) &&
                !EP.DUT.phy_txelecidle),
        .in_valid(EP.DUT.phy_txdata_valid),
        .in_data(EP.DUT.phy_txdata[15:0]),
        .in_datak(EP.DUT.phy_txdatak),
        .ts1_valid(k14_ep_raw_ts1), .ts2_valid(k14_ep_raw_ts2),
        .malformed(), .idle_pair_valid(), .link_number(), .link_is_pad(),
        .lane_number(), .lane_is_pad(), .n_fts(),
        .rate_id(k14_ep_raw_rate_id), .training_control()
    );

    always @(posedge RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_clk or
             negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            k14_seen_rp_raw_gen3_ts <= 1'b0;
            k14_ab_seen_rp_ts1 <= 1'b0;
            k14_ab_seen_rp_ts2 <= 1'b0;
            k14_ab_rp_rate_or <= 8'h00;
            k14_ab_rp_ts_count <= 0;
        end else if (k14_reboot_active && k14_rp_raw_ts1 &&
                     k14_rp_raw_rate_id[7] && k14_rp_raw_rate_id[3]) begin
            k14_seen_rp_raw_gen3_ts <= 1'b1;
            $display("K14_RP_RAW_GEN3_TS epoch=%0d time_ps=%0t rate_id=%02x rp_state=%0h",
                     k14_epoch, $time, k14_rp_raw_rate_id,
                     RP.cfg_ltssm_state);
        end else if (k14_rate_ab_active &&
                     (k14_rp_raw_ts1 || k14_rp_raw_ts2)) begin
            k14_ab_seen_rp_ts1 <= k14_ab_seen_rp_ts1 || k14_rp_raw_ts1;
            k14_ab_seen_rp_ts2 <= k14_ab_seen_rp_ts2 || k14_rp_raw_ts2;
            k14_ab_rp_rate_or <= k14_ab_rp_rate_or | k14_rp_raw_rate_id;
            k14_ab_rp_ts_count <= k14_ab_rp_ts_count + 1;
        end
    end

    // Bounded receiver-side envelope capture.  This distinguishes a PCS
    // block-sync failure (RXDATA_VALID never asserts) from a TS decoder
    // failure after valid Gen3 PIPE data has already reached the RP.
    integer k15_rp_rx_envelope_samples;
    integer k15_ep_post_eq_samples;
    always @(posedge RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_clk or
             negedge sys_rst_n) begin
        if (!sys_rst_n)
            k15_rp_rx_envelope_samples <= 0;
        else if ($test$plusargs("K15_GEN3") &&
                 (EP.DUT.phy_active_rate == 2'b10) &&
                 (RP.cfg_ltssm_state >= 6'h28) &&
                 (k15_rp_rx_envelope_samples < 64)) begin
            $display("K15_RP_RX_ENVELOPE n=%0d time_ps=%0t valid=%0d start=%0d header=%02b data=%08x gt_valid=%0d gt_start=%0d gt_header=%02b gt_data=%08x gt_ctrl=%04x rxvalid=%0d cdrlock=%0d rxresetdone=%0d rate_gen3=%0d user_gen3_rdy=%0d user_rate_start=%0d rate_idle=%0d rx_idle=%0d",
                     k15_rp_rx_envelope_samples, $time,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_data_valid[0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_start_block[0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_syncheader[1:0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_data[31:0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.phy_lane[0].gt_channel_int.gt_channel_i.GT_RXDATA_VALID,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.phy_lane[0].gt_channel_int.gt_channel_i.GT_RXSTART_BLOCK,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.phy_lane[0].gt_channel_int.gt_channel_i.GT_RXSYNC_HEADER,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.phy_lane[0].gt_channel_int.gt_channel_i.GT_RXDATA,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.phy_lane[0].gt_channel_int.gt_channel_i.GT_RXDATAK,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.phy_lane[0].gt_channel_int.gt_channel_i.GT_RXVALID,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.phy_lane[0].gt_channel_int.gt_channel_i.GT_RXCDRLOCK,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.gt_rxresetdone[0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.gt_pcierategen3[0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.gt_pcieusergen3rdy[0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_pcieuserratestart[0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.gt_pcierateidle[0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_elec_idle[0]);
            k15_rp_rx_envelope_samples <= k15_rp_rx_envelope_samples + 1;
        end
    end

    // Once the RP reaches its explicit Phase-0/1 state, sample the EP side
    // again.  This catches a TX-side idle/reset mismatch that would otherwise
    // look identical to a receive PCS failure at the RP.
    always @(posedge EP.DUT.phy_pclk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            k15_ep_post_eq_samples <= 0;
        else if ($test$plusargs("K15_GEN3") &&
                 (RP.cfg_ltssm_state >= 6'h28) &&
                 (k15_ep_post_eq_samples < 16)) begin
            $display("K15_EP_POST_EQ n=%0d time_ps=%0t state=%0h data=%08x valid=%0d start=%0d header=%02b rate=%02b txidle=%0d gt_valid=%0d gt_start=%0d gt_header=%02b",
                     k15_ep_post_eq_samples, $time, EP.DUT.ltssm_state,
                     EP.DUT.phy_txdata, EP.DUT.phy_txdata_valid,
                     EP.DUT.phy_txstart_block, EP.DUT.phy_txsync_header,
                     EP.DUT.phy_active_rate, EP.DUT.phy_txelecidle,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.GT_TXDATA_VALID,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.GT_TXSTART_BLOCK,
                     EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.GT_TXSYNC_HEADER);
            k15_ep_post_eq_samples <= k15_ep_post_eq_samples + 1;
        end
    end

    always @(posedge EP.DUT.phy_pclk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            k14_ab_seen_ep_ts1 <= 1'b0;
            k14_ab_seen_ep_ts2 <= 1'b0;
            k14_ab_ep_rate_or <= 8'h00;
            k14_ab_ep_ts_count <= 0;
        end else if (k14_rate_ab_active &&
                     (k14_ep_raw_ts1 || k14_ep_raw_ts2)) begin
            k14_ab_seen_ep_ts1 <= k14_ab_seen_ep_ts1 || k14_ep_raw_ts1;
            k14_ab_seen_ep_ts2 <= k14_ab_seen_ep_ts2 || k14_ep_raw_ts2;
            k14_ab_ep_rate_or <= k14_ab_ep_rate_or | k14_ep_raw_rate_id;
            k14_ab_ep_ts_count <= k14_ab_ep_ts_count + 1;
        end
    end

    always @(posedge EP.DUT.phy_pclk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            k14_seen_partner_gen3_ts <= 1'b0;
            k14_seen_partner_accept <= 1'b0;
            k14_seen_gen3_rate <= 1'b0;
            k14_seen_gen3_phystatus <= 1'b0;
            k14_seen_qpll_lock <= 1'b0;
            k14_seen_timeout_fallback <= 1'b0;
            k14_seen_gen1_rate <= 1'b0;
        end else if (k14_reboot_active) begin
            if (EP.DUT.os_ts1_valid && EP.DUT.os_rate_id[7] &&
                EP.DUT.os_rate_id[3]) begin
                k14_seen_partner_gen3_ts <= 1'b1;
                $display("K14_RP_AUTO_GEN3_TS epoch=%0d time_ps=%0t rate_id=%02x ep_state=%0d rp_state=%0h",
                         k14_epoch, $time, EP.DUT.os_rate_id,
                         EP.DUT.ltssm_state, RP.cfg_ltssm_state);
            end
            if (EP.DUT.g_gen3_rate_change.speed_retrain_accept) begin
                if (!k14_seen_partner_accept)
                    $display("K14_PARTNER_REQUEST_ACCEPTED epoch=%0d time_ps=%0t speed_state=%0d",
                             k14_epoch, $time,
                             EP.DUT.speed_state);
                k14_seen_partner_accept <= 1'b1;
            end
            if (EP.DUT.phy_rate == 2'b10) begin
                if (!k14_seen_gen3_rate)
                    $display("K14_GEN3_PHY_RATE_SEEN epoch=%0d time_ps=%0t rate_state=%0d",
                             k14_epoch, $time, EP.DUT.phy_rate_state);
                k14_seen_gen3_rate <= 1'b1;
            end
            if ((EP.DUT.phy_rate == 2'b10) && EP.DUT.phy_phystatus) begin
                if (!k14_seen_gen3_phystatus)
                    $display("K14_GEN3_PHYSTATUS_SEEN epoch=%0d time_ps=%0t qpll=%0d",
                             k14_epoch, $time, k14_qpll1lock);
                k14_seen_gen3_phystatus <= 1'b1;
            end
            if ((EP.DUT.phy_rate == 2'b10) && k14_qpll1lock)
                k14_seen_qpll_lock <= 1'b1;
            if (EP.DUT.g_gen3_rate_change.speed_timeout_sticky &&
                EP.DUT.speed_fallback_active) begin
                if (!k14_seen_timeout_fallback)
                    $display("K14_TIMEOUT_FALLBACK_SEEN epoch=%0d time_ps=%0t speed_state=%0d ep_state=%0d",
                             k14_epoch, $time,
                             EP.DUT.speed_state,
                             EP.DUT.ltssm_state);
                k14_seen_timeout_fallback <= 1'b1;
            end
            if (k14_seen_timeout_fallback &&
                (EP.DUT.phy_rate == 2'b00) && EP.DUT.phy_phystatus) begin
                if (!k14_seen_gen1_rate)
                    $display("K14_GEN1_FALLBACK_PHYSTATUS_SEEN epoch=%0d time_ps=%0t",
                             k14_epoch, $time);
                k14_seen_gen1_rate <= 1'b1;
            end
        end
    end

    initial begin : k14_reboot_test
        k14_epoch = 0;
        k14_wait_cycles = 0;
        k14_final_gen1_stable = 0;
        if ($test$plusargs("K14_REBOOT")) begin
            wait (sys_rst_n === 1'b1);
            for (k14_epoch = 0; k14_epoch < 2; k14_epoch = k14_epoch + 1) begin
                wait ((EP.DUT.link_up === 1'b1) &&
                      (EP.DUT.phy_rate === 2'b00));
                if (RP.cfg_ltssm_state === 6'h10)
                    $display("K14_REBOOT_GEN1_L0_PASS epoch=%0d time_ps=%0t",
                             k14_epoch, $time);
                else
                    $display("K14_REBOOT_GEN1_TO_RECOVERY_HANDOFF epoch=%0d time_ps=%0t rp_state=%0h",
                             k14_epoch, $time, RP.cfg_ltssm_state);

                k14_wait_cycles = 0;
                while (!k14_seen_rp_raw_gen3_ts &&
                       (k14_wait_cycles < K14_AUTO_REQUEST_WAIT_CYCLES)) begin
                    @(posedge EP.DUT.phy_pclk);
                    k14_wait_cycles = k14_wait_cycles + 1;
                end
                if (!k14_seen_rp_raw_gen3_ts) begin
                    $display("RP_AUTO_GEN3_REQUEST_MISSING epoch=%0d wait_cycles=%0d ep_state=%0d rp_state=%0h rp_speed=%0d ep_rate=%0d auto=0 mailbox=%0d",
                             k14_epoch, k14_wait_cycles, EP.DUT.ltssm_state,
                             RP.cfg_ltssm_state, RP.cfg_current_speed,
                             EP.DUT.phy_rate,
                             EP.DUT.g_gen3_rate_change.mailbox_valid);
                    $fatal(1, "Root Port did not autonomously request Gen3");
                end

                k14_wait_cycles = 0;
                while (!k14_seen_partner_gen3_ts &&
                       (k14_wait_cycles < K14_AUTO_REQUEST_WAIT_CYCLES)) begin
                    @(posedge EP.DUT.phy_pclk);
                    k14_wait_cycles = k14_wait_cycles + 1;
                end
                if (!k14_seen_partner_gen3_ts)
                    $fatal(1, "K14_RP_GEN3_TS_NOT_DECODED");

                k14_wait_cycles = 0;
                while (!(k14_seen_partner_accept && k14_seen_gen3_rate &&
                         k14_seen_gen3_phystatus && k14_seen_qpll_lock &&
                         k14_seen_timeout_fallback && k14_seen_gen1_rate) &&
                       (k14_wait_cycles < K14_EPOCH_TIMEOUT_CYCLES)) begin
                    @(posedge EP.DUT.phy_pclk);
                    k14_wait_cycles = k14_wait_cycles + 1;
                end
                if (!k14_seen_partner_accept)
                    $fatal(1, "K14_PARTNER_REQUEST_NOT_ACCEPTED");
                if (!k14_seen_gen3_rate)
                    $fatal(1, "K14_GEN3_RATE_MISSING");
                if (!k14_seen_gen3_phystatus)
                    $fatal(1, "K14_GEN3_PHYSTATUS_MISSING");
                if (!k14_seen_qpll_lock)
                    $fatal(1, "K14_GEN3_QPLL_LOCK_MISSING");
                if (!k14_seen_timeout_fallback)
                    $fatal(1, "K14_TIMEOUT_FALLBACK_MISSING");
                if (!k14_seen_gen1_rate)
                    $fatal(1, "K14_GEN1_RATE_RETURN_MISSING");

                k14_final_gen1_stable = 0;
                while (k14_final_gen1_stable < 64) begin
                    @(posedge EP.DUT.phy_pclk);
                    if ((EP.DUT.link_up === 1'b1) &&
                        (EP.DUT.dll_active === 1'b1) &&
                        (EP.DUT.phy_rate === 2'b00) &&
                        (RP.cfg_ltssm_state === 6'h10) &&
                        (RP.user_lnk_up === 1'b1))
                        k14_final_gen1_stable = k14_final_gen1_stable + 1;
                    else
                        k14_final_gen1_stable = 0;
                end
                $display("K14_REBOOT_EPOCH_PASS epoch=%0d wait=%0d",
                         k14_epoch, k14_wait_cycles);

                if (k14_epoch == 0) begin
                    sys_rst_n = 1'b0;
                    rp_sys_rst_n = 1'b0;
                    repeat (K14_PERST_HOLD_REFCLK_CYCLES) @(posedge refclk_p);
                    sys_rst_n = 1'b1;
                    $display("K14_EP_PERST_RELEASE epoch=%0d time_ps=%0t",
                             k14_epoch + 1, $time);
                    repeat (K14_RP_RELEASE_DELAY_REFCLK_CYCLES) @(posedge refclk_p);
                    rp_sys_rst_n = 1'b1;
                    $display("K14_RP_RESET_RELEASE epoch=%0d time_ps=%0t",
                             k14_epoch + 1, $time);
                    $display("K14_REBOOT_SECOND_RESET_RELEASE time_ps=%0t",
                             $time);
                end
            end
            $display("K14_REBOOT_VCS_PASS epochs=2");
            $finish;
        end
    end

    // Observation-only A/B experiment.  It does not invoke the RP usrapp,
    // configuration writes, retrain tasks, Endpoint AUTO, or force protocol
    // state.  Both variants finish successfully and leave interpretation to
    // the comparison runner so a missing L0 remains useful evidence.
    initial begin : k14_rate_id_ab_test
        k14_ab_seen_l0 = 1'b0;
        if ($test$plusargs("K14_RATE_AB")) begin
            wait (sys_rst_n === 1'b1);
            k14_wait_cycles = 0;
            while (!k14_ab_seen_l0 && (k14_wait_cycles < 60_000)) begin
                @(posedge EP.DUT.phy_pclk);
                k14_wait_cycles = k14_wait_cycles + 1;
                if ((EP.DUT.link_up === 1'b1) &&
                    (EP.DUT.phy_rate === 2'b00) &&
                    (RP.cfg_ltssm_state === 6'h10))
                    k14_ab_seen_l0 = 1'b1;
            end
            if (k14_ab_seen_l0)
                $display("K14_RATE_ID_GEN1_L0_SEEN time_ps=%0t", $time);

            k14_wait_cycles = 0;
            while (!k14_seen_rp_raw_gen3_ts &&
                   (k14_wait_cycles < 32_000)) begin
                @(posedge EP.DUT.phy_pclk);
                k14_wait_cycles = k14_wait_cycles + 1;
            end
            $display("K14_RATE_ID_CAPTURE_PASS configured=%02x l0=%0d ep_ts1=%0d ep_ts2=%0d ep_rate_or=%02x ep_ts_count=%0d rp_ts1=%0d rp_ts2=%0d rp_rate_or=%02x rp_ts_count=%0d rp_gen3_speed_ts1=%0d ep_state=%0d rp_state=%0h rp_speed=%0d ep_rate=%0d auto=0 mailbox=%0d",
                     EP.DUT.LTSSM_TX_RATE_ID, k14_ab_seen_l0,
                     k14_ab_seen_ep_ts1, k14_ab_seen_ep_ts2,
                     k14_ab_ep_rate_or, k14_ab_ep_ts_count,
                     k14_ab_seen_rp_ts1, k14_ab_seen_rp_ts2,
                     k14_ab_rp_rate_or, k14_ab_rp_ts_count,
                     k14_seen_rp_raw_gen3_ts, EP.DUT.ltssm_state,
                     RP.cfg_ltssm_state, RP.cfg_current_speed,
                     EP.DUT.phy_rate,
                     EP.DUT.g_gen3_rate_change.mailbox_valid);
            $finish;
        end
    end

`ifdef K15_VCS
    localparam integer K15_EPOCH_TIMEOUT_CYCLES = 3_000_000;
    localparam integer K15_L0_STABLE_CYCLES = 256;
    localparam integer K15_GEN1_RECOVERY_TIMEOUT_CYCLES = 3_000_000;
    integer k15_epoch;
    integer k15_wait_cycles;
    integer k15_l0_stable;
    integer k15_eq_trace_count;
    integer k15_ep_tx_word_count;
    integer k15_rp_rx_valid_beats;
    integer k15_rp_rx_decoded_ts;
    integer k15_rp_tx_word_count;
    integer k15_ep_serial_edges;
    time k15_ep_serial_last_edge;
    reg k15_seen_initial_capability;
    reg k15_seen_eq_phase0;
    reg k15_seen_eq_phase1;
    reg k15_seen_eq_phase2;
    reg k15_seen_eq_phase3;
    reg k15_seen_recovery_idle;
    reg k15_seen_gen3_l0;
    reg k15_seen_eq_failure;
    reg k15_seen_rp_gen3_rxdata_valid;
    reg [5:0] k15_last_ep_state;
    wire k15_rp_rx_ts1;
    wire k15_rp_rx_ts2;
    wire k15_rp_rx_malformed;
    wire [7:0] k15_rp_rx_rate;
    wire [7:0] k15_rp_rx_control;
    wire [7:0] k15_rp_rx_eq_control;
    wire [23:0] k15_rp_rx_eq_data;

    // The standalone PHY and the integrated XDMA endpoint can present an
    // identical PIPE stream while serializing it at different effective
    // rates.  Capture a bounded set of post-switch edge intervals so a PCS
    // lock failure is distinguishable from an ordered-set decode failure.
    always @(ep_txp) begin
        if ($test$plusargs("K15_GEN3") &&
            (EP.DUT.phy_active_rate == 2'b10) &&
            (k15_ep_serial_edges < 32)) begin
            $display("K15_EP_SERIAL_EDGE n=%0d time_ps=%0t delta_ps=%0t value=%0d",
                     k15_ep_serial_edges, $time,
                     $time - k15_ep_serial_last_edge, ep_txp);
            k15_ep_serial_last_edge = $time;
            k15_ep_serial_edges = k15_ep_serial_edges + 1;
        end
    end

    // Capture the golden XDMA Root Port's own Gen3 PIPE and GT transmit
    // contract.  This is intentionally bounded: it records the exact words
    // and envelope at the same boundary as K15_EP_TX_PIPE without modifying
    // the encrypted RP or supplying a protocol bypass.
    always @(posedge RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_clk or
             negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            k15_rp_tx_word_count <= 0;
        end else if ($test$plusargs("K15_GEN3") &&
                     (RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_rate == 2'b10) &&
                     (RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data_valid) &&
                     (k15_rp_tx_word_count < 24)) begin
            $display("K15_RP_TX_PIPE n=%0d time_ps=%0t state=%0h data=%08x valid=%0d start=%0d header=%02b gt_data=%08x gt_ctrl=%04x rate_gen3=%0d user_gen3_rdy=%0d txresetdone=%0d qpll1lock=%0d txelecidle=%0d txvalid=%0d txstart=%0d txheader=%02b",
                     k15_rp_tx_word_count, $time,
                     RP.cfg_ltssm_state,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_data_valid,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_start_block,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_syncheader,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.phy_lane[0].gt_channel_int.gt_channel_i.GT_TXDATA,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.phy_lane[0].gt_channel_int.gt_channel_i.GT_TXDATAK,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.gt_pcierategen3[0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.gt_pcieusergen3rdy[0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_txresetdone[0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_qpll1lock[0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.phy_lane[0].gt_channel_int.gt_channel_i.GT_TXELECIDLE,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.phy_lane[0].gt_channel_int.gt_channel_i.GT_TXDATA_VALID,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.phy_lane[0].gt_channel_int.gt_channel_i.GT_TXSTART_BLOCK,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.gt_top_i.phy_lane[0].gt_channel_int.gt_channel_i.GT_TXSYNC_HEADER);
            k15_rp_tx_word_count <= k15_rp_tx_word_count + 1;
        end
    end

    always @(EP.DUT.phy_rate or EP.DUT.phy_txelecidle or
             EP.DUT.phy_phystatus or EP.DUT.phy_txeq_ctrl or
             EP.DUT.phy_txeq_done or EP.DUT.as_cdr_hold_req) begin
        if ($test$plusargs("K15_GEN3"))
            $display("K15_PHY_ENVELOPE time_ps=%0t ep_state=%0h speed_state=%0d cmd_state=%0d rate=%02b txei=%0d txeq_ctrl=%02b txeq_preset=%0d txeq_done=%0d phystatus=%0d cdr_hold=%0d",
                     $time, EP.DUT.ltssm_state, EP.DUT.speed_state,
                     EP.DUT.phy_rate_state, EP.DUT.phy_rate,
                     EP.DUT.phy_txelecidle, EP.DUT.phy_txeq_ctrl,
                     EP.DUT.phy_txeq_preset, EP.DUT.phy_txeq_done,
                     EP.DUT.phy_phystatus, EP.DUT.as_cdr_hold_req);
    end

    // Independent decode at the Root Port PIPE receive boundary proves that
    // the scrambled Endpoint response, rather than only controller intent,
    // reached the encrypted RP model.
    pcie_gen3_os_rx K15_RP_PIPE_RX_OS_RX (
        .clk(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_clk),
        .rst_n(sys_rst_n), .enable(1'b1),
        .in_valid(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_data_valid[0]),
        .start_block(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_start_block[0]),
        .sync_header(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_syncheader[1:0]),
        .in_data(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_data[31:0]),
        .ts1_valid(k15_rp_rx_ts1), .ts2_valid(k15_rp_rx_ts2),
        .malformed(k15_rp_rx_malformed), .idle_valid(),
        .link_number(), .link_is_pad(), .lane_number(), .lane_is_pad(),
        .n_fts(), .rate_id(k15_rp_rx_rate),
        .training_control(k15_rp_rx_control),
        .eq_control(k15_rp_rx_eq_control), .eq_data(k15_rp_rx_eq_data)
    );

    always @(posedge RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_clk or
             negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            k15_seen_rp_gen3_rxdata_valid <= 1'b0;
            k15_rp_rx_valid_beats <= 0;
            k15_rp_rx_decoded_ts <= 0;
        end else if ($test$plusargs("K15_GEN3") &&
                     (EP.DUT.phy_active_rate == 2'b10)) begin
            if (RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_data_valid[0]) begin
                k15_seen_rp_gen3_rxdata_valid <= 1'b1;
                k15_rp_rx_valid_beats <= k15_rp_rx_valid_beats + 1;
            end
            if (k15_rp_rx_ts1 || k15_rp_rx_ts2)
                k15_rp_rx_decoded_ts <= k15_rp_rx_decoded_ts + 1;
        end

        if ($test$plusargs("K15_GEN3") &&
            (k15_rp_rx_ts1 || k15_rp_rx_ts2) &&
            (k15_eq_trace_count < 96))
            $display("K15_RP_PIPE_RX_TRACE time_ps=%0t ts1=%0d ts2=%0d rate=%02x ctl=%02x eqctl=%02x eqdata=%06x malformed=%0d",
                     $time, k15_rp_rx_ts1, k15_rp_rx_ts2,
                     k15_rp_rx_rate, k15_rp_rx_control,
                     k15_rp_rx_eq_control, k15_rp_rx_eq_data,
                     k15_rp_rx_malformed);
    end

    // Capability is checked at the actual Endpoint PIPE transmitter while the
    // committed PHY rate is still Gen1.  Rate bit 7 must remain clear until
    // the downstream port requests a speed change.
    always @(posedge EP.DUT.phy_pclk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            k15_seen_initial_capability <= 1'b0;
            k15_seen_eq_phase0 <= 1'b0;
            k15_seen_eq_phase1 <= 1'b0;
            k15_seen_eq_phase2 <= 1'b0;
            k15_seen_eq_phase3 <= 1'b0;
            k15_seen_recovery_idle <= 1'b0;
            k15_seen_gen3_l0 <= 1'b0;
            k15_seen_eq_failure <= 1'b0;
            k15_last_ep_state <= 6'h3f;
            k15_eq_trace_count <= 0;
            k15_ep_tx_word_count <= 0;
            k15_rp_tx_word_count <= 0;
            k15_ep_serial_edges = 0;
            k15_ep_serial_last_edge = 0;
        end else if ($test$plusargs("K15_GEN3")) begin
            if ((EP.DUT.phy_active_rate == 2'b10) &&
                EP.DUT.phy_txdata_valid &&
                (k15_ep_tx_word_count < 24)) begin
                // Gen3 PIPE carries one 128b/130b block over four 32-bit
                // beats.  Only the first beat advertises the ordered-set
                // sync header (01); continuation beats must be 00, matching
                // the XDMA golden EP and the receiver PCS contract.
                if (!EP.DUT.phy_txstart_block &&
                    (EP.DUT.phy_txsync_header != 2'b00))
                    $fatal(1, "K15_GEN3_CONTINUATION_SYNC_HEADER_BAD header=%02b",
                           EP.DUT.phy_txsync_header);
                $display("K15_EP_TX_PIPE n=%0d time_ps=%0t state=%0h data=%08x valid=%0d start=%0d header=%02b gt_data=%08x gt_ctrl=%04x rate_gen3=%0d user_gen3_rdy=%0d txresetdone=%0d txuserrdy=%0d gttxreset=%0d syncstart=%0d pcs_syncdone=%0d txphalign=%0d txsyncdone=%0d",
                         k15_ep_tx_word_count, $time, EP.DUT.ltssm_state,
                         EP.DUT.phy_txdata, EP.DUT.phy_txdata_valid,
                         EP.DUT.phy_txstart_block, EP.DUT.phy_txsync_header,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.txdata_in[31:0],
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.txctrl0_in[15:0],
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.GT_PCIERATEGEN3,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.GT_PCIEUSERGEN3RDY,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.GT_TXRESETDONE,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.txuserrdy_in,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.gttxreset_in,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.GT_PCIERSTTXSYNCSTART,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.GT_PCIESYNCTXSYNCDONE,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.GT_TXPHALIGNDONE,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.txsyncdone_out);
                k15_ep_tx_word_count <= k15_ep_tx_word_count + 1;
            end
            if ((k14_ep_raw_ts1 || k14_ep_raw_ts2) &&
                (k14_ep_raw_rate_id[3:1] == 3'b111) &&
                !k14_ep_raw_rate_id[7] &&
                (EP.DUT.phy_active_rate == 2'b00)) begin
                if (!k15_seen_initial_capability)
                    $display("K15_INITIAL_GEN3_CAPABILITY_SEEN epoch=%0d time_ps=%0t rate_id=%02x",
                             k15_epoch, $time, k14_ep_raw_rate_id);
                k15_seen_initial_capability <= 1'b1;
            end

            if (EP.DUT.ltssm_state == 6'h28)
                k15_seen_eq_phase0 <= 1'b1;
            if ((EP.DUT.ltssm_state == 6'h29) && !k15_seen_eq_phase1) begin
                k15_seen_eq_phase1 <= 1'b1;
                $display("K15_EQ_PHASE0_DONE epoch=%0d time_ps=%0t", k15_epoch, $time);
            end
            if ((EP.DUT.ltssm_state == 6'h2a) && !k15_seen_eq_phase2) begin
                k15_seen_eq_phase2 <= 1'b1;
                $display("K15_EQ_PHASE1_DONE epoch=%0d time_ps=%0t", k15_epoch, $time);
            end
            if ((EP.DUT.ltssm_state == 6'h2b) && !k15_seen_eq_phase3) begin
                k15_seen_eq_phase3 <= 1'b1;
                $display("K15_EQ_PHASE2_DONE epoch=%0d time_ps=%0t", k15_epoch, $time);
            end
            if ((k15_last_ep_state == 6'h2b) &&
                (EP.DUT.ltssm_state != 6'h2b))
                $display("K15_EQ_PHASE3_DONE epoch=%0d time_ps=%0t next_state=%0h",
                         k15_epoch, $time, EP.DUT.ltssm_state);

            if ((EP.DUT.ltssm_state == 6'd13) && !k15_seen_recovery_idle) begin
                k15_seen_recovery_idle <= 1'b1;
                $display("K15_RECOVERY_IDLE epoch=%0d time_ps=%0t rp_state=%0h",
                         k15_epoch, $time, RP.cfg_ltssm_state);
            end
            if ((EP.DUT.ltssm_state == 6'd10) &&
                (EP.DUT.phy_active_rate == 2'b10) && !k15_seen_gen3_l0) begin
                k15_seen_gen3_l0 <= 1'b1;
                $display("K15_GEN3_L0_PASS epoch=%0d time_ps=%0t rp_speed=%0d",
                         k15_epoch, $time, RP.cfg_current_speed);
            end
            if (EP.DUT.gen3_eq_failed)
                k15_seen_eq_failure <= 1'b1;
            if ((EP.DUT.os_ts1_valid || EP.DUT.os_ts2_valid) &&
                (EP.DUT.phy_active_rate == 2'b10) &&
                (k15_eq_trace_count < 96)) begin
                $display("K15_EQ_RX_TRACE epoch=%0d time_ps=%0t ep_state=%0h rp_state=%0h rp_phase=%0d ts1=%0d ts2=%0d ctl=%02x data=%06x txctl=%02x txdata=%06x op=%0d",
                         k15_epoch, $time, EP.DUT.ltssm_state,
                         RP.cfg_ltssm_state,
                         RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pl_eq_phase,
                         EP.DUT.os_ts1_valid, EP.DUT.os_ts2_valid,
                         EP.DUT.os_eq_control, EP.DUT.os_eq_data,
                         EP.DUT.u_ltssm_mac.k15_tx_eq_control,
                         EP.DUT.u_ltssm_mac.k15_tx_eq_data,
                         EP.DUT.u_ltssm_mac.eq_operation_state);
                k15_eq_trace_count <= k15_eq_trace_count + 1;
            end
            k15_last_ep_state <= EP.DUT.ltssm_state;
        end
    end

    initial begin : k15_autonomous_gen3_test
        k15_epoch = 0;
        k15_wait_cycles = 0;
        k15_l0_stable = 0;
        if ($test$plusargs("K15_GEN3")) begin
            wait (sys_rst_n === 1'b1);
            for (k15_epoch = 0; k15_epoch < 2; k15_epoch = k15_epoch + 1) begin
                k15_wait_cycles = 0;
                while (!(k15_seen_initial_capability &&
                         k14_seen_rp_raw_gen3_ts &&
                         k14_seen_partner_accept &&
                         k14_seen_gen3_rate &&
                         k14_seen_gen3_phystatus &&
                         k14_seen_qpll_lock &&
                         k15_seen_eq_phase0 &&
                         k15_seen_eq_phase1 &&
                         k15_seen_eq_phase2 &&
                         k15_seen_eq_phase3 &&
                         k15_seen_recovery_idle &&
                         k15_seen_gen3_l0) &&
                       !EP.DUT.g_gen3_rate_change.speed_timeout_sticky &&
                       !EP.DUT.g_gen3_rate_change.speed_fallback_sticky &&
                       !k15_seen_eq_failure &&
                       (k15_wait_cycles < K15_EPOCH_TIMEOUT_CYCLES)) begin
                    @(posedge EP.DUT.phy_pclk);
                    k15_wait_cycles = k15_wait_cycles + 1;
                end

                if (!k15_seen_initial_capability)
                    $fatal(1, "K15_INITIAL_GEN3_CAPABILITY_MISSING");
                if (EP.DUT.g_gen3_rate_change.speed_timeout_sticky ||
                    EP.DUT.g_gen3_rate_change.speed_fallback_sticky) begin
                    $display("K15_VCS_BLOCKED_RP_EQ_RESPONSE_NOT_CONSUMED epoch=%0d ep_txvalid=%0d ep_txstart=%0d rp_rxvalid_seen=%0d rp_rxvalid_beats=%0d rp_decoded_ts=%0d rp_state=%0h ep_state=%0h ep_tx_eq_control=%02x ep_tx_eq_data=%06x",
                             k15_epoch, EP.DUT.phy_txdata_valid,
                             EP.DUT.phy_txstart_block,
                             k15_seen_rp_gen3_rxdata_valid,
                             k15_rp_rx_valid_beats,
                             k15_rp_rx_decoded_ts,
                             RP.cfg_ltssm_state, EP.DUT.ltssm_state,
                             EP.DUT.u_ltssm_mac.k15_tx_eq_control,
                             EP.DUT.u_ltssm_mac.k15_tx_eq_data);
                    if (!$test$plusargs("K15_CONTINUE_AFTER_FALLBACK") &&
                        !$test$plusargs("K15_LOCAL_PHY_LOOPBACK"))
                        $fatal(1, "K15_UNEXPECTED_SPEED_TIMEOUT_FALLBACK");

                    // Diagnostic mode: do not stop at the Gen3 failure.  The
                    // strict K15 gate above remains the default; this branch
                    // only answers whether the endpoint and RP recover to a
                    // stable Gen1 link after the failed higher-rate attempt.
                    k15_wait_cycles = 0;
                    k15_l0_stable = 0;
                    while ((k15_wait_cycles < K15_GEN1_RECOVERY_TIMEOUT_CYCLES) &&
                           (k15_l0_stable < K15_L0_STABLE_CYCLES)) begin
                        // The endpoint PHY clock may be stopped or held while
                        // the fallback rate command is being applied.  Use
                        // the always-running board reference clock for the
                        // diagnostic timeout; otherwise this monitor itself
                        // can deadlock exactly at the fallback boundary.
                        @(posedge refclk_p);
                        k15_wait_cycles = k15_wait_cycles + 1;
                        if ((k15_wait_cycles % 100000) == 0)
                            $display("K15_GEN1_RECOVERY_WAIT epoch=%0d wait=%0d ep_state=%0h rp_state=%0h active_rate=%02b dll=%0d rp_link=%0d rp_phy=%02b",
                                     k15_epoch, k15_wait_cycles,
                                     EP.DUT.ltssm_state, RP.cfg_ltssm_state,
                                     EP.DUT.phy_active_rate,
                                     EP.DUT.dll_active, RP.user_lnk_up,
                                     RP.cfg_phy_link_status);
                        if ((EP.DUT.link_up === 1'b1) &&
                            (EP.DUT.dll_active === 1'b1) &&
                            (EP.DUT.phy_active_rate === 2'b00) &&
                            (EP.DUT.negotiated_speed === 2'b00) &&
                            (RP.cfg_ltssm_state === 6'h10) &&
                            (RP.cfg_current_speed === 2'b01) &&
                            (RP.cfg_phy_link_status === 2'b11) &&
                            (RP.user_lnk_up === 1'b1))
                            k15_l0_stable = k15_l0_stable + 1;
                        else
                            k15_l0_stable = 0;
                    end

                    if (k15_l0_stable >= K15_L0_STABLE_CYCLES) begin
                        $display("K15_GEN1_RECOVERY_PASS_AFTER_FALLBACK epoch=%0d wait=%0d stable=%0d ep_state=%0h rp_state=%0h",
                                 k15_epoch, k15_wait_cycles, k15_l0_stable,
                                 EP.DUT.ltssm_state, RP.cfg_ltssm_state);
                        $finish;
                    end else begin
                        $display("K15_GEN1_RECOVERY_FAIL_AFTER_FALLBACK epoch=%0d wait=%0d stable=%0d ep_state=%0h rp_state=%0h active_rate=%02b dll=%0d rp_link=%0d rp_phy=%02b",
                                 k15_epoch, k15_wait_cycles, k15_l0_stable,
                                 EP.DUT.ltssm_state, RP.cfg_ltssm_state,
                                 EP.DUT.phy_active_rate, EP.DUT.dll_active,
                                 RP.user_lnk_up, RP.cfg_phy_link_status);
                        $fatal(1, "K15_GEN1_RECOVERY_MISSING");
                    end
                end
                if (!k14_seen_rp_raw_gen3_ts)
                    $fatal(1, "K15_RP_SPEED_CHANGE_MISSING");
                $display("K15_RP_SPEED_CHANGE_SEEN epoch=%0d", k15_epoch);
                if (!k14_seen_partner_accept)
                    $fatal(1, "K15_PARTNER_ACCEPT_MISSING");
                $display("K15_PARTNER_ACCEPT epoch=%0d", k15_epoch);
                if (!(k14_seen_gen3_rate && k14_seen_gen3_phystatus &&
                      k14_seen_qpll_lock))
                    $fatal(1, "K15_GEN3_RATE_DONE_MISSING");
                $display("K15_GEN3_RATE_DONE epoch=%0d", k15_epoch);
                if (!(k15_seen_eq_phase0 && k15_seen_eq_phase1 &&
                      k15_seen_eq_phase2 && k15_seen_eq_phase3))
                    $fatal(1, "K15_EQUALIZATION_INCOMPLETE");
                if (!(k15_seen_recovery_idle && k15_seen_gen3_l0))
                    $fatal(1, "K15_GEN3_L0_MISSING");
                if (k15_seen_eq_failure ||
                    EP.DUT.g_gen3_rate_change.speed_timeout_sticky ||
                    EP.DUT.g_gen3_rate_change.speed_fallback_sticky)
                    $fatal(1, "K15_UNEXPECTED_FALLBACK_OR_EQ_FAILURE");
                if (EP.DUT.g_gen3_rate_change.auto_retrain_pulse ||
                    EP.DUT.g_gen3_rate_change.mailbox_valid)
                    $fatal(1, "K15_NON_AUTONOMOUS_TRIGGER_SEEN");

                k15_l0_stable = 0;
                while (k15_l0_stable < K15_L0_STABLE_CYCLES) begin
                    @(posedge EP.DUT.phy_pclk);
                    if ((EP.DUT.link_up === 1'b1) &&
                        (EP.DUT.dll_active === 1'b0) &&
                        (EP.DUT.phy_active_rate === 2'b10) &&
                        (EP.DUT.negotiated_speed === 2'b10) &&
                        (RP.cfg_ltssm_state === 6'h10) &&
                        (RP.cfg_current_speed === 2'b11) &&
                        (RP.cfg_phy_link_status === 2'b11) &&
                        (RP.user_lnk_up === 1'b1))
                        k15_l0_stable = k15_l0_stable + 1;
                    else
                        k15_l0_stable = 0;
                end
                $display("K15_EPOCH_PASS epoch=%0d stable=%0d auto=0 mailbox=0",
                         k15_epoch, k15_l0_stable);

                if (k15_epoch == 0) begin
                    sys_rst_n = 1'b0;
                    rp_sys_rst_n = 1'b0;
                    repeat (K14_PERST_HOLD_REFCLK_CYCLES) @(posedge refclk_p);
                    sys_rst_n = 1'b1;
                    repeat (K14_RP_RELEASE_DELAY_REFCLK_CYCLES) @(posedge refclk_p);
                    rp_sys_rst_n = 1'b1;
                    $display("K15_SECOND_EPOCH_RELEASE time_ps=%0t", $time);
                end
            end
            $display("K15_VCS_PASS epochs=2");
            $finish;
        end
    end
`endif
`endif

    initial begin : k11b2_timeout_diagnostics
        if ($test$plusargs("K11B2_RUN")) begin
            #190000000;
            $display("K11B2_DIAG mac_rx=%0d/%0d dll_rx_tlp=%0d dll_tx_tlp=%0d lcrc=%0d seq=%0d dup=%0d ack_tx=%0d cfg_req=%0d cpl_tx=%0d core_rx=%0d core_tx=%0d bdf_valid=%0d cdc=%02x",
                     EP.DUT.mac_rx_valid, EP.DUT.mac_rx_is_dllp,
                     EP.DUT.u_protocol_core.dll_rx_tlp_count,
                     EP.DUT.u_protocol_core.dll_tx_tlp_count,
                     EP.DUT.u_protocol_core.lcrc_error_count,
                     EP.DUT.u_protocol_core.sequence_error_count,
                     EP.DUT.u_protocol_core.duplicate_tlp_count,
                     EP.DUT.u_protocol_core.ack_tx_count,
                     EP.DUT.u_protocol_core.codec_cfg_request_count,
                     EP.DUT.u_protocol_core.codec_tx_completion_count,
                     EP.DUT.u_protocol_core.core_rx_valid,
                     EP.DUT.u_protocol_core.core_tx_valid,
                     EP.DUT.bdf_valid, EP.DUT.cdc_errors);
        end
    end

    // B2的Root Port事务驱动。只使用RP示例环境已经公开的task和结果寄存器。
    initial begin : k11b2_transaction_test
        if ($test$plusargs("K11B2_RUN")) begin
            wait (sys_rst_n === 1'b1);
            fork : b2_timeout_guard
                begin
            #2000000000;
                    $display("K11B2_VCS_FAIL reason=global_timeout ep_state=%0d ep_link=%0d ep_dll=%0d rp_state=%0h rp_user_link=%0d fc=%0d cdc=%02x",
                             EP.DUT.ltssm_state, EP.DUT.link_up,
                             EP.DUT.dll_active, RP.cfg_ltssm_state,
                             RP.user_lnk_up, EP.DUT.dll_fc_state,
                             EP.DUT.cdc_errors);
                    $fatal(1);
                end
                begin : b2_sequence
                    wait ((EP.DUT.link_up === 1'b1) &&
                          (EP.DUT.dll_active === 1'b1) &&
                          (RP.user_lnk_up === 1'b1));
                    $display("K11B2_DLL_ACTIVE_PASS ep_fc=%0d rp_state=%0h",
                             EP.DUT.dll_fc_state, RP.cfg_ltssm_state);

                    RP.tx_usrapp.DEFAULT_TAG = 8'h20;
                    RP.tx_usrapp.TSK_TX_TYPE0_CONFIGURATION_READ(
                        RP.tx_usrapp.DEFAULT_TAG, 12'h000, 4'hf);
                    RP.tx_usrapp.TSK_WAIT_FOR_READ_DATA;
                    if (RP.tx_usrapp.P_READ_DATA !== 32'hE0011234) begin
                        $display("K11B2_VCS_FAIL reason=vendor_device actual=%08x",
                                 RP.tx_usrapp.P_READ_DATA);
                        $fatal(1);
                    end

                    // Xilinx XDMA示例把Endpoint PCIe Capability硬编码在0xc0，
                    // 本Endpoint的标准Capability Pointer为0x40。按本端链表读取，
                    // 不使用示例环境针对其自带Endpoint的0xd0固定地址检查。
                    RP.tx_usrapp.DEFAULT_TAG = RP.tx_usrapp.DEFAULT_TAG + 1'b1;
                    RP.tx_usrapp.TSK_TX_TYPE0_CONFIGURATION_READ(
                        RP.tx_usrapp.DEFAULT_TAG, 12'h034, 4'hf);
                    RP.tx_usrapp.TSK_WAIT_FOR_READ_DATA;
                    if (RP.tx_usrapp.P_READ_DATA[7:0] !== 8'h40) begin
                        $display("K11B2_VCS_FAIL reason=cap_pointer actual=%08x",
                                 RP.tx_usrapp.P_READ_DATA);
                        $fatal(1);
                    end

                    RP.tx_usrapp.DEFAULT_TAG = RP.tx_usrapp.DEFAULT_TAG + 1'b1;
                    RP.tx_usrapp.TSK_TX_TYPE0_CONFIGURATION_READ(
                        RP.tx_usrapp.DEFAULT_TAG, 12'h04c, 4'hf);
                    RP.tx_usrapp.TSK_WAIT_FOR_READ_DATA;
                    if ((RP.tx_usrapp.P_READ_DATA[3:0] !== 4'd3) ||
                        (RP.tx_usrapp.P_READ_DATA[9:4] !== 6'd1)) begin
                        $display("K11B2_VCS_FAIL reason=link_cap actual=%08x",
                                 RP.tx_usrapp.P_READ_DATA);
                        $fatal(1);
                    end
`ifdef K13_DUT
                    $display("K13_VCS_CFG_CAP_PASS cap_ptr=40 max_speed=3 max_width=1");
`else
                    $display("K11B2_CFG_CAP_PASS cap_ptr=40 max_speed=3 max_width=1");
`endif

                    RP.tx_usrapp.DEFAULT_TAG = RP.tx_usrapp.DEFAULT_TAG + 1'b1;
                    RP.tx_usrapp.TSK_TX_TYPE0_CONFIGURATION_WRITE(
                        RP.tx_usrapp.DEFAULT_TAG, 12'h010, 32'hffff_ffff, 4'hf);
                    RP.tx_usrapp.TSK_TX_CLK_EAT(100);
                    RP.tx_usrapp.DEFAULT_TAG = RP.tx_usrapp.DEFAULT_TAG + 1'b1;
                    RP.tx_usrapp.TSK_TX_TYPE0_CONFIGURATION_READ(
                        RP.tx_usrapp.DEFAULT_TAG, 12'h010, 4'hf);
                    RP.tx_usrapp.TSK_WAIT_FOR_READ_DATA;
                    if (RP.tx_usrapp.P_READ_DATA !== 32'hffff_f000) begin
                        $display("K11B2_VCS_FAIL reason=bar_mask actual=%08x",
                                 RP.tx_usrapp.P_READ_DATA);
                        $fatal(1);
                    end

                    RP.tx_usrapp.DEFAULT_TAG = RP.tx_usrapp.DEFAULT_TAG + 1'b1;
                    RP.tx_usrapp.TSK_TX_TYPE0_CONFIGURATION_WRITE(
                        RP.tx_usrapp.DEFAULT_TAG, 12'h010, 32'h8000_0000, 4'hf);
                    RP.tx_usrapp.TSK_TX_CLK_EAT(100);
                    RP.tx_usrapp.DEFAULT_TAG = RP.tx_usrapp.DEFAULT_TAG + 1'b1;
                    RP.tx_usrapp.TSK_TX_TYPE0_CONFIGURATION_WRITE(
                        RP.tx_usrapp.DEFAULT_TAG, 12'h004, 32'h0000_0002, 4'h3);
                    // 真实Gen1链路上的Cfg Write Completion往返约1 us；等待500个
                    // Root user_clk后再观察跨域后的MSE状态。
                    RP.tx_usrapp.TSK_TX_CLK_EAT(500);

                    if (!EP.DUT.bdf_valid ||
                        (EP.DUT.bar0_base !== 32'h8000_0000) ||
                        !EP.DUT.memory_space_enable) begin
                        $display("K11B2_VCS_FAIL reason=cfg_state bdf_valid=%0d bar=%08x mse=%0d",
                                 EP.DUT.bdf_valid, EP.DUT.bar0_base,
                                 EP.DUT.memory_space_enable);
                        $fatal(1);
                    end
                    $display("K11B2_ENUM_PASS bdf=%04x bar0=%08x",
                             EP.DUT.captured_bdf, EP.DUT.bar0_base);

                    RP.tx_usrapp.DEFAULT_TAG = RP.tx_usrapp.DEFAULT_TAG + 1'b1;
                    RP.tx_usrapp.TSK_TX_MEMORY_READ_32(
                        RP.tx_usrapp.DEFAULT_TAG, 3'd0, 11'd1,
                        32'h8000_0000, 4'h0, 4'hf);
                    RP.tx_usrapp.TSK_WAIT_FOR_READ_DATA;
                    if (RP.tx_usrapp.P_READ_DATA !== 32'h5043_4945) begin
                        $display("K11B2_VCS_FAIL reason=signature actual=%08x",
                                 RP.tx_usrapp.P_READ_DATA);
                        $fatal(1);
                    end

                    RP.tx_usrapp.DATA_STORE[0] = 8'h19;
                    RP.tx_usrapp.DATA_STORE[1] = 8'h7e;
                    RP.tx_usrapp.DATA_STORE[2] = 8'hc3;
                    RP.tx_usrapp.DATA_STORE[3] = 8'ha5;
                    RP.tx_usrapp.DEFAULT_TAG = RP.tx_usrapp.DEFAULT_TAG + 1'b1;
                    RP.tx_usrapp.TSK_TX_MEMORY_WRITE_32(
                        RP.tx_usrapp.DEFAULT_TAG, 3'd0, 11'd1,
                        32'h8000_0040, 4'h0, 4'hf, 1'b0);
                    RP.tx_usrapp.TSK_TX_CLK_EAT(100);
                    RP.tx_usrapp.DEFAULT_TAG = RP.tx_usrapp.DEFAULT_TAG + 1'b1;
                    RP.tx_usrapp.TSK_TX_MEMORY_READ_32(
                        RP.tx_usrapp.DEFAULT_TAG, 3'd0, 11'd1,
                        32'h8000_0040, 4'h0, 4'hf);
                    RP.tx_usrapp.TSK_WAIT_FOR_READ_DATA;
                    if (RP.tx_usrapp.P_READ_DATA !== 32'hA5C3_7E19) begin
                        $display("K11B2_VCS_FAIL reason=scratch actual=%08x",
                                 RP.tx_usrapp.P_READ_DATA);
                        $fatal(1);
                    end
                    if ((EP.DUT.cdc_errors !== 8'h00) ||
                        (EP.DUT.link_up !== 1'b1) ||
                        (EP.DUT.dll_active !== 1'b1)) begin
                        $display("K11B2_VCS_FAIL reason=final_state cdc=%02x link=%0d dll=%0d",
                                 EP.DUT.cdc_errors, EP.DUT.link_up,
                                 EP.DUT.dll_active);
                        $fatal(1);
                    end
                    $display("K11B2_BAR_PASS signature=50434945 scratch=%08x",
                             RP.tx_usrapp.P_READ_DATA);

`ifdef K13_DUT
                    if (k13_retrain_active) begin
                        k13_seen_rp_recovery = 1'b0;
                        k13_seen_rcvrlock = 1'b0;
                        k13_seen_rcvrcfg = 1'b0;
                        k13_seen_recovery_speed = 1'b0;
                        k13_seen_recovery_idle = 1'b0;
                        k13_seen_rate_gen3 = 1'b0;
                        k13_seen_phystatus = 1'b0;
                        k13_seen_eq_phase = 5'd0;
                        k13_gen3_pipe_samples = 0;
                        k13_rp_pipe_samples = 0;
                        k13_rp_fallback_pipe_samples = 0;
                        k13_rp_recovery_ts_samples = 0;
                        k13_ep_recovery_rx_samples = 0;
                        k13_ep_recovery_tx_samples = 0;
                        k13_rp_recovery_rx_samples = 0;
                        k13_ep_fallback_pipe_samples = 0;
                        k13_ep_rx_contract_samples = 0;
                        k13_rp_tx_contract_samples = 0;
                        k13_retry_sent = 1'b0;
                        k13_gen1_l0_stable = 0;
                        k13_rp_tx_edges_at_retrain = rp_tx_edge_count[0];
                        k13_ep_tx_edges_at_retrain = ep_tx_edge_count;
                        k13_retrain_monitor_armed = 1'b1;
                        // dual preserves the historical regression.  rp mirrors
                        // the official demo ordering and lets the endpoint learn
                        // the target from the directed TS1 speed-change request.
                        if (k13_do_rp_retrain)
                            RP.cfg_usrapp.TSK_WRITE_CFG_DW(
                                32'h3c, 32'h0000_0003, 4'h1);
                        if (k13_do_ep_retrain) begin
                            RP.tx_usrapp.DEFAULT_TAG = RP.tx_usrapp.DEFAULT_TAG + 1'b1;
                            RP.tx_usrapp.TSK_TX_TYPE0_CONFIGURATION_WRITE(
                                RP.tx_usrapp.DEFAULT_TAG, 12'h070,
                                32'h0000_0003, 4'h1);
                            RP.tx_usrapp.TSK_TX_CLK_EAT(100);
                            RP.tx_usrapp.DEFAULT_TAG = RP.tx_usrapp.DEFAULT_TAG + 1'b1;
                            RP.tx_usrapp.TSK_TX_TYPE0_CONFIGURATION_WRITE(
                                RP.tx_usrapp.DEFAULT_TAG, 12'h050,
                                32'h0000_0020, 4'h1);
                            RP.tx_usrapp.TSK_TX_CLK_EAT(100);
                        end
                        if (k13_do_rp_retrain)
                            RP.cfg_usrapp.TSK_WRITE_CFG_DW(
                                32'h34, 32'h0081_0020, 4'hf);
                        $display("K13_VCS_RETRAIN_TRIGGER target=3 link_control=0020 rp=%0d ep=%0d",
                                 k13_do_rp_retrain, k13_do_ep_retrain);

                        k13_wait_cycles = 0;
                        k13_fallback_wait_limit = 20000;
                        void'($value$plusargs("K13_FALLBACK_WAIT=%d", k13_fallback_wait_limit));
                        while (!((EP.DUT.negotiated_speed == 2'b10) &&
                                 (EP.DUT.ltssm_state == 6'd10) &&
                                 EP.DUT.link_up && EP.DUT.dll_active &&
                                 (RP.cfg_current_speed == 2'b11) &&
                                 (RP.cfg_ltssm_state == 6'h10) &&
                                 RP.user_lnk_up) &&
                               (k13_wait_cycles < k13_fallback_wait_limit)) begin
                            @(posedge EP.DUT.phy_pclk);
                            k13_wait_cycles = k13_wait_cycles + 1;
                            // The first Gen3 attempt may deliberately take
                            // the RXEQ done-only failure path.  Once the
                            // endpoint has committed the safe Gen1 fallback,
                            // model the Root Port's next retrain request so
                            // the regression covers fallback -> re-rate.
                            // Do not treat the controller's ST_L0 as a
                            // completed fallback.  Both LTSSMs and the DLL
                            // must be back in a stable Gen1 L0 before a new
                            // directed Gen3 retrain is issued.
                            if (EP.DUT.k13_fallback_sticky &&
                                (EP.DUT.phy_rate == 2'b00) &&
                                (EP.DUT.k13_speed_state == 3'd0) &&
                                (EP.DUT.negotiated_speed == 2'b00) &&
                                (EP.DUT.ltssm_state == 6'd10) &&
                                EP.DUT.link_up && EP.DUT.dll_active &&
                                (RP.cfg_ltssm_state == 6'h10) &&
                                (RP.cfg_current_speed == 2'b01) &&
                                RP.user_lnk_up) begin
                                if (k13_gen1_l0_stable < 64)
                                    k13_gen1_l0_stable =
                                        k13_gen1_l0_stable + 1;
                            end else begin
                                k13_gen1_l0_stable = 0;
                            end

                            if (!k13_retry_sent &&
                                (k13_gen1_l0_stable >= 64)) begin
                                if (k13_do_rp_retrain)
                                    RP.cfg_usrapp.TSK_WRITE_CFG_DW(
                                        32'h3c, 32'h0000_0003, 4'h1);
                                if (k13_do_ep_retrain) begin
                                    RP.tx_usrapp.DEFAULT_TAG =
                                        RP.tx_usrapp.DEFAULT_TAG + 1'b1;
                                    RP.tx_usrapp.TSK_TX_TYPE0_CONFIGURATION_WRITE(
                                        RP.tx_usrapp.DEFAULT_TAG, 12'h070,
                                        32'h0000_0003, 4'h1);
                                    RP.tx_usrapp.TSK_TX_CLK_EAT(100);
                                    RP.tx_usrapp.DEFAULT_TAG =
                                        RP.tx_usrapp.DEFAULT_TAG + 1'b1;
                                    RP.tx_usrapp.TSK_TX_TYPE0_CONFIGURATION_WRITE(
                                        RP.tx_usrapp.DEFAULT_TAG, 12'h050,
                                        32'h0000_0020, 4'h1);
                                    RP.tx_usrapp.TSK_TX_CLK_EAT(100);
                                end
                                if (k13_do_rp_retrain)
                                    RP.cfg_usrapp.TSK_WRITE_CFG_DW(
                                        32'h34, 32'h0081_0020, 4'hf);
                                k13_retry_sent = 1'b1;
                                k13_gen1_l0_stable = 0;
                                k13_wait_cycles = 0;
                                $display("K13_VCS_RETRAIN_RETRY target=3 after_gen1_l0_stable cycles=64 rp=%0d ep=%0d",
                                         k13_do_rp_retrain,
                                         k13_do_ep_retrain);
                            end
                        end

                        if (k13_wait_cycles >= k13_fallback_wait_limit) begin
                            $display("K13_VCS_GEN3_RETRAIN_FAIL wait=%0d ep_state=%0d speed_state=%0d rate=%0d negotiated=%0d eq_active=%0d eq_phase=%0d eq_done=%0d fallback=%0d speed_timeout=%0d ts_accept=%0d ts_reject=%0d rp_state=%0h rp_speed=%0d rp_link=%0d seen_rp_recovery=%0d seen_states=%0d%0d%0d%0d seen_rate=%0d seen_phystatus=%0d seen_eq=%05b rp_tx_edges=%0d ep_tx_edges=%0d",
                                     k13_wait_cycles, EP.DUT.ltssm_state,
                                     EP.DUT.k13_speed_state, EP.DUT.phy_rate,
                                     EP.DUT.negotiated_speed,
                                     EP.DUT.k13_eq_active, EP.DUT.k13_eq_phase,
                                     EP.DUT.k13_eq_done,
                                     EP.DUT.k13_fallback_sticky,
                                     EP.DUT.k13_speed_timeout_sticky,
                                     EP.DUT.k13_ts_accept, EP.DUT.k13_ts_reject,
                                     RP.cfg_ltssm_state, RP.cfg_current_speed,
                                     RP.user_lnk_up, k13_seen_rp_recovery,
                                     k13_seen_rcvrlock, k13_seen_rcvrcfg,
                                     k13_seen_recovery_speed,
                                     k13_seen_recovery_idle,
                                     k13_seen_rate_gen3, k13_seen_phystatus,
                                     k13_seen_eq_phase,
                                     rp_tx_edge_count[0] - k13_rp_tx_edges_at_retrain,
                                     ep_tx_edge_count - k13_ep_tx_edges_at_retrain);
                            $fatal(1);
                        end
                        if (!k13_seen_rp_recovery || !k13_seen_rcvrlock ||
                            !k13_seen_rcvrcfg || !k13_seen_recovery_speed ||
                            !k13_seen_recovery_idle || !k13_seen_rate_gen3 ||
                            !k13_seen_phystatus ||
                            (k13_seen_eq_phase != 5'b11111)) begin
                            $display("K13_VCS_GEN3_RETRAIN_FAIL reason=coverage rp_recovery=%0d states=%0d%0d%0d%0d rate=%0d phystatus=%0d eq=%05b",
                                     k13_seen_rp_recovery, k13_seen_rcvrlock,
                                     k13_seen_rcvrcfg, k13_seen_recovery_speed,
                                     k13_seen_recovery_idle, k13_seen_rate_gen3,
                                     k13_seen_phystatus, k13_seen_eq_phase);
                            $fatal(1);
                        end
                        $display("K13_VCS_GEN3_RETRAIN_PASS cycles=%0d eq=%05b",
                                 k13_wait_cycles, k13_seen_eq_phase);
                    end
`endif

                    if (b2_stress) begin
                        // 固定种子的100组Scratch随机地址/数据/Byte Enable回归。
                        // 先建立与当前Demo寄存器状态一致的逐DW参考模型。
                        for (b2_iter = 0; b2_iter < 48; b2_iter = b2_iter + 1)
                            b2_expected[b2_iter] = 32'h0000_0000;
                        b2_expected[0] = 32'hA5C3_7E19;
                        b2_lfsr = 32'h1ACE_B00C;
                        for (b2_iter = 0; b2_iter < 100; b2_iter = b2_iter + 1) begin
                            b2_lfsr = {b2_lfsr[30:0],
                                       b2_lfsr[31] ^ b2_lfsr[21] ^
                                       b2_lfsr[1] ^ b2_lfsr[0]};
                            b2_random_addr = 32'h8000_0040 + ((b2_lfsr % 48) << 2);
                            b2_random_data = b2_lfsr ^ (32'h9E37_79B9 * (b2_iter + 1));
                            b2_random_be = b2_lfsr[7:4];
                            if (b2_random_be == 4'h0)
                                b2_random_be = 4'hf;

                            RP.tx_usrapp.DATA_STORE[0] = b2_random_data[7:0];
                            RP.tx_usrapp.DATA_STORE[1] = b2_random_data[15:8];
                            RP.tx_usrapp.DATA_STORE[2] = b2_random_data[23:16];
                            RP.tx_usrapp.DATA_STORE[3] = b2_random_data[31:24];
                            RP.tx_usrapp.DEFAULT_TAG = RP.tx_usrapp.DEFAULT_TAG + 1'b1;
                            RP.tx_usrapp.TSK_TX_MEMORY_WRITE_32(
                                RP.tx_usrapp.DEFAULT_TAG, 3'd0, 11'd1,
                                b2_random_addr, 4'h0, b2_random_be, 1'b0);
                            RP.tx_usrapp.TSK_TX_CLK_EAT(100);

                            for (b2_byte = 0; b2_byte < 4; b2_byte = b2_byte + 1)
                                if (b2_random_be[b2_byte])
                                    b2_expected[(b2_random_addr - 32'h8000_0040) >> 2]
                                        [b2_byte*8 +: 8] = b2_random_data[b2_byte*8 +: 8];

                            RP.tx_usrapp.DEFAULT_TAG = RP.tx_usrapp.DEFAULT_TAG + 1'b1;
                            RP.tx_usrapp.TSK_TX_MEMORY_READ_32(
                                RP.tx_usrapp.DEFAULT_TAG, 3'd0, 11'd1,
                                b2_random_addr, 4'h0, 4'hf);
                            RP.tx_usrapp.TSK_WAIT_FOR_READ_DATA;
                            if (RP.tx_usrapp.P_READ_DATA !==
                                b2_expected[(b2_random_addr - 32'h8000_0040) >> 2]) begin
                                $display("K11B2_VCS_FAIL reason=random_mmio iter=%0d addr=%08x be=%x expected=%08x actual=%08x",
                                         b2_iter, b2_random_addr, b2_random_be,
                                         b2_expected[(b2_random_addr - 32'h8000_0040) >> 2],
                                         RP.tx_usrapp.P_READ_DATA);
                                $fatal(1);
                            end
                        end
                        $display("K11B2_RANDOM_MMIO_PASS transactions=100 seed=1aceb00c");

                        // 将下一包RP->EP TLP的LCRC结果改坏。EP必须NAK，RP重放后
                        // 同一个MRd仍然得到正确Completion。
                        b2_old_lcrc_count = EP.DUT.u_protocol_core.lcrc_error_count;
                        b2_old_nak_count = EP.DUT.u_protocol_core.nak_tx_count;
                        fork
                            begin : b2_bad_lcrc_injector
                                wait (EP.DUT.u_protocol_core.u_dll.u_replay.rx_proc_state == 3'd2);
                                force EP.DUT.u_protocol_core.u_dll.u_replay.rx_crc_good_latched = 1'b0;
                                wait (EP.DUT.u_protocol_core.u_dll.u_replay.rx_proc_state == 3'd3);
                                @(posedge EP.DUT.phy_pclk);
                                release EP.DUT.u_protocol_core.u_dll.u_replay.rx_crc_good_latched;
                            end
                            begin : b2_bad_lcrc_request
                                RP.tx_usrapp.DEFAULT_TAG = RP.tx_usrapp.DEFAULT_TAG + 1'b1;
                                RP.tx_usrapp.TSK_TX_MEMORY_READ_32(
                                    RP.tx_usrapp.DEFAULT_TAG, 3'd0, 11'd1,
                                    32'h8000_0000, 4'h0, 4'hf);
                                RP.tx_usrapp.TSK_WAIT_FOR_READ_DATA;
                            end
                        join
                        if ((RP.tx_usrapp.P_READ_DATA !== 32'h5043_4945) ||
                            (EP.DUT.u_protocol_core.lcrc_error_count <= b2_old_lcrc_count) ||
                            (EP.DUT.u_protocol_core.nak_tx_count <= b2_old_nak_count)) begin
                            $display("K11B2_VCS_FAIL reason=bad_lcrc data=%08x lcrc=%0d/%0d nak=%0d/%0d",
                                     RP.tx_usrapp.P_READ_DATA,
                                     EP.DUT.u_protocol_core.lcrc_error_count,
                                     b2_old_lcrc_count,
                                     EP.DUT.u_protocol_core.nak_tx_count,
                                     b2_old_nak_count);
                            $fatal(1);
                        end
                        $display("K11B2_BAD_LCRC_PASS lcrc=%0d nak=%0d",
                                 EP.DUT.u_protocol_core.lcrc_error_count,
                                 EP.DUT.u_protocol_core.nak_tx_count);

                        // 屏蔽首个Completion的ACK，等待Endpoint replay timer到期。
                        // 释放后，重放Completion的ACK必须清空Replay Buffer。
                        b2_old_replay_count = EP.DUT.u_protocol_core.replay_count;
                        force EP.DUT.u_protocol_core.u_dll.u_replay.rx_dllp_valid = 1'b0;
                        RP.tx_usrapp.DEFAULT_TAG = RP.tx_usrapp.DEFAULT_TAG + 1'b1;
                        RP.tx_usrapp.TSK_TX_MEMORY_READ_32(
                            RP.tx_usrapp.DEFAULT_TAG, 3'd0, 11'd1,
                            32'h8000_0000, 4'h0, 4'hf);
                        RP.tx_usrapp.TSK_WAIT_FOR_READ_DATA;
                        b2_delayed_ack_seq = EP.DUT.u_protocol_core.next_tx_seq - 1'b1;
                        repeat (2055) @(posedge EP.DUT.phy_pclk);
                        release EP.DUT.u_protocol_core.u_dll.u_replay.rx_dllp_valid;
                        b2_wait_cycles = 0;
                        while ((EP.DUT.u_protocol_core.replay_count <= b2_old_replay_count) &&
                               (b2_wait_cycles < 4096)) begin
                            @(posedge EP.DUT.phy_pclk);
                            b2_wait_cycles = b2_wait_cycles + 1;
                        end
                        // Xilinx RP示例模型不会为被判为重复的Completion再次产生
                        // ACK；partner在此补发先前丢失的合法累计ACK。
                        force EP.DUT.u_protocol_core.u_dll.u_replay.rx_dllp_valid = 1'b1;
                        force EP.DUT.u_protocol_core.u_dll.u_replay.rx_dllp_crc_good = 1'b1;
                        force EP.DUT.u_protocol_core.u_dll.u_replay.rx_dllp_error = 4'h0;
                        force EP.DUT.u_protocol_core.u_dll.u_replay.rx_dllp_data =
                            {b2_delayed_ack_seq[7:0], 4'h0,
                             b2_delayed_ack_seq[11:8], 8'h00, 8'h00};
                        repeat (2) @(posedge EP.DUT.phy_pclk);
                        @(negedge EP.DUT.phy_pclk);
                        release EP.DUT.u_protocol_core.u_dll.u_replay.rx_dllp_valid;
                        release EP.DUT.u_protocol_core.u_dll.u_replay.rx_dllp_crc_good;
                        release EP.DUT.u_protocol_core.u_dll.u_replay.rx_dllp_error;
                        release EP.DUT.u_protocol_core.u_dll.u_replay.rx_dllp_data;
                        repeat (16) @(posedge EP.DUT.phy_pclk);
                        if ((EP.DUT.u_protocol_core.replay_count <= b2_old_replay_count) ||
                            (EP.DUT.u_protocol_core.replay_occupancy != 0) ||
                            EP.DUT.u_protocol_core.replay_fatal) begin
                            $display("K11B2_VCS_FAIL reason=ack_loss replay=%0d/%0d occupancy=%0d fatal=%0d",
                                     EP.DUT.u_protocol_core.replay_count,
                                     b2_old_replay_count,
                                     EP.DUT.u_protocol_core.replay_occupancy,
                                     EP.DUT.u_protocol_core.replay_fatal);
                            $fatal(1);
                        end
                        $display("K11B2_ACK_LOSS_PASS replay=%0d occupancy=%0d",
                                 EP.DUT.u_protocol_core.replay_count,
                                 EP.DUT.u_protocol_core.replay_occupancy);

                        // 一次PERST#后配置空间和BAR会恢复缺省值，因此重新执行
                        // Vendor检查、BAR分配和MSE，再验证MMIO仍可用。
                        RP.tx_usrapp.TSK_RESET(1'b0);
                        repeat (500) @(posedge refclk_p);
                        RP.tx_usrapp.TSK_RESET(1'b1);
                        wait ((EP.DUT.link_up === 1'b1) &&
                              (EP.DUT.dll_active === 1'b1) &&
                              (RP.user_lnk_up === 1'b1));
                        RP.tx_usrapp.DEFAULT_TAG = 8'h80;
                        RP.tx_usrapp.TSK_TX_TYPE0_CONFIGURATION_READ(
                            RP.tx_usrapp.DEFAULT_TAG, 12'h000, 4'hf);
                        RP.tx_usrapp.TSK_WAIT_FOR_READ_DATA;
                        if (RP.tx_usrapp.P_READ_DATA !== 32'hE0011234) begin
                            $display("K11B2_VCS_FAIL reason=perst_vendor actual=%08x",
                                     RP.tx_usrapp.P_READ_DATA);
                            $fatal(1);
                        end
                        RP.tx_usrapp.DEFAULT_TAG = RP.tx_usrapp.DEFAULT_TAG + 1'b1;
                        RP.tx_usrapp.TSK_TX_TYPE0_CONFIGURATION_WRITE(
                            RP.tx_usrapp.DEFAULT_TAG, 12'h010, 32'h8000_0000, 4'hf);
                        RP.tx_usrapp.TSK_TX_CLK_EAT(100);
                        RP.tx_usrapp.DEFAULT_TAG = RP.tx_usrapp.DEFAULT_TAG + 1'b1;
                        RP.tx_usrapp.TSK_TX_TYPE0_CONFIGURATION_WRITE(
                            RP.tx_usrapp.DEFAULT_TAG, 12'h004, 32'h0000_0002, 4'h3);
                        RP.tx_usrapp.TSK_TX_CLK_EAT(500);
                        RP.tx_usrapp.DEFAULT_TAG = RP.tx_usrapp.DEFAULT_TAG + 1'b1;
                        RP.tx_usrapp.TSK_TX_MEMORY_READ_32(
                            RP.tx_usrapp.DEFAULT_TAG, 3'd0, 11'd1,
                            32'h8000_0000, 4'h0, 4'hf);
                        RP.tx_usrapp.TSK_WAIT_FOR_READ_DATA;
                        if ((RP.tx_usrapp.P_READ_DATA !== 32'h5043_4945) ||
                            (EP.DUT.cdc_errors !== 8'h00)) begin
                            $display("K11B2_VCS_FAIL reason=perst_recovery data=%08x cdc=%02x",
                                     RP.tx_usrapp.P_READ_DATA, EP.DUT.cdc_errors);
                            $fatal(1);
                        end
                        $display("K11B2_PERST_RECOVERY_PASS vendor=e0011234 signature=50434945");
                        $display("K11B2_STRESS_PASS");
                    end
                    $display("K11B2_VCS_PASS");
                    $finish;
                end
            join
        end
    end
`endif

    initial begin
        wait (sys_rst_n === 1'b1);
        if (disconnect_lane0) begin
            #500000000;
            if ((EP.DUT.link_up === 1'b1) ||
                (RP.cfg_ltssm_state === 6'h10)) begin
                $display("K11B_VCS_CHECKER_SELFTEST_FAIL reason=disconnected_l0 ep=%0d rp_state=%0h",
                         EP.DUT.link_up, RP.cfg_ltssm_state);
                $fatal(1);
            end
            $display("K11B_VCS_CHECKER_SELFTEST_PASS ep_state=%0d rp_link=%0d timeout=%0d",
                     EP.DUT.ltssm_state, RP.user_lnk_up, EP.DUT.timeout_count);
            $finish;
        end else if (!b2_active && !k14_reboot_active) begin
            #160000000;
            $display("K11B_SERIAL_ACTIVITY ep_tx=%0d rp_tx=%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d ep_rxvalid=%0d ep_data_valid=%0d ep_elec_idle=%0d ep_rxstatus=%0d",
                     ep_tx_edge_count, rp_tx_edge_count[0], rp_tx_edge_count[1],
                     rp_tx_edge_count[2], rp_tx_edge_count[3], rp_tx_edge_count[4],
                     rp_tx_edge_count[5], rp_tx_edge_count[6], rp_tx_edge_count[7],
                     EP.DUT.phy_rxvalid, EP.DUT.phy_rxdata_valid,
                     EP.DUT.phy_rxelecidle, EP.DUT.phy_rxstatus);
            $display("K11B_VCS_GEN1_L0_FAIL reason=timeout ep_state=%0d ep_link=%0d rp_link=%0d rx_ts=%0d train_err=%0d timeout_count=%0d frame_err=%0d",
                     EP.DUT.ltssm_state, EP.DUT.link_up, RP.user_lnk_up,
                     EP.DUT.rx_ts_count, EP.DUT.training_error_count,
                     EP.DUT.timeout_count, EP.DUT.frame_error_count);
            $fatal(1);
        end
    end

    wire _unused = &{1'b0, ep_led};
endmodule

// XDMA Root Port 的示例 usrapp 在未被调用的测试 task 中仍存在对 board.EP AXI
// 信号的层次引用。兼容壳只为 VCS 展开提供这些名字，K11-B1 不驱动或使用 AXI。
module k11b_endpoint_compat #(
    parameter integer DETECT_QUIET_CYCLES   = 1_500_000,
    parameter integer DETECT_TIMEOUT_CYCLES = 3_000_000,
    parameter integer TRAIN_TIMEOUT_CYCLES  = 6_000_000,
    parameter integer HOT_RESET_CYCLES      = 250_000
) (
    input  wire       pcie_refclk_p,
    input  wire       pcie_refclk_n,
    input  wire       pcie_perst_n,
    input  wire       pcie_rxp,
    input  wire       pcie_rxn,
    output wire       pcie_txp,
    output wire       pcie_txn,
    output wire [7:0] led
);
    parameter integer C_NUM_USR_IRQ = 4;
    wire         user_clk = DUT.phy_coreclk;
    wire         m_axi_wvalid = 1'b0;
    wire         m_axi_wready = 1'b0;
    wire [511:0] m_axi_wdata = 512'd0;
    wire [63:0]  m_axi_wstrb = 64'd0;
    reg  [C_NUM_USR_IRQ-1:0] usr_irq_req;
    wire [C_NUM_USR_IRQ-1:0] usr_irq_ack = {C_NUM_USR_IRQ{1'b0}};

    initial usr_irq_req = {C_NUM_USR_IRQ{1'b0}};

`ifdef K11B2_DUT
    wire link_up, dll_active, bdf_valid, memory_space_enable;
    wire [5:0] ltssm_state;
    wire [1:0] dll_fc_state, negotiated_speed;
    wire [2:0] negotiated_width;
    wire [15:0] captured_bdf;
    wire [31:0] bar0_base;
    wire [7:0] cdc_errors;

    kcu105_pcie_ep_gen1_top #(
        .DETECT_QUIET_CYCLES   (DETECT_QUIET_CYCLES),
        .DETECT_TIMEOUT_CYCLES (DETECT_TIMEOUT_CYCLES),
        .TRAIN_TIMEOUT_CYCLES  (TRAIN_TIMEOUT_CYCLES),
        .HOT_RESET_CYCLES      (HOT_RESET_CYCLES),
`ifdef K14_REBOOT_VCS
        .K14_RATE_DEBUG        (0),
        .GEN3_RATE_CHANGE_ENABLE(1),
        .GEN3_SPEED_TIMEOUT_CYCLES(16_384),
        .GEN3_AUTO_RETRAIN_CYCLES(0),
`ifdef K14_EP_TX_RATE_ID_VALUE
        .LTSSM_TX_RATE_ID      (`K14_EP_TX_RATE_ID_VALUE),
`endif
`endif
        // The encrypted Root-Port model restarts Detect when the Endpoint
        // holds the board-only G9 activity window.  G9 itself is covered by
        // the K03/controller directed suite; the canonical hardware release
        // keeps it enabled.
        .G9_WAIT_REMOTE_DETECT (0),
        .G9_WAIT_REMOTE_DETECT_CYCLES(65_536)
    ) DUT (
        .pcie_refclk_p(pcie_refclk_p), .pcie_refclk_n(pcie_refclk_n),
        .pcie_perst_n(pcie_perst_n), .pcie_rxp(pcie_rxp), .pcie_rxn(pcie_rxn),
        .pcie_txp(pcie_txp), .pcie_txn(pcie_txn), .led(led),
        .link_up(link_up), .dll_active(dll_active), .ltssm_state(ltssm_state),
        .dll_fc_state(dll_fc_state), .negotiated_speed(negotiated_speed),
        .negotiated_width(negotiated_width), .captured_bdf(captured_bdf),
        .bdf_valid(bdf_valid), .bar0_base(bar0_base),
        .memory_space_enable(memory_space_enable), .cdc_errors(cdc_errors)
    );
`else
    kcu105_pcie_gen1_top #(
        .DETECT_QUIET_CYCLES   (DETECT_QUIET_CYCLES),
        .DETECT_TIMEOUT_CYCLES (DETECT_TIMEOUT_CYCLES),
        .TRAIN_TIMEOUT_CYCLES  (TRAIN_TIMEOUT_CYCLES),
        .HOT_RESET_CYCLES      (HOT_RESET_CYCLES)
    ) DUT (
        .pcie_refclk_p (pcie_refclk_p),
        .pcie_refclk_n (pcie_refclk_n),
        .pcie_perst_n  (pcie_perst_n),
        .pcie_rxp      (pcie_rxp),
        .pcie_rxn      (pcie_rxn),
        .pcie_txp      (pcie_txp),
        .pcie_txn      (pcie_txn),
        .led           (led)
    );
`endif

    wire _unused_compat = &{1'b0, user_clk, m_axi_wvalid, m_axi_wready,
                            m_axi_wdata, m_axi_wstrb, usr_irq_req, usr_irq_ack};
endmodule

// Simulation-only Gen1 Ordered-Set reconstruction at a selected PIPE/GT
// boundary.  It deliberately does not share the production parser so that a
// model-side word splice can be distinguished from a DUT parser defect.
module k13_gen1_os_boundary_monitor #(
    parameter integer BOUNDARY_ID = 0,
    parameter integer LOG_LIMIT = 128
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire        epoch,
    input  wire        sample_valid,
    input  wire [15:0] sample_data,
    input  wire [1:0]  sample_datak,
    input  wire [5:0]  ltssm_state,
    output reg         event_valid,
    output reg  [1:0]  event_kind,
    output reg  [11:0] event_seq,
    output reg  [63:0] event_start_ps,
    output reg  [63:0] event_end_ps
);
    localparam [7:0] K_COM = 8'hbc;
    localparam [7:0] D_TS1 = 8'h4a;
    localparam [7:0] D_TS2 = 8'h45;

    reg active;
    reg [2:0] word_index;
    reg [1:0] identifier_kind;
    reg parse_error;
    reg [11:0] sequence_count;
    reg [63:0] start_time;
    reg [5:0] start_state;

    wire [7:0] symbol0 = sample_data[7:0];
    wire [7:0] symbol1 = sample_data[15:8];
    wire ident_ts1 = (sample_datak == 2'b00) &&
                     (symbol0 == D_TS1) && (symbol1 == D_TS1);
    wire ident_ts2 = (sample_datak == 2'b00) &&
                     (symbol0 == D_TS2) && (symbol1 == D_TS2);

    task automatic emit_event(input [1:0] kind);
        begin
            if (sequence_count != 12'hfff) begin
                event_valid <= 1'b1;
                event_kind <= kind;
                event_seq <= sequence_count;
                event_start_ps <= start_time;
                event_end_ps <= $time;
                if (sequence_count < LOG_LIMIT)
                    $display("K13_PIPE_OS epoch=%0d boundary=%0d seq=%0d kind=%0d start_ps=%0d end_ps=%0t start_state=%0h end_state=%0h",
                             epoch, BOUNDARY_ID, sequence_count, kind,
                             start_time, $time, start_state, ltssm_state);
                sequence_count <= sequence_count + 1'b1;
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active <= 1'b0;
            word_index <= 3'd0;
            identifier_kind <= 2'd0;
            parse_error <= 1'b0;
            sequence_count <= 12'd0;
            start_time <= 64'd0;
            start_state <= 6'd0;
            event_valid <= 1'b0;
            event_kind <= 2'd0;
            event_seq <= 12'd0;
            event_start_ps <= 64'd0;
            event_end_ps <= 64'd0;
        end else begin
            event_valid <= 1'b0;
            if (!enable) begin
                active <= 1'b0;
                word_index <= 3'd0;
                identifier_kind <= 2'd0;
                parse_error <= 1'b0;
                sequence_count <= 12'd0;
            end else if (!sample_valid) begin
                if (active) begin
                    emit_event(2'd3);
                    active <= 1'b0;
                    word_index <= 3'd0;
                end
            end else if (!active) begin
                if (sample_datak[0] && (symbol0 == K_COM)) begin
                    active <= 1'b1;
                    word_index <= 3'd1;
                    identifier_kind <= 2'd0;
                    parse_error <= 1'b0;
                    start_time <= $time;
                    start_state <= ltssm_state;
                end
            end else begin
                // A fresh COM while a residual/mode-switch word is being
                // assembled is a stronger boundary than the stale word index.
                // Resynchronize here so the first complete TS is numbered 0.
                if (sample_datak[0] && (symbol0 == K_COM)) begin
                    active <= 1'b1;
                    word_index <= 3'd1;
                    identifier_kind <= 2'd0;
                    parse_error <= 1'b0;
                    start_time <= $time;
                    start_state <= ltssm_state;
                end else case (word_index)
                    3'd1, 3'd2: word_index <= word_index + 1'b1;
                    3'd3: begin
                        if (ident_ts1)
                            identifier_kind <= 2'd1;
                        else if (ident_ts2)
                            identifier_kind <= 2'd2;
                        else begin
                            identifier_kind <= 2'd0;
                            parse_error <= 1'b1;
                        end
                        word_index <= 3'd4;
                    end
                    3'd4, 3'd5, 3'd6: begin
                        if (((identifier_kind == 2'd1) && !ident_ts1) ||
                            ((identifier_kind == 2'd2) && !ident_ts2) ||
                            (identifier_kind == 2'd0))
                            parse_error <= 1'b1;
                        word_index <= word_index + 1'b1;
                    end
                    default: begin
                        if (parse_error ||
                            ((identifier_kind == 2'd1) && !ident_ts1) ||
                            ((identifier_kind == 2'd2) && !ident_ts2) ||
                            (identifier_kind == 2'd0))
                            emit_event(2'd3);
                        else
                            emit_event(identifier_kind);
                        active <= 1'b0;
                        word_index <= 3'd0;
                    end
                endcase
            end
        end
    end
endmodule

`default_nettype wire
