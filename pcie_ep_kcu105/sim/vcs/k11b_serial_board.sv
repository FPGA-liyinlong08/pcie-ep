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
    integer ep_rx_sample_count;
    integer os_event_count;
    integer rp_rx_sample_count;
    integer ep_idle_sample_count;
    integer rp_idle_sample_count;
    reg seen_detect;
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

    initial begin
        last_ep_state = 6'h3f;
        stable_count = 0;
        ep_rx_sample_count = 0;
        os_event_count = 0;
        rp_rx_sample_count = 0;
        ep_idle_sample_count = 0;
        rp_idle_sample_count = 0;
        seen_detect = 1'b0;
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

    // 仅用于 K11-B bring-up：观察 Root Port PIPE Lane 0 实际收到的 TS2。
    always @(posedge RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_clk) begin
        if (($time > 138700000) && (rp_rx_sample_count < 48) &&
            RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_valid[0] &&
            !RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_elec_idle[0]) begin
            $display("K11B_RP_RX time_ps=%0t state=%0h data=%08x datak=%02b",
                     $time, RP.cfg_ltssm_state,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_data[31:0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_char_is_k[1:0]);
            rp_rx_sample_count = rp_rx_sample_count + 1;
        end
        if (($time > 140900000) && (rp_idle_sample_count < 96) &&
            RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_valid[0] &&
            !RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_elec_idle[0]) begin
            $display("K11B_RP_IDLE_RX time_ps=%0t state=%0h ep_state=%0d ep_tx=%04x ep_k=%02b rx=%04x rx_k=%02b",
                     $time, RP.cfg_ltssm_state, EP.DUT.ltssm_state,
                     EP.DUT.phy_txdata[15:0], EP.DUT.phy_txdatak,
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_data[15:0],
                     RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.pipe_rx_char_is_k[1:0]);
            rp_idle_sample_count = rp_idle_sample_count + 1;
        end
    end

    always @(posedge EP.DUT.phy_pclk) begin
        if (!EP.DUT.pipe_rst_n) begin
            last_ep_state <= 6'h3f;
            stable_count <= 0;
        end else begin
            if ((EP.DUT.ltssm_state == 6'd9) &&
                (ep_idle_sample_count < 64)) begin
                $display("K11B_EP_IDLE_RX time_ps=%0t raw_valid=%0d raw_data=%04x raw_k=%02b aligned_valid=%0d aligned_data=%04x aligned_k=%02b idle_pulse=%0d",
                         $time, EP.DUT.phy_rxvalid, EP.DUT.phy_rxdata[15:0],
                         EP.DUT.phy_rxdatak,
                         EP.DUT.u_ltssm_mac.rx_aligned_valid,
                         EP.DUT.u_ltssm_mac.rx_aligned_data,
                         EP.DUT.u_ltssm_mac.rx_aligned_datak,
                         EP.DUT.u_ltssm_mac.os_idle_pair_valid);
                ep_idle_sample_count <= ep_idle_sample_count + 1;
            end
            if ((EP.DUT.u_ltssm_mac.os_ts1_valid ||
                 EP.DUT.u_ltssm_mac.os_ts2_valid) && ($time > 50000000) &&
                (os_event_count < 96)) begin
                $display("K11B_EP_OS time_ps=%0t state=%0d kind=%0d link=%02x link_pad=%0d lane=%02x lane_pad=%0d nfts=%02x rate=%02x ctl=%02x count=%0d",
                         $time, EP.DUT.ltssm_state,
                         EP.DUT.u_ltssm_mac.os_ts2_valid ? 2 : 1,
                         EP.DUT.u_ltssm_mac.os_link_number,
                         EP.DUT.u_ltssm_mac.os_link_is_pad,
                         EP.DUT.u_ltssm_mac.os_lane_number,
                         EP.DUT.u_ltssm_mac.os_lane_is_pad,
                         EP.DUT.u_ltssm_mac.os_n_fts,
                         EP.DUT.u_ltssm_mac.os_rate_id,
                         EP.DUT.u_ltssm_mac.os_training_control,
                         EP.DUT.rx_ts_count);
                os_event_count <= os_event_count + 1;
            end
            if (EP.DUT.phy_rxvalid && !EP.DUT.phy_rxelecidle &&
                (ep_rx_sample_count < 32)) begin
                $display("K11B_EP_RX time_ps=%0t data=%08x datak=%02b elecidle=%0d status=%0d",
                         $time, EP.DUT.phy_rxdata, EP.DUT.phy_rxdatak,
                         EP.DUT.phy_rxelecidle, EP.DUT.phy_rxstatus);
                ep_rx_sample_count <= ep_rx_sample_count + 1;
            end
            if (EP.DUT.ltssm_state != last_ep_state) begin
                $display("K11B_EP_STATE time_ps=%0t state=%0d rx_ts=%0d train_err=%0d timeout=%0d",
                         $time, EP.DUT.ltssm_state, EP.DUT.rx_ts_count,
                         EP.DUT.training_error_count, EP.DUT.timeout_count);
                last_ep_state <= EP.DUT.ltssm_state;
            end

            if (EP.DUT.ltssm_state <= 6'd1)
                seen_detect <= 1'b1;
            if ((EP.DUT.ltssm_state == 6'd2) || (EP.DUT.ltssm_state == 6'd3))
                seen_polling <= 1'b1;
            if ((EP.DUT.ltssm_state >= 6'd4) && (EP.DUT.ltssm_state <= 6'd9))
                seen_configuration <= 1'b1;

            if ((EP.DUT.link_up === 1'b1) && (RP.user_lnk_up === 1'b1))
                stable_count <= stable_count + 1;
            else
                stable_count <= 0;

            if (!disconnect_lane0 && (stable_count == STABLE_PCLK_CYCLES-1)) begin
                if (!seen_detect || !seen_polling || !seen_configuration) begin
                    $display("K11B_VCS_GEN1_L0_FAIL reason=missing_state_coverage detect=%0d polling=%0d config=%0d",
                             seen_detect, seen_polling, seen_configuration);
                    $fatal(1);
                end
                if ((EP.DUT.negotiated_width !== 3'd1) ||
                    (EP.DUT.negotiated_speed !== 2'b00)) begin
                    $display("K11B_VCS_GEN1_L0_FAIL reason=bad_negotiation width=%0d speed=%0d",
                             EP.DUT.negotiated_width, EP.DUT.negotiated_speed);
                    $fatal(1);
                end
                $display("K11B_VCS_GEN1_L0_PASS stable_pclk=%0d ep_state=%0d rp_link=%0d",
                         STABLE_PCLK_CYCLES, EP.DUT.ltssm_state, RP.user_lnk_up);
                $finish;
            end
        end
    end

    initial begin
        wait (sys_rst_n === 1'b1);
        if (disconnect_lane0) begin
            #500000000;
            if ((EP.DUT.link_up === 1'b1) || (RP.user_lnk_up === 1'b1)) begin
                $display("K11B_VCS_CHECKER_SELFTEST_FAIL reason=disconnected_link_up ep=%0d rp=%0d",
                         EP.DUT.link_up, RP.user_lnk_up);
                $fatal(1);
            end
            $display("K11B_VCS_CHECKER_SELFTEST_PASS ep_state=%0d rp_link=%0d timeout=%0d",
                     EP.DUT.ltssm_state, RP.user_lnk_up, EP.DUT.timeout_count);
            $finish;
        end else begin
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

    wire _unused_compat = &{1'b0, user_clk, m_axi_wvalid, m_axi_wready,
                            m_axi_wdata, m_axi_wstrb, usr_irq_req, usr_irq_ack};
endmodule

`default_nettype wire
