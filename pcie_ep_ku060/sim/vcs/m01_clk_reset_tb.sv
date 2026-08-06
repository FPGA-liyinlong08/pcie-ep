`timescale 1ns/1ps

module m01_clk_reset_tb;

    logic pcie_refclk_p = 1'b0;
    wire  pcie_refclk_n = ~pcie_refclk_p;
    logic sys_clk_100 = 1'b0;
    logic pcie_perst_n = 1'b0;
    logic gt_txoutclk = 1'b0;
    logic gt_rxoutclk = 1'b0;
    logic gt_pll_lock = 1'b0;
    logic gt_tx_reset_done = 1'b0;
    logic gt_rx_reset_done = 1'b0;

    wire gt_refclk;
    wire core_clk_250;
    wire core_rst_n;
    wire gt_txusrclk;
    wire gt_rxusrclk;
    wire pipe_clk;
    wire pipe_rst_n;
    wire core_mmcm_locked;
    wire clock_ready;

    realtime period_start;
    realtime period_end;
    real core_period_ns;

    always #5 pcie_refclk_p = ~pcie_refclk_p;
    always #5 sys_clk_100 = ~sys_clk_100;
    always #8 gt_txoutclk = ~gt_txoutclk;
    always #8 gt_rxoutclk = ~gt_rxoutclk;

    pcie_clk_reset dut (
        .pcie_refclk_p       (pcie_refclk_p),
        .pcie_refclk_n       (pcie_refclk_n),
        .sys_clk_100         (sys_clk_100),
        .pcie_perst_n        (pcie_perst_n),
        .gt_txoutclk         (gt_txoutclk),
        .gt_rxoutclk         (gt_rxoutclk),
        .gt_pll_lock         (gt_pll_lock),
        .gt_tx_reset_done    (gt_tx_reset_done),
        .gt_rx_reset_done    (gt_rx_reset_done),
        .gt_refclk           (gt_refclk),
        .core_clk_250        (core_clk_250),
        .core_rst_n          (core_rst_n),
        .gt_txusrclk         (gt_txusrclk),
        .gt_rxusrclk         (gt_rxusrclk),
        .pipe_clk            (pipe_clk),
        .pipe_rst_n          (pipe_rst_n),
        .core_mmcm_locked    (core_mmcm_locked),
        .clock_ready         (clock_ready)
    );

    initial begin : watchdog
        #50000;
        $fatal(1, "M01 VCS timeout");
    end

    initial begin : test_sequence
        repeat (10) @(posedge sys_clk_100);
        if ((core_rst_n !== 1'b0) || (pipe_rst_n !== 1'b0))
            $fatal(1, "reset output active before PERST release");

        @(negedge sys_clk_100);
        pcie_perst_n = 1'b1;

        wait (core_mmcm_locked === 1'b1);
        repeat (6) @(posedge core_clk_250);
        #0.001;
        if (core_rst_n !== 1'b1) $fatal(1, "core reset did not release");
        if (pipe_rst_n !== 1'b0) $fatal(1, "pipe reset released before GT ready");

        @(posedge core_clk_250);
        period_start = $realtime;
        repeat (20) @(posedge core_clk_250);
        period_end = $realtime;
        core_period_ns = (period_end - period_start) / 20.0;
        if ((core_period_ns < 3.98) || (core_period_ns > 4.02))
            $fatal(1, "core clock period out of range: %0.4f ns", core_period_ns);

        @(negedge gt_txoutclk);
        gt_pll_lock = 1'b1;
        gt_tx_reset_done = 1'b1;
        gt_rx_reset_done = 1'b1;

        repeat (5) @(posedge pipe_clk);
        #0.001;
        if (pipe_rst_n !== 1'b1) $fatal(1, "pipe reset did not release");

        wait (clock_ready === 1'b1);

        @(posedge pcie_refclk_p);
        #0.100;
        if (gt_refclk !== 1'b1) $fatal(1, "GT reference clock did not follow P input");

        #1.300;
        pcie_perst_n = 1'b0;
        #0.001;
        if ((core_rst_n !== 1'b0) || (pipe_rst_n !== 1'b0) || (clock_ready !== 1'b0))
            $fatal(1, "PERST did not asynchronously assert all reset outputs");

        $display("M01_VCS_PASS core_period_ns=%0.4f", core_period_ns);
        $finish;
    end

endmodule

