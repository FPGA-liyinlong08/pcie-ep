`define PCIESVC_MEM_PATH test_top.global_shadow0.shadow_mem0
`timescale 1ps/1ps

`define EXPERTIO_PCIESVC_GLOBAL_SHADOW_PATH test_top.global_shadow0
`define SVC_RANDOM_SEED_SCOPE test_top.global_random_seed

module test_top;
    localparam integer REF_CLK_HALF_CYCLE = 5_000;
    localparam integer PERST_HOLD_CYCLES = 10_000;
    localparam integer RP_RELEASE_DELAY_CYCLES = 10_000;

    reg refclk_p;
    wire refclk_n = ~refclk_p;
    reg ep_perst_n;
    reg vip_reset;
    wire clkreq_n;
    integer reset_epoch_count;
    int unsigned global_random_seed;

    wire [3:0] vip_txp, vip_txn;
    wire ep_rxp = vip_txp[0];
    wire ep_rxn = vip_txn[0];
    wire ep_txp, ep_txn;
    wire [7:0] ep_led;
    wire ep_link_up, ep_dll_active;
    wire [5:0] ep_ltssm_state;
    wire [1:0] ep_dll_fc_state, ep_negotiated_speed;
    wire [2:0] ep_negotiated_width;
    wire [15:0] ep_captured_bdf;
    wire ep_bdf_valid;
    wire [31:0] ep_bar0_base;
    wire ep_memory_space_enable;
    wire [7:0] ep_cdc_errors;

    reg seen_partner_accept, seen_gen3_rate, seen_gen3_phystatus;
    reg seen_timeout_fallback, seen_gen1_fallback_phystatus;
    reg seen_eq_phase0, seen_eq_phase1, seen_eq_phase2, seen_eq_phase3;
    reg seen_recovery_idle;
    integer rx_pipe_debug_count;
    integer tx_eieos_debug_count;

    // K15_L0FIX: the VIP detects "Invalid sync hdr 2'b11 -- block alignment
    // lost" within ~33ns of L0 up, then non-IDL token / framing error.
    // sh=11 is the classic 1-bit-slip signature ("01|10" read one bit late),
    // so capture the VIP RX and EP TX beats around the first Gen3 sh==11 to
    // see exactly what the wire carried and where alignment diverged.
    localparam SH11_RING = 96;
    // {status[1:0], ei_code[7:0], valid, data_valid, start, sh[1:0], data[31:0]}
    reg [46:0] sh11_vip_ring [0:SH11_RING-1];
    reg [35:0] sh11_ep_ring  [0:SH11_RING-1]; // {valid, start, sh[1:0], data[31:0]}
    integer sh11_vip_head, sh11_ep_head, sh11_j;
    reg sh11_triggered, sh11_ep_dump;
    integer sh11_ep_post, sh11_vip_post;
    reg [5:0] ep_ltssm_trace_last;
    // K15_L0FIX: the VIP sat in Recovery.Idle for its full 20us timeout
    // while the EP was already in L0 (267.07-286.97us) -- it never accepted
    // the EP's idle stream.  Re-arm both PIPE beat captures at the EP's
    // first Gen3 Recovery.Idle entry so the 0d->L0 handoff is covered.
    integer ep_tx_debug_count;
    reg recov_idle_cap_armed;
    // K15_L0FIX: mirror probe -- what the VIP transmits as seen by the EP's
    // ordered-set receiver.  The VIP sat silent in Recovery.Idle while the
    // EP's stream (TS2 -> EIEOS -> SDS -> idle) killed its receiver, so
    // record the block sequence the EP RX decodes from the VIP side.
    reg [2:0] ep_rxblk_last;
    reg [31:0] ep_rxblk_w0;
    integer ep_rxblk_trace_count;
    integer phy_forensics_count;
    integer phy_forensics_skp_count;
    integer phy_forensics_error_count;

    `include "svc_util_parms.v"

    initial begin
        refclk_p = 1'b0;
        forever #REF_CLK_HALF_CYCLE refclk_p = ~refclk_p;
    end

    task automatic apply_reset_epoch;
        begin
            vip_reset = 1'b1;
            ep_perst_n = 1'b0;
            repeat (PERST_HOLD_CYCLES) @(posedge refclk_p);
            ep_perst_n = 1'b1;
            $display("K15_SVT_EP_PERST_RELEASE epoch=%0d time_ps=%0t",
                     reset_epoch_count, $time);
            repeat (RP_RELEASE_DELAY_CYCLES) @(posedge refclk_p);
            vip_reset = 1'b0;
            reset_epoch_count = reset_epoch_count + 1;
            $display("K15_SVT_RP_RESET_RELEASE epoch=%0d time_ps=%0t",
                     reset_epoch_count - 1, $time);
        end
    endtask

    initial begin
        ep_perst_n = 1'b0;
        vip_reset = 1'b1;
        reset_epoch_count = 0;
        rx_pipe_debug_count = 0;
        tx_eieos_debug_count = 0;
        ep_tx_debug_count = 0;
        sh11_triggered = 1'b0;
        sh11_ep_dump = 1'b0;
        sh11_vip_head = 0;
        sh11_ep_head = 0;
        sh11_ep_post = 0;
        ep_rxblk_trace_count = 0;
        phy_forensics_count = 0;
        phy_forensics_skp_count = 0;
        phy_forensics_error_count = 0;
        ep_ltssm_trace_last = 6'h3f;
        global_random_seed = 0;
        apply_reset_epoch();
    end

    kcu105_pcie_ep_gen1_top #(
        .DETECT_QUIET_CYCLES(128),
        .DETECT_TIMEOUT_CYCLES(1_000_000),
        .TRAIN_TIMEOUT_CYCLES(2_000_000),
        .HOT_RESET_CYCLES(16_384),
        .K14_RATE_DEBUG(0),
        .GEN3_RATE_CHANGE_ENABLE(1),
        .GEN3_SPEED_TIMEOUT_CYCLES(16_384),
        .GEN3_AUTO_RETRAIN_CYCLES(0),
        .G9_WAIT_REMOTE_DETECT(0),
        .G9_WAIT_REMOTE_DETECT_CYCLES(65_536),
        .LTSSM_TX_RATE_ID(8'h0e)
    ) DUT (
        .pcie_refclk_p(refclk_p), .pcie_refclk_n(refclk_n),
        .pcie_perst_n(ep_perst_n), .pcie_rxp(ep_rxp), .pcie_rxn(ep_rxn),
        .pcie_txp(ep_txp), .pcie_txn(ep_txn), .led(ep_led),
        .link_up(ep_link_up), .dll_active(ep_dll_active),
        .ltssm_state(ep_ltssm_state), .dll_fc_state(ep_dll_fc_state),
        .negotiated_speed(ep_negotiated_speed),
        .negotiated_width(ep_negotiated_width),
        .captured_bdf(ep_captured_bdf), .bdf_valid(ep_bdf_valid),
        .bar0_base(ep_bar0_base), .memory_space_enable(ep_memory_space_enable),
        .cdc_errors(ep_cdc_errors)
    );

    // O-2018.09 has no native x1 8G device-group wrapper.  x4 is the
    // smallest 8G wrapper; the VMM config restricts it to x1.  Only lane 0
    // connects to the DUT and the other receive lanes see electrical silence.
    svt_pcie_device_group_serdes_x4_8g_hdl #(
        .DISPLAY_NAME("root0."), .PCIE_SPEC_VER(3.0)
    ) root0 (
        .reset(vip_reset), .clkreq_n(clkreq_n),
        .rx_datap_0(ep_txp), .rx_datan_0(ep_txn),
        .rx_datap_1(1'b0), .rx_datan_1(1'b0),
        .rx_datap_2(1'b0), .rx_datan_2(1'b0),
        .rx_datap_3(1'b0), .rx_datan_3(1'b0),
        .tx_datap_0(vip_txp[0]), .tx_datan_0(vip_txn[0]),
        .tx_datap_1(vip_txp[1]), .tx_datan_1(vip_txn[1]),
        .tx_datap_2(vip_txp[2]), .tx_datan_2(vip_txn[2]),
        .tx_datap_3(vip_txp[3]), .tx_datan_3(vip_txn[3])
    );

    always @(posedge DUT.phy_pclk or negedge ep_perst_n) begin
        if (!ep_perst_n) begin
            seen_partner_accept <= 1'b0;
            seen_gen3_rate <= 1'b0;
            seen_gen3_phystatus <= 1'b0;
            seen_timeout_fallback <= 1'b0;
            seen_gen1_fallback_phystatus <= 1'b0;
            seen_eq_phase0 <= 1'b0;
            seen_eq_phase1 <= 1'b0;
            seen_eq_phase2 <= 1'b0;
            seen_eq_phase3 <= 1'b0;
            seen_recovery_idle <= 1'b0;
        end else begin
            if (DUT.g_gen3_rate_change.partner_retrain_accept)
                seen_partner_accept <= 1'b1;
            if (DUT.phy_active_rate == 2'b10)
                seen_gen3_rate <= 1'b1;
            // The rate-change phystatus pulse can race the active_rate
            // update, and the Gen3 EQ handshake completes on the dedicated
            // rxeq/txeq done ports without further phystatus pulses -- so
            // also latch once the LTSSM is inside Recovery.Equalization,
            // which is only reachable after the PHY completed the rate
            // change handshake.
            if ((DUT.phy_active_rate == 2'b10) &&
                (DUT.phy_phystatus || DUT.u_ltssm_mac.eq_phase_valid))
                seen_gen3_phystatus <= 1'b1;
            if (DUT.g_gen3_rate_change.speed_timeout_sticky &&
                DUT.g_gen3_rate_change.speed_fallback_sticky)
                seen_timeout_fallback <= 1'b1;
            if (seen_timeout_fallback && (DUT.phy_active_rate == 2'b00) &&
                DUT.phy_phystatus)
                seen_gen1_fallback_phystatus <= 1'b1;
            case (ep_ltssm_state)
                6'h28: seen_eq_phase0 <= 1'b1;
                6'h29: seen_eq_phase1 <= 1'b1;
                6'h2a: seen_eq_phase2 <= 1'b1;
                6'h2b: seen_eq_phase3 <= 1'b1;
                6'h0d: seen_recovery_idle <= 1'b1;
                default: begin end
            endcase
        end
    end

    // Diagnostic-only monitor of the SVT Root Port PIPE receive output.  The
    // serial model may lock its CDR while still failing SDS/block alignment;
    // capture the first Gen3 beats to distinguish that case from a clean
    // EIEOS/SDS handoff.  This monitor has no effect on DUT behavior.
    always @(posedge DUT.phy_pclk) begin
        if (!vip_reset && (DUT.phy_active_rate == 2'b10) &&
            DUT.u_ltssm_mac.gen3_os_tx_eieos_active &&
            (tx_eieos_debug_count < 16)) begin
            #1;
            $display("K15_SVT_EP_TX_EIEOS n=%0d t_ps=%0t valid=%0d start=%0d sh=%02h data=%08h word=%0d",
                     tx_eieos_debug_count, $time,
                     DUT.phy_txdata_valid, DUT.phy_txstart_block,
                     DUT.phy_txsync_header, DUT.phy_txdata,
                     DUT.u_ltssm_mac.gen3_os_tx_word_index);
            tx_eieos_debug_count = tx_eieos_debug_count + 1;
        end
    end

    always @(posedge root0.port0.pipe_clk) begin
        if (!vip_reset && (DUT.phy_active_rate == 2'b10) &&
            (rx_pipe_debug_count < 8192) &&
            ((rx_pipe_debug_count < 96) ||
             root0.port0.pcs0_rx_valid || root0.port0.pcs0_rx_data_valid ||
             root0.port0.pcs0_rx_start_block ||
             (root0.port0.pcs0_rx_sync_header != 2'b00) ||
             (root0.port0.pcs0_rx_data != 32'd0) ||
             (root0.port0.pcs0_rx_ei_code != 32'd0) ||
             (root0.port0.pcs0_rx_status != 0))) begin
            #1;
            $display("K15_SVT_RP_PIPE_RX n=%0d t_ps=%0t valid=%0d data_valid=%0d start=%0d sh=%02h data=%08h ei=%08h status=%0h",
                     rx_pipe_debug_count, $time,
                     root0.port0.pcs0_rx_valid,
                     root0.port0.pcs0_rx_data_valid,
                     root0.port0.pcs0_rx_start_block,
                     root0.port0.pcs0_rx_sync_header,
                     root0.port0.pcs0_rx_data,
                     root0.port0.pcs0_rx_ei_code,
                     root0.port0.pcs0_rx_status);
            rx_pipe_debug_count = rx_pipe_debug_count + 1;
        end
    end

    // K15_SVT l0fix31k: 0d-handoff forensics.  The +-27-byte VIP/EP
    // descrambler phase offset at the first scrambled idle block requires
    // both sides' LFSR accounting to be visible.  Print (a) every EP os_tx
    // EIEOS completion (the only in-stream LFSR reset), (b) the
    // Recovery.Idle handoff moment with both sources' LFSR states, and
    // (c) the first SDS beat actually driven by the idle source.
    reg handoff_prev_owner;
    always @(posedge DUT.phy_pclk or negedge ep_perst_n) begin
        if (!ep_perst_n) begin
            handoff_prev_owner <= 1'b0;
        end else if (DUT.phy_active_rate == 2'b10) begin
            if (ep_ltssm_state >= 6'h0b &&
                ep_ltssm_state <= 6'h0d &&
                DUT.u_ltssm_mac.u_gen3_os_tx.stream_state == 2'd0 &&
                DUT.u_ltssm_mac.u_gen3_os_tx.word_index == 2'd3 &&
                DUT.u_ltssm_mac.gen3_os_tx_valid)
                $display("K15_SVT_EIEOS_RESET t_ps=%0t ltssm=%02h lfsr_next_tick=%06h",
                         $time, ep_ltssm_state,
                         DUT.u_ltssm_mac.u_gen3_os_tx.lfsr_state);
            if (DUT.u_ltssm_mac.gen3_idle_tx_owner &&
                !handoff_prev_owner)
                $display("K15_SVT_HANDOFF t_ps=%0t ltssm=%02h os_lfsr=%06h os_lfsr_after=%06h idle_lfsr=%06h",
                         $time, ep_ltssm_state,
                         DUT.u_ltssm_mac.u_gen3_os_tx.lfsr_state,
                         DUT.u_ltssm_mac.gen3_os_tx_lfsr_after_word,
                         DUT.u_ltssm_mac.u_gen3_idle_tx.lfsr_state);
            handoff_prev_owner <= DUT.u_ltssm_mac.gen3_idle_tx_owner;
        end else begin
            handoff_prev_owner <= 1'b0;
        end
    end

    // K15_L0FIX sh=11 capture: VIP RX history ring on pipe_clk.
    always @(posedge root0.port0.pipe_clk) begin
        if (vip_reset) begin
            sh11_triggered <= 1'b0;
            sh11_vip_head <= 0;
            sh11_vip_post <= 0;
        end else begin
            sh11_vip_ring[sh11_vip_head] <= {
                root0.port0.pcs0_rx_status[1:0],
                root0.port0.pcs0_rx_ei_code[7:0],
                root0.port0.pcs0_rx_valid,
                root0.port0.pcs0_rx_data_valid,
                root0.port0.pcs0_rx_start_block,
                root0.port0.pcs0_rx_sync_header,
                root0.port0.pcs0_rx_data};
            sh11_vip_head <= (sh11_vip_head == SH11_RING-1) ? 0 :
                             sh11_vip_head + 1;
            if (!sh11_triggered && (DUT.phy_active_rate == 2'b10) &&
                root0.port0.pcs0_rx_valid &&
                (root0.port0.pcs0_rx_sync_header == 2'b11)) begin
                sh11_triggered <= 1'b1;
                $display("K15_SVT_SH11_HIT t_ps=%0t", $time);
                $display("K15_SVT_SH11_NOW valid=%0d dv=%0d start=%0d sh=%02b data=%08h ei=%02h status=%0b",
                         root0.port0.pcs0_rx_valid,
                         root0.port0.pcs0_rx_data_valid,
                         root0.port0.pcs0_rx_start_block,
                         root0.port0.pcs0_rx_sync_header,
                         root0.port0.pcs0_rx_data,
                         root0.port0.pcs0_rx_ei_code[7:0],
                         root0.port0.pcs0_rx_status[1:0]);
                for (sh11_j = 0; sh11_j < SH11_RING; sh11_j = sh11_j + 1) begin
                    // oldest first; entry (head+1) is the oldest beat
                    $display("K15_SVT_SH11_PRE n=-%0d valid=%0d dv=%0d start=%0d sh=%02b data=%08h ei=%02h status=%0b",
                             SH11_RING - sh11_j,
                             sh11_vip_ring[(sh11_vip_head + sh11_j) % SH11_RING][36],
                             sh11_vip_ring[(sh11_vip_head + sh11_j) % SH11_RING][35],
                             sh11_vip_ring[(sh11_vip_head + sh11_j) % SH11_RING][34],
                             sh11_vip_ring[(sh11_vip_head + sh11_j) % SH11_RING][33:32],
                             sh11_vip_ring[(sh11_vip_head + sh11_j) % SH11_RING][31:0],
                             sh11_vip_ring[(sh11_vip_head + sh11_j) % SH11_RING][43:36],
                             sh11_vip_ring[(sh11_vip_head + sh11_j) % SH11_RING][45:44]);
                end
            end else if (sh11_triggered && (sh11_vip_post < SH11_RING) &&
                         (root0.port0.pcs0_rx_valid ||
                          root0.port0.pcs0_rx_data_valid)) begin
                $display("K15_SVT_SH11_POST valid=%0d dv=%0d start=%0d sh=%02b data=%08h ei=%02h status=%0b",
                         root0.port0.pcs0_rx_valid,
                         root0.port0.pcs0_rx_data_valid,
                         root0.port0.pcs0_rx_start_block,
                         root0.port0.pcs0_rx_sync_header,
                         root0.port0.pcs0_rx_data,
                         root0.port0.pcs0_rx_ei_code[7:0],
                         root0.port0.pcs0_rx_status[1:0]);
                sh11_vip_post <= sh11_vip_post + 1;
            end
        end
    end

    // K15_L0FIX sh=11 capture: EP TX history ring on phy_pclk, dumped one
    // sh11_triggered delay later (both clocks run at the same nominal rate).
    always @(posedge DUT.phy_pclk) begin
        if (vip_reset) begin
            sh11_ep_dump <= 1'b0;
            sh11_ep_head <= 0;
            sh11_ep_post <= 0;
        end else begin
            sh11_ep_ring[sh11_ep_head] <= {
                DUT.phy_txdata_valid,
                DUT.phy_txstart_block,
                DUT.phy_txsync_header,
                DUT.phy_txdata};
            sh11_ep_head <= (sh11_ep_head == SH11_RING-1) ? 0 :
                            sh11_ep_head + 1;
            if (sh11_triggered && !sh11_ep_dump) begin
                sh11_ep_dump <= 1'b1;
                for (sh11_j = 0; sh11_j < SH11_RING; sh11_j = sh11_j + 1) begin
                    $display("K15_SVT_SH11_EPPRE n=-%0d valid=%0d start=%0d sh=%02b data=%08h",
                             SH11_RING - sh11_j,
                             sh11_ep_ring[(sh11_ep_head + sh11_j) % SH11_RING][35],
                             sh11_ep_ring[(sh11_ep_head + sh11_j) % SH11_RING][34],
                             sh11_ep_ring[(sh11_ep_head + sh11_j) % SH11_RING][33:32],
                             sh11_ep_ring[(sh11_ep_head + sh11_j) % SH11_RING][31:0]);
                end
            end else if (sh11_ep_dump && (sh11_ep_post < SH11_RING)) begin
                $display("K15_SVT_SH11_EPPOST n=%0d valid=%0d start=%0d sh=%02b data=%08h",
                         sh11_ep_post,
                         DUT.phy_txdata_valid,
                         DUT.phy_txstart_block,
                         DUT.phy_txsync_header,
                         DUT.phy_txdata);
                sh11_ep_post <= sh11_ep_post + 1;
            end
        end
    end

    // K15_L0FIX: EP LTSSM trace once Gen3 is active (the interesting window
    // is post-speed-change; pre-Gen3 training transitions are noise).
    always @(posedge DUT.phy_pclk or negedge ep_perst_n) begin
        if (!ep_perst_n) begin
            ep_ltssm_trace_last <= 6'h3f;
        end else if ((ep_ltssm_state != ep_ltssm_trace_last) &&
                     seen_gen3_rate && (DUT.phy_active_rate == 2'b10)) begin
            $display("K15_SVT_EP_LTSSM t_ps=%0t state=%02h rate=%02b",
                     $time, ep_ltssm_state, DUT.phy_active_rate);
            ep_ltssm_trace_last <= ep_ltssm_state;
        end else if (ep_ltssm_state != ep_ltssm_trace_last) begin
            ep_ltssm_trace_last <= ep_ltssm_state;
        end
    end

    // Unified physical/data-stream evidence record.  This deliberately uses
    // the same field names and ordering as the XDMA Golden probe, allowing a
    // cycle-by-cycle diff at the first Gen3 L0/SKP/compensation divergence.
    // It is opt-in so normal K15 regressions retain their existing log volume.
    always @(posedge root0.port0.pipe_clk) begin
        if ($test$plusargs("PHY_FORENSICS") && !vip_reset &&
            (DUT.phy_active_rate == 2'b10) && (phy_forensics_count < 20000)) begin
            #1;
            if (root0.port0.pcs0_rx_start_block)
                phy_forensics_skp_count = phy_forensics_skp_count + 1;
            if ((root0.port0.pcs0_rx_sync_header == 2'b11) ||
                (root0.port0.pcs0_rx_status != 0) ||
                (root0.port0.pcs0_rx_ei_code != 0))
                phy_forensics_error_count = phy_forensics_error_count + 1;
            $display("PHY_FORENSICS side=K15 t_ps=%0t ltssm=%02h rate=%0d txdata=%08h txdata_valid=%0d txstart_block=%0d txsync_header=%02h tx_electrical_idle=%0d rxdata=%08h rxdata_valid=%0d rxstart_block=%0d rxsync_header=%02h rxstatus=%0h rx_electrical_idle=%0d",
                     $time, ep_ltssm_state,
                     (DUT.phy_active_rate == 2'b10) ? 3 :
                     ((DUT.phy_active_rate == 2'b01) ? 2 : 1),
                     DUT.phy_txdata, DUT.phy_txdata_valid,
                     DUT.phy_txstart_block, DUT.phy_txsync_header,
                     DUT.phy_txelecidle, root0.port0.pcs0_rx_data,
                     root0.port0.pcs0_rx_data_valid,
                     root0.port0.pcs0_rx_start_block,
                     root0.port0.pcs0_rx_sync_header,
                     root0.port0.pcs0_rx_status,
                     DUT.phy_rxelecidle);
            phy_forensics_count = phy_forensics_count + 1;
        end
    end

    final begin
        $display("K15_SVT_FORENSICS_SUMMARY records=%0d start_blocks=%0d errors=%0d",
                 phy_forensics_count, phy_forensics_skp_count,
                 phy_forensics_error_count);
    end

    // K15_L0FIX: re-arm the beat captures at the EP's first Gen3
    // Recovery.Idle entry.  The window then covers Recovery.Idle TX, the
    // SDS/L0 handoff and the first idle blocks as the VIP sees them.
    always @(posedge DUT.phy_pclk or negedge ep_perst_n) begin
        if (!ep_perst_n) begin
            recov_idle_cap_armed <= 1'b0;
        end else if (!recov_idle_cap_armed &&
                     (ep_ltssm_state == 6'h0d) &&
                     (DUT.phy_active_rate == 2'b10)) begin
            recov_idle_cap_armed <= 1'b1;
            $display("K15_SVT_CAP_REARM t_ps=%0t ep_state=0d", $time);
            rx_pipe_debug_count = 0;
            ep_tx_debug_count = 0;
        end
    end

    // K15_L0FIX: EP TX PIPE beat capture (mirrors the RP_PIPE_RX monitor).
    always @(posedge DUT.phy_pclk) begin
        if (!vip_reset && (DUT.phy_active_rate == 2'b10) &&
            (ep_tx_debug_count < 512) &&
            ((ep_tx_debug_count < 96) ||
             DUT.phy_txdata_valid || DUT.phy_txstart_block ||
             (DUT.phy_txsync_header != 2'b00))) begin
            #1;
            $display("K15_SVT_EP_TX_PIPE n=%0d t_ps=%0t valid=%0d start=%0d sh=%02b data=%08h",
                     ep_tx_debug_count, $time,
                     DUT.phy_txdata_valid, DUT.phy_txstart_block,
                     DUT.phy_txsync_header, DUT.phy_txdata);
            ep_tx_debug_count = ep_tx_debug_count + 1;
        end
    end

    // K15_L0FIX: EP RX block-kind trace (what the VIP transmits).  Gated to
    // non-L0 EP states and capped so the L0 idle stream cannot flood the log;
    // the VIP's L0 entry is observed while the EP is still in Recovery.Idle.
    always @(posedge DUT.phy_pclk) begin
        if (vip_reset) begin
            ep_rxblk_last <= 3'd0;
        end else if ((DUT.phy_active_rate == 2'b10) &&
                     (ep_ltssm_state != 6'h0a) &&
                     (ep_rxblk_trace_count < 2000)) begin
            if (DUT.u_ltssm_mac.u_gen3_os_rx.block_kind == 3'd0) begin
                ep_rxblk_last <= 3'd0;
            end else if (DUT.u_ltssm_mac.u_gen3_os_rx.block_kind !=
                         ep_rxblk_last) begin
                ep_rxblk_last <= DUT.u_ltssm_mac.u_gen3_os_rx.block_kind;
                ep_rxblk_w0 <= DUT.phy_rxdata;
                ep_rxblk_trace_count = ep_rxblk_trace_count + 1;
                $display("K15_SVT_EP_RXBLK t_ps=%0t kind=%0d w0=%08h valid=%0d status=%0b ep_state=%02h",
                         $time, DUT.u_ltssm_mac.u_gen3_os_rx.block_kind,
                         DUT.phy_rxdata, DUT.phy_rxvalid, DUT.phy_rxstatus,
                         ep_ltssm_state);
            end
        end
    end

    // l0fix30j: 0d exit-path debug.  The EP sits in Recovery.Idle despite
    // 11+ decoded VIP idle blocks; print every idle_valid pulse with the
    // exit inputs, plus a slow heartbeat exposing the os_rx internals
    // (parse_error / descrambler state) that decide whether idle_valid
    // can fire at all.
    reg [15:0] idle0d_pulse_cnt;
    always @(posedge DUT.phy_pclk) begin
        if (!vip_reset && (DUT.phy_active_rate == 2'b10) &&
            (ep_ltssm_state == 6'h0d)) begin
            idle0d_pulse_cnt <= idle0d_pulse_cnt + 1'b1;
            if (DUT.u_ltssm_mac.gen3_os_idle_valid)
                $display("K15_SVT_0D_IDLE t_ps=%0t n=%0d ts=%0d force=%b",
                         $time, idle0d_pulse_cnt, DUT.u_ltssm_mac.rx_ts_count,
                         DUT.u_ltssm_mac.force_recovery);
            else if (idle0d_pulse_cnt[9:0] == 0)
                $display("K15_SVT_0D_HEART t_ps=%0t n=%0d ts=%0d force=%b perr=%b idlev=%b kind=%0d dw=%08h",
                         $time, idle0d_pulse_cnt, DUT.u_ltssm_mac.rx_ts_count,
                         DUT.u_ltssm_mac.force_recovery,
                         DUT.u_ltssm_mac.u_gen3_os_rx.parse_error,
                         DUT.u_ltssm_mac.u_gen3_os_rx.idle_valid,
                         DUT.u_ltssm_mac.u_gen3_os_rx.block_kind,
                         DUT.u_ltssm_mac.u_gen3_os_rx.descrambled_data);
        end else begin
            idle0d_pulse_cnt <= 16'd0;
        end
    end

    task automatic display_diagnostics;
        begin
            $display("K15_SVT_DIAG epoch=%0d ep_state=%0h link=%0d dll=%0d negotiated=%02b active_rate=%02b partner=%0d phystatus=%0d phases=%0d%0d%0d%0d idle=%0d timeout=%0d fallback=%0d gen1_phystatus=%0d eq_failed=%0d",
                     reset_epoch_count - 1, ep_ltssm_state, ep_link_up,
                     ep_dll_active, ep_negotiated_speed, DUT.phy_active_rate,
                     seen_partner_accept, seen_gen3_phystatus,
                     seen_eq_phase0, seen_eq_phase1, seen_eq_phase2,
                     seen_eq_phase3, seen_recovery_idle,
                     DUT.g_gen3_rate_change.speed_timeout_sticky,
                     DUT.g_gen3_rate_change.speed_fallback_sticky,
                     seen_gen1_fallback_phystatus,
                     DUT.gen3_eq_failed);
        end
    endtask

    pciesvc_global_shadow #(.DISPLAY_NAME("global_shadow0.")) global_shadow0();
    pcie_svt_k15_x1 pcie_svt_k15_x1_tb();

`ifdef WAVES
    initial begin
        $vcdplusfile("k15_svt_x1.vpd");
        $vcdpluson;
        $vcdplusglitchon;
    end
`endif

    wire _unused = &{1'b0, vip_txp[3:1], vip_txn[3:1], ep_led,
                     ep_dll_fc_state, ep_negotiated_width, ep_captured_bdf,
                     ep_bdf_valid, ep_bar0_base, ep_memory_space_enable,
                     ep_cdc_errors};
endmodule
