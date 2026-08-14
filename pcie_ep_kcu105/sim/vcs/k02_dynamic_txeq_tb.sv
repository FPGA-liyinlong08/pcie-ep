`timescale 1ps/1ps

// K02 standalone PHY dynamic Gen1->Gen3 A/B test.
// Default: Preset Apply only.  With +K02_QUERY: Preset Apply followed by
// Coefficient Query, then Gen3 rate change.
module k02_dynamic_txeq_tb;
    localparam time REFCLK_HALF_PERIOD = 5_000;

    logic pcie_refclk_p = 1'b0;
    wire  pcie_refclk_n = ~pcie_refclk_p;
    logic pcie_perst_n = 1'b0;
    logic pcie_rxp = 1'b0;
    logic pcie_rxn = 1'b1;
    wire pcie_txp, pcie_txn;

    logic [31:0] phy_txdata = 32'b0;
    logic [1:0]  phy_txdatak = 2'b0;
    logic        phy_txdata_valid = 1'b0;
    logic        phy_txstart_block = 1'b0;
    logic [1:0]  phy_txsync_header = 2'b0;
    logic        phy_txdetectrx = 1'b0;
    logic        phy_txelecidle = 1'b1;
    logic        phy_txcompliance = 1'b0;
    logic        phy_rxpolarity = 1'b0;
    logic [1:0]  phy_powerdown = 2'b10;
    logic [1:0]  phy_rate = 2'b00;
    logic [2:0]  phy_txmargin = 3'b0;
    logic        phy_txswing = 1'b0;
    logic        phy_txdeemph = 1'b0;
    logic [1:0]  phy_txeq_ctrl = 2'b00;
    logic [3:0]  phy_txeq_preset = 4'd4;
    logic [5:0]  phy_txeq_coeff = 6'b0;
    logic [1:0]  phy_rxeq_ctrl = 2'b0;
    logic [3:0]  phy_rxeq_txpreset = 4'b0;
    logic        as_mac_in_detect = 1'b1;
    logic        as_cdr_hold_req = 1'b0;

    wire phy_coreclk, phy_userclk, phy_mcapclk, phy_pclk;
    wire pipe_rst_n, core_rst_n;
    wire [31:0] phy_rxdata;
    wire [1:0] phy_rxdatak;
    wire phy_rxdata_valid, phy_rxstart_block, phy_rxvalid;
    wire [1:0] phy_rxsync_header;
    wire phy_phystatus, phy_phystatus_rst, phy_rxelecidle;
    wire [2:0] phy_rxstatus;
    wire [5:0] phy_txeq_fs, phy_txeq_lf;
    wire [17:0] phy_txeq_new_coeff;
    wire phy_txeq_done, phy_rxeq_preset_sel;
    wire [17:0] phy_rxeq_new_txcoeff;
    wire phy_rxeq_adapt_done, phy_rxeq_done;
    bit query_mode;

    always #REFCLK_HALF_PERIOD pcie_refclk_p = ~pcie_refclk_p;

    kcu105_pcie_phy_wrapper dut (.*);

    task automatic wait_status(input [127:0] name);
        integer cycles;
        begin : wait_status_block
            for (cycles = 0; cycles < 200_000; cycles = cycles + 1) begin
                @(posedge phy_pclk);
                if (phy_phystatus === 1'b1) begin
                    $display("K02_VCS_TXEQ_STATUS op=%0s rate=%02b rxstatus=%03b time_ps=%0t",
                             name, phy_rate, phy_rxstatus, $time);
                    disable wait_status_block;
                end
            end
            $fatal(1, "K02 TXEQ A/B wait PhyStatus timeout: %0s", name);
        end
    endtask

    task automatic wait_txeq(input [127:0] name);
        integer cycles;
        begin : wait_txeq_block
            for (cycles = 0; cycles < 200_000; cycles = cycles + 1) begin
                @(posedge phy_pclk);
                if (phy_txeq_done === 1'b1) begin
                    $display("K02_VCS_TXEQ_DONE op=%0s coeff=%018b time_ps=%0t",
                             name, phy_txeq_new_coeff, $time);
                    disable wait_txeq_block;
                end
            end
            $fatal(1, "K02 TXEQ A/B wait TXEQ_DONE timeout: %0s", name);
        end
    endtask

    initial begin
        if (!$value$plusargs("K02_QUERY=%d", query_mode))
            query_mode = 1'b0;
    end

    initial begin : watchdog
        #2_000_000_000;
        $fatal(1, "K02 TXEQ A/B global timeout");
    end

    initial begin : test_sequence
        integer cycles;
        #500_000;
        pcie_perst_n = 1'b1;

        begin : wait_initial_reset
            for (cycles = 0; cycles < 200_000; cycles = cycles + 1) begin
                @(posedge phy_pclk);
                if ((phy_phystatus_rst === 1'b0) && (phy_pclk !== 1'bx))
                    disable wait_initial_reset;
            end
            $fatal(1, "K02 TXEQ A/B initial reset timeout");
        end

        phy_powerdown = 2'b00;
        wait_status("PowerUpP0");

        // Keep the lane in electrical idle and CDR hold while issuing the
        // exact TXEQ command sequence under test.
        phy_txelecidle = 1'b1;
        as_cdr_hold_req = 1'b1;
        phy_rate = 2'b00;
        phy_txeq_ctrl = 2'b01;
        phy_txeq_preset = 4'd4;
        wait_txeq("PresetApply");

        phy_txeq_ctrl = 2'b00;
        @(posedge phy_pclk);

        if (query_mode) begin
            phy_txeq_ctrl = 2'b11;
            wait_txeq("CoefficientQuery");
            phy_txeq_ctrl = 2'b00;
            @(posedge phy_pclk);
        end

        phy_rate = 2'b10;
        wait_status("Gen1ToGen3");
        $display("K02_VCS_DYNAMIC_TXEQ_PASS query=%0d", query_mode);
        $finish;
    end
endmodule
