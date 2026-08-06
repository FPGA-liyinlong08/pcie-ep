`timescale 1ns/1ps

module k01_refclk_reset_tb;

    localparam integer RESET_SYNC_STAGES = 4;

    logic pcie_refclk_p       = 1'b0;
    wire  pcie_refclk_n       = ~pcie_refclk_p;
    logic phy_pclk            = 1'b0;
    logic phy_coreclk         = 1'b0;
    logic pcie_perst_n        = 1'b0;
    logic phy_phystatus_rst   = 1'b1;

    wire phy_gtrefclk;
    wire phy_refclk;
    wire phy_rst_n;
    wire pipe_rst_n;
    wire core_rst_n;

    real gt_edge_1;
    real gt_edge_2;
    real ref_edge_1;
    real ref_edge_2;

    always #5.0 pcie_refclk_p = ~pcie_refclk_p;
    always #8.0 phy_pclk      = ~phy_pclk;
    always #2.0 phy_coreclk   = ~phy_coreclk;

    kcu105_refclk_reset #(
        .RESET_SYNC_STAGES (RESET_SYNC_STAGES)
    ) dut (
        .pcie_refclk_p       (pcie_refclk_p),
        .pcie_refclk_n       (pcie_refclk_n),
        .pcie_perst_n        (pcie_perst_n),
        .phy_pclk            (phy_pclk),
        .phy_coreclk         (phy_coreclk),
        .phy_phystatus_rst   (phy_phystatus_rst),
        .phy_gtrefclk        (phy_gtrefclk),
        .phy_refclk          (phy_refclk),
        .phy_rst_n           (phy_rst_n),
        .pipe_rst_n          (pipe_rst_n),
        .core_rst_n          (core_rst_n)
    );

    task automatic check_low(input logic value, input string name);
        if (value !== 1'b0) begin
            $fatal(1, "%s expected 0 at %0t, got %b", name, $time, value);
        end
    endtask

    task automatic check_high(input logic value, input string name);
        if (value !== 1'b1) begin
            $fatal(1, "%s expected 1 at %0t, got %b", name, $time, value);
        end
    endtask

    task automatic expect_core_release;
        integer cycle;
        begin
            for (cycle = 1; cycle < RESET_SYNC_STAGES; cycle = cycle + 1) begin
                @(posedge phy_coreclk);
                #0.001;
                check_low(core_rst_n, "core_rst_n early release");
            end
            @(posedge phy_coreclk);
            #0.001;
            check_high(core_rst_n, "core_rst_n release");
        end
    endtask

    task automatic expect_pipe_release;
        integer cycle;
        begin
            for (cycle = 1; cycle < RESET_SYNC_STAGES; cycle = cycle + 1) begin
                @(posedge phy_pclk);
                #0.001;
                check_low(pipe_rst_n, "pipe_rst_n early release");
            end
            @(posedge phy_pclk);
            #0.001;
            check_high(pipe_rst_n, "pipe_rst_n release");
        end
    endtask

    initial begin
        #0.001;
        check_low(phy_rst_n, "phy_rst_n during PERST#");
        check_low(pipe_rst_n, "pipe_rst_n during PERST#");
        check_low(core_rst_n, "core_rst_n during PERST#");

        fork
            begin
                @(posedge phy_gtrefclk);
                gt_edge_1 = $realtime;
                @(posedge phy_gtrefclk);
                gt_edge_2 = $realtime;
            end
            begin
                @(posedge phy_refclk);
                ref_edge_1 = $realtime;
                @(posedge phy_refclk);
                ref_edge_2 = $realtime;
            end
        join

        if (((gt_edge_2 - gt_edge_1) < 9.999) ||
            ((gt_edge_2 - gt_edge_1) > 10.001)) begin
            $fatal(1, "phy_gtrefclk period mismatch: %0.3f ns",
                   gt_edge_2 - gt_edge_1);
        end
        if (((ref_edge_2 - ref_edge_1) < 9.999) ||
            ((ref_edge_2 - ref_edge_1) > 10.001)) begin
            $fatal(1, "phy_refclk period mismatch: %0.3f ns",
                   ref_edge_2 - ref_edge_1);
        end

        @(negedge phy_coreclk);
        pcie_perst_n = 1'b1;
        #0.001;
        check_high(phy_rst_n, "phy_rst_n direct release");
        expect_core_release();
        check_low(pipe_rst_n, "PIPE held by phy_phystatus_rst");

        @(negedge phy_pclk);
        phy_phystatus_rst = 1'b0;
        expect_pipe_release();

        #1.307;
        phy_phystatus_rst = 1'b1;
        #0.001;
        check_low(pipe_rst_n, "PIPE asynchronous PHY Status reset");
        check_high(core_rst_n, "Core isolation from PHY Status reset");
        check_high(phy_rst_n, "PHY isolation from PHY Status reset");

        #0.217;
        phy_phystatus_rst = 1'b0;
        expect_pipe_release();

        #0.911;
        pcie_perst_n = 1'b0;
        #0.001;
        check_low(phy_rst_n, "PHY asynchronous PERST#");
        check_low(pipe_rst_n, "PIPE asynchronous PERST#");
        check_low(core_rst_n, "Core asynchronous PERST#");

        $display("K01_VCS_PASS gtrefclk_period_ns=%0.3f phy_refclk_period_ns=%0.3f",
                 gt_edge_2 - gt_edge_1, ref_edge_2 - ref_edge_1);
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "K01 VCS timeout");
    end

endmodule
