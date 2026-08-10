`timescale 1ns/1ps
`default_nettype none

// Checker自检替身：TX数据能通过，但故意破坏Packet元数据。
module k11a_bridge_test_top (
    input wire pipe_clk, pipe_rst_n, core_clk, core_rst_n,
    input wire dll_rx_valid, output wire dll_rx_ready,
    input wire [127:0] dll_rx_data, input wire [15:0] dll_rx_keep,
    input wire dll_rx_sop, dll_rx_eop, input wire [3:0] dll_rx_error,
    output wire core_rx_valid, input wire core_rx_ready,
    output wire [127:0] core_rx_data, output wire [15:0] core_rx_keep,
    output wire core_rx_sop, core_rx_eop, output wire [3:0] core_rx_error,
    input wire core_tx_valid, output wire core_tx_ready,
    input wire [127:0] core_tx_data, input wire [15:0] core_tx_keep,
    input wire core_tx_sop, core_tx_eop, input wire [3:0] core_tx_error,
    input wire [1:0] core_tx_type, input wire [11:0] core_tx_data_credits,
    output wire dll_tx_valid, input wire dll_tx_ready,
    output wire [127:0] dll_tx_data, output wire [15:0] dll_tx_keep,
    output wire dll_tx_sop, dll_tx_eop, output wire [3:0] dll_tx_error,
    output wire [1:0] dll_tx_type, output wire [11:0] dll_tx_data_credits,
    input wire core_release_valid, output wire core_release_ready,
    input wire [1:0] core_release_type,
    input wire [11:0] core_release_data_credits,
    output wire dll_release_valid, input wire dll_release_ready,
    output wire [1:0] dll_release_type,
    output wire [11:0] dll_release_data_credits,
    output wire [7:0] sticky_errors
);
    assign core_tx_ready = dll_tx_ready;
    assign dll_tx_valid = core_tx_valid;
    assign dll_tx_data = core_tx_data;
    assign dll_tx_keep = core_tx_keep;
    assign dll_tx_sop = core_tx_sop;
    assign dll_tx_eop = core_tx_eop;
    assign dll_tx_error = core_tx_error;
    assign dll_tx_type = 2'd0;
    assign dll_tx_data_credits = 12'd0;
    assign dll_rx_ready = core_rx_ready;
    assign core_rx_valid = dll_rx_valid;
    assign core_rx_data = dll_rx_data;
    assign core_rx_keep = dll_rx_keep;
    assign core_rx_sop = dll_rx_sop;
    assign core_rx_eop = dll_rx_eop;
    assign core_rx_error = dll_rx_error;
    assign core_release_ready = dll_release_ready;
    assign dll_release_valid = core_release_valid;
    assign dll_release_type = core_release_type;
    assign dll_release_data_credits = core_release_data_credits;
    assign sticky_errors = 8'd0;
    wire _unused = &{1'b0, pipe_clk, pipe_rst_n, core_clk, core_rst_n,
                     core_tx_type, core_tx_data_credits};
endmodule

`default_nettype wire
