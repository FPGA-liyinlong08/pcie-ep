`timescale 1ps/1ps

module k02_pcie_phy_tb;
    localparam time REFCLK_HALF_PERIOD = 5_000;

    logic        pcie_refclk_p = 1'b0;
    wire         pcie_refclk_n = ~pcie_refclk_p;
    logic        pcie_perst_n  = 1'b0;
    logic        pcie_rxp      = 1'b0;
    logic        pcie_rxn      = 1'b1;
    wire         pcie_txp;
    wire         pcie_txn;

    logic [31:0] phy_txdata         = 32'b0;
    logic [1:0]  phy_txdatak        = 2'b0;
    logic        phy_txdata_valid   = 1'b0;
    logic        phy_txstart_block  = 1'b0;
    logic [1:0]  phy_txsync_header  = 2'b0;
    logic        phy_txdetectrx     = 1'b0;
    logic        phy_txelecidle     = 1'b1;
    logic        phy_txcompliance   = 1'b0;
    logic        phy_rxpolarity     = 1'b0;
    logic [1:0]  phy_powerdown      = 2'b10;
    logic [1:0]  phy_rate           = 2'b00;
    logic [2:0]  phy_txmargin       = 3'b0;
    logic        phy_txswing        = 1'b0;
    logic        phy_txdeemph       = 1'b0;
    logic [1:0]  phy_txeq_ctrl      = 2'b0;
    logic [3:0]  phy_txeq_preset    = 4'd4;
    logic [5:0]  phy_txeq_coeff     = 6'b0;
    logic [1:0]  phy_rxeq_ctrl      = 2'b0;
    logic [3:0]  phy_rxeq_txpreset  = 4'b0;
    logic        as_mac_in_detect   = 1'b1;
    logic        as_cdr_hold_req    = 1'b0;

    wire         phy_coreclk;
    wire         phy_userclk;
    wire         phy_mcapclk;
    wire         phy_pclk;
    wire         pipe_rst_n;
    wire         core_rst_n;
    wire [31:0]  phy_rxdata;
    wire [1:0]   phy_rxdatak;
    wire         phy_rxdata_valid;
    wire         phy_rxstart_block;
    wire [1:0]   phy_rxsync_header;
    wire         phy_rxvalid;
    wire         phy_phystatus;
    wire         phy_phystatus_rst;
    wire         phy_rxelecidle;
    wire [2:0]   phy_rxstatus;
    wire [5:0]   phy_txeq_fs;
    wire [5:0]   phy_txeq_lf;
    wire [17:0]  phy_txeq_new_coeff;
    wire         phy_txeq_done;
    wire         phy_rxeq_preset_sel;
    wire [17:0]  phy_rxeq_new_txcoeff;
    wire         phy_rxeq_adapt_done;
    wire         phy_rxeq_done;

    always #REFCLK_HALF_PERIOD pcie_refclk_p = ~pcie_refclk_p;

    kcu105_pcie_phy_wrapper dut (
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

    task automatic wait_phystatus(input [127:0] operation);
        integer cycles;
        begin : wait_status_block
            for (cycles = 0; cycles < 200_000; cycles = cycles + 1) begin
                @(posedge phy_pclk);
                if (phy_phystatus === 1'b1) begin
                    $display("K02_VCS_STATUS operation=%0s time_ps=%0t rxstatus=%03b",
                             operation, $time, phy_rxstatus);
                    disable wait_status_block;
                end
            end
            $fatal(1, "K02 VCS 等待 PhyStatus 超时：%0s", operation);
        end
    endtask

    task automatic wait_pipe_release(input [127:0] operation);
        integer cycles;
        begin : wait_pipe_block
            for (cycles = 0; cycles < 64; cycles = cycles + 1) begin
                @(posedge phy_pclk);
                if (pipe_rst_n === 1'b1) begin
                    disable wait_pipe_block;
                end
            end
            $fatal(1, "K02 VCS 等待 PIPE 复位释放超时：%0s", operation);
        end
    endtask

    task automatic check_period(
        input [127:0] clock_name,
        input integer expected_ps,
        input integer measured_ps
    );
        begin
            if ((measured_ps < expected_ps - 50) ||
                (measured_ps > expected_ps + 50)) begin
                $fatal(1, "K02 %0s 周期错误：actual=%0d ps expected=%0d ps",
                       clock_name, measured_ps, expected_ps);
            end
            $display("K02_VCS_CLOCK clock=%0s period_ps=%0d", clock_name, measured_ps);
        end
    endtask

    task automatic measure_core_clock;
        time first_edge;
        time second_edge;
        begin
            @(posedge phy_coreclk);
            first_edge = $time;
            @(posedge phy_coreclk);
            second_edge = $time;
            check_period("phy_coreclk", 4_000, second_edge - first_edge);
        end
    endtask

    task automatic measure_user_clock;
        time first_edge;
        time second_edge;
        begin
            @(posedge phy_userclk);
            first_edge = $time;
            @(posedge phy_userclk);
            second_edge = $time;
            check_period("phy_userclk", 8_000, second_edge - first_edge);
        end
    endtask

    task automatic measure_pclk(input integer expected_ps);
        time first_edge;
        time second_edge;
        begin
            repeat (4) @(posedge phy_pclk);
            first_edge = $time;
            @(posedge phy_pclk);
            second_edge = $time;
            check_period("phy_pclk", expected_ps, second_edge - first_edge);
        end
    endtask

    task automatic change_rate(input [1:0] new_rate, input integer expected_pclk_ps);
        begin
            phy_rate = new_rate;
            wait_phystatus("RateChange");
            if (core_rst_n !== 1'b1) begin
                $fatal(1, "K02 Rate Change 错误地复位 Core");
            end
            wait_pipe_release("RateChange");
            measure_pclk(expected_pclk_ps);
        end
    endtask

    initial begin : watchdog
        #2_000_000_000;
        $fatal(1, "K02 VCS 全局超时（2 ms）");
    end

    initial begin : test_sequence
        integer cycles;

        #500_000;
        pcie_perst_n = 1'b1;

        begin : wait_initial_reset
            for (cycles = 0; cycles < 200_000; cycles = cycles + 1) begin
                #1_000;
                if ((phy_phystatus_rst === 1'b0) &&
                    (phy_pclk !== 1'bx) && (phy_coreclk !== 1'bx)) begin
                    disable wait_initial_reset;
                end
            end
            $fatal(1, "K02 VCS PHY 初始复位超时");
        end

        wait_pipe_release("InitialReset");
        if (core_rst_n !== 1'b1) begin
            $fatal(1, "K02 Core 复位未释放");
        end
        measure_core_clock();
        measure_user_clock();
        measure_pclk(8_000);

        // 按 Xilinx standalone PHY 示例流程从 P1 进入 P0。
        phy_powerdown = 2'b00;
        wait_phystatus("PowerUpP0");

        // Receiver Detect：P1 + Electrical Idle + TxDetectRx。
        phy_powerdown  = 2'b10;
        phy_txelecidle = 1'b1;
        phy_txdetectrx = 1'b1;
        wait_phystatus("ReceiverDetect");
        if (phy_rxstatus !== 3'b011) begin
            $fatal(1, "K02 Receiver Detect 结果错误：rxstatus=%03b", phy_rxstatus);
        end
        phy_txdetectrx = 1'b0;

        phy_powerdown = 2'b00;
        wait_phystatus("ReturnP0");
        change_rate(2'b01, 4_000);
        change_rate(2'b10, 4_000);
        change_rate(2'b00, 8_000);

        $display("K02_VCS_PHY_PASS receiver_detect=forced-model rate_sequence=G1-G2-G3-G1");
        $finish;
    end
endmodule
