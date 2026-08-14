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

`default_nettype wire
