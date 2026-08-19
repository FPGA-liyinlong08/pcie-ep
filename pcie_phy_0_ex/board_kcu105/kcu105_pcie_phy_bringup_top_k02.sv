`timescale 1ns/1ps
`default_nettype none

// KCU105 Hardware Golden top variant for the 2x2 controller x PHY IP
// cell #3: the proven Xilinx phy_ctrl.v + phy_bringup_seq drive K02's
// pcie_phy_x1_gen3 XCI (8.0_GT/s, QPLL1, GTHE3_CHANNEL_X0Y7,
// Add-in_Card, tx_preset 4) instead of the baseline pcie_phy_0.
//
// The 2x2 cross: if this combination completes Gen1->Gen3 the way the
// baseline Golden image does, then K02's PHY IP and GT configuration are
// exonerated and the failure of the K02 FSM build must be in the
// K02-side controller, not the IP.
module kcu105_pcie_phy_bringup_top_k02 #(
    parameter integer SEQ_CLK_HZ = 250_000_000,
    parameter integer WAIT_AFTER_READY_NS = 10_000,
    parameter integer WAIT_AFTER_GEN1_ON_NS = 5_000,
    parameter integer GEN1_HOLD_NS = 50_000,
    parameter integer WAIT_AFTER_GEN1_OFF_NS = 10_000,
    parameter integer GEN3_HOLD_NS = 80_000
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

    wire        phy_coreclk;
    wire        phy_userclk;
    wire        phy_mcapclk;
    wire        phy_pclk;
    wire        pipe_rst_n;
    wire        core_rst_n;
    wire        phy_phystatus;
    wire        phy_phystatus_rst;
    wire [2:0]  phy_rxstatus;

    (* mark_debug = "true" *) wire [2:0] phy_rate;
    (* mark_debug = "true" *) wire [1:0] phy_powerdown;
    (* mark_debug = "true" *) wire [1:0] phy_txeq_ctrl;
    (* mark_debug = "true" *) wire [3:0] phy_txeq_preset;
    (* mark_debug = "true" *) wire [7:0] debug_state;
    (* mark_debug = "true" *) wire       as_mac_in_detect;
    (* mark_debug = "true" *) wire       as_cdr_hold_req;
    (* mark_debug = "true" *) wire       phy_phystatus_debug;
    (* mark_debug = "true" *) wire       phy_phystatus_rst_debug;

    (* mark_debug = "true" *) wire       tx_elec_idle;
    (* mark_debug = "true" *) wire       phy_ready_en;
    (* mark_debug = "true" *) wire       gen1_en;
    (* mark_debug = "true" *) wire       gen2_en;
    (* mark_debug = "true" *) wire       gen3_en;
    (* mark_debug = "true" *) wire       gen4_en;
    (* mark_debug = "true" *) wire [3:0] seq_state;
    (* mark_debug = "true" *) wire       gen3_request;

    assign phy_phystatus_debug     = phy_phystatus;
    assign phy_phystatus_rst_debug = phy_phystatus_rst;

    phy_bringup_seq #(
        .SEQ_CLK_HZ                  (SEQ_CLK_HZ),
        .WAIT_AFTER_READY_NS         (WAIT_AFTER_READY_NS),
        .WAIT_AFTER_GEN1_ON_NS       (WAIT_AFTER_GEN1_ON_NS),
        .GEN1_HOLD_NS                (GEN1_HOLD_NS),
        .WAIT_AFTER_GEN1_OFF_NS      (WAIT_AFTER_GEN1_OFF_NS),
        .GEN3_HOLD_NS                (GEN3_HOLD_NS)
    ) u_phy_bringup_seq (
        .clk                    (phy_pclk),
        .rst                    (!pcie_perst_n),
        .phy_status_ready       (!phy_phystatus_rst),
        .phy_ctrl_debug_state   (debug_state),
        .tx_elec_idle           (tx_elec_idle),
        .phy_ready_en           (phy_ready_en),
        .gen1_en                (gen1_en),
        .gen2_en                (gen2_en),
        .gen3_en                (gen3_en),
        .gen4_en                (gen4_en),
        .seq_state              (seq_state),
        .gen3_request           (gen3_request)
    );

    kcu105_pcie_phy_wrapper_k02 u_phy_wrapper (
        .pcie_refclk_p          (pcie_refclk_p),
        .pcie_refclk_n          (pcie_refclk_n),
        .pcie_perst_n           (pcie_perst_n),
        .pcie_rxp               (pcie_rxp),
        .pcie_rxn               (pcie_rxn),
        .pcie_txp               (pcie_txp),
        .pcie_txn               (pcie_txn),
        .tx_elec_idle           (tx_elec_idle),
        .phy_ready_en           (phy_ready_en),
        .gen1_en                (gen1_en),
        .gen2_en                (gen2_en),
        .gen3_en                (gen3_en),
        .gen4_en                (gen4_en),
        .phy_coreclk            (phy_coreclk),
        .phy_userclk            (phy_userclk),
        .phy_mcapclk            (phy_mcapclk),
        .phy_pclk               (phy_pclk),
        .pipe_rst_n             (pipe_rst_n),
        .core_rst_n             (core_rst_n),
        .phy_rate               (phy_rate),
        .phy_powerdown          (phy_powerdown),
        .phy_txeq_ctrl          (phy_txeq_ctrl),
        .phy_txeq_preset        (phy_txeq_preset),
        .phy_txeq_coeff         (),
        .phy_rxstatus           (phy_rxstatus),
        .phy_phystatus          (phy_phystatus),
        .phy_phystatus_rst      (phy_phystatus_rst),
        .phy_txeq_done          (),
        .debug_state             (debug_state),
        .as_mac_in_detect       (as_mac_in_detect),
        .as_cdr_hold_req        (as_cdr_hold_req)
    );

    assign led[0] = pipe_rst_n;
    assign led[1] = !phy_phystatus_rst;
    assign led[2] = (debug_state == 8'h04);
    assign led[3] = gen1_en;
    assign led[4] = gen3_en;
    assign led[5] = gen3_request;
    assign led[6] = as_cdr_hold_req;
    assign led[7] = core_rst_n;

endmodule

`default_nettype wire
