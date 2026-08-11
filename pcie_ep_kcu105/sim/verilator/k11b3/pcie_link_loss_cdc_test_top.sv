`timescale 1ns/1ps
`default_nettype none

module pcie_link_loss_cdc_test_top (
    input  wire pipe_clk,
    input  wire core_clk,
    input  wire pipe_rst_n,
    input  wire core_rst_n,
    input  wire link_up,
    input  wire dll_active,
    output wire operational_seen,
    output wire link_loss_pulse,
    output wire core_link_loss_pulse
);
    wire link_loss_seen;

    pcie_link_loss_trigger u_trigger (
        .clk              (pipe_clk),
        .rst_n            (pipe_rst_n),
        .link_up          (link_up),
        .dll_active       (dll_active),
        .operational_seen (operational_seen),
        .link_loss_seen   (link_loss_seen),
        .link_loss_pulse  (link_loss_pulse)
    );

    pcie_cdc_pulse u_cdc (
        .s_clk   (pipe_clk),
        .s_rst_n (pipe_rst_n),
        .s_pulse (link_loss_pulse),
        .d_clk   (core_clk),
        .d_rst_n (core_rst_n),
        .d_pulse (core_link_loss_pulse)
    );
endmodule

`default_nettype wire
