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

    reg  refclk_p;
    wire refclk_n = ~refclk_p;
    reg  sys_rst_n;
    reg  disconnect_lane0;
    reg  b2_negative_stub;
    reg  b2_active;
    reg  b2_stress;
    reg  k13_retrain_active;
    reg  k13_retrain_monitor_armed;
    reg  k13_retry_sent;

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
    integer k13_ep_fallback_pipe_samples;
    reg [1:0] k13_last_rxeq_ctrl;
    reg       k13_last_rxeq_done;
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
        disconnect_lane0 = $test$plusargs("K11B_DISCONNECT_LANE0");
        b2_negative_stub = $test$plusargs("K11B2_NEGATIVE_STUB");
        b2_active = $test$plusargs("K11B2_RUN");
        b2_stress = $test$plusargs("K11B2_STRESS");
        k13_retrain_active = $test$plusargs("K13_RETRAIN");
        k13_retrain_monitor_armed = 1'b0;
        k13_retry_sent = 1'b0;
        repeat (500) @(posedge refclk_p);
        sys_rst_n = 1'b1;
        $display("K11B_RESET_RELEASE time_ps=%0t disconnect=%0d", $time,
                 disconnect_lane0);
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
        .sys_rst_n   (sys_rst_n)
    );

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
        if ($test$plusargs("K13_GEN3_COLD_PHY")) begin
            force EP.DUT.phy_rate = 2'b10;
            force EP.DUT.u_ltssm_mac.ltssm_state = 6'd11;
            force ep_rxp = ep_txp;
            force ep_rxn = ep_txn;
            wait (EP.DUT.pipe_rst_n === 1'b1);
            cold_wait = 0;
            while (!EP.DUT.phy_rxdata_valid && (cold_wait < 25000)) begin
                @(posedge EP.DUT.phy_pclk);
                cold_wait = cold_wait + 1;
            end
            $display("K13_GEN3_COLD_PHY_RESULT wait=%0d rxvalid=%0d data_valid=%0d start=%0d header=%02b data=%08x tx_edges=%0d",
                     cold_wait, EP.DUT.phy_rxvalid,
                     EP.DUT.phy_rxdata_valid, EP.DUT.phy_rxstart_block,
                     EP.DUT.phy_rxsync_header, EP.DUT.phy_rxdata,
                     ep_tx_edge_count);
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
        k13_ep_fallback_pipe_samples = 0;
        k13_rp_tx_edges_at_retrain = 0;
        k13_ep_tx_edges_at_retrain = 0;
        k13_last_rxeq_ctrl = 2'b00;
        k13_last_rxeq_done = 1'b0;
        k13_last_rxeq_fsm = 3'd0;
    end

    always @(RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_rate or
             EP.DUT.phy_rate or EP.DUT.phy_phystatus) begin
        if (k13_retrain_monitor_armed)
            $display("K13_RATE_EVENT time_ps=%0t rp_rate=%02b ep_rate=%02b ep_phystatus=%0d rp_state=%0h ep_state=%0d speed_state=%0d",
                     $time,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_rate,
                     EP.DUT.phy_rate, EP.DUT.phy_phystatus,
                     RP.cfg_ltssm_state, EP.DUT.ltssm_state,
                     EP.DUT.k13_speed_state);
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
                (EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.phy_lane[0].phy_rxeq_i.fsm != k13_last_rxeq_fsm)) begin
                $display("K13_RXEQ_EVENT time_ps=%0t ctrl=%02b done=%0d adapt_done=%0d fsm=%0d post_active=%0d post_ready=%0d gtreset=%0d userrdy=%0d progreset=%0d progdone=%0d",
                         $time, EP.DUT.phy_rxeq_ctrl,
                         EP.DUT.phy_rxeq_done,
                         EP.DUT.phy_rxeq_adapt_done,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.phy_lane[0].phy_rxeq_i.fsm,
                         EP.DUT.g_k13_enabled_top.u_k13_production_ctrl.post_rate_rxeq_active,
                         EP.DUT.g_k13_enabled_top.u_k13_production_ctrl.post_rate_rxeq_ready,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.gtrxreset_in,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.rxuserrdy_in,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.rxprogdivreset_in,
                         EP.DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.rxprgdivresetdone_out[0]);
                k13_last_rxeq_ctrl <= EP.DUT.phy_rxeq_ctrl;
                k13_last_rxeq_done <= EP.DUT.phy_rxeq_done;
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
                (k13_recovery_ts_samples < 96)) begin
                $display("K13_RECOVERY_TS n=%0d ep_state=%0d ts1=%0d ts2=%0d malformed=%0d link=%02x lane=%02x rate=%02x ctrl=%02x rx_count=%0d",
                         k13_recovery_ts_samples, EP.DUT.ltssm_state,
                         EP.DUT.os_ts1_valid, EP.DUT.os_ts2_valid,
                         EP.DUT.os_malformed, EP.DUT.os_link_number,
                         EP.DUT.os_lane_number, EP.DUT.os_rate_id,
                         EP.DUT.os_training_control, EP.DUT.rx_ts_count);
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
                $display("K13_GEN3_PIPE_SAMPLE n=%0d rp_rate=%02b rp_txidle=%0d rp_txvalid=%0d rp_txstart=%0d rp_txheader=%02b rp_txdata=%08x rxvalid=%0d rx_data_valid=%0d rx_start=%0d rx_header=%02b rx_data=%08x tx_valid=%0d tx_start=%0d tx_header=%02b tx_data=%08x",
                         k13_gen3_pipe_samples,
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
            if ((EP.DUT.phy_rate == 2'b10) &&
                (RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_rate == 2'b10) &&
                (k13_gen3_rx_samples < 256) &&
                (!RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_tx0_elec_idle ||
                 EP.DUT.phy_rxdata_valid || EP.DUT.phy_rxstart_block)) begin
                $display("K13_GEN3_RX_SAMPLE n=%0d rp_state=%0h rp_idle=%0d rp_valid=%0d rp_start=%0d rp_header=%02b rp_data=%08x ep_rxvalid=%0d ep_data_valid=%0d ep_start=%0d ep_header=%02b ep_data=%08x cdr=%0d rxreset=%0d rategen3=%0d gen3rdy=%0d rateidle=%0d rxctrl0=%04x rawdata=%08x",
                         k13_gen3_rx_samples, RP.cfg_ltssm_state,
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
        end
    end
`endif

    always @(posedge EP.DUT.phy_pclk) begin
        if (!EP.DUT.pipe_rst_n) begin
            last_ep_state <= 6'h3f;
            stable_count <= 0;
        end else begin
            if (EP.DUT.ltssm_state != last_ep_state) begin
                $display("K11B_EP_STATE time_ps=%0t state=%0d rx_ts=%0d train_err=%0d timeout=%0d",
                         $time, EP.DUT.ltssm_state, EP.DUT.rx_ts_count,
                         EP.DUT.training_error_count, EP.DUT.timeout_count);
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

            if (!disconnect_lane0 && !b2_active &&
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
                        k13_ep_fallback_pipe_samples = 0;
                        k13_retry_sent = 1'b0;
                        k13_gen1_l0_stable = 0;
                        k13_rp_tx_edges_at_retrain = rp_tx_edge_count[0];
                        k13_ep_tx_edges_at_retrain = ep_tx_edge_count;
                        k13_retrain_monitor_armed = 1'b1;
                        // Program the Root Port target as well as the endpoint.
                        // A Type-0 write only changes the endpoint; it cannot make
                        // the Root Port PHY leave Gen1 by itself.
                        RP.cfg_usrapp.TSK_WRITE_CFG_DW(
                            32'h3c, 32'h0000_0003, 4'h1);
                        RP.tx_usrapp.DEFAULT_TAG = RP.tx_usrapp.DEFAULT_TAG + 1'b1;
                        RP.tx_usrapp.TSK_TX_TYPE0_CONFIGURATION_WRITE(
                            RP.tx_usrapp.DEFAULT_TAG, 12'h070, 32'h0000_0003, 4'h1);
                        RP.tx_usrapp.TSK_TX_CLK_EAT(100);
                        RP.tx_usrapp.DEFAULT_TAG = RP.tx_usrapp.DEFAULT_TAG + 1'b1;
                        RP.tx_usrapp.TSK_TX_TYPE0_CONFIGURATION_WRITE(
                            RP.tx_usrapp.DEFAULT_TAG, 12'h050, 32'h0000_0020, 4'h1);
                        RP.tx_usrapp.TSK_TX_CLK_EAT(100);
                        RP.cfg_usrapp.TSK_WRITE_CFG_DW(
                            32'h34, 32'h0081_0020, 4'hf);
                        $display("K13_VCS_RETRAIN_TRIGGER target=3 link_control=0020");

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
                                RP.cfg_usrapp.TSK_WRITE_CFG_DW(
                                    32'h3c, 32'h0000_0003, 4'h1);
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
                                RP.cfg_usrapp.TSK_WRITE_CFG_DW(
                                    32'h34, 32'h0081_0020, 4'hf);
                                k13_retry_sent = 1'b1;
                                k13_gen1_l0_stable = 0;
                                k13_wait_cycles = 0;
                                $display("K13_VCS_RETRAIN_RETRY target=3 after_gen1_l0_stable cycles=64");
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
        end else if (!b2_active) begin
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

`ifdef K13_DUT
    localparam integer K13_ENABLED = 1;
`else
    localparam integer K13_ENABLED = 0;
`endif
`ifdef K13_RXEQ_BOOTSTRAP_VALUE
    localparam integer K13_RXEQ_BOOTSTRAP_CFG = `K13_RXEQ_BOOTSTRAP_VALUE;
`else
    localparam integer K13_RXEQ_BOOTSTRAP_CFG = 1;
`endif

    kcu105_pcie_ep_gen1_top #(
        .DETECT_QUIET_CYCLES   (DETECT_QUIET_CYCLES),
        .DETECT_TIMEOUT_CYCLES (DETECT_TIMEOUT_CYCLES),
        .TRAIN_TIMEOUT_CYCLES  (TRAIN_TIMEOUT_CYCLES),
        .HOT_RESET_CYCLES      (HOT_RESET_CYCLES),
        .K13_ENABLE            (K13_ENABLED),
        // The encrypted Xilinx Root Port can spend tens of microseconds in
        // same-rate Recovery before asserting the rate-change handshake.
        // Keep these above that real serial-model latency.
        .K13_SPEED_TIMEOUT_CYCLES(65_536),
        .K13_EQ_TIMEOUT_CYCLES (65_536),
        .K13_RXEQ_BOOTSTRAP    (K13_RXEQ_BOOTSTRAP_CFG)
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

`default_nettype wire
