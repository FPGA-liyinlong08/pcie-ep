`timescale 1ps/1ps

// K02 的真实 pcie_phy/GT Wizard Gen3 steady-state 用例。
// 与 k02_pcie_phy_tb 的 G1->G2->G3->G1 动态用例分开，整个测试期间
// phy_rate 固定为 Gen3，目的是先验证 QPLL1/Gen3 时钟和 PHY P0 稳态。
module k02_gen3_steady_tb;
    localparam time REFCLK_HALF_PERIOD = 5_000;

    logic pcie_refclk_p = 1'b0;
    wire  pcie_refclk_n = ~pcie_refclk_p;
    logic pcie_perst_n = 1'b0;
    logic pcie_rxp = 1'b0;
    logic pcie_rxn = 1'b1;
    wire pcie_txp, pcie_txn;

    logic [31:0] phy_txdata = 32'b0;
    logic [1:0] phy_txdatak = 2'b0;
    logic phy_txdata_valid = 1'b0;
    logic phy_txstart_block = 1'b0;
    logic [1:0] phy_txsync_header = 2'b0;
    logic phy_txdetectrx = 1'b0;
    logic phy_txelecidle = 1'b1;
    logic phy_txcompliance = 1'b0;
    logic phy_rxpolarity = 1'b0;
    logic [1:0] phy_powerdown = 2'b10;
    logic [1:0] phy_rate = 2'b10;
    logic [2:0] phy_txmargin = 3'b0;
    logic phy_txswing = 1'b0;
    logic phy_txdeemph = 1'b0;
    logic [1:0] phy_txeq_ctrl = 2'b0;
    logic [3:0] phy_txeq_preset = 4'd4;
    logic [5:0] phy_txeq_coeff = 6'b0;
    logic [1:0] phy_rxeq_ctrl = 2'b0;
    logic [3:0] phy_rxeq_txpreset = 4'b0;
    logic as_mac_in_detect = 1'b0;
    logic as_cdr_hold_req = 1'b0;

    wire phy_coreclk, phy_userclk, phy_mcapclk, phy_pclk;
    wire pipe_rst_n, core_rst_n;
    wire [31:0] phy_rxdata;
    wire [1:0] phy_rxdatak;
    wire phy_rxdata_valid, phy_rxstart_block;
    wire [1:0] phy_rxsync_header;
    wire phy_rxvalid, phy_phystatus, phy_phystatus_rst, phy_rxelecidle;
    wire [2:0] phy_rxstatus;
    wire [5:0] phy_txeq_fs, phy_txeq_lf;
    wire [17:0] phy_txeq_new_coeff;
    wire phy_txeq_done, phy_rxeq_preset_sel;
    wire [17:0] phy_rxeq_new_txcoeff;
    wire phy_rxeq_adapt_done, phy_rxeq_done;

    always #REFCLK_HALF_PERIOD pcie_refclk_p = ~pcie_refclk_p;

    kcu105_pcie_phy_wrapper dut (.*);

    task automatic wait_pipe_release;
        integer cycles;
        begin
            for (cycles = 0; cycles < 200_000; cycles = cycles + 1) begin
                @(posedge phy_pclk);
                if (pipe_rst_n === 1'b1) disable wait_pipe_release;
            end
            $fatal(1, "K02 Gen3 steady VCS PIPE reset release timeout");
        end
    endtask

    task automatic wait_phystatus;
        integer cycles;
        begin
            for (cycles = 0; cycles < 200_000; cycles = cycles + 1) begin
                @(posedge phy_pclk);
                if (phy_phystatus === 1'b1) disable wait_phystatus;
            end
            $fatal(1, "K02 Gen3 steady VCS P0 PhyStatus timeout");
        end
    endtask

    task automatic check_period(input [127:0] name, input integer expected_ps,
                                input integer actual_ps);
        begin
            if ((actual_ps < expected_ps - 50) || (actual_ps > expected_ps + 50))
                $fatal(1, "K02 Gen3 steady %0s period=%0d expected=%0d",
                       name, actual_ps, expected_ps);
            $display("K02_VCS_GEN3_CLOCK clock=%0s period_ps=%0d", name, actual_ps);
        end
    endtask

    initial begin : watchdog
        #2_000_000_000;
        $fatal(1, "K02 Gen3 steady VCS global timeout");
    end

    initial begin : test_sequence
        time first_edge, second_edge;
        #500_000;
        pcie_perst_n = 1'b1;
        wait_pipe_release();
        if (core_rst_n !== 1'b1) $fatal(1, "K02 Gen3 steady core reset active");
        if (phy_rate !== 2'b10) $fatal(1, "K02 Gen3 steady rate changed before P0");

        // 仅执行 P1->P0 上电；没有 Receiver Detect，也没有任何速率切换。
        phy_powerdown = 2'b00;
        wait_phystatus();

        repeat (4) @(posedge phy_pclk);
        first_edge = $time; @(posedge phy_pclk); second_edge = $time;
        check_period("phy_pclk_gen3", 4_000, second_edge - first_edge);
        @(posedge phy_coreclk); first_edge = $time;
        @(posedge phy_coreclk); second_edge = $time;
        check_period("phy_coreclk_gen3", 4_000, second_edge - first_edge);
        @(posedge phy_userclk); first_edge = $time;
        @(posedge phy_userclk); second_edge = $time;
        check_period("phy_userclk_gen3", 8_000, second_edge - first_edge);

        $display("K02_VCS_GEN3_STEADY_PASS rate=Gen3 powerdown=P0 receiver_detect=skipped");
        $finish;
    end
endmodule
