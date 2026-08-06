`timescale 1ns/1ps
`default_nettype none

module k06_arbiter_test_top (
    input wire clk, input wire rst_n, input wire enable,
    input wire raw_ack_valid, output wire raw_ack_ready,
    input wire [31:0] raw_ack_data,
    input wire raw_fc_valid, output wire raw_fc_ready,
    input wire [31:0] raw_fc_data,
    output wire raw_out_valid, input wire raw_out_ready,
    output wire [31:0] raw_out_data,
    input wire dllp_valid, output wire dllp_ready,
    input wire [15:0] dllp_data, input wire [1:0] dllp_keep,
    input wire dllp_sop, input wire dllp_eop, input wire dllp_bad,
    input wire tlp_valid, output wire tlp_ready,
    input wire [15:0] tlp_data, input wire [1:0] tlp_keep,
    input wire tlp_sop, input wire tlp_eop, input wire tlp_bad,
    output wire out_valid, input wire out_ready,
    output wire [15:0] out_data, output wire [1:0] out_keep,
    output wire out_sop, output wire out_eop,
    output wire out_is_dllp, output wire out_bad
);
    pcie_dllp_tx_arbiter u_raw (
        .ack_valid(raw_ack_valid), .ack_ready(raw_ack_ready),
        .ack_data(raw_ack_data), .fc_valid(raw_fc_valid),
        .fc_ready(raw_fc_ready), .fc_data(raw_fc_data),
        .out_valid(raw_out_valid), .out_ready(raw_out_ready),
        .out_data(raw_out_data)
    );
    pcie_dll_mac_tx_arbiter u_packet (.*);
endmodule

`default_nettype wire
