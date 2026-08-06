`timescale 1ns/1ps

// 故意错误：PERST# 有效期间错误地释放 PIPE/Core 复位，供 Checker 自检。
module kcu105_pcie_phy_wrapper (
    input  wire        pcie_refclk_p,
    input  wire        pcie_refclk_n,
    input  wire        pcie_perst_n,
    input  wire        pcie_rxp,
    input  wire        pcie_rxn,
    output wire        pcie_txp,
    output wire        pcie_txn,
    input  wire [31:0] phy_txdata,
    input  wire [1:0]  phy_txdatak,
    input  wire        phy_txdata_valid,
    input  wire        phy_txstart_block,
    input  wire [1:0]  phy_txsync_header,
    input  wire        phy_txdetectrx,
    input  wire        phy_txelecidle,
    input  wire        phy_txcompliance,
    input  wire        phy_rxpolarity,
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
    output wire        pipe_rst_n,
    output wire        core_rst_n,
    output wire [31:0] phy_rxdata,
    output wire [1:0]  phy_rxdatak,
    output wire        phy_rxdata_valid,
    output wire        phy_rxstart_block,
    output wire [1:0]  phy_rxsync_header,
    output wire        phy_rxvalid,
    output wire        phy_phystatus,
    output wire        phy_phystatus_rst,
    output wire        phy_rxelecidle,
    output wire [2:0]  phy_rxstatus,
    output wire [5:0]  phy_txeq_fs,
    output wire [5:0]  phy_txeq_lf,
    output wire [17:0] phy_txeq_new_coeff,
    output wire        phy_txeq_done,
    output wire        phy_rxeq_preset_sel,
    output wire [17:0] phy_rxeq_new_txcoeff,
    output wire        phy_rxeq_adapt_done,
    output wire        phy_rxeq_done
);
    assign pcie_txp = 1'b0;
    assign pcie_txn = 1'b1;
    assign phy_coreclk = pcie_refclk_p;
    assign phy_userclk = pcie_refclk_p;
    assign phy_mcapclk = pcie_refclk_p;
    assign phy_pclk = pcie_refclk_p;
    assign pipe_rst_n = 1'b1;
    assign core_rst_n = 1'b1;
    assign phy_rxdata = '0;
    assign phy_rxdatak = '0;
    assign phy_rxdata_valid = 1'b0;
    assign phy_rxstart_block = 1'b0;
    assign phy_rxsync_header = '0;
    assign phy_rxvalid = 1'b0;
    assign phy_phystatus = 1'b0;
    assign phy_phystatus_rst = 1'b0;
    assign phy_rxelecidle = 1'b1;
    assign phy_rxstatus = '0;
    assign phy_txeq_fs = '0;
    assign phy_txeq_lf = '0;
    assign phy_txeq_new_coeff = '0;
    assign phy_txeq_done = 1'b0;
    assign phy_rxeq_preset_sel = 1'b0;
    assign phy_rxeq_new_txcoeff = '0;
    assign phy_rxeq_adapt_done = 1'b0;
    assign phy_rxeq_done = 1'b0;
endmodule
