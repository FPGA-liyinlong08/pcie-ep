`timescale 1ns/1ps
`default_nettype none

// K03 集成/上板顶层。DLL 尚未实现，Packet TX 输入固定为空，RX 仅观测。
module kcu105_pcie_gen1_top #(
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
    wire        phy_coreclk;
    wire        phy_userclk;
    wire        phy_mcapclk;
    wire        phy_pclk;
    wire        pipe_rst_n;
    wire        core_rst_n;
    wire [31:0] phy_rxdata;
    wire [1:0]  phy_rxdatak;
    wire        phy_rxdata_valid;
    wire        phy_rxstart_block;
    wire [1:0]  phy_rxsync_header;
    wire        phy_rxvalid;
    wire        phy_phystatus;
    wire        phy_phystatus_rst;
    wire        phy_rxelecidle;
    wire [2:0]  phy_rxstatus;
    wire [5:0]  phy_txeq_fs;
    wire [5:0]  phy_txeq_lf;
    wire [17:0] phy_txeq_new_coeff;
    wire        phy_txeq_done;
    wire        phy_rxeq_preset_sel;
    wire [17:0] phy_rxeq_new_txcoeff;
    wire        phy_rxeq_adapt_done;
    wire        phy_rxeq_done;

    wire [31:0] phy_txdata;
    wire [1:0]  phy_txdatak;
    wire        phy_txdata_valid;
    wire        phy_txstart_block;
    wire [1:0]  phy_txsync_header;
    wire        phy_txdetectrx;
    wire        phy_txelecidle;
    wire        phy_txcompliance;
    wire        phy_rxpolarity;
    wire [1:0]  phy_powerdown;
    wire [1:0]  phy_rate;
    wire [2:0]  phy_txmargin;
    wire        phy_txswing;
    wire        phy_txdeemph;
    wire [1:0]  phy_txeq_ctrl;
    wire [3:0]  phy_txeq_preset;
    wire [5:0]  phy_txeq_coeff;
    wire [1:0]  phy_rxeq_ctrl;
    wire [3:0]  phy_rxeq_txpreset;
    wire        as_mac_in_detect;
    wire        as_cdr_hold_req;

    (* mark_debug = "true" *) wire [5:0]  ltssm_state;
    (* mark_debug = "true" *) wire        link_up;
    (* mark_debug = "true" *) wire [7:0]  link_number;
    (* mark_debug = "true" *) wire [4:0]  rx_ts_count;
    (* mark_debug = "true" *) wire [31:0] training_error_count;
    (* mark_debug = "true" *) wire [31:0] timeout_count;
    (* mark_debug = "true" *) wire [31:0] frame_error_count;
    wire [2:0]  negotiated_width;
    wire [1:0]  negotiated_speed;
    wire        hot_reset_seen;
    wire        tx_pkt_ready;
    wire        rx_pkt_valid;
    wire [15:0] rx_pkt_data;
    wire [1:0]  rx_pkt_keep;
    wire        rx_pkt_sop;
    wire        rx_pkt_eop;
    wire        rx_pkt_is_dllp;
    wire [3:0]  rx_pkt_error;
    reg  [24:0] heartbeat_count;

    always @(posedge phy_pclk or negedge pipe_rst_n) begin
        if (!pipe_rst_n)
            heartbeat_count <= 25'd0;
        else
            heartbeat_count <= heartbeat_count + 1'b1;
    end

    assign led[0] = pipe_rst_n && !phy_phystatus_rst;
    assign led[1] = link_up;
    assign led[2] = phy_txdetectrx;
    assign led[3] = core_rst_n;
    assign led[4] = (ltssm_state == 6'd2) || (ltssm_state == 6'd3);
    assign led[5] = (ltssm_state >= 6'd4) && (ltssm_state <= 6'd9);
    assign led[6] = |training_error_count || |timeout_count || |frame_error_count;
    assign led[7] = heartbeat_count[24];

    kcu105_pcie_phy_wrapper u_phy_wrapper (
        .pcie_refclk_p          (pcie_refclk_p),
        .pcie_refclk_n          (pcie_refclk_n),
        .pcie_perst_n           (pcie_perst_n),
        .pcie_rxp               (pcie_rxp),
        .pcie_rxn               (pcie_rxn),
        .pcie_txp               (pcie_txp),
        .pcie_txn               (pcie_txn),
        .phy_txdata             (phy_txdata),
        .phy_txdatak            (phy_txdatak),
        .phy_txdata_valid       (phy_txdata_valid),
        .phy_txstart_block      (phy_txstart_block),
        .phy_txsync_header      (phy_txsync_header),
        .phy_txdetectrx         (phy_txdetectrx),
        .phy_txelecidle         (phy_txelecidle),
        .phy_txcompliance       (phy_txcompliance),
        .phy_rxpolarity         (phy_rxpolarity),
        .phy_powerdown          (phy_powerdown),
        .phy_rate               (phy_rate),
        .phy_txmargin           (phy_txmargin),
        .phy_txswing            (phy_txswing),
        .phy_txdeemph           (phy_txdeemph),
        .phy_txeq_ctrl          (phy_txeq_ctrl),
        .phy_txeq_preset        (phy_txeq_preset),
        .phy_txeq_coeff         (phy_txeq_coeff),
        .phy_rxeq_ctrl          (phy_rxeq_ctrl),
        .phy_rxeq_txpreset      (phy_rxeq_txpreset),
        .as_mac_in_detect       (as_mac_in_detect),
        .as_cdr_hold_req        (as_cdr_hold_req),
        .phy_coreclk            (phy_coreclk),
        .phy_userclk            (phy_userclk),
        .phy_mcapclk            (phy_mcapclk),
        .phy_pclk               (phy_pclk),
        .pipe_rst_n             (pipe_rst_n),
        .core_rst_n             (core_rst_n),
        .phy_rxdata             (phy_rxdata),
        .phy_rxdatak            (phy_rxdatak),
        .phy_rxdata_valid       (phy_rxdata_valid),
        .phy_rxstart_block      (phy_rxstart_block),
        .phy_rxsync_header      (phy_rxsync_header),
        .phy_rxvalid            (phy_rxvalid),
        .phy_phystatus          (phy_phystatus),
        .phy_phystatus_rst      (phy_phystatus_rst),
        .phy_rxelecidle         (phy_rxelecidle),
        .phy_rxstatus           (phy_rxstatus),
        .phy_txeq_fs            (phy_txeq_fs),
        .phy_txeq_lf            (phy_txeq_lf),
        .phy_txeq_new_coeff     (phy_txeq_new_coeff),
        .phy_txeq_done          (phy_txeq_done),
        .phy_rxeq_preset_sel    (phy_rxeq_preset_sel),
        .phy_rxeq_new_txcoeff   (phy_rxeq_new_txcoeff),
        .phy_rxeq_adapt_done    (phy_rxeq_adapt_done),
        .phy_rxeq_done          (phy_rxeq_done)
    );

    pcie_ltssm_mac_gen1 #(
        .DETECT_QUIET_CYCLES   (DETECT_QUIET_CYCLES),
        .DETECT_TIMEOUT_CYCLES (DETECT_TIMEOUT_CYCLES),
        .TRAIN_TIMEOUT_CYCLES  (TRAIN_TIMEOUT_CYCLES),
        .HOT_RESET_CYCLES      (HOT_RESET_CYCLES)
    ) u_ltssm_mac (
        .phy_pclk               (phy_pclk),
        .pipe_rst_n             (pipe_rst_n),
        .phy_rxdata             (phy_rxdata),
        .phy_rxdatak            (phy_rxdatak),
        .phy_rxdata_valid       (phy_rxdata_valid),
        .phy_rxstart_block      (phy_rxstart_block),
        .phy_rxsync_header      (phy_rxsync_header),
        .phy_rxvalid            (phy_rxvalid),
        .phy_phystatus          (phy_phystatus),
        .phy_rxelecidle         (phy_rxelecidle),
        .phy_rxstatus           (phy_rxstatus),
        .active_phy_rate        (phy_rate),
        .recovery_target_rate   (2'b00),
        .recovery_fallback_active(1'b0),
        .gen3_tx_eq_control     (8'h01),
        .gen3_tx_eq_data        (24'h8a0c28),
        .gen3_protocol_eq_complete(1'b0),
        .phy_txdata             (phy_txdata),
        .phy_txdatak            (phy_txdatak),
        .phy_txdata_valid       (phy_txdata_valid),
        .phy_txstart_block      (phy_txstart_block),
        .phy_txsync_header      (phy_txsync_header),
        .phy_txdetectrx         (phy_txdetectrx),
        .phy_txelecidle         (phy_txelecidle),
        .phy_txcompliance       (phy_txcompliance),
        .phy_rxpolarity         (phy_rxpolarity),
        .phy_powerdown          (phy_powerdown),
        .phy_rate               (phy_rate),
        .phy_txmargin           (phy_txmargin),
        .phy_txswing            (phy_txswing),
        .phy_txdeemph           (phy_txdeemph),
        .phy_txeq_ctrl          (phy_txeq_ctrl),
        .phy_txeq_preset        (phy_txeq_preset),
        .phy_txeq_coeff         (phy_txeq_coeff),
        .phy_rxeq_ctrl          (phy_rxeq_ctrl),
        .phy_rxeq_txpreset      (phy_rxeq_txpreset),
        .as_mac_in_detect       (as_mac_in_detect),
        .as_cdr_hold_req        (as_cdr_hold_req),
        .tx_pkt_valid           (1'b0),
        .tx_pkt_ready           (tx_pkt_ready),
        .tx_pkt_data            (16'd0),
        .tx_pkt_keep            (2'd0),
        .tx_pkt_sop             (1'b0),
        .tx_pkt_eop             (1'b0),
        .tx_pkt_is_dllp         (1'b0),
        .tx_pkt_bad             (1'b0),
        .rx_pkt_valid           (rx_pkt_valid),
        .rx_pkt_data            (rx_pkt_data),
        .rx_pkt_keep            (rx_pkt_keep),
        .rx_pkt_sop             (rx_pkt_sop),
        .rx_pkt_eop             (rx_pkt_eop),
        .rx_pkt_is_dllp         (rx_pkt_is_dllp),
        .rx_pkt_error           (rx_pkt_error),
        .link_disable           (1'b0),
        .hot_reset_req          (1'b0),
        .force_recovery         (1'b0),
        .speed_retrain_active   (1'b0),
        .recovery_speed_done    (1'b0),
        .recovery_speed_ready   (),
        .ltssm_state            (ltssm_state),
        .link_up                (link_up),
        .negotiated_width       (negotiated_width),
        .negotiated_speed       (negotiated_speed),
        .link_number            (link_number),
        .rx_ts_count            (rx_ts_count),
        .training_error_count   (training_error_count),
        .timeout_count          (timeout_count),
        .frame_error_count      (frame_error_count),
        .hot_reset_seen         (hot_reset_seen)
    );

    wire _unused = &{1'b0, phy_coreclk, phy_userclk, phy_mcapclk,
        phy_rxstart_block, phy_rxsync_header, phy_txeq_fs, phy_txeq_lf,
        phy_txeq_new_coeff, phy_txeq_done, phy_rxeq_preset_sel,
        phy_rxeq_new_txcoeff, phy_rxeq_adapt_done, phy_rxeq_done,
        tx_pkt_ready, rx_pkt_valid, rx_pkt_data, rx_pkt_keep, rx_pkt_sop,
        rx_pkt_eop, rx_pkt_is_dllp, rx_pkt_error, negotiated_width,
        negotiated_speed, link_number, rx_ts_count, hot_reset_seen};
endmodule

`default_nettype wire
