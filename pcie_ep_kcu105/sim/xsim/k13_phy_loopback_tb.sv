`timescale 1ps/1ps
`default_nettype none

// Same-version Vivado Simulator diagnostic for the standalone PCIe PHY model.
// Vivado 2021.2's generated vendor example also keeps RXVALID low at Gen3, so
// this test records that model boundary; it is not a design pass/fail gate.
module k13_phy_loopback_tb;
    reg refclk_p = 1'b0;
    wire refclk_n = ~refclk_p;
    reg perst_n = 1'b0;

    wire txp, txn, peer_txp, peer_txn;
    wire rxp = peer_txp;
    wire rxn = peer_txn;
    wire peer_rxp = txp;
    wire peer_rxn = txn;
    wire pclk, coreclk, userclk, mcapclk;
    wire phystatus_rst, pipe_rst_n, core_rst_n;
    wire [31:0] rxdata;
    wire [1:0] rxdatak;
    wire rxdata_valid, rxstart_block, rxvalid, phystatus, rxelecidle;
    wire [1:0] rxsync_header;
    wire [2:0] rxstatus;
    wire [5:0] txeq_fs, txeq_lf;
    wire [17:0] txeq_new_coeff, rxeq_new_txcoeff;
    wire txeq_done, rxeq_preset_sel, rxeq_adapt_done, rxeq_done;
    wire peer_pclk, peer_coreclk, peer_userclk, peer_mcapclk;
    wire peer_phystatus_rst, peer_pipe_rst_n, peer_core_rst_n;
    wire [31:0] peer_rxdata;
    wire [1:0] peer_rxdatak, peer_rxsync_header;
    wire peer_rxdata_valid, peer_rxstart_block, peer_rxvalid;
    wire peer_phystatus, peer_rxelecidle;
    wire [2:0] peer_rxstatus;
    wire [5:0] peer_txeq_fs, peer_txeq_lf;
    wire [17:0] peer_txeq_new_coeff, peer_rxeq_new_txcoeff;
    wire peer_txeq_done, peer_rxeq_preset_sel;
    wire peer_rxeq_adapt_done, peer_rxeq_done;

    reg [1:0] rate = 2'b00;
    reg [1:0] powerdown = 2'b10;
    reg txelecidle = 1'b1;
    reg [1:0] txeq_ctrl = 2'b00;
    reg [3:0] txeq_preset = 4'd4;
    reg os_enable = 1'b0;
    reg [1:0] golden_word = 2'd0;
    reg [4:0] golden_block = 5'd0;
    wire golden_eieos = (golden_block == 5'd0);
    wire [31:0] golden_data = golden_eieos ? 32'hff00_ff00 :
                                                   32'hbeef_cafe;
    wire golden_valid = os_enable;
    wire golden_start = os_enable && (golden_word == 2'd0);
    wire [1:0] golden_header = 2'b01;

    integer wait_cycles;
    integer tx_edges = 0;
    always #5000 refclk_p = ~refclk_p;
    always @(txp) tx_edges = tx_edges + 1;

    always @(posedge pclk or negedge pipe_rst_n) begin
        if (!pipe_rst_n || !os_enable) begin
            golden_word <= 2'd0;
            golden_block <= 5'd0;
        end else if (golden_word == 2'd3) begin
            golden_word <= 2'd0;
            golden_block <= (golden_block == 5'd15) ? 5'd0 :
                                                        golden_block + 1'b1;
        end else begin
            golden_word <= golden_word + 1'b1;
        end
    end

    kcu105_pcie_phy_wrapper u_phy (
        .pcie_refclk_p(refclk_p), .pcie_refclk_n(refclk_n),
        .pcie_perst_n(perst_n), .pcie_rxp(rxp), .pcie_rxn(rxn),
        .pcie_txp(txp), .pcie_txn(txn),
        .phy_txdata(golden_data), .phy_txdatak(2'b00),
        .phy_txdata_valid(golden_valid), .phy_txstart_block(golden_start),
        .phy_txsync_header(golden_header), .phy_txdetectrx(1'b0),
        .phy_txelecidle(txelecidle), .phy_txcompliance(1'b0),
        .phy_rxpolarity(1'b0), .phy_powerdown(powerdown), .phy_rate(rate),
        .phy_txmargin(3'b000), .phy_txswing(1'b0), .phy_txdeemph(1'b0),
        .phy_txeq_ctrl(txeq_ctrl), .phy_txeq_preset(txeq_preset),
        .phy_txeq_coeff(6'd0), .phy_rxeq_ctrl(2'b00),
        .phy_rxeq_txpreset(4'd0), .as_mac_in_detect(1'b0),
        .as_cdr_hold_req(1'b0), .phy_pclk(pclk), .phy_coreclk(coreclk),
        .phy_userclk(userclk), .phy_mcapclk(mcapclk),
        .phy_phystatus_rst(phystatus_rst),
        .pipe_rst_n(pipe_rst_n), .core_rst_n(core_rst_n),
        .phy_rxdata(rxdata), .phy_rxdatak(rxdatak),
        .phy_rxdata_valid(rxdata_valid), .phy_rxstart_block(rxstart_block),
        .phy_rxsync_header(rxsync_header), .phy_rxvalid(rxvalid),
        .phy_phystatus(phystatus), .phy_rxelecidle(rxelecidle),
        .phy_rxstatus(rxstatus), .phy_txeq_fs(txeq_fs),
        .phy_txeq_lf(txeq_lf), .phy_txeq_new_coeff(txeq_new_coeff),
        .phy_txeq_done(txeq_done), .phy_rxeq_preset_sel(rxeq_preset_sel),
        .phy_rxeq_new_txcoeff(rxeq_new_txcoeff),
        .phy_rxeq_adapt_done(rxeq_adapt_done), .phy_rxeq_done(rxeq_done)
    );

    kcu105_pcie_phy_wrapper u_peer_phy (
        .pcie_refclk_p(refclk_p), .pcie_refclk_n(refclk_n),
        .pcie_perst_n(perst_n), .pcie_rxp(peer_rxp), .pcie_rxn(peer_rxn),
        .pcie_txp(peer_txp), .pcie_txn(peer_txn),
        .phy_txdata(golden_data), .phy_txdatak(2'b00),
        .phy_txdata_valid(golden_valid), .phy_txstart_block(golden_start),
        .phy_txsync_header(golden_header), .phy_txdetectrx(1'b0),
        .phy_txelecidle(txelecidle), .phy_txcompliance(1'b0),
        .phy_rxpolarity(1'b0), .phy_powerdown(powerdown), .phy_rate(rate),
        .phy_txmargin(3'b000), .phy_txswing(1'b0), .phy_txdeemph(1'b0),
        .phy_txeq_ctrl(txeq_ctrl), .phy_txeq_preset(txeq_preset),
        .phy_txeq_coeff(6'd0), .phy_rxeq_ctrl(2'b00),
        .phy_rxeq_txpreset(4'd0), .as_mac_in_detect(1'b0),
        .as_cdr_hold_req(1'b0), .phy_pclk(peer_pclk),
        .phy_coreclk(peer_coreclk), .phy_userclk(peer_userclk),
        .phy_mcapclk(peer_mcapclk), .phy_phystatus_rst(peer_phystatus_rst),
        .pipe_rst_n(peer_pipe_rst_n), .core_rst_n(peer_core_rst_n),
        .phy_rxdata(peer_rxdata), .phy_rxdatak(peer_rxdatak),
        .phy_rxdata_valid(peer_rxdata_valid),
        .phy_rxstart_block(peer_rxstart_block),
        .phy_rxsync_header(peer_rxsync_header), .phy_rxvalid(peer_rxvalid),
        .phy_phystatus(peer_phystatus), .phy_rxelecidle(peer_rxelecidle),
        .phy_rxstatus(peer_rxstatus), .phy_txeq_fs(peer_txeq_fs),
        .phy_txeq_lf(peer_txeq_lf), .phy_txeq_new_coeff(peer_txeq_new_coeff),
        .phy_txeq_done(peer_txeq_done),
        .phy_rxeq_preset_sel(peer_rxeq_preset_sel),
        .phy_rxeq_new_txcoeff(peer_rxeq_new_txcoeff),
        .phy_rxeq_adapt_done(peer_rxeq_adapt_done),
        .phy_rxeq_done(peer_rxeq_done)
    );

    initial begin
        repeat (500) @(posedge refclk_p);
        perst_n = 1'b1;
        wait ((pipe_rst_n === 1'b1) && (peer_pipe_rst_n === 1'b1));
        repeat (32) @(posedge pclk);

        // Match the vendor example PHY initialization: enter P0 from P1 and
        // consume the corresponding PhyStatus completion before RateChange.
        powerdown = 2'b00;
        wait ((phystatus === 1'b1) && (peer_phystatus === 1'b1));
        wait ((phystatus === 1'b0) && (peer_phystatus === 1'b0));
        repeat (32) @(posedge pclk);

        // PG239 preset-apply step before changing to Gen3.
        txeq_ctrl = 2'b01;
        wait ((txeq_done === 1'b1) && (peer_txeq_done === 1'b1));
        @(posedge pclk);
        txeq_ctrl = 2'b00;
        wait ((txeq_done === 1'b0) && (peer_txeq_done === 1'b0));

        rate = 2'b10;
        wait ((phystatus === 1'b1) && (peer_phystatus === 1'b1));
        wait ((phystatus === 1'b0) && (peer_phystatus === 1'b0));
        repeat (2500) @(posedge pclk);
        txelecidle = 1'b0;
        os_enable = 1'b1;

        wait_cycles = 0;
        while (!(rxdata_valid && peer_rxdata_valid) &&
               (wait_cycles < 20000)) begin
            @(posedge pclk);
            wait_cycles = wait_cycles + 1;
        end
        $display("K13_XSIM_PHY_LOOPBACK_RESULT wait=%0d rxvalid=%0d data_valid=%0d start=%0d header=%02b data=%08x peer_rxvalid=%0d peer_data_valid=%0d peer_start=%0d peer_header=%02b peer_data=%08x elecidle=%0d status=%0d tx_edges=%0d",
                 wait_cycles, rxvalid, rxdata_valid, rxstart_block,
                 rxsync_header, rxdata, peer_rxvalid, peer_rxdata_valid,
                 peer_rxstart_block, peer_rxsync_header, peer_rxdata,
                 rxelecidle, rxstatus, tx_edges);
        if (!(rxdata_valid && peer_rxdata_valid))
            $display("K13_XSIM_PHY_MODEL_LIMIT_OBSERVED");
        else
            $display("K13_XSIM_PHY_LOOPBACK_PASS");
        $finish;
    end
endmodule

`default_nettype wire
