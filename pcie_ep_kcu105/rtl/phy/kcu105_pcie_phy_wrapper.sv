`timescale 1ns/1ps
`default_nettype none

// K02：KCU105 standalone PCIe PHY 的板级封装。
//
// 本模块只完成以下工作：
//   1. 连接 KCU105 PCIe 参考时钟、PERST# 与 x1 串行端口；
//   2. 实例化 Vivado 2021.2 pcie_phy:1.0 生成的 pcie_phy_x1_gen3；
//   3. 复用 K01 的参考时钟缓冲和 PIPE/Core 复位分发；
//   4. 将 Xilinx PHY 原生 32-bit 接口原样提供给后续 LTSSM/MAC。
//
// 不在这里实现 LTSSM、Ordered Set、DLL 或速率切换策略。
module kcu105_pcie_phy_wrapper #(
    parameter integer RESET_SYNC_STAGES = 4
) (
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

    wire phy_gtrefclk;
    wire phy_refclk;
    wire phy_rst_n;

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

    pcie_phy_x1_gen3 u_pcie_phy (
        .phy_refclk            (phy_refclk),
        .phy_gtrefclk          (phy_gtrefclk),
        .phy_rst_n             (phy_rst_n),

        .phy_txdata            (phy_txdata),
        .phy_txdatak           (phy_txdatak),
        .phy_txdata_valid      (phy_txdata_valid),
        .phy_txstart_block     (phy_txstart_block),
        .phy_txsync_header     (phy_txsync_header),

        .phy_rxp               (pcie_rxp),
        .phy_rxn               (pcie_rxn),
        .phy_txp               (pcie_txp),
        .phy_txn               (pcie_txn),

        .phy_txdetectrx        (phy_txdetectrx),
        .phy_txelecidle        (phy_txelecidle),
        .phy_txcompliance      (phy_txcompliance),
        .phy_rxpolarity        (phy_rxpolarity),
        .phy_powerdown         (phy_powerdown),
        .phy_rate              (phy_rate),
        .phy_txmargin          (phy_txmargin),
        .phy_txswing           (phy_txswing),
        .phy_txdeemph          (phy_txdeemph),

        .phy_txeq_ctrl         (phy_txeq_ctrl),
        .phy_txeq_preset       (phy_txeq_preset),
        .phy_txeq_coeff        (phy_txeq_coeff),
        .phy_rxeq_ctrl         (phy_rxeq_ctrl),
        .phy_rxeq_txpreset     (phy_rxeq_txpreset),
        .as_mac_in_detect      (as_mac_in_detect),
        .as_cdr_hold_req       (as_cdr_hold_req),

        .phy_coreclk           (phy_coreclk),
        .phy_userclk           (phy_userclk),
        .phy_mcapclk           (phy_mcapclk),
        .phy_pclk              (phy_pclk),

        .phy_rxdata            (phy_rxdata),
        .phy_rxdatak           (phy_rxdatak),
        .phy_rxdata_valid      (phy_rxdata_valid),
        .phy_rxstart_block     (phy_rxstart_block),
        .phy_rxsync_header     (phy_rxsync_header),
        .phy_rxvalid           (phy_rxvalid),
        .phy_phystatus         (phy_phystatus),
        .phy_phystatus_rst     (phy_phystatus_rst),
        .phy_rxelecidle        (phy_rxelecidle),
        .phy_rxstatus          (phy_rxstatus),

        .phy_txeq_fs           (phy_txeq_fs),
        .phy_txeq_lf           (phy_txeq_lf),
        .phy_txeq_new_coeff    (phy_txeq_new_coeff),
        .phy_txeq_done         (phy_txeq_done),
        .phy_rxeq_preset_sel   (phy_rxeq_preset_sel),
        .phy_rxeq_new_txcoeff  (phy_rxeq_new_txcoeff),
        .phy_rxeq_adapt_done   (phy_rxeq_adapt_done),
        .phy_rxeq_done         (phy_rxeq_done)
    );

endmodule

`default_nettype wire
