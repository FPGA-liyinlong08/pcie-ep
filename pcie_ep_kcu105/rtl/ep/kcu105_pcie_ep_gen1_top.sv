`timescale 1ns/1ps
`default_nettype none

// K11 Gen1 x1 Endpoint production boundary:
// LTSSM/MAC -> semantic PHY command controller -> K02 PHY wrapper.
module kcu105_pcie_ep_gen1_top #(
    parameter integer DETECT_QUIET_CYCLES = 1_500_000,
    parameter integer DETECT_TIMEOUT_CYCLES = 3_000_000,
    parameter integer TRAIN_TIMEOUT_CYCLES = 6_000_000,
    parameter integer HOT_RESET_CYCLES = 250_000,
    parameter integer K11B2_ILA_DEBUG = 0,
    parameter integer K14_RATE_DEBUG = 0,
    parameter integer G9_WAIT_REMOTE_DETECT = 1,
    parameter integer G9_WAIT_REMOTE_DETECT_CYCLES = 6_250_000,
    // Phase D experimental path.  Zero is the signed Phase C Gen1 release.
    parameter integer GEN3_RATE_CHANGE_ENABLE = 1,
    parameter integer GEN3_SPEED_TIMEOUT_CYCLES = 1_000_000,
    parameter integer GEN3_AUTO_RETRAIN_CYCLES = 0,
    // K15 reversible PHY-envelope knobs. Production defaults enable the
    // Figure-1 canonical preset/query flow; Query may be disabled for A/B.
    parameter integer K15_AB_CDR_HOLD = 0,
    parameter integer K15_AB_PRERATE_TXEQ = 1,
    parameter integer K15_AB_PRERATE_QUERY = 1,
    parameter integer K15_AB_PRERATE_DWELL_CYCLES = 0,
    parameter integer K15_AB_PRERATE_PRESET = 4,
    // K15 production capability: Gen1/2/3 supported, speed_change clear until
    // an accepted Recovery transaction requests the physical transition.
    parameter [7:0] LTSSM_TX_RATE_ID = 8'h0e
) (
    input wire pcie_refclk_p, input wire pcie_refclk_n,
    input wire pcie_perst_n, input wire pcie_rxp, input wire pcie_rxn,
    output wire pcie_txp, output wire pcie_txn, output wire [7:0] led,
    output wire link_up, output wire dll_active,
    output wire [5:0] ltssm_state, output wire [1:0] dll_fc_state,
    output wire [1:0] negotiated_speed, output wire [2:0] negotiated_width,
    output wire [15:0] captured_bdf, output wire bdf_valid,
    output wire [31:0] bar0_base, output wire memory_space_enable,
    output wire [7:0] cdc_errors
);
    wire phy_coreclk, phy_userclk, phy_mcapclk, phy_pclk;
    wire pipe_rst_n, core_rst_n;
    wire [31:0] phy_rxdata, phy_txdata;
    wire [1:0] phy_rxdatak, phy_txdatak;
    wire phy_rxdata_valid, phy_rxstart_block, phy_rxvalid;
    wire [1:0] phy_rxsync_header;
    wire phy_phystatus, phy_phystatus_rst, phy_rxelecidle;
    wire [2:0] phy_rxstatus;
    wire [5:0] phy_txeq_fs, phy_txeq_lf;
    wire [17:0] phy_txeq_new_coeff, phy_rxeq_new_txcoeff;
    wire phy_txeq_done, phy_rxeq_preset_sel;
    wire phy_rxeq_adapt_done, phy_rxeq_done;

    wire phy_txdata_valid, phy_txstart_block, phy_txdetectrx;
    wire [1:0] phy_txsync_header;
    wire phy_txelecidle, phy_txcompliance, phy_rxpolarity;
    wire [1:0] phy_powerdown, phy_rate;
    wire [2:0] phy_txmargin;
    wire phy_txswing, phy_txdeemph;
    wire [1:0] phy_txeq_ctrl, phy_rxeq_ctrl;
    wire [3:0] phy_txeq_preset, phy_rxeq_txpreset;
    wire [5:0] phy_txeq_coeff;
    wire as_mac_in_detect, as_cdr_hold_req;

    wire [2:0] phy_cmd_profile;
    wire phy_cmd_valid, phy_cmd_kind, phy_cmd_ready, phy_cmd_done;
    wire [1:0] phy_cmd_result;
    wire phy_rate_req_valid, phy_rate_req_ready, phy_rate_busy;
    wire phy_rate_done, phy_rate_abort;
    wire [1:0] phy_rate_req_target, phy_active_rate;
    wire [2:0] phy_rate_result;
    wire [3:0] phy_rate_state;
    wire prerate_preset_valid, prerate_query_valid;
    wire [3:0] prerate_preset;
    wire [17:0] prerate_query_coeff;

    wire mac_rx_valid, mac_rx_sop, mac_rx_eop, mac_rx_is_dllp;
    wire [15:0] mac_rx_data;
    wire [1:0] mac_rx_keep;
    wire [3:0] mac_rx_error;
    wire mac_tx_valid, mac_tx_valid_core, mac_tx_ready, mac_tx_sop, mac_tx_eop;
    wire mac_tx_is_dllp, mac_tx_bad;
    wire [15:0] mac_tx_data;
    wire [1:0] mac_tx_keep;
    wire recovery_req, hot_reset_seen;
    wire [7:0] link_number;
    wire [4:0] rx_ts_count;
    wire [31:0] training_error_count, timeout_count, frame_error_count;
    wire core_retrain_link_pulse;
    wire [1:0] core_target_link_speed;
    wire ltssm_recovery_speed_ready;
    wire os_ts1_valid, os_ts2_valid, os_malformed, os_tx_complete;
    wire [7:0] os_link_number, os_lane_number, os_rate_id;
    wire [7:0] os_training_control, os_eq_control;
    wire [23:0] os_eq_data;
    wire speed_recovery_active, speed_recovery_done;
    wire speed_traffic_quiesce, speed_fallback_req, speed_fallback_active;
    wire [1:0] speed_requested_rate;
    wire [2:0] speed_state;
    wire eq_req_valid, eq_req_ready, eq_busy, eq_done;
    wire [2:0] eq_req_kind, eq_result;
    wire [3:0] eq_req_preset;
    wire [17:0] eq_req_coeff, eq_rsp_coeff;
    wire eq_rsp_preset_sel;
    wire gen3_eq_active, gen3_eq_failed;
    wire [1:0] gen3_eq_phase;
    wire [2:0] dbg_eq_operation_state;
    wire [3:0] dbg_eq_phase_ts_count;
    wire dbg_eq_phase_done, dbg_eq_phase_failed;
    wire [7:0] dbg_eq_tx_control;
    wire [23:0] dbg_eq_tx_data;
    wire [31:0] dbg_eq_phase2_internal;
    reg [24:0] heartbeat_count;

    wire dbg_operational_seen, dbg_link_loss_seen;
    wire dbg_link_loss_pipe, dbg_link_loss_core;
    generate if (K11B2_ILA_DEBUG != 0) begin : g_ila_debug
        // Stable board-level aliases required by the PIPE ILA Tcl. These are
        // observation-only and remain absent from the functional build.
        (* mark_debug = "true", keep = "true" *)
        wire dbg_pipe_clk = phy_pclk;
        (* mark_debug = "true", keep = "true" *)
        wire dbg_pipe_tlp_trigger = phy_txdata_valid && phy_txstart_block;
        (* mark_debug = "true", keep = "true" *)
        wire dbg_pipe_link_loss_trigger = dbg_link_loss_pipe;
        (* mark_debug = "true", keep = "true" *)
        wire dbg_phy_rxidle_conflict = phy_rxelecidle &&
                                       (phy_rxvalid || phy_rxdata_valid);
        reg dbg_perst_n_pipe_d;
        reg dbg_phystatus_rst_d;
        always @(posedge phy_pclk or negedge pipe_rst_n) begin
            if (!pipe_rst_n) begin
                dbg_perst_n_pipe_d <= 1'b0;
                dbg_phystatus_rst_d <= 1'b0;
            end else begin
                dbg_perst_n_pipe_d <= pipe_rst_n;
                dbg_phystatus_rst_d <= phy_phystatus_rst;
            end
        end
        (* mark_debug = "true", keep = "true" *)
        wire dbg_perst_n_pipe = pipe_rst_n;
        (* mark_debug = "true", keep = "true" *)
        wire dbg_perst_rise_pipe = pipe_rst_n && !dbg_perst_n_pipe_d;
        (* mark_debug = "true", keep = "true" *)
        wire dbg_phystatus_rst_fall_pipe = dbg_phystatus_rst_d &&
                                            !phy_phystatus_rst;
    end endgenerate
    generate if (K11B2_ILA_DEBUG != 0) begin : g_link_loss_debug
        pcie_link_loss_trigger u_link_loss_trigger (
            .clk(phy_pclk), .rst_n(pipe_rst_n), .link_up(link_up),
            .dll_active(dll_active), .operational_seen(dbg_operational_seen),
            .link_loss_seen(dbg_link_loss_seen),
            .link_loss_pulse(dbg_link_loss_pipe)
        );
        pcie_cdc_pulse u_link_loss_cdc (
            .s_clk(phy_pclk), .s_rst_n(pipe_rst_n),
            .s_pulse(dbg_link_loss_pipe), .d_clk(phy_coreclk),
            .d_rst_n(core_rst_n), .d_pulse(dbg_link_loss_core)
        );
    end else begin : g_link_loss_debug_disabled
        assign dbg_operational_seen = 1'b0;
        assign dbg_link_loss_seen = 1'b0;
        assign dbg_link_loss_pipe = 1'b0;
        assign dbg_link_loss_core = 1'b0;
    end endgenerate

    // Phase D coordinator is semantic-only.  It can accept an Endpoint
    // configuration retrain request through the CDC mailbox, a Root Port TS1
    // speed-change indication, or the explicitly configured one-shot board
    // stimulus.  None of these paths owns a raw PHY signal.
    generate if (GEN3_RATE_CHANGE_ENABLE != 0) begin : g_gen3_rate_change
        wire mailbox_valid, mailbox_accept, mailbox_busy;
        wire mailbox_overflow_sticky;
        wire [1:0] mailbox_target;
        wire speed_retrain_accept;
        wire speed_rate_req_valid;
        wire [1:0] speed_rate_req_target;
        wire speed_timeout_sticky, speed_peer_reject_sticky;
        wire speed_illegal_sticky, speed_cdr_loss_sticky;
        wire speed_fallback_sticky;
        wire [1:0] speed_negotiated;
        localparam integer AUTO_RETRAIN_LIMIT =
            (GEN3_AUTO_RETRAIN_CYCLES < 1) ? 1 : GEN3_AUTO_RETRAIN_CYCLES;
        reg [31:0] auto_retrain_count;
        reg auto_retrain_issued;
        wire auto_retrain_pulse = (GEN3_AUTO_RETRAIN_CYCLES != 0) &&
                                   link_up && !auto_retrain_issued &&
                                   (auto_retrain_count >=
                                    (AUTO_RETRAIN_LIMIT - 1));
        wire partner_retrain_window = link_up ||
                                      (ltssm_state == 6'd11) ||
                                      (ltssm_state == 6'd12) ||
                                      (ltssm_state == 6'd18);
        wire [1:0] partner_target = os_rate_id[3] ? 2'b10 :
                                    os_rate_id[2] ? 2'b01 :
                                    os_rate_id[1] ? 2'b00 : 2'b11;
        wire partner_request_valid = partner_retrain_window && os_ts1_valid &&
                                     os_rate_id[7] &&
                                     (partner_target != 2'b11);
        wire partner_retrain_pending;
        wire [1:0] partner_retrain_target;
        wire partner_retrain_armed;
        wire partner_retrain_accept = partner_retrain_pending &&
                                      speed_retrain_accept &&
                                      !auto_retrain_pulse;

        pcie_partner_retrain_pending u_partner_retrain_pending (
            .clk(phy_pclk), .rst_n(pipe_rst_n),
            .request_valid(partner_request_valid),
            .request_target(partner_target),
            // Re-arm only after the accepted Recovery transaction has
            // returned to the semantic L0 state.  Intermediate Recovery
            // substates must not turn repeated TS1s into a second request.
            .rearm(link_up && (speed_state == 3'd0) &&
                   !speed_recovery_active),
            .accept(partner_retrain_accept),
            .pending(partner_retrain_pending),
            .pending_target(partner_retrain_target),
            .armed(partner_retrain_armed)
        );

        always @(posedge phy_pclk or negedge pipe_rst_n) begin
            if (!pipe_rst_n) begin
                auto_retrain_count <= 32'd0;
                auto_retrain_issued <= 1'b0;
            end else if (!auto_retrain_issued && link_up) begin
                if (auto_retrain_pulse)
                    auto_retrain_issued <= 1'b1;
                else if (GEN3_AUTO_RETRAIN_CYCLES != 0)
                    auto_retrain_count <= auto_retrain_count + 1'b1;
            end
        end

        pcie_retrain_cdc_mailbox u_retrain_mailbox (
            .s_clk(phy_coreclk), .s_rst_n(core_rst_n),
            .s_retrain_pulse(core_retrain_link_pulse),
            .s_target_speed(core_target_link_speed),
            .s_busy(mailbox_busy),
            .s_overflow_sticky(mailbox_overflow_sticky),
            .d_clk(phy_pclk), .d_rst_n(pipe_rst_n),
            .d_retrain_valid(mailbox_valid), .d_target_speed(mailbox_target),
            .d_retrain_accept(mailbox_accept)
        );

        wire semantic_retrain_valid = auto_retrain_pulse ||
                                      partner_retrain_pending || mailbox_valid;
        wire [1:0] semantic_retrain_target = auto_retrain_pulse ? 2'b10 :
                                               partner_retrain_pending ?
                                               partner_retrain_target : mailbox_target;
        assign mailbox_accept = mailbox_valid && speed_retrain_accept &&
                                !auto_retrain_pulse &&
                                !partner_retrain_pending;

        wire reinitialize_gen1 = (ltssm_state == 6'd0) ||
                                 (ltssm_state == 6'd1) ||
                                 (ltssm_state == 6'd14) ||
                                 (ltssm_state == 6'd15) ||
                                 (ltssm_state == 6'd16) ||
                                 (ltssm_state == 6'd17);
        wire rate_op_success = phy_rate_done &&
                               (phy_rate_result == 3'd1);
        wire rate_op_failed = phy_rate_done &&
                              (phy_rate_result != 3'd0) &&
                              (phy_rate_result != 3'd1);
        // A single TS at the new rate proves only that the receiver is alive;
        // it does not prove that the partner completed Recovery.  Declare the
        // peer side complete only after the LTSSM consumed the required
        // RcvrLock/RcvrCfg sequence and entered Recovery.Idle.  Otherwise the
        // existing semantic timeout must drive the safe Gen1 fallback.
        wire peer_speed_ok = (phy_active_rate == speed_requested_rate) &&
                             (ltssm_state == 6'd13);

        pcie_recovery_speed_ctrl #(
            .SPEED_TIMEOUT_CYCLES(GEN3_SPEED_TIMEOUT_CYCLES)
        ) u_recovery_speed (
            .clk(phy_pclk), .rst_n(pipe_rst_n), .link_up(link_up),
            .reinitialize_gen1(reinitialize_gen1),
            .retrain_valid(semantic_retrain_valid),
            .retrain_target_speed(semantic_retrain_target),
            .ltssm_speed_ready(ltssm_recovery_speed_ready),
            .rate_req_valid(speed_rate_req_valid),
            .rate_req_target(speed_rate_req_target),
            .fallback_req(speed_fallback_req),
            .rate_req_ready(phy_rate_req_ready),
            .rate_op_done(rate_op_success), .rate_op_failed(rate_op_failed),
            .active_rate(phy_active_rate), .requested_rate(speed_requested_rate),
            .retrain_accept(speed_retrain_accept), .phy_cdr_lost(1'b0),
            .peer_speed_ok(peer_speed_ok),
            .peer_speed_reject(gen3_eq_failed),
            .state(speed_state), .traffic_quiesce(speed_traffic_quiesce),
            .recovery_active(speed_recovery_active),
            .negotiated_speed(speed_negotiated),
            .speed_timeout_sticky(speed_timeout_sticky),
            .peer_reject_sticky(speed_peer_reject_sticky),
            .illegal_speed_sticky(speed_illegal_sticky),
            .cdr_loss_sticky(speed_cdr_loss_sticky),
            .fallback_taken_sticky(speed_fallback_sticky)
        );

        assign phy_rate_req_valid = speed_rate_req_valid;
        assign phy_rate_req_target = speed_rate_req_target;
        assign phy_rate_abort = reinitialize_gen1 || rate_op_failed;
        assign speed_recovery_done = rate_op_success;

        if (K14_RATE_DEBUG != 0) begin : g_rate_debug
            (* KEEP = "TRUE" *) wire qpll1lock_record_in;
            (* KEEP = "TRUE" *) wire qpll1reset_record_in;
            (* mark_debug = "true" *) wire [117:0] k14_event_record_w;
            (* mark_debug = "true" *) wire [3:0] k14_event_state_w =
                rate_op_success ? 4'd8 :
                rate_op_failed ? 4'd15 :
                (speed_rate_req_valid || phy_rate_busy) ? 4'd6 : 4'd0;
            (* mark_debug = "true" *) wire [1:0] k14_phy_rate_w = phy_rate;
            (* mark_debug = "true" *) wire [1:0] k14_phy_powerdown_w =
                phy_powerdown;
            (* mark_debug = "true" *) wire k14_phy_txei_w = phy_txelecidle;
            (* mark_debug = "true" *) wire k14_detect_assist_w =
                as_mac_in_detect;
            (* mark_debug = "true" *) wire k14_cdr_hold_w = as_cdr_hold_req;
            (* mark_debug = "true" *) wire [3:0] k14_rate_state_w =
                phy_rate_state;
            (* mark_debug = "true" *) wire [2:0] k14_speed_state_w =
                speed_state;
            (* mark_debug = "true" *) wire [5:0] k14_ltssm_state_w =
                ltssm_state;
            (* mark_debug = "true" *) wire k14_rp_gen3_request_seen_w =
                partner_request_valid && (partner_target == 2'b10);
            (* mark_debug = "true" *) wire k14_partner_pending_w =
                partner_retrain_pending;
            (* mark_debug = "true" *) wire k14_partner_armed_w =
                partner_retrain_armed;
            (* mark_debug = "true" *) wire k14_partner_accept_w =
                partner_retrain_accept;
            (* mark_debug = "true" *) wire k14_gen3_rate_success_w =
                rate_op_success && (phy_rate == 2'b10);
            (* mark_debug = "true" *) wire k14_timeout_fallback_w =
                speed_timeout_sticky && speed_fallback_sticky;
            (* mark_debug = "true" *) wire k14_gen1_fallback_success_w =
                rate_op_success && (phy_rate == 2'b00) &&
                (speed_state >= 3'd5);
            (* mark_debug = "true" *) wire k14_auto_retrain_w =
                auto_retrain_pulse;
            (* mark_debug = "true" *) wire k14_mailbox_valid_w =
                mailbox_valid;
            // Phase 2 can remain active for TRAIN_TIMEOUT_CYCLES (24 ms at
            // 250 MHz), much longer than the 8192-sample ILA window.  Keep
            // milestones sticky so a fallback trigger still tells which
            // command/protocol boundaries were crossed earlier.
            reg [5:0] k15_phase2_sticky_r;
            reg [22:0] k15_phase2_elapsed_r;
            reg k15_rxeq_done_q;
            reg k15_phase2_active_q;
            wire k15_phase2_active = (ltssm_state == 6'h2a);
            wire k15_eq_req_accept = k15_phase2_active &&
                                      eq_req_valid && eq_req_ready;
            wire k15_eq_proposal = k15_phase2_active && eq_done &&
                                    (eq_result == 3'd2);
            wire k15_proposal_match = k15_phase2_active &&
                                      dbg_eq_phase2_internal[0] &&
                                      dbg_eq_phase2_internal[3] &&
                                      dbg_eq_phase2_internal[4];
            wire k15_rxeq_done_rise = phy_rxeq_done &&
                                       !k15_rxeq_done_q;

            always @(posedge phy_pclk or negedge pipe_rst_n) begin
                if (!pipe_rst_n) begin
                    k15_phase2_sticky_r <= 6'd0;
                    k15_phase2_elapsed_r <= 23'd0;
                    k15_rxeq_done_q <= 1'b0;
                    k15_phase2_active_q <= 1'b0;
                end else begin
                    k15_rxeq_done_q <= phy_rxeq_done;
                    k15_phase2_active_q <= k15_phase2_active;
                    if (k15_phase2_active && !k15_phase2_active_q) begin
                        k15_phase2_elapsed_r <= 23'd1;
                        k15_phase2_sticky_r <=
                            {dbg_eq_phase_failed, dbg_eq_phase_done,
                             k15_proposal_match, k15_eq_proposal,
                             k15_rxeq_done_rise, k15_eq_req_accept};
                    end else if (k15_phase2_active) begin
                        if (!(&k15_phase2_elapsed_r))
                            k15_phase2_elapsed_r <=
                                k15_phase2_elapsed_r + 1'b1;
                        if (k15_eq_req_accept)
                            k15_phase2_sticky_r[0] <= 1'b1;
                        if (k15_rxeq_done_rise)
                            k15_phase2_sticky_r[1] <= 1'b1;
                        if (k15_eq_proposal)
                            k15_phase2_sticky_r[2] <= 1'b1;
                        if (k15_proposal_match)
                            k15_phase2_sticky_r[3] <= 1'b1;
                        if (dbg_eq_phase_done)
                            k15_phase2_sticky_r[4] <= 1'b1;
                        if (dbg_eq_phase_failed)
                            k15_phase2_sticky_r[5] <= 1'b1;
                    end
                end
            end

            // Fixed-width aliases make post-synthesis ILA insertion and CSV
            // decoding deterministic.  See the K15 Phase-2 board report for
            // the complete bit allocation.
            (* mark_debug = "true", keep = "true" *)
            wire [117:0] k15_phase2_debug_w = {
                k15_phase2_elapsed_r,       // [117:95]
                k15_phase2_sticky_r,        // [94:89]
                dbg_eq_operation_state,     // [88:86]
                dbg_eq_phase_ts_count,      // [85:82]
                dbg_eq_phase_done,          // [81]
                dbg_eq_phase_failed,        // [80]
                eq_req_valid,               // [79]
                eq_req_ready,               // [78]
                eq_req_kind,                // [77:75]
                eq_busy,                    // [74]
                eq_done,                    // [73]
                eq_result,                  // [72:70]
                phy_rxeq_ctrl,              // [69:68]
                phy_rxeq_txpreset,          // [67:64]
                phy_rxeq_done,              // [63]
                phy_rxeq_adapt_done,        // [62]
                phy_rxeq_preset_sel,        // [61]
                phy_rxeq_new_txcoeff,       // [60:43]
                os_ts1_valid,               // [42]
                os_malformed,               // [41]
                os_eq_control,              // [40:33]
                os_eq_data,                 // [32:9]
                dbg_eq_tx_control,          // [8:1]
                os_tx_complete              // [0]
            };
            (* mark_debug = "true", keep = "true" *)
            wire [37:0] k15_phase2_detail_w = {
                dbg_eq_phase2_internal[13:0], // [37:24]
                dbg_eq_tx_data                // [23:0]
            };
            k02_phy_event_recorder u_k14_event_recorder (
                .clk(phy_pclk), .rst(!pipe_rst_n),
                .qpll1lock(qpll1lock_record_in),
                .qpll1reset(qpll1reset_record_in), .phy_rate(phy_rate),
                .phy_phystatus(phy_phystatus),
                .seq_state(k14_event_state_w),
                .record_bus(k14_event_record_w)
            );
        end

        wire _unused_gen3 = &{1'b0, mailbox_busy, mailbox_overflow_sticky,
            partner_retrain_armed,
            speed_fallback_req,
            speed_timeout_sticky, speed_peer_reject_sticky,
            speed_illegal_sticky, speed_cdr_loss_sticky,
            speed_fallback_sticky, speed_negotiated};
    end else begin : g_gen3_rate_change_disabled
        assign phy_rate_req_valid = 1'b0;
        assign phy_rate_req_target = 2'b00;
        assign phy_rate_abort = 1'b0;
        assign speed_recovery_active = 1'b0;
        assign speed_recovery_done = 1'b0;
        assign speed_traffic_quiesce = 1'b0;
        assign speed_fallback_req = 1'b0;
        assign speed_requested_rate = 2'b00;
        assign speed_state = 3'd0;
    end endgenerate

    // The LTSSM needs a level for the complete fallback sequence, not the
    // coordinator's one-cycle fallback request pulse.
    assign speed_fallback_active = (speed_state >= 3'd5);

    kcu105_pcie_phy_wrapper u_phy_wrapper (
        .pcie_refclk_p(pcie_refclk_p), .pcie_refclk_n(pcie_refclk_n),
        .pcie_perst_n(pcie_perst_n), .pcie_rxp(pcie_rxp), .pcie_rxn(pcie_rxn),
        .pcie_txp(pcie_txp), .pcie_txn(pcie_txn),
        .phy_txdata(phy_txdata), .phy_txdatak(phy_txdatak),
        .phy_txdata_valid(phy_txdata_valid),
        .phy_txstart_block(phy_txstart_block),
        .phy_txsync_header(phy_txsync_header),
        .phy_txdetectrx(phy_txdetectrx), .phy_txelecidle(phy_txelecidle),
        .phy_txcompliance(phy_txcompliance), .phy_rxpolarity(phy_rxpolarity),
        .phy_powerdown(phy_powerdown), .phy_rate(phy_rate),
        .phy_txmargin(phy_txmargin), .phy_txswing(phy_txswing),
        .phy_txdeemph(phy_txdeemph), .phy_txeq_ctrl(phy_txeq_ctrl),
        .phy_txeq_preset(phy_txeq_preset), .phy_txeq_coeff(phy_txeq_coeff),
        .phy_rxeq_ctrl(phy_rxeq_ctrl), .phy_rxeq_txpreset(phy_rxeq_txpreset),
        .as_mac_in_detect(as_mac_in_detect),
        .as_cdr_hold_req(as_cdr_hold_req),
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

    pcie_phy_command_ctrl #(
        .K15_AB_CDR_HOLD(K15_AB_CDR_HOLD),
        .K15_AB_PRERATE_TXEQ(K15_AB_PRERATE_TXEQ),
        .K15_AB_PRERATE_QUERY(K15_AB_PRERATE_QUERY),
        .K15_AB_PRERATE_DWELL_CYCLES(K15_AB_PRERATE_DWELL_CYCLES),
        .K15_AB_PRERATE_PRESET(K15_AB_PRERATE_PRESET)
    ) u_phy_command_ctrl (
        .phy_pclk(phy_pclk), .pipe_rst_n(pipe_rst_n),
        .cmd_profile(phy_cmd_profile), .op_valid(phy_cmd_valid),
        .op_kind(phy_cmd_kind), .op_ready(phy_cmd_ready),
        .op_done(phy_cmd_done), .op_result(phy_cmd_result),
        .rate_req_valid(phy_rate_req_valid),
        .rate_req_target(phy_rate_req_target),
        .prerate_preset_valid(prerate_preset_valid),
        .prerate_preset(prerate_preset),
        .rate_abort(phy_rate_abort), .rate_req_ready(phy_rate_req_ready),
        .rate_busy(phy_rate_busy), .rate_done(phy_rate_done),
        .rate_result(phy_rate_result), .active_rate(phy_active_rate),
        .rate_state(phy_rate_state),
        .prerate_query_valid(prerate_query_valid),
        .prerate_query_coeff(prerate_query_coeff),
        .eq_req_valid(eq_req_valid), .eq_req_kind(eq_req_kind),
        .eq_req_preset(eq_req_preset), .eq_req_coeff(eq_req_coeff),
        .eq_req_ready(eq_req_ready), .eq_busy(eq_busy),
        .eq_done(eq_done), .eq_result(eq_result),
        .eq_rsp_preset_sel(eq_rsp_preset_sel),
        .eq_rsp_coeff(eq_rsp_coeff),
        .phy_phystatus(phy_phystatus), .phy_rxstatus(phy_rxstatus),
        .phy_txeq_fs(phy_txeq_fs), .phy_txeq_lf(phy_txeq_lf),
        .phy_txeq_new_coeff(phy_txeq_new_coeff),
        .phy_txeq_done(phy_txeq_done),
        .phy_rxeq_preset_sel(phy_rxeq_preset_sel),
        .phy_rxeq_new_txcoeff(phy_rxeq_new_txcoeff),
        .phy_rxeq_adapt_done(phy_rxeq_adapt_done),
        .phy_rxeq_done(phy_rxeq_done),
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
        .K11B2_ILA_DEBUG(K11B2_ILA_DEBUG),
        .G9_WAIT_REMOTE_DETECT(G9_WAIT_REMOTE_DETECT),
        .G9_WAIT_REMOTE_DETECT_CYCLES(G9_WAIT_REMOTE_DETECT_CYCLES),
        .TX_RATE_ID(LTSSM_TX_RATE_ID)
    ) u_ltssm_mac (
        .phy_pclk(phy_pclk), .pipe_rst_n(pipe_rst_n),
        .phy_rxdata(phy_rxdata), .phy_rxdatak(phy_rxdatak),
        .phy_rxdata_valid(phy_rxdata_valid),
        .phy_rxstart_block(phy_rxstart_block),
        .phy_rxsync_header(phy_rxsync_header), .phy_rxvalid(phy_rxvalid),
        .phy_rxelecidle(phy_rxelecidle),
        .phy_cmd_profile(phy_cmd_profile), .phy_cmd_valid(phy_cmd_valid),
        .phy_cmd_kind(phy_cmd_kind), .phy_cmd_ready(phy_cmd_ready),
        .phy_cmd_done(phy_cmd_done), .phy_cmd_result(phy_cmd_result),
        .active_phy_rate(phy_active_rate),
        .recovery_target_rate(speed_requested_rate),
        .recovery_fallback_active(speed_fallback_active),
        .gen3_tx_eq_control(8'h00),
        .gen3_tx_eq_data(24'd0), .gen3_protocol_eq_complete(1'b0),
        .eq_req_valid(eq_req_valid), .eq_req_kind(eq_req_kind),
        .eq_req_preset(eq_req_preset), .eq_req_coeff(eq_req_coeff),
        .eq_req_ready(eq_req_ready), .eq_busy(eq_busy),
        .eq_done(eq_done), .eq_result(eq_result),
        .eq_rsp_preset_sel(eq_rsp_preset_sel),
        .eq_rsp_coeff(eq_rsp_coeff),
        .prerate_query_valid(prerate_query_valid),
        .prerate_query_coeff(prerate_query_coeff),
        .local_txeq_fs(phy_txeq_fs), .local_txeq_lf(phy_txeq_lf),
        .prerate_preset_valid(prerate_preset_valid),
        .prerate_preset(prerate_preset),
        .gen3_eq_active(gen3_eq_active), .gen3_eq_phase(gen3_eq_phase),
        .gen3_eq_failed(gen3_eq_failed),
        .phy_txdata(phy_txdata), .phy_txdatak(phy_txdatak),
        .phy_txdata_valid(phy_txdata_valid),
        .phy_txstart_block(phy_txstart_block),
        .phy_txsync_header(phy_txsync_header),
        .tx_pkt_valid(mac_tx_valid), .tx_pkt_ready(mac_tx_ready),
        .tx_pkt_data(mac_tx_data), .tx_pkt_keep(mac_tx_keep),
        .tx_pkt_sop(mac_tx_sop), .tx_pkt_eop(mac_tx_eop),
        .tx_pkt_is_dllp(mac_tx_is_dllp), .tx_pkt_bad(mac_tx_bad),
        .rx_pkt_valid(mac_rx_valid), .rx_pkt_data(mac_rx_data),
        .rx_pkt_keep(mac_rx_keep), .rx_pkt_sop(mac_rx_sop),
        .rx_pkt_eop(mac_rx_eop), .rx_pkt_is_dllp(mac_rx_is_dllp),
        .rx_pkt_error(mac_rx_error), .link_disable(1'b0),
        .hot_reset_req(1'b0),
        .force_recovery(recovery_req || speed_recovery_active),
        .speed_retrain_active(speed_recovery_active),
        .recovery_speed_done(speed_recovery_done),
        .recovery_speed_ready(ltssm_recovery_speed_ready),
        .ltssm_state(ltssm_state), .link_up(link_up),
        .negotiated_width(negotiated_width),
        .negotiated_speed(negotiated_speed), .link_number(link_number),
        .rx_ts_count(rx_ts_count),
        .training_error_count(training_error_count),
        .timeout_count(timeout_count), .frame_error_count(frame_error_count),
        .hot_reset_seen(hot_reset_seen), .os_ts1_valid(os_ts1_valid),
        .os_ts2_valid(os_ts2_valid), .os_malformed(os_malformed),
        .os_link_number(os_link_number), .os_lane_number(os_lane_number),
        .os_rate_id(os_rate_id), .os_training_control(os_training_control),
        .os_tx_complete(os_tx_complete), .os_eq_control(os_eq_control),
        .os_eq_data(os_eq_data),
        .dbg_eq_operation_state(dbg_eq_operation_state),
        .dbg_eq_phase_ts_count(dbg_eq_phase_ts_count),
        .dbg_eq_phase_done(dbg_eq_phase_done),
        .dbg_eq_phase_failed(dbg_eq_phase_failed),
        .dbg_eq_tx_control(dbg_eq_tx_control),
        .dbg_eq_tx_data(dbg_eq_tx_data),
        .dbg_eq_phase2_internal(dbg_eq_phase2_internal)
    );

    // K15 reaches a stable Gen3 L0 with an idle-only 128b/130b stream. Keep
    // the Gen1 DLL/TLP core offline until K16 supplies a Gen3 data path.
    wire protocol_link_up = link_up && (phy_active_rate != 2'b10);
    k11a_offline_top #(.K11B2_ILA_DEBUG(K11B2_ILA_DEBUG)) u_protocol_core (
        .pipe_clk(phy_pclk), .pipe_rst_n(pipe_rst_n),
        .core_clk(phy_coreclk), .core_rst_n(core_rst_n),
        .link_up(protocol_link_up), .ltssm_state(ltssm_state),
        .link_speed(negotiated_speed), .link_width(negotiated_width),
        .hot_reset(hot_reset_seen),
        .dbg_link_loss_trigger(dbg_link_loss_core),
        .mac_rx_valid(mac_rx_valid), .mac_rx_data(mac_rx_data),
        .mac_rx_keep(mac_rx_keep), .mac_rx_sop(mac_rx_sop),
        .mac_rx_eop(mac_rx_eop), .mac_rx_is_dllp(mac_rx_is_dllp),
        .mac_rx_error(mac_rx_error), .mac_tx_valid(mac_tx_valid_core),
        .mac_tx_ready(mac_tx_ready), .mac_tx_data(mac_tx_data),
        .mac_tx_keep(mac_tx_keep), .mac_tx_sop(mac_tx_sop),
        .mac_tx_eop(mac_tx_eop), .mac_tx_is_dllp(mac_tx_is_dllp),
        .mac_tx_bad(mac_tx_bad), .dll_active(dll_active),
        .dll_fc_state(dll_fc_state), .recovery_req(recovery_req),
        .captured_bdf(captured_bdf), .bdf_valid(bdf_valid),
        .bar0_base(bar0_base), .memory_space_enable(memory_space_enable),
        .retrain_link_pulse(core_retrain_link_pulse),
        .target_link_speed(core_target_link_speed), .cdc_errors(cdc_errors)
    );

    assign mac_tx_valid = mac_tx_valid_core && !speed_traffic_quiesce &&
                          (phy_active_rate != 2'b10);

    always @(posedge phy_pclk or negedge pipe_rst_n) begin
        if (!pipe_rst_n) heartbeat_count <= 25'd0;
        else heartbeat_count <= heartbeat_count + 1'b1;
    end

    assign led[0] = pipe_rst_n && !phy_phystatus_rst;
    assign led[1] = link_up;
    assign led[2] = dll_active;
    assign led[3] = core_rst_n;
    assign led[4] = memory_space_enable;
    assign led[5] = bdf_valid;
    assign led[6] = (|cdc_errors) || recovery_req ||
                    (|training_error_count) || (|timeout_count) ||
                    (|frame_error_count);
    assign led[7] = heartbeat_count[24];

    wire _unused = &{1'b0, phy_userclk, phy_mcapclk, phy_rxstart_block,
        phy_rxsync_header, phy_txeq_fs, phy_txeq_lf, phy_txeq_new_coeff,
        phy_txeq_done, phy_rxeq_preset_sel, phy_rxeq_new_txcoeff,
        phy_rxeq_adapt_done, phy_rxeq_done, link_number, rx_ts_count,
        ltssm_recovery_speed_ready, core_retrain_link_pulse,
        core_target_link_speed, dbg_operational_seen, dbg_link_loss_seen,
        dbg_link_loss_pipe, os_malformed, os_link_number, os_lane_number,
        os_training_control, os_tx_complete, os_eq_control, os_eq_data,
        phy_rate_state, speed_state, gen3_eq_active, gen3_eq_phase,
        eq_busy, eq_done, eq_result, dbg_eq_operation_state,
        dbg_eq_phase_ts_count, dbg_eq_phase_done, dbg_eq_phase_failed,
        dbg_eq_tx_control, dbg_eq_tx_data, dbg_eq_phase2_internal};
endmodule

`default_nettype wire
