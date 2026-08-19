`timescale 1ns/1ps
`default_nettype none

// KCU105 hardware wrapper variant that drives the Xilinx pcie_phy IP with
// the same K02-issued pcie_phy_x1_gen3 XCI (K02's own configuration:
// 8.0_GT/s, QPLL1, GTHE3_CHANNEL_X0Y7, Add-in_Card, tx_preset 4, ...).
//
// Everything else - phy_ctrl.v, phy_bringup_seq, refclk/reset, the six
// bring-up inputs, the phy_ctrl outputs - is byte-identical to the
// baseline pcie_phy_0_ex Hardware Golden wrapper.  This is the cell #3 of
// the 2x2 controller x PHY IP cross: the proven Golden controller must
// drive K02's PHY IP.  If this still produces debug_state==0x04 and a
// QPLL1 1->0->1 transition, K02's PHY IP/GT configuration is exonerated.
module kcu105_pcie_phy_wrapper_k02 #(
    parameter integer RESET_SYNC_STAGES = 4
) (
    input  wire        pcie_refclk_p,
    input  wire        pcie_refclk_n,
    input  wire        pcie_perst_n,
    input  wire        pcie_rxp,
    input  wire        pcie_rxn,
    output wire        pcie_txp,
    output wire        pcie_txn,

    input  wire        tx_elec_idle,
    input  wire        phy_ready_en,
    input  wire        gen1_en,
    input  wire        gen2_en,
    input  wire        gen3_en,
    input  wire        gen4_en,

    output wire        phy_coreclk,
    output wire        phy_userclk,
    output wire        phy_mcapclk,
    output wire        phy_pclk,
    output wire        pipe_rst_n,
    output wire        core_rst_n,

    output wire [2:0]  phy_rate,
    output wire [1:0]  phy_powerdown,
    output wire [1:0]  phy_txeq_ctrl,
    output wire [3:0]  phy_txeq_preset,
    output wire [5:0]  phy_txeq_coeff,
    output wire [2:0]  phy_rxstatus,
    output wire        phy_phystatus,
    output wire        phy_phystatus_rst,
    output wire        phy_txeq_done,
    output wire [7:0]  debug_state,
    output wire        as_mac_in_detect,
    output wire        as_cdr_hold_req
);

    wire phy_gtrefclk;
    wire phy_refclk;
    wire phy_rst_n;

    // Original Xilinx phy_ctrl data and command outputs.
    wire [31:0] ctrl_txdata;
    wire [1:0]  ctrl_txdatak;
    wire        ctrl_txdata_valid;
    wire        ctrl_txstart_block;
    wire [1:0]  ctrl_txsync_header;
    wire        ctrl_txdetectrx;
    wire        ctrl_txelecidle;
    wire        ctrl_txcompliance;
    wire        ctrl_rxpolarity;
    wire [2:0]  ctrl_phy_rate;
    wire [1:0]  ctrl_phy_powerdown;
    wire [2:0]  ctrl_txmargin;
    wire        ctrl_txswing;
    wire        ctrl_txdeemph;
    wire [1:0]  ctrl_txeq_ctrl;
    wire [3:0]  ctrl_txeq_preset;
    wire [5:0]  ctrl_txeq_coeff;
    wire [1:0]  ctrl_rxeq_ctrl;
    wire [3:0]  ctrl_rxeq_txpreset;

    // PHY status/data returned to the original Xilinx phy_ctrl.
    wire [31:0] phy_rxdata;
    wire [1:0]  phy_rxdatak;
    wire        phy_rxdata_valid;
    wire        phy_rxstart_block;
    wire [1:0]  phy_rxsync_header;
    wire        phy_rxvalid;
    wire        phy_rxelecidle;
    wire [5:0]  phy_txeq_fs;
    wire [5:0]  phy_txeq_lf;
    wire [17:0] phy_txeq_new_coeff;
    wire        phy_rxeq_preset_sel;
    wire [17:0] phy_rxeq_new_txcoeff;
    wire        phy_rxeq_adapt_done;
    wire        phy_rxeq_done;

    kcu105_refclk_reset #(
        .RESET_SYNC_STAGES (RESET_SYNC_STAGES)
    ) u_refclk_reset (
        .pcie_refclk_p     (pcie_refclk_p),
        .pcie_refclk_n     (pcie_refclk_n),
        .pcie_perst_n      (pcie_perst_n),
        .phy_pclk          (phy_pclk),
        .phy_coreclk       (phy_coreclk),
        .phy_phystatus_rst (phy_phystatus_rst),
        .phy_gtrefclk      (phy_gtrefclk),
        .phy_refclk        (phy_refclk),
        .phy_rst_n         (phy_rst_n),
        .pipe_rst_n        (pipe_rst_n),
        .core_rst_n        (core_rst_n)
    );

    // Unmodified Xilinx reference controller from imports/.
    phy_ctrl #(
        .PHY_LANE (1),
        .DW       (32),
        .TCQ      (1)
    ) u_phy_ctrl (
        .CLK                 (phy_pclk),
        .RST                 (phy_phystatus_rst),
        .PHY_TXDATA          (ctrl_txdata),
        .PHY_TXDATAK         (ctrl_txdatak),
        .PHY_TXDATA_VALID    (ctrl_txdata_valid),
        .PHY_TXSTART_BLOCK   (ctrl_txstart_block),
        .PHY_TXSYNC_HEADER   (ctrl_txsync_header),
        .PHY_RXDATA          (phy_rxdata),
        .PHY_RXDATAK         (phy_rxdatak),
        .PHY_RXDATA_VALID    (phy_rxdata_valid),
        .PHY_RXSTART_BLOCK   (phy_rxstart_block),
        .PHY_RXSYNC_HEADER   (phy_rxsync_header),
        .PHY_TXDETECTRX      (ctrl_txdetectrx),
        .PHY_TXELECIDLE      (ctrl_txelecidle),
        .PHY_TXCOMPLIANCE    (ctrl_txcompliance),
        .PHY_RXPOLARITY      (ctrl_rxpolarity),
        .PHY_POWERDOWN       (ctrl_phy_powerdown),
        .PHY_RATE            (ctrl_phy_rate),
        .PHY_RXVALID         (phy_rxvalid),
        .PHY_PHYSTATUS       (phy_phystatus),
        .PHY_PHYSTATUS_RST   (phy_phystatus_rst),
        .PHY_RXELECIDLE      (phy_rxelecidle),
        .PHY_RXSTATUS        (phy_rxstatus),
        .PHY_TXMARGIN        (ctrl_txmargin),
        .PHY_TXSWING         (ctrl_txswing),
        .PHY_TXDEEMPH        (ctrl_txdeemph),
        .PHY_TXEQ_CTRL       (ctrl_txeq_ctrl),
        .PHY_TXEQ_PRESET     (ctrl_txeq_preset),
        .PHY_TXEQ_COEFF      (ctrl_txeq_coeff),
        .PHY_RXEQ_CTRL       (ctrl_rxeq_ctrl),
        .PHY_RXEQ_TXPRESET   (ctrl_rxeq_txpreset),
        .PHY_TXEQ_FS         (phy_txeq_fs),
        .PHY_TXEQ_LF         (phy_txeq_lf),
        .PHY_TXEQ_NEW_COEFF  (phy_txeq_new_coeff),
        .PHY_TXEQ_DONE       (phy_txeq_done),
        .PHY_RXEQ_PRESET_SEL (phy_rxeq_preset_sel),
        .PHY_RXEQ_NEW_TXCOEFF(phy_rxeq_new_txcoeff),
        .PHY_RXEQ_ADAPT_DONE (phy_rxeq_adapt_done),
        .PHY_RXEQ_DONE       (phy_rxeq_done),
        .as_mac_in_detect    (as_mac_in_detect),
        .as_cdr_hold_req     (as_cdr_hold_req),
        .debug_state         (debug_state),
        .tx_elec_idle        (tx_elec_idle),
        .phy_ready_en        (phy_ready_en),
        .gen1_en             (gen1_en),
        .gen2_en             (gen2_en),
        .gen3_en             (gen3_en),
        .gen4_en             (gen4_en)
    );

    // K02's pcie_phy_x1_gen3 XCI is the same xilinx.com:ip:pcie_phy:1.0 IP
    // as the baseline pcie_phy_0 but generated with K02's settings
    // (8.0_GT/s, QPLL1, Add-in_Card, tx_preset 4, etc.).  All commands
    // still enter from the unmodified Xilinx phy_ctrl.
    pcie_phy_x1_gen3 u_pcie_phy (
        .phy_refclk          (phy_refclk),
        .phy_gtrefclk        (phy_gtrefclk),
        .phy_rst_n           (phy_rst_n),
        .phy_txdata          (ctrl_txdata),
        .phy_txdatak         (ctrl_txdatak),
        .phy_txdata_valid    (ctrl_txdata_valid),
        .phy_txstart_block   (ctrl_txstart_block),
        .phy_txsync_header   (ctrl_txsync_header),
        .phy_rxp             (pcie_rxp),
        .phy_rxn             (pcie_rxn),
        .phy_txp             (pcie_txp),
        .phy_txn             (pcie_txn),
        .phy_txdetectrx      (ctrl_txdetectrx),
        .phy_txelecidle      (ctrl_txelecidle),
        .phy_txcompliance    (ctrl_txcompliance),
        .phy_rxpolarity      (ctrl_rxpolarity),
        .phy_powerdown       (ctrl_phy_powerdown),
        .phy_rate            (ctrl_phy_rate[1:0]),
        .phy_txmargin        (ctrl_txmargin),
        .phy_txswing         (ctrl_txswing),
        .phy_txdeemph        (ctrl_txdeemph),
        .phy_txeq_ctrl       (ctrl_txeq_ctrl),
        .phy_txeq_preset     (ctrl_txeq_preset),
        .phy_txeq_coeff      (ctrl_txeq_coeff),
        .phy_rxeq_ctrl       (ctrl_rxeq_ctrl),
        .phy_rxeq_txpreset   (ctrl_rxeq_txpreset),
        .as_mac_in_detect    (as_mac_in_detect),
        .as_cdr_hold_req     (as_cdr_hold_req),
        .phy_coreclk         (phy_coreclk),
        .phy_userclk         (phy_userclk),
        .phy_mcapclk         (phy_mcapclk),
        .phy_pclk            (phy_pclk),
        .phy_rxdata          (phy_rxdata),
        .phy_rxdatak         (phy_rxdatak),
        .phy_rxdata_valid    (phy_rxdata_valid),
        .phy_rxstart_block   (phy_rxstart_block),
        .phy_rxsync_header   (phy_rxsync_header),
        .phy_rxvalid         (phy_rxvalid),
        .phy_phystatus       (phy_phystatus),
        .phy_phystatus_rst   (phy_phystatus_rst),
        .phy_rxelecidle      (phy_rxelecidle),
        .phy_rxstatus        (phy_rxstatus),
        .phy_txeq_fs         (phy_txeq_fs),
        .phy_txeq_lf         (phy_txeq_lf),
        .phy_txeq_new_coeff  (phy_txeq_new_coeff),
        .phy_txeq_done       (phy_txeq_done),
        .phy_rxeq_preset_sel (phy_rxeq_preset_sel),
        .phy_rxeq_new_txcoeff(phy_rxeq_new_txcoeff),
        .phy_rxeq_adapt_done (phy_rxeq_adapt_done),
        .phy_rxeq_done       (phy_rxeq_done)
    );

    assign phy_rate        = ctrl_phy_rate;
    assign phy_powerdown   = ctrl_phy_powerdown;
    assign phy_txeq_ctrl   = ctrl_txeq_ctrl;
    assign phy_txeq_preset = ctrl_txeq_preset;
    assign phy_txeq_coeff  = ctrl_txeq_coeff;

endmodule

`default_nettype wire
