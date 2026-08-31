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
            if ((DUT.phy_active_rate == 2'b10) && DUT.phy_phystatus)
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
            (rx_pipe_debug_count < 512) &&
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
