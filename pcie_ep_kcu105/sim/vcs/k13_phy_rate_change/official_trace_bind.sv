`timescale 1ps/1ps
`default_nettype none

module k13_official_phy_trace #(
    parameter integer LABEL = 0
) (
    input wire clk,
    input wire [2:0] phy_rate,
    input wire [1:0] phy_powerdown,
    input wire phy_txelecidle,
    input wire [1:0] phy_txeq_ctrl,
    input wire [3:0] phy_txeq_preset,
    input wire phy_txeq_done,
    input wire phy_phystatus,
    input wire as_cdr_hold_req
);
    integer fd;
    integer cycle;
    reg [2:0] last_rate;
    reg [1:0] last_powerdown;
    reg last_txei, last_txeq_done, last_phystatus, last_cdr;
    reg [1:0] last_txeq_ctrl;
    reg [3:0] last_txeq_preset;

    initial begin
        cycle = 0;
        last_rate = 3'bxxx;
        last_powerdown = 2'bxx;
        last_txei = 1'bx; last_txeq_done = 1'bx;
        last_phystatus = 1'bx; last_cdr = 1'bx;
        last_txeq_ctrl = 2'bxx; last_txeq_preset = 4'bxxxx;
        if (LABEL == 0)
            fd = $fopen("official_rp_phy_trace.csv", "w");
        else
            fd = $fopen("official_ep_phy_trace.csv", "w");
        $fdisplay(fd, "cycle,time_ps,rate,powerdown,txelecidle,txeq_ctrl,txeq_preset,txeq_done,phystatus,cdr_hold");
    end

    always @(posedge clk) begin
        if ((phy_rate !== last_rate) || (phy_powerdown !== last_powerdown) ||
            (phy_txelecidle !== last_txei) ||
            (phy_txeq_ctrl !== last_txeq_ctrl) ||
            (phy_txeq_preset !== last_txeq_preset) ||
            (phy_txeq_done !== last_txeq_done) ||
            (phy_phystatus !== last_phystatus) ||
            (as_cdr_hold_req !== last_cdr)) begin
            $fdisplay(fd, "%0d,%0t,%03b,%02b,%0d,%02b,%0d,%0d,%0d,%0d",
                      cycle, $time, phy_rate, phy_powerdown, phy_txelecidle,
                      phy_txeq_ctrl, phy_txeq_preset, phy_txeq_done,
                      phy_phystatus, as_cdr_hold_req);
            last_rate = phy_rate;
            last_powerdown = phy_powerdown;
            last_txei = phy_txelecidle;
            last_txeq_ctrl = phy_txeq_ctrl;
            last_txeq_preset = phy_txeq_preset;
            last_txeq_done = phy_txeq_done;
            last_phystatus = phy_phystatus;
            last_cdr = as_cdr_hold_req;
        end
        cycle = cycle + 1;
    end
endmodule

module k13_official_phy_trace_rp (
    input wire clk, input wire [2:0] phy_rate, input wire [1:0] phy_powerdown,
    input wire phy_txelecidle, input wire [1:0] phy_txeq_ctrl,
    input wire [3:0] phy_txeq_preset, input wire phy_txeq_done,
    input wire phy_phystatus, input wire as_cdr_hold_req
);
    k13_official_phy_trace #(.LABEL(0)) u_trace (
        .clk(clk), .phy_rate(phy_rate), .phy_powerdown(phy_powerdown),
        .phy_txelecidle(phy_txelecidle), .phy_txeq_ctrl(phy_txeq_ctrl),
        .phy_txeq_preset(phy_txeq_preset), .phy_txeq_done(phy_txeq_done),
        .phy_phystatus(phy_phystatus), .as_cdr_hold_req(as_cdr_hold_req)
    );
endmodule

module k13_official_phy_trace_ep (
    input wire clk, input wire [2:0] phy_rate, input wire [1:0] phy_powerdown,
    input wire phy_txelecidle, input wire [1:0] phy_txeq_ctrl,
    input wire [3:0] phy_txeq_preset, input wire phy_txeq_done,
    input wire phy_phystatus, input wire as_cdr_hold_req
);
    k13_official_phy_trace #(.LABEL(1)) u_trace (
        .clk(clk), .phy_rate(phy_rate), .phy_powerdown(phy_powerdown),
        .phy_txelecidle(phy_txelecidle), .phy_txeq_ctrl(phy_txeq_ctrl),
        .phy_txeq_preset(phy_txeq_preset), .phy_txeq_done(phy_txeq_done),
        .phy_phystatus(phy_phystatus), .as_cdr_hold_req(as_cdr_hold_req)
    );
endmodule

bind xilinx_pcie_phy_top k13_official_phy_trace_rp
    official_rp_trace (
        .clk(pipe_clk), .phy_rate(phy_rate), .phy_powerdown(phy_powerdown),
        .phy_txelecidle(phy_txelecidle), .phy_txeq_ctrl(phy_txeq_ctrl),
        .phy_txeq_preset(phy_txeq_preset), .phy_txeq_done(phy_txeq_done),
        .phy_phystatus(phy_phystatus), .as_cdr_hold_req(as_cdr_hold_req)
    );

bind xilinx_pcie_phy_model k13_official_phy_trace_ep
    official_ep_trace (
        .clk(pipe_clk), .phy_rate(phy_rate), .phy_powerdown(phy_powerdown),
        .phy_txelecidle(phy_txelecidle), .phy_txeq_ctrl(phy_txeq_ctrl),
        .phy_txeq_preset(phy_txeq_preset), .phy_txeq_done(phy_txeq_done),
        .phy_phystatus(phy_phystatus), .as_cdr_hold_req(as_cdr_hold_req)
    );

// Capture the standalone example PIPE contract.  This is a PHY framing
// golden only: the example sends EIEOS followed by a generic OS pattern,
// not protocol-complete Gen3 SKP or TS ordered sets.
module k13_official_pipe_trace #(
    parameter integer LABEL = 0
) (
    input wire clk,
    input wire [2:0] phy_rate,
    input wire [31:0] phy_txdata,
    input wire phy_txdata_valid,
    input wire phy_txstart_block,
    input wire [1:0] phy_txsync_header,
    input wire phy_txelecidle,
    input wire [31:0] phy_rxdata,
    input wire phy_rxdata_valid,
    input wire phy_rxstart_block,
    input wire [1:0] phy_rxsync_header
);
    integer fd;
    integer tx_sample_count;
    integer rx_sample_count;
    initial begin
        tx_sample_count = 0;
        rx_sample_count = 0;
        if (LABEL == 0)
            fd = $fopen("official_rp_pipe_trace.csv", "w");
        else
            fd = $fopen("official_ep_pipe_trace.csv", "w");
        $fdisplay(fd, "tx_sample,rx_sample,time_ps,rate,txvalid,txstart,txheader,txelecidle,txdata,rxvalid,rxstart,rxheader,rxdata");
    end

    always @(posedge clk) begin
        if ((phy_rate[1:0] == 2'b10) &&
            (((tx_sample_count < 512) && phy_txdata_valid) ||
             ((rx_sample_count < 512) && phy_rxdata_valid))) begin
            $fdisplay(fd, "%0d,%0d,%0t,%03b,%0d,%0d,%02b,%0d,%08x,%0d,%0d,%02b,%08x",
                      tx_sample_count, rx_sample_count, $time, phy_rate,
                      phy_txdata_valid, phy_txstart_block,
                      phy_txsync_header, phy_txelecidle, phy_txdata,
                      phy_rxdata_valid, phy_rxstart_block,
                      phy_rxsync_header, phy_rxdata);
            if ((tx_sample_count < 512) && phy_txdata_valid)
                tx_sample_count = tx_sample_count + 1;
            if ((rx_sample_count < 512) && phy_rxdata_valid)
                rx_sample_count = rx_sample_count + 1;
        end
    end
endmodule

bind xilinx_pcie_phy_top k13_official_pipe_trace #(.LABEL(0))
    official_rp_pipe_trace (
        .clk(pipe_clk), .phy_rate(phy_rate),
        .phy_txdata(phy_txdata), .phy_txdata_valid(phy_txdata_valid),
        .phy_txstart_block(phy_txstart_block),
        .phy_txsync_header(phy_txsync_header),
        .phy_txelecidle(phy_txelecidle),
        .phy_rxdata(phy_rxdata), .phy_rxdata_valid(phy_rxdata_valid),
        .phy_rxstart_block(phy_rxstart_block),
        .phy_rxsync_header(phy_rxsync_header)
    );

bind xilinx_pcie_phy_model k13_official_pipe_trace #(.LABEL(1))
    official_ep_pipe_trace (
        .clk(pipe_clk), .phy_rate(phy_rate),
        .phy_txdata(phy_txdata), .phy_txdata_valid(phy_txdata_valid),
        .phy_txstart_block(phy_txstart_block),
        .phy_txsync_header(phy_txsync_header),
        .phy_txelecidle(phy_txelecidle),
        .phy_rxdata(phy_rxdata), .phy_rxdata_valid(phy_rxdata_valid),
        .phy_rxstart_block(phy_rxstart_block),
        .phy_rxsync_header(phy_rxsync_header)
    );

// Compare the serialized result with the failing Endpoint trace.  Matching
// edge deltas prove more than matching PIPE words because they include the
// generated PHY's 128b/130b gearbox and serializer.
module k13_official_serial_trace (
    input wire serial_p,
    input wire [2:0] phy_rate,
    input wire phy_txelecidle
);
    integer edge_count;
    time last_edge;
    initial begin
        edge_count = 0;
        last_edge = 0;
    end

    always @(serial_p) begin
        if ((phy_rate == 3'b010) && !phy_txelecidle &&
            (edge_count < 32)) begin
            $display("K13_OFFICIAL_SERIAL_EDGE n=%0d time_ps=%0t delta_ps=%0t value=%0d",
                     edge_count, $time, $time - last_edge, serial_p);
            last_edge = $time;
            edge_count = edge_count + 1;
        end
    end
endmodule

bind board k13_official_serial_trace official_rp_serial_trace (
    .serial_p(rp_pci_exp_txp[0]),
    .phy_rate(PCIE_PHY.phy_rate),
    .phy_txelecidle(PCIE_PHY.phy_txelecidle)
);

`default_nettype wire
