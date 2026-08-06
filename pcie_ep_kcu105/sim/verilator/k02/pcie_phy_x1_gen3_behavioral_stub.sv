`timescale 1ns/1ps

// 与 Vivado 2021.2 pcie_phy:1.0 端口一致的纯行为模型，只供 Verilator。
module pcie_phy_x1_gen3 (
    input  wire        phy_refclk,
    input  wire        phy_gtrefclk,
    input  wire        phy_rst_n,
    input  wire [31:0] phy_txdata,
    input  wire [1:0]  phy_txdatak,
    input  wire [0:0]  phy_txdata_valid,
    input  wire [0:0]  phy_txstart_block,
    input  wire [1:0]  phy_txsync_header,
    input  wire [0:0]  phy_rxp,
    input  wire [0:0]  phy_rxn,
    input  wire        phy_txdetectrx,
    input  wire [0:0]  phy_txelecidle,
    input  wire [0:0]  phy_txcompliance,
    input  wire [0:0]  phy_rxpolarity,
    input  wire [1:0]  phy_powerdown,
    input  wire [1:0]  phy_rate,
    input  wire [2:0]  phy_txmargin,
    input  wire        phy_txswing,
    input  wire        phy_txdeemph,
    input  wire [1:0]  phy_txeq_ctrl,
    input  wire [3:0]  phy_txeq_preset,
    input  wire [5:0]  phy_txeq_coeff,
    input  wire [1:0]  phy_rxeq_ctrl,
    input  wire [3:0]  phy_rxeq_txpreset,
    input  wire        as_mac_in_detect,
    input  wire        as_cdr_hold_req,
    output wire        phy_coreclk,
    output wire        phy_userclk,
    output wire        phy_mcapclk,
    output wire        phy_pclk,
    output wire [0:0]  phy_txp,
    output wire [0:0]  phy_txn,
    output wire [31:0] phy_rxdata,
    output wire [1:0]  phy_rxdatak,
    output wire [0:0]  phy_rxdata_valid,
    output wire [0:0]  phy_rxstart_block,
    output wire [1:0]  phy_rxsync_header,
    output wire [0:0]  phy_rxvalid,
    output logic [0:0] phy_phystatus,
    output wire        phy_phystatus_rst,
    output wire [0:0]  phy_rxelecidle,
    output logic [2:0] phy_rxstatus,
    output wire [5:0]  phy_txeq_fs,
    output wire [5:0]  phy_txeq_lf,
    output wire [17:0] phy_txeq_new_coeff,
    output wire [0:0]  phy_txeq_done,
    output wire [0:0]  phy_rxeq_preset_sel,
    output wire [17:0] phy_rxeq_new_txcoeff,
    output wire [0:0]  phy_rxeq_adapt_done,
    output wire [0:0]  phy_rxeq_done
);
    logic [1:0] rate_q;
    logic rate_reset_q;

    assign phy_coreclk = phy_refclk;
    assign phy_userclk = phy_refclk;
    assign phy_mcapclk = phy_refclk;
    assign phy_pclk = phy_refclk;
    assign phy_txp[0] = phy_txelecidle[0] ? 1'b0 : phy_txdata[0];
    assign phy_txn[0] = ~phy_txp[0];

    assign phy_rxdata = phy_txdata;
    assign phy_rxdatak = phy_txdatak;
    assign phy_rxdata_valid = phy_txdata_valid;
    assign phy_rxstart_block = phy_txstart_block;
    assign phy_rxsync_header = phy_txsync_header;
    assign phy_rxvalid = phy_txdata_valid;
    assign phy_rxelecidle = phy_txelecidle;

    assign phy_txeq_fs = {4'b0000, phy_txeq_ctrl};
    assign phy_txeq_lf = {2'b00, phy_txeq_preset};
    assign phy_txeq_new_coeff = {12'b0, phy_txeq_coeff};
    assign phy_txeq_done[0] = |phy_txeq_ctrl;
    assign phy_rxeq_preset_sel[0] = phy_rxeq_ctrl[0];
    assign phy_rxeq_new_txcoeff = {14'b0, phy_rxeq_txpreset};
    assign phy_rxeq_adapt_done[0] = phy_rxeq_ctrl[0];
    assign phy_rxeq_done[0] = phy_rxeq_ctrl[1];
    assign phy_phystatus_rst = !phy_rst_n || rate_reset_q;

    always_ff @(posedge phy_refclk or negedge phy_rst_n) begin
        if (!phy_rst_n) begin
            rate_q          <= 2'b00;
            rate_reset_q    <= 1'b0;
            phy_phystatus   <= 1'b0;
            phy_rxstatus    <= 3'b000;
        end else begin
            rate_reset_q  <= 1'b0;
            phy_phystatus <= 1'b0;
            phy_rxstatus  <= 3'b000;
            if (phy_txdetectrx) begin
                phy_phystatus <= 1'b1;
                phy_rxstatus  <= 3'b011;
            end else if (phy_rate != rate_q) begin
                rate_q          <= phy_rate;
                rate_reset_q    <= 1'b1;
                phy_phystatus   <= 1'b1;
            end
        end
    end
endmodule
