`timescale 1ns/1ps
`default_nettype none

// KU060 顶层时钟与复位封装。厂商原语仅出现在本文件中。
module pcie_clk_reset #(
    parameter integer RESET_SYNC_STAGES  = 4,
    parameter integer STATUS_SYNC_STAGES = 2
) (
    input  wire pcie_refclk_p,
    input  wire pcie_refclk_n,
    input  wire sys_clk_100,
    input  wire pcie_perst_n,

    input  wire gt_txoutclk,
    input  wire gt_rxoutclk,
    input  wire gt_pll_lock,
    input  wire gt_tx_reset_done,
    input  wire gt_rx_reset_done,

    output wire gt_refclk,
    output wire core_clk_250,
    output wire core_rst_n,
    output wire gt_txusrclk,
    output wire gt_rxusrclk,
    output wire pipe_clk,
    output wire pipe_rst_n,
    output wire core_mmcm_locked,
    output wire clock_ready
);

    wire core_clk_mmcm;
    wire core_clk_feedback;
    wire core_clk_feedback_buf;

    IBUFDS_GTE3 #(
        .REFCLK_EN_TX_PATH (1'b0),
        .REFCLK_HROW_CK_SEL(2'b00),
        .REFCLK_ICNTL_RX   (2'b00)
    ) u_pcie_refclk_ibuf (
        .I     (pcie_refclk_p),
        .IB    (pcie_refclk_n),
        .CEB   (1'b0),
        .O     (gt_refclk),
        .ODIV2 ()
    );

    MMCME3_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKFBOUT_MULT_F    (10.000),
        .CLKFBOUT_PHASE     (0.000),
        .CLKIN1_PERIOD      (10.000),
        .CLKOUT0_DIVIDE_F   (4.000),
        .CLKOUT0_DUTY_CYCLE (0.500),
        .CLKOUT0_PHASE      (0.000),
        .DIVCLK_DIVIDE      (1),
        .REF_JITTER1        (0.010),
        .STARTUP_WAIT       ("FALSE")
    ) u_core_mmcm (
        .CLKIN1    (sys_clk_100),
        .CLKFBIN   (core_clk_feedback_buf),
        .RST       (!pcie_perst_n),
        .PWRDWN    (1'b0),
        .CLKFBOUT  (core_clk_feedback),
        .CLKFBOUTB (),
        .CLKOUT0   (core_clk_mmcm),
        .CLKOUT0B  (),
        .CLKOUT1   (),
        .CLKOUT1B  (),
        .CLKOUT2   (),
        .CLKOUT2B  (),
        .CLKOUT3   (),
        .CLKOUT3B  (),
        .CLKOUT4   (),
        .CLKOUT5   (),
        .CLKOUT6   (),
        .LOCKED    (core_mmcm_locked)
    );

    BUFG u_core_feedback_bufg (
        .I (core_clk_feedback),
        .O (core_clk_feedback_buf)
    );

    BUFG u_core_clk_bufg (
        .I (core_clk_mmcm),
        .O (core_clk_250)
    );

    BUFG_GT u_gt_txusrclk_bufg (
        .I       (gt_txoutclk),
        .CE      (1'b1),
        .CEMASK  (1'b0),
        .CLR     (!pcie_perst_n),
        .CLRMASK (1'b0),
        .DIV     (3'b000),
        .O       (gt_txusrclk)
    );

    BUFG_GT u_gt_rxusrclk_bufg (
        .I       (gt_rxoutclk),
        .CE      (1'b1),
        .CEMASK  (1'b0),
        .CLR     (!pcie_perst_n),
        .CLRMASK (1'b0),
        .DIV     (3'b000),
        .O       (gt_rxusrclk)
    );

    assign pipe_clk = gt_txusrclk;

    pcie_clk_reset_ctrl #(
        .RESET_SYNC_STAGES  (RESET_SYNC_STAGES),
        .STATUS_SYNC_STAGES (STATUS_SYNC_STAGES)
    ) u_reset_ctrl (
        .core_clk          (core_clk_250),
        .pipe_clk          (pipe_clk),
        .pcie_perst_n      (pcie_perst_n),
        .core_clock_locked (core_mmcm_locked),
        .gt_pll_lock       (gt_pll_lock),
        .gt_tx_reset_done  (gt_tx_reset_done),
        .gt_rx_reset_done  (gt_rx_reset_done),
        .core_rst_n        (core_rst_n),
        .pipe_rst_n        (pipe_rst_n),
        .clock_ready       (clock_ready)
    );

endmodule

`default_nettype wire

