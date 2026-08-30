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

    reg seen_partner_accept;
    reg seen_gen3_rate;
    reg seen_qpll_lock;
    reg seen_gen3_phystatus;
    reg seen_timeout_fallback;
    reg seen_gen1_fallback_phystatus;

    integer recovery_rx_debug_count;
    reg [5:0] previous_ep_ltssm_state;
    wire qpll1lock =
        DUT.u_phy_wrapper.u_pcie_phy.inst.Uscale_gt.us_gt_phy_wrapper.gt_wizard.gtwizard_top_i.qpll1lock_out[0];

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
            $display("K14_GOLDEN_SVT_EP_PERST_RELEASE epoch=%0d time_ps=%0t",
                     reset_epoch_count, $time);
            repeat (RP_RELEASE_DELAY_CYCLES) @(posedge refclk_p);
            vip_reset = 1'b0;
            reset_epoch_count = reset_epoch_count + 1;
            $display("K14_GOLDEN_SVT_RP_RESET_RELEASE epoch=%0d time_ps=%0t",
                     reset_epoch_count - 1, $time);
        end
    endtask

    initial begin
        ep_perst_n = 1'b0;
        vip_reset = 1'b1;
        reset_epoch_count = 0;
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

    // O-2018.09 has no native x1 8G device-group wrapper.  Restrict the x4
    // wrapper to x1, connect lane 0 only, and hold all unused RX lanes quiet.
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

    // Keep this monitor in the independent SVT board: it compares what the
    // serial VIP transmits with what the K14 PIPE/OS detector actually sees.
    always @(posedge DUT.phy_pclk or negedge ep_perst_n) begin
        if (!ep_perst_n) begin
            recovery_rx_debug_count <= 0;
            previous_ep_ltssm_state <= 6'h3f;
        end else begin
            if (ep_ltssm_state != previous_ep_ltssm_state) begin
                $display("K14_GOLDEN_SVT_EP_STATE old=%0h new=%0h time_ps=%0t",
                         previous_ep_ltssm_state, ep_ltssm_state, $time);
                previous_ep_ltssm_state <= ep_ltssm_state;
            end
            if ((ep_ltssm_state == 6'd10) &&
                DUT.u_ltssm_mac.rx_raw_aligned_valid &&
                (DUT.u_ltssm_mac.rx_raw_aligned_datak != 2'b00) &&
                (recovery_rx_debug_count < 24)) begin
                $display("K14_GOLDEN_SVT_L0_RX_K data=%04h datak=%02b time_ps=%0t",
                         DUT.u_ltssm_mac.rx_raw_aligned_data,
                         DUT.u_ltssm_mac.rx_raw_aligned_datak, $time);
                recovery_rx_debug_count <= recovery_rx_debug_count + 1;
            end
            if (DUT.u_ltssm_mac.gen1_os_ts1_valid &&
                (ep_ltssm_state >= 6'd10) &&
                (ep_ltssm_state <= 6'd12))
                $display("K14_GOLDEN_SVT_EP_RX_TS1 state=%0h link=%02h lane=%02h rate=%02h ctrl=%02h time_ps=%0t",
                         ep_ltssm_state, DUT.u_ltssm_mac.gen1_os_link_number,
                         DUT.u_ltssm_mac.gen1_os_lane_number,
                         DUT.u_ltssm_mac.gen1_os_rate_id,
                         DUT.u_ltssm_mac.gen1_os_training_control, $time);
        end
    end

    always @(posedge DUT.phy_pclk or negedge ep_perst_n) begin
        if (!ep_perst_n) begin
            seen_partner_accept <= 1'b0;
            seen_gen3_rate <= 1'b0;
            seen_qpll_lock <= 1'b0;
            seen_gen3_phystatus <= 1'b0;
            seen_timeout_fallback <= 1'b0;
            seen_gen1_fallback_phystatus <= 1'b0;
        end else begin
            if (DUT.g_gen3_rate_change.partner_retrain_accept) begin
                if (!seen_partner_accept)
                    $display("K14_GOLDEN_SVT_PARTNER_ACCEPT epoch=%0d time_ps=%0t",
                             reset_epoch_count - 1, $time);
                seen_partner_accept <= 1'b1;
            end
            if (DUT.phy_active_rate == 2'b10) begin
                if (!seen_gen3_rate)
                    $display("K14_GOLDEN_SVT_GEN3_RATE epoch=%0d time_ps=%0t",
                             reset_epoch_count - 1, $time);
                seen_gen3_rate <= 1'b1;
            end
            if ((DUT.phy_active_rate == 2'b10) && qpll1lock)
                seen_qpll_lock <= 1'b1;
            if ((DUT.phy_active_rate == 2'b10) && DUT.phy_phystatus) begin
                if (!seen_gen3_phystatus)
                    $display("K14_GOLDEN_SVT_GEN3_PHYSTATUS epoch=%0d time_ps=%0t qpll=%0d",
                             reset_epoch_count - 1, $time, qpll1lock);
                seen_gen3_phystatus <= 1'b1;
            end
            if (DUT.g_gen3_rate_change.speed_timeout_sticky &&
                DUT.g_gen3_rate_change.speed_fallback_sticky)
                seen_timeout_fallback <= 1'b1;
            if (seen_timeout_fallback && (DUT.phy_active_rate == 2'b00) &&
                DUT.phy_phystatus)
                seen_gen1_fallback_phystatus <= 1'b1;
        end
    end

    task automatic display_diagnostics;
        begin
            $display("K14_GOLDEN_SVT_DIAG epoch=%0d ep_state=%0h link=%0d dll=%0d rate=%02b partner=%0d qpll=%0d phystatus=%0d timeout=%0d fallback=%0d gen1_phystatus=%0d",
                     reset_epoch_count - 1, ep_ltssm_state, ep_link_up,
                     ep_dll_active, DUT.phy_active_rate, seen_partner_accept,
                     seen_qpll_lock, seen_gen3_phystatus,
                     DUT.g_gen3_rate_change.speed_timeout_sticky,
                     DUT.g_gen3_rate_change.speed_fallback_sticky,
                     seen_gen1_fallback_phystatus);
        end
    endtask

    pciesvc_global_shadow #(.DISPLAY_NAME("global_shadow0.")) global_shadow0();
    pcie_svt_k14_golden_x1 pcie_svt_k14_golden_x1_tb();

    wire _unused = &{1'b0, vip_txp[3:1], vip_txn[3:1], ep_led,
                     ep_dll_fc_state, ep_negotiated_speed,
                     ep_negotiated_width, ep_captured_bdf, ep_bdf_valid,
                     ep_bar0_base, ep_memory_space_enable, ep_cdc_errors};
endmodule
