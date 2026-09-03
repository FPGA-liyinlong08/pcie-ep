`timescale 1ps/1ps
`default_nettype none

// Xilinx generated XDMA x1 Endpoint connected to the Synopsys SVT Root Port.
// The endpoint and all of its GT/PCIe logic are kept from the official example
// design; only the serial lane is replaced at the board boundary by SVT.
`define PCIESVC_MEM_PATH test_top.global_shadow0.shadow_mem0
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

    wire [3:0] vip_txp;
    wire [3:0] vip_txn;
    wire ep_rxp = vip_txp[0];
    wire ep_rxn = vip_txn[0];
    wire [0:0] ep_txp;
    wire [0:0] ep_txn;
    // While the SVT device is held in reset the encrypted Xilinx GT may drive
    // X on its serial TX pins.  Clamp only that reset interval to a defined
    // electrical-idle pair so the SVT serdes never samples X; after reset the
    // official serial lane is connected without alteration.  (The historical
    // pl-proxy Null-object-access crash was not caused by these pins: its
    // root cause was the VMM program missing from the simv because VCS did
    // not pick it up as a top -- see run_xdma_x1_svt.sh.)
    wire golden_rxp0 = vip_reset ? 1'b0 : ep_txp[0];
    wire golden_rxn0 = vip_reset ? 1'b1 : ep_txn[0];

    initial begin
        refclk_p = 1'b0;
        // Let the VMM program construct its environment before the encrypted
        // GT model starts producing serial/PIPE callbacks.  Without this
        // delta-time guard the official GT can emit an X startup beat while
        // svt_pcie_pl_proxy's callback client is still null.
        #1_000;
        forever #REF_CLK_HALF_CYCLE refclk_p = ~refclk_p;
    end

    initial begin
        ep_perst_n = 1'b0;
        vip_reset = 1'b1;
        reset_epoch_count = 0;
        global_random_seed = 0;
        repeat (PERST_HOLD_CYCLES) @(posedge refclk_p);
        ep_perst_n = 1'b1;
        $display("XDMA_X1_SVT_EP_PERST_RELEASE time_ps=%0t", $time);
        repeat (RP_RELEASE_DELAY_CYCLES) @(posedge refclk_p);
        vip_reset = 1'b0;
        reset_epoch_count = 1;
        $display("XDMA_X1_SVT_RP_RESET_RELEASE time_ps=%0t", $time);
    end

    // This is the unmodified wrapper generated with the Xilinx XDMA example
    // design.  It instantiates xdma_x1, the GT Wizard model and xdma_app.
    xilinx_dma_pcie_ep #(
        .PL_LINK_CAP_MAX_LINK_WIDTH(1),
        .PL_LINK_CAP_MAX_LINK_SPEED(4),
        .C_DATA_WIDTH(64)
    ) EP (
        .sys_clk_p(refclk_p),
        .sys_clk_n(refclk_n),
        .sys_rst_n(ep_perst_n),
        .pci_exp_txp(ep_txp),
        .pci_exp_txn(ep_txn),
        .pci_exp_rxp(ep_rxp),
        .pci_exp_rxn(ep_rxn)
    );

    // O-2018.09 has no native x1 8G wrapper.  x4 is the smallest 8G model;
    // lanes 1..3 remain electrically quiet and only lane 0 is connected.
    svt_pcie_device_group_serdes_x4_8g_hdl #(
        .DISPLAY_NAME("root0."),
        .PCIE_SPEC_VER(3.0)
    ) root0 (
        .reset(vip_reset),
        .clkreq_n(clkreq_n),
        .rx_datap_0(golden_rxp0),
        .rx_datan_0(golden_rxn0),
        .rx_datap_1(1'b0),
        .rx_datan_1(1'b0),
        .rx_datap_2(1'b0),
        .rx_datan_2(1'b0),
        .rx_datap_3(1'b0),
        .rx_datan_3(1'b0),
        .tx_datap_0(vip_txp[0]),
        .tx_datan_0(vip_txn[0]),
        .tx_datap_1(vip_txp[1]),
        .tx_datan_1(vip_txn[1]),
        .tx_datap_2(vip_txp[2]),
        .tx_datan_2(vip_txn[2]),
        .tx_datap_3(vip_txp[3]),
        .tx_datan_3(vip_txn[3])
    );

    // The SVT VMM transaction/configuration agents use this fixed shadow
    // hierarchy for configuration-space and memory bookkeeping.
    pciesvc_global_shadow #(.DISPLAY_NAME("global_shadow0.")) global_shadow0();

    // Keep the Golden probe at the official core's PIPE boundary.  The
    // generated PCIe wrapper packs the lane-0 transmit PIPE fields in
    // pipe_tx_0_sigs (see xdma_x1_pcie3_ip_pcie3_uscale_core_top.v):
    // data[31:0], elec_idle[34], data_valid[35], start_block[36],
    // sync_header[38:37].  This is the exact shape used by the K15 probe.
    wire [83:0] xdma_pipe_tx0 =
        EP.xdma_x1_i.inst.pcie3_ip_i.inst.pipe_tx_0_sigs;
    wire [5:0] xdma_ltssm = EP.xdma_x1_i.inst.pcie3_ip_i.cfg_ltssm_state;
    wire [2:0] xdma_rate = EP.xdma_x1_i.inst.pcie3_ip_i.cfg_current_speed;
    wire [31:0] xdma_txdata = xdma_pipe_tx0[31:0];
    wire xdma_tx_electrical_idle = xdma_pipe_tx0[34];
    wire xdma_txdata_valid = xdma_pipe_tx0[35];
    wire xdma_txstart_block = xdma_pipe_tx0[36];
    wire [1:0] xdma_txsync_header = xdma_pipe_tx0[38:37];
    integer xdma_forensics_count;
    integer xdma_forensics_skp_count;
    integer xdma_forensics_error_count;

    // Startup probe: two fixed samples of the serial pins and the SVT
    // decoder's PIPE result while the environment is still in reset.
    initial begin
        #4_000;
        $display("XDMA_SVT_STARTUP_PROBE t_ps=%0t reset=%b ep_perst_n=%b raw_tx=%b%b rx_pcs=%08h valid=%b data_valid=%b start=%b sh=%b status=%h ei=%h",
                 $time, vip_reset, ep_perst_n, ep_txp[0], ep_txn[0],
                 root0.port0.pcs0_rx_data, root0.port0.pcs0_rx_valid,
                 root0.port0.pcs0_rx_data_valid,
                 root0.port0.pcs0_rx_start_block,
                 root0.port0.pcs0_rx_sync_header,
                 root0.port0.pcs0_rx_status, root0.port0.pcs0_rx_ei_code);
        #1_000;
        $display("XDMA_SVT_STARTUP_PROBE t_ps=%0t reset=%b ep_perst_n=%b raw_tx=%b%b rx_pcs=%08h valid=%b data_valid=%b start=%b sh=%b status=%h ei=%h",
                 $time, vip_reset, ep_perst_n, ep_txp[0], ep_txn[0],
                 root0.port0.pcs0_rx_data, root0.port0.pcs0_rx_valid,
                 root0.port0.pcs0_rx_data_valid,
                 root0.port0.pcs0_rx_start_block,
                 root0.port0.pcs0_rx_sync_header,
                 root0.port0.pcs0_rx_status, root0.port0.pcs0_rx_ei_code);
    end

    initial begin
        xdma_forensics_count = 0;
        xdma_forensics_skp_count = 0;
        xdma_forensics_error_count = 0;
    end

    // One machine-readable record per Gen3 PIPE cycle.  Keep the SVT-side
    // fields in the same record so the two environments can be diffed by
    // cycle without interpreting transaction/DLLP logs.
    // cfg_current_speed uses the Xilinx PG194 encoding: 3'b001 = Gen1,
    // 3'b010 = Gen2, 3'b100 = Gen3 (verified live: 3'b100 in 8GT/s L0).
    always @(posedge root0.port0.pipe_clk) begin
        if ($test$plusargs("PHY_FORENSICS") && !vip_reset &&
            (xdma_rate == 3'd4) && (xdma_forensics_count < 20000)) begin
            #1;
            if (root0.port0.pcs0_rx_start_block)
                xdma_forensics_skp_count = xdma_forensics_skp_count + 1;
            if ((root0.port0.pcs0_rx_sync_header == 2'b11) ||
                (root0.port0.pcs0_rx_status != 0) ||
                (root0.port0.pcs0_rx_ei_code != 0))
                xdma_forensics_error_count = xdma_forensics_error_count + 1;
            $display("PHY_FORENSICS side=XDMA t_ps=%0t ltssm=%02h rate=%0d txdata=%08h txdata_valid=%0d txstart_block=%0d txsync_header=%02h tx_electrical_idle=%0d rxdata=%08h rxdata_valid=%0d rxstart_block=%0d rxsync_header=%02h rxstatus=%0h rx_electrical_idle=%08h",
                     $time, xdma_ltssm, xdma_rate, xdma_txdata,
                     xdma_txdata_valid, xdma_txstart_block, xdma_txsync_header,
                     xdma_tx_electrical_idle, root0.port0.pcs0_rx_data,
                     root0.port0.pcs0_rx_data_valid,
                     root0.port0.pcs0_rx_start_block,
                     root0.port0.pcs0_rx_sync_header,
                     root0.port0.pcs0_rx_status,
                     root0.port0.pcs0_rx_ei_code);
            xdma_forensics_count = xdma_forensics_count + 1;
        end
    end

    final begin
        $display("XDMA_SVT_FORENSICS_SUMMARY records=%0d start_blocks=%0d errors=%0d",
                 xdma_forensics_count, xdma_forensics_skp_count,
                 xdma_forensics_error_count);
    end

    initial begin
        if ($test$plusargs("dump_all")) begin
`ifdef VCS
            $vcdplusfile("xdma_x1_svt.vpd");
            $vcdpluson;
            $vcdplusglitchon;
            $vcdplusflush;
`endif
        end
    end
endmodule

`default_nettype wire
