`timescale 1ns/1ps
`default_nettype none

// K13生产接线层：把K12-A/B/C/D控制器组合成一个可关闭的PHY控制单元。
// K13_ENABLE=0时，所有控制输出保持K11 Gen1安全值；启用后才接受Retrain。
//
// K13 PHY Rate-Change 架构（2026-08-19 重构）：
//   1. pcie_recovery_speed_ctrl 不再直接驱动 phy_rate / phy_txelecidle，
//      也不消费 raw phy_phystatus。
//   2. 通过 rate_req_valid/target 发出 semantic 请求，
//      等 rate_req_ready → rate_op_done/failed。
//   3. pcie_phy_rate_contract 是 raw phy_rate / force_txelecidle 的唯一 owner。
//   4. production_ctrl 输出 phy_rate_cmd（来自 contract），
//      phy_txelecidle 是 ltssm stuff OR contract.force_txelecidle OR EQ stuff。
module pcie_k13_production_ctrl #(
    parameter integer K13_ENABLE = 0,
    parameter integer K13_RXEQ_BOOTSTRAP = 1,
    // 250 MHz PIPE下分别为4 ms；行为仿真继续通过参数覆盖缩短。
    parameter integer SPEED_TIMEOUT_CYCLES = 1_000_000,
    parameter integer EQ_TIMEOUT_CYCLES    = 1_000_000,
    // Gen1 release gap (Golden stimulus 是 10us @ 250 MHz = 2500 cycles)
    // 仿真默认缩短
    parameter integer GEN1_RELEASE_GAP_CYCLES = 2500
) (
    input wire       core_clk,
    input wire       core_rst_n,
    input wire       phy_clk,
    input wire       phy_rst_n,
    input wire       link_up,
    input wire       reinitialize_gen1,
    input wire       ltssm_speed_ready,
    input wire       retrain_pulse,
    input wire [1:0] target_speed,
    input wire       partner_retrain_valid,
    input wire [1:0] partner_target_speed,
    input wire       phy_phystatus,
    input wire       phy_cdr_lost,
    input wire       phy_txeq_done,
    input wire       phy_rxeq_adapt_done,
    input wire       phy_rxeq_done,
    input wire       ts_valid,
    input wire       ts_complete,
    input wire       ts_is_ts1,
    input wire       ts_is_ts2,
    input wire [2:0] ts_lane,
    input wire [7:0] ts_link,
    input wire [1:0] ts_rate,
    input wire       ts_eq_request,
    input wire [2:0] expected_lane,
    input wire [7:0] expected_link,

    // PHY command (来自 contract) 与 protocol 状态
    output wire [1:0] phy_rate_cmd,        // 替换原 phy_rate：去 wrapper
    output wire [1:0] active_rate,         // 来自 contract：去 LTSSM active_phy_rate
    output wire       phy_txelecidle,      // OR-arbitrated
    output wire [1:0] phy_txeq_ctrl,
    output wire [3:0] phy_txeq_preset,
    output wire [5:0] phy_txeq_coeff,
    output wire [1:0] phy_rxeq_ctrl,
    output wire [3:0] phy_rxeq_txpreset,
    output wire       traffic_quiesce,
    output wire       recovery_active,
    output wire       recovery_speed_done,
    output wire [1:0] negotiated_speed,
    output wire [2:0] speed_state,

    // EQ / TS / 故障 sticky
    output wire       eq_active,
    output wire       eq_done,
    output wire       eq_failed,
    output wire [2:0] eq_phase,
    output wire       ts_accept,
    output wire       ts_reject,
    output wire       cdr_loss_sticky,
    output wire       speed_timeout_sticky,
    output wire       fallback_sticky,
    output wire       illegal_ts_sticky,

    // Rate Contract 调试
    output wire [3:0] rate_contract_state,
    output wire       rate_contract_busy,
    output wire       rate_contract_done,
    output wire       rate_contract_failed,
    output wire       rate_contract_illegal
);
    wire mailbox_busy, mailbox_valid, mailbox_accept;
    wire [1:0] mailbox_target;
    wire speed_retrain_accept;
    wire retrain_request_valid = mailbox_valid || partner_retrain_valid;
    wire [1:0] retrain_request_target = mailbox_valid ? mailbox_target :
                                                        partner_target_speed;
    wire speed_timeout, peer_reject, illegal_speed, speed_cdr_loss;
    wire speed_fallback;
    wire ts_malformed, ts_illegal_rate, ts_lane_link_mismatch;
    wire eq_start_accept, eq_illegal_param, eq_phase_timeout;

    // 内部 TS 仲裁（来自 u_ts_guard 的输出，仅在 K13 enabled branch 驱动）
    wire       ts_accept_w;
    wire       ts_reject_w;

    // Recovery speed controller → contract 的 semantic handshake
    wire       speed_rate_req_valid;
    wire [1:0] speed_rate_req_target;
    wire       speed_fallback_req;
    wire       speed_recovery_active;
    wire [2:0] speed_state_w;
    wire [1:0] speed_negotiated;
    wire       speed_traffic_quiesce;

    // Contract → PHY / 调试
    wire [3:0] contract_state;
    wire [1:0] contract_active_rate;
    wire [1:0] contract_phy_rate_cmd;
    wire       contract_force_txelecidle;
    wire       contract_rate_req_ready;
    wire       contract_rate_busy;
    wire       contract_rate_done;
    wire       contract_rate_failed;
    wire       contract_illegal_target_sticky;
    // A TS accepted before PhyStatus completion belongs to the old
    // Recovery.RcvrCfg exchange and must not close the new speed operation.
    wire       post_rate_peer_speed_ok = ts_accept_w &&
                                         (speed_state_w == 3'd4) &&
                                         !contract_rate_done;

    wire [1:0] eq_phy_txeq_ctrl;
    wire [3:0] eq_phy_txeq_preset;
    wire [5:0] eq_phy_txeq_coeff;
    wire [1:0] eq_phy_rxeq_ctrl;
    wire [3:0] eq_phy_rxeq_txpreset;
    wire eq_done_w, eq_failed_w;
    reg eq_start_q;
    reg pre_rate_txeq_active;
    reg pre_rate_txeq_ready;
    reg post_rate_rxeq_active;
    reg post_rate_rxeq_ready;
    reg post_rate_rxeq_failed;
    reg [31:0] post_rate_rxeq_timeout_count;
    reg [1:0] active_target;
    // The mailbox request and active_target cross the acceptance edge at
    // different NBA boundaries.  Include the live request while it is
    // present; otherwise the first Recovery.Speed cycle can be interpreted
    // as a non-Gen3 transition and bypass the mandatory pre-rate TXEQ window.
    wire gen3_target_active = (active_target == 2'b10) ||
                              (retrain_request_valid &&
                               (retrain_request_target == 2'b10));
    wire speed_boundary_ready = ltssm_speed_ready &&
                                (!gen3_target_active ||
                                 pre_rate_txeq_ready);
    wire rxeq_bootstrap_ready = (K13_RXEQ_BOOTSTRAP == 0) ? 1'b1 :
                                 post_rate_rxeq_ready;
    localparam integer RXEQ_BOOTSTRAP_TIMEOUT =
        (EQ_TIMEOUT_CYCLES < 1) ? 1 : EQ_TIMEOUT_CYCLES;
    wire rxeq_bootstrap_timeout_expired =
        post_rate_rxeq_timeout_count >= (RXEQ_BOOTSTRAP_TIMEOUT - 1);

    generate if (K13_ENABLE != 0) begin : g_k13_enabled
        pcie_retrain_cdc_mailbox u_mailbox (
            .s_clk(core_clk), .s_rst_n(core_rst_n),
            .s_retrain_pulse(retrain_pulse), .s_target_speed(target_speed),
            .s_busy(mailbox_busy), .s_overflow_sticky(),
            .d_clk(phy_clk), .d_rst_n(phy_rst_n),
            .d_retrain_valid(mailbox_valid), .d_target_speed(mailbox_target),
            .d_retrain_accept(mailbox_accept)
        );

        assign mailbox_accept = speed_retrain_accept && mailbox_valid;

        // 固定本次Recovery的目标速率。mailbox_target只在mailbox事务期间有效，
        // partner请求也只有一拍，后续TS guard、Preset和EQ都必须使用锁存值。
        always @(posedge phy_clk or negedge phy_rst_n) begin
            if (!phy_rst_n)
                active_target <= 2'b00;
            else if (speed_retrain_accept)
                active_target <= retrain_request_target;
        end

        pcie_recovery_ts_guard u_ts_guard (
            .clk(phy_clk), .rst_n(phy_rst_n),
            .ts_valid(ts_valid), .ts_complete(ts_complete),
            .ts_is_ts1(ts_is_ts1), .ts_is_ts2(ts_is_ts2),
            .ts_lane(ts_lane), .ts_link(ts_link), .ts_rate(ts_rate),
            .expected_rate(retrain_request_valid ? retrain_request_target :
                                                   active_target),
            .ts_eq_request(ts_eq_request), .expected_lane(expected_lane),
            .expected_link(expected_link), .ts_accept(ts_accept_w),
            .ts_reject(ts_reject_w), .malformed_sticky(ts_malformed),
            .illegal_rate_sticky(ts_illegal_rate),
            .lane_link_mismatch_sticky(ts_lane_link_mismatch)
        );

        pcie_recovery_speed_ctrl #(
            .SPEED_TIMEOUT_CYCLES(SPEED_TIMEOUT_CYCLES)
        ) u_speed (
            .clk(phy_clk), .rst_n(phy_rst_n), .link_up(link_up),
            .reinitialize_gen1(reinitialize_gen1),
            .retrain_valid(retrain_request_valid),
            .retrain_target_speed(retrain_request_target),
            .ltssm_speed_ready(speed_boundary_ready),
            // semantic request → contract（contract 在 RC_RDY2_STABLE
            //  唯一拉高 rate_req_ready 作为 back-pressure）
            .rate_req_valid(speed_rate_req_valid),
            .rate_req_target(speed_rate_req_target),
            .fallback_req(speed_fallback_req),
            .rate_req_ready(contract_rate_req_ready),
            // contract → speed completion
            .rate_op_done(contract_rate_done),
            .rate_op_failed(contract_rate_failed),
            .active_rate(contract_active_rate),
            // 内部诊断
            .retrain_accept(speed_retrain_accept),
            .phy_cdr_lost(phy_cdr_lost),
            .peer_speed_ok(post_rate_peer_speed_ok),
            .peer_speed_reject(ts_reject_w),
            .state(speed_state_w),
            // 协议层状态
            .traffic_quiesce(speed_traffic_quiesce),
            .recovery_active(speed_recovery_active),
            .negotiated_speed(speed_negotiated),
            // sticky
            .speed_timeout_sticky(speed_timeout),
            .peer_reject_sticky(peer_reject),
            .illegal_speed_sticky(illegal_speed),
            .cdr_loss_sticky(speed_cdr_loss),
            .fallback_taken_sticky(speed_fallback)
        );

        // ------------------------------------------------------------------
        // Rate Contract 实例：唯一 raw phy_rate / force_txelecidle owner
        // ------------------------------------------------------------------
        pcie_phy_rate_contract #(
            .RATE_TIMEOUT_CYCLES(SPEED_TIMEOUT_CYCLES),
            .GEN1_RELEASE_GAP_CYCLES(GEN1_RELEASE_GAP_CYCLES)
        ) u_rate_contract (
            .clk(phy_clk), .rst_n(phy_rst_n),
            .link_ready(link_up),
            .reinitialize_gen1(reinitialize_gen1),
            .rate_req_valid(speed_rate_req_valid),
            .rate_req_target(speed_rate_req_target),
            .fallback_req(speed_fallback_req),
            .rate_req_ready(contract_rate_req_ready),
            .phy_phystatus(phy_phystatus),
            .phy_rate_cmd(contract_phy_rate_cmd),
            .force_txelecidle(contract_force_txelecidle),
            .active_rate(contract_active_rate),
            .rate_busy(contract_rate_busy),
            .rate_done(contract_rate_done),
            .rate_failed(contract_rate_failed),
            .dbg_state(contract_state),
            .phystatus_seen(), .timeout_sticky(),
            .illegal_target_sticky(contract_illegal_target_sticky)
        );

        // PG239 requires the initial Gen3 transmitter preset to be applied
        // while TxElecIdle is asserted and before changing PIPE Rate.  Keep
        // the speed controller at the Recovery.Speed boundary until the
        // real PHY acknowledges TXEQ_DONE.
        always @(posedge phy_clk or negedge phy_rst_n) begin
            if (!phy_rst_n) begin
                pre_rate_txeq_active <= 1'b0;
                pre_rate_txeq_ready <= 1'b0;
            end else begin
                if ((speed_state_w == 3'd0) ||
                    (!gen3_target_active && !retrain_request_valid)) begin
                    pre_rate_txeq_active <= 1'b0;
                    pre_rate_txeq_ready <= 1'b0;
                end else if ((speed_state_w == 3'd1) &&
                             ltssm_speed_ready &&
                             gen3_target_active &&
                             !pre_rate_txeq_ready &&
                             !pre_rate_txeq_active) begin
                    pre_rate_txeq_active <= 1'b1;
                end else if (pre_rate_txeq_active && phy_txeq_done) begin
                    pre_rate_txeq_active <= 1'b0;
                    pre_rate_txeq_ready <= 1'b1;
                end
            end
        end

        // Break the Gen3 receive bootstrap deadlock: TS fields cannot start
        // protocol equalization until the RX PCS emits blocks, while the RX
        // PCS needs its first DFE adaptation after the rate change.  Start
        // adaptation as soon as PhyStatus completes the Gen3 switch.
        always @(posedge phy_clk or negedge phy_rst_n) begin
            if (!phy_rst_n) begin
                post_rate_rxeq_active <= 1'b0;
                post_rate_rxeq_ready <= 1'b0;
                post_rate_rxeq_failed <= 1'b0;
                post_rate_rxeq_timeout_count <= 32'd0;
            end else begin
                if ((speed_state_w == 3'd0) ||
                    (active_target != 2'b10)) begin
                    post_rate_rxeq_active <= 1'b0;
                    post_rate_rxeq_ready <= 1'b0;
                    post_rate_rxeq_failed <= 1'b0;
                    post_rate_rxeq_timeout_count <= 32'd0;
                end else if ((K13_RXEQ_BOOTSTRAP != 0) &&
                             (speed_state_w == 3'd4) &&
                             !post_rate_rxeq_ready &&
                             !post_rate_rxeq_active) begin
                    post_rate_rxeq_active <= 1'b1;
                    post_rate_rxeq_timeout_count <= 32'd0;
                end else if ((K13_RXEQ_BOOTSTRAP != 0) &&
                             post_rate_rxeq_active && phy_rxeq_done &&
                             phy_rxeq_adapt_done) begin
                    post_rate_rxeq_active <= 1'b0;
                    post_rate_rxeq_ready <= 1'b1;
                    post_rate_rxeq_timeout_count <= 32'd0;
                end else if ((K13_RXEQ_BOOTSTRAP != 0) &&
                             post_rate_rxeq_active && phy_rxeq_done) begin
                    // PG239's done indication without adaptation is a
                    // failed bootstrap, not a successful RXEQ phase.  Stop
                    // driving the command and let the speed controller take
                    // its normal CDR-loss/fallback path.
                    post_rate_rxeq_active <= 1'b0;
                    post_rate_rxeq_failed <= 1'b1;
                    post_rate_rxeq_timeout_count <= 32'd0;
                end else if ((K13_RXEQ_BOOTSTRAP != 0) &&
                             post_rate_rxeq_active &&
                             rxeq_bootstrap_timeout_expired) begin
                    post_rate_rxeq_active <= 1'b0;
                    post_rate_rxeq_failed <= 1'b1;
                    post_rate_rxeq_timeout_count <= 32'd0;
                end else if ((K13_RXEQ_BOOTSTRAP != 0) &&
                             post_rate_rxeq_active) begin
                    post_rate_rxeq_timeout_count <=
                        post_rate_rxeq_timeout_count + 1'b1;
                end
            end
        end

        always @(posedge phy_clk or negedge phy_rst_n) begin
            if (!phy_rst_n)
                eq_start_q <= 1'b0;
            else begin
                eq_start_q <= 1'b0;
                if ((speed_state_w == 3'd4) && (active_target == 2'b10) &&
                    rxeq_bootstrap_ready && ts_accept_w &&
                    !eq_active && !eq_done && !eq_failed)
                    eq_start_q <= 1'b1;
            end
        end

        pcie_equalization_ctrl #(
            .EQ_TIMEOUT_CYCLES(EQ_TIMEOUT_CYCLES)
        ) u_eq (
            .clk(phy_clk), .rst_n(phy_rst_n && !speed_cdr_loss),
            .eq_start(eq_start_q), .target_speed(active_target),
            .tx_preset(4'd4), .tx_coeff(6'd12), .tx_coeff_valid(1'b1),
            .rx_txpreset(4'd5), .rx_preset_valid(1'b1),
            .phy_txeq_done(phy_txeq_done),
            .phy_rxeq_adapt_done(phy_rxeq_adapt_done),
            .phy_rxeq_done(phy_rxeq_done),
            .eq_start_accept(eq_start_accept), .eq_active(eq_active),
            .eq_done(eq_done_w), .eq_failed(eq_failed_w), .phase(eq_phase),
            .phy_txeq_ctrl(eq_phy_txeq_ctrl),
            .phy_txeq_preset(eq_phy_txeq_preset),
            .phy_txeq_coeff(eq_phy_txeq_coeff),
            .phy_rxeq_ctrl(eq_phy_rxeq_ctrl),
            .phy_rxeq_txpreset(eq_phy_rxeq_txpreset),
            .illegal_param_sticky(eq_illegal_param),
            .phase_timeout_sticky(eq_phase_timeout)
        );
    end else begin : g_k13_disabled
        assign mailbox_busy = 1'b0;
        assign mailbox_valid = 1'b0;
        assign mailbox_accept = 1'b0;
        assign mailbox_target = 2'b00;
        assign speed_retrain_accept = 1'b0;
        assign active_target = 2'b00;
        assign speed_rate_req_valid = 1'b0;
        assign speed_rate_req_target = 2'b00;
        assign speed_fallback_req = 1'b0;
        assign speed_recovery_active = 1'b0;
        assign speed_state_w = 3'd0;
        assign speed_negotiated = 2'b00;
        assign speed_traffic_quiesce = 1'b0;
        assign contract_state = 4'h0;
        assign contract_active_rate = 2'b00;
        assign contract_phy_rate_cmd = 2'b00;
        assign contract_rate_req_ready = 1'b0;
        assign contract_rate_busy = 1'b0;
        assign contract_rate_done = 1'b0;
        assign contract_rate_failed = 1'b0;
        assign contract_illegal_target_sticky = 1'b0;
        assign ts_accept_w = 1'b0;
        assign ts_reject_w = 1'b0;
        assign ts_malformed = 1'b0;
        assign ts_illegal_rate = 1'b0;
        assign ts_lane_link_mismatch = 1'b0;
        assign speed_timeout = 1'b0;
        assign peer_reject = 1'b0;
        assign illegal_speed = 1'b0;
        assign speed_cdr_loss = 1'b0;
        assign speed_fallback = 1'b0;
        assign pre_rate_txeq_active = 1'b0;
        assign pre_rate_txeq_ready = 1'b0;
        assign post_rate_rxeq_active = 1'b0;
        assign post_rate_rxeq_ready = 1'b0;
        assign post_rate_rxeq_failed = 1'b0;
        assign post_rate_rxeq_timeout_count = 32'd0;
        assign eq_start_q = 1'b0;
        assign eq_start_accept = 1'b0;
        assign eq_active = 1'b0;
        assign eq_done_w = 1'b0;
        assign eq_failed_w = 1'b0;
        assign eq_phase = 3'd7;
        assign eq_phy_txeq_ctrl = 2'b00;
        assign eq_phy_txeq_preset = 4'd0;
        assign eq_phy_txeq_coeff = 6'd0;
        assign eq_phy_rxeq_ctrl = 2'b00;
        assign eq_phy_rxeq_txpreset = 4'd0;
        assign eq_illegal_param = 1'b0;
        assign eq_phase_timeout = 1'b0;
    end endgenerate

    // A done-only RXEQ bootstrap failure must expose the safe Gen1 rate even
    // if the speed sub-controller has not yet consumed the sticky fault.
    // 在新架构下，phy_rate_cmd 由 contract 拥有；
    // 这里的 post_rate_rxeq_failed 不能再直接覆盖 phy_rate_cmd，
    // 只能通过强制把 active_target 锁回 Gen1（等 speed ctrl 触发 fallback）。
    assign phy_rate_cmd = contract_phy_rate_cmd;
    assign active_rate  = contract_active_rate;

    assign eq_done = eq_done_w;
    assign eq_failed = eq_failed_w || post_rate_rxeq_failed;
    // pre_rate_txeq_ready is asserted one clock before u_speed can observe
    // speed_boundary_ready.  Keep the electrical-idle window closed during
    // that NBA hand-off; otherwise ST_QUIESCE creates a one-PCLK hole.
    //
    // 新增 OR：
    //   - contract force_txelecidle：contract 任何 transition 状态都强制 TXEI
    //   - speed_traffic_quiesce：speed ctrl 在 RATE_REQUEST 期间 contract
    //     还在 RC_RDY2_STABLE (force=0)，必须由 speed_ctrl 侧的 recovery
    //     意图补上 TXEI，避免 RX 端在 rate change 前看到非 TXEI 字符
    //   - pre_rate_txeq_active / (Gen3 && state==1 && pre_rate_txeq_ready)：
    //     pre-EQ + QUIESCE 期间的传统窗口
    // traffic_quiesce is a packet-flow policy and is asserted already in
    // Recovery.RcvrCfg so the LTSSM can own the TS exchange.  Do not map that
    // level directly to TXEI or the endpoint hides its TS2 from the partner.
    assign phy_txelecidle = pre_rate_txeq_active ||
                            (speed_traffic_quiesce &&
                             (speed_state_w >= 3'd2)) ||
                            ((active_target == 2'b10) &&
                             (speed_state_w == 3'd1) &&
                             pre_rate_txeq_ready) ||
                            contract_force_txelecidle;
    assign phy_txeq_ctrl = pre_rate_txeq_active ? 2'b01 :
                                                    eq_phy_txeq_ctrl;
    assign phy_txeq_preset = pre_rate_txeq_active ? 4'd4 :
                                                      eq_phy_txeq_preset;
    assign phy_txeq_coeff = pre_rate_txeq_active ? 6'd0 :
                                                     eq_phy_txeq_coeff;
    assign phy_rxeq_ctrl = post_rate_rxeq_active ? 2'b10 :
                                                       eq_phy_rxeq_ctrl;
    assign phy_rxeq_txpreset = post_rate_rxeq_active ? 4'd5 :
                                                           eq_phy_rxeq_txpreset;
    // recovery_active 包含 contract_busy：physical 切速期间 LTSSM 必须停在 Recovery.Speed
    assign traffic_quiesce = speed_traffic_quiesce || eq_active ||
                             pre_rate_txeq_active || post_rate_rxeq_active ||
                             contract_rate_busy;
    assign recovery_active = speed_recovery_active || eq_active ||
                             pre_rate_txeq_active || post_rate_rxeq_active ||
                             contract_rate_busy;
    // recovery_speed_done：speed_state 进入 ST_RECOVERY_IDLE (3'd4) 或
    // ST_FALLBACK_IDLE (3'd7) 即表示物理切速完成、等对端 TS / link stable
    assign recovery_speed_done = (speed_state_w == 3'd4) ||
                                 (speed_state_w == 3'd7);
    assign negotiated_speed = post_rate_rxeq_failed ? 2'b00 : speed_negotiated;
    assign speed_state = speed_state_w;
    assign ts_accept = ts_accept_w;
    assign ts_reject = ts_reject_w;
    assign cdr_loss_sticky = speed_cdr_loss;
    assign speed_timeout_sticky = speed_timeout;
    assign fallback_sticky = speed_fallback || post_rate_rxeq_failed;
    assign illegal_ts_sticky = ts_malformed || ts_illegal_rate ||
                                ts_lane_link_mismatch;

    // Rate Contract 调试透传
    assign rate_contract_state   = contract_state;
    assign rate_contract_busy    = contract_rate_busy;
    assign rate_contract_done    = contract_rate_done;
    assign rate_contract_failed  = contract_rate_failed;
    assign rate_contract_illegal = contract_illegal_target_sticky;

`ifndef SYNTHESIS
    // Lightweight simulation assertion for the Recovery.Speed boundary.  The
    // Python directed test also checks this externally, but keeping the
    // invariant beside the mux catches regressions in any simulator or top.
    reg txelecidle_window_q;
    always @(posedge phy_clk or negedge phy_rst_n) begin
        if (!phy_rst_n) begin
            txelecidle_window_q <= 1'b0;
        end else begin
            if (txelecidle_window_q && !phy_txelecidle && !phy_phystatus)
                $error("K13 Recovery.Speed TXELECIDLE gap before PhyStatus");
            if (phy_phystatus)
                txelecidle_window_q <= 1'b0;
            else if ((active_target == 2'b10) &&
                     (pre_rate_txeq_active || (speed_state_w == 3'd2)))
                txelecidle_window_q <= 1'b1;
            else if ((active_target != 2'b10) || (speed_state_w == 3'd0))
                txelecidle_window_q <= 1'b0;
        end
    end
`endif
endmodule

`default_nettype wire
