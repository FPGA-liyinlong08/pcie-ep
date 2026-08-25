`timescale 1ns/1ps
`default_nettype none

// K03 Checker 自检专用：Receiver Detect 成功后非法跳过全部训练状态直达 L0。
module pcie_ltssm_mac_gen1 #(
    parameter integer DETECT_QUIET_CYCLES = 4,
    parameter integer DETECT_TIMEOUT_CYCLES = 64,
    parameter integer TRAIN_TIMEOUT_CYCLES = 512,
    parameter integer HOT_RESET_CYCLES = 8,
    parameter integer TX_BUFFER_BYTES = 160,
    parameter integer G9_WAIT_REMOTE_DETECT = 0,
    parameter integer G9_WAIT_REMOTE_DETECT_CYCLES = 32
) (
    input wire phy_pclk, input wire pipe_rst_n,
    input wire [31:0] phy_rxdata, input wire [1:0] phy_rxdatak,
    input wire phy_rxdata_valid, input wire phy_rxstart_block,
    input wire [1:0] phy_rxsync_header, input wire phy_rxvalid,
    input wire phy_phystatus, input wire phy_rxelecidle, input wire [2:0] phy_rxstatus,
    input wire [1:0] active_phy_rate,
    output wire [31:0] phy_txdata, output wire [1:0] phy_txdatak,
    output wire phy_txdata_valid, output wire phy_txstart_block,
    output wire [1:0] phy_txsync_header,
    output wire phy_txdetectrx, output wire phy_txelecidle,
    output wire phy_txcompliance, output wire phy_rxpolarity,
    output wire [1:0] phy_powerdown, output wire [1:0] phy_rate,
    output wire [2:0] phy_txmargin, output wire phy_txswing, output wire phy_txdeemph,
    output wire [1:0] phy_txeq_ctrl, output wire [3:0] phy_txeq_preset,
    output wire [5:0] phy_txeq_coeff, output wire [1:0] phy_rxeq_ctrl,
    output wire [3:0] phy_rxeq_txpreset, output wire as_mac_in_detect,
    output wire as_cdr_hold_req,
    input wire tx_pkt_valid, output wire tx_pkt_ready, input wire [15:0] tx_pkt_data,
    input wire [1:0] tx_pkt_keep, input wire tx_pkt_sop, input wire tx_pkt_eop,
    input wire tx_pkt_is_dllp, input wire tx_pkt_bad,
    output wire rx_pkt_valid, output wire [15:0] rx_pkt_data,
    output wire [1:0] rx_pkt_keep, output wire rx_pkt_sop, output wire rx_pkt_eop,
    output wire rx_pkt_is_dllp, output wire [3:0] rx_pkt_error,
    input wire link_disable, input wire hot_reset_req, input wire force_recovery,
    input wire speed_retrain_active, input wire recovery_speed_done,
    output wire recovery_speed_ready,
    output reg [5:0] ltssm_state, output wire link_up,
    output wire [2:0] negotiated_width, output wire [1:0] negotiated_speed,
    output wire [7:0] link_number, output wire [4:0] rx_ts_count,
    output wire [31:0] training_error_count, output wire [31:0] timeout_count,
    output wire [31:0] frame_error_count, output wire hot_reset_seen
);
    reg [7:0] quiet_count;
    always @(posedge phy_pclk or negedge pipe_rst_n) begin
        if (!pipe_rst_n) begin
            ltssm_state <= 6'd0;
            quiet_count <= 0;
        end else if (ltssm_state == 0) begin
            if (quiet_count == DETECT_QUIET_CYCLES-1) ltssm_state <= 6'd1;
            else quiet_count <= quiet_count + 1'b1;
        end else if ((ltssm_state == 1) && phy_phystatus && (phy_rxstatus == 3'b011)) begin
            ltssm_state <= 6'd10;
        end
    end
    assign phy_txdata = 0; assign phy_txdatak = 0; assign phy_txdata_valid = 0;
    assign phy_txstart_block = 0; assign phy_txsync_header = 0;
    assign phy_txdetectrx = (ltssm_state == 1); assign phy_txelecidle = (ltssm_state < 2);
    assign phy_txcompliance = 0; assign phy_rxpolarity = 0;
    assign phy_powerdown = (ltssm_state < 2) ? 2'b10 : 2'b00; assign phy_rate = 0;
    assign phy_txmargin = 0; assign phy_txswing = 0; assign phy_txdeemph = 0;
    assign phy_txeq_ctrl = 0; assign phy_txeq_preset = 0; assign phy_txeq_coeff = 0;
    assign phy_rxeq_ctrl = 0; assign phy_rxeq_txpreset = 0;
    assign as_mac_in_detect = (ltssm_state < 2); assign as_cdr_hold_req = 0;
    assign tx_pkt_ready = 0; assign rx_pkt_valid = 0; assign rx_pkt_data = 0;
    assign rx_pkt_keep = 0; assign rx_pkt_sop = 0; assign rx_pkt_eop = 0;
    assign rx_pkt_is_dllp = 0; assign rx_pkt_error = 0;
    assign link_up = (ltssm_state == 10); assign negotiated_width = link_up ? 1 : 0;
    assign negotiated_speed = 0; assign link_number = 8'hf7; assign rx_ts_count = 0;
    assign training_error_count = 0; assign timeout_count = 0;
    assign frame_error_count = 0; assign hot_reset_seen = 0;
    assign recovery_speed_ready = 0;
    wire _unused = &{1'b0, phy_rxdata, phy_rxdatak, phy_rxdata_valid,
        phy_rxstart_block, phy_rxsync_header, active_phy_rate, phy_rxvalid,
        phy_rxelecidle, tx_pkt_valid, tx_pkt_data, tx_pkt_keep, tx_pkt_sop, tx_pkt_eop,
        tx_pkt_is_dllp, tx_pkt_bad, link_disable, hot_reset_req, force_recovery,
        speed_retrain_active, recovery_speed_done,
        DETECT_TIMEOUT_CYCLES[0], TRAIN_TIMEOUT_CYCLES[0], HOT_RESET_CYCLES[0],
        TX_BUFFER_BYTES[0], G9_WAIT_REMOTE_DETECT[0],
        G9_WAIT_REMOTE_DETECT_CYCLES[0]};
endmodule

`default_nettype wire
