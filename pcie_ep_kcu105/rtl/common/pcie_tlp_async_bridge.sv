`timescale 1ns/1ps
`default_nettype none

// K11-A：K06 PIPE域与K07 Core域之间的原子Packet/信用CDC。
module pcie_tlp_async_bridge #(
    parameter integer PKT_LGFIFO = 9,
    parameter integer EVENT_LGFIFO = 4
) (
    input  wire         pipe_clk,
    input  wire         pipe_rst_n,
    input  wire         core_clk,
    input  wire         core_rst_n,

    input  wire         dll_rx_valid,
    output wire         dll_rx_ready,
    input  wire [127:0] dll_rx_data,
    input  wire [15:0]  dll_rx_keep,
    input  wire         dll_rx_sop,
    input  wire         dll_rx_eop,
    input  wire [3:0]   dll_rx_error,

    output wire         core_rx_valid,
    input  wire         core_rx_ready,
    output wire [127:0] core_rx_data,
    output wire [15:0]  core_rx_keep,
    output wire         core_rx_sop,
    output wire         core_rx_eop,
    output wire [3:0]   core_rx_error,

    input  wire         core_tx_valid,
    output wire         core_tx_ready,
    input  wire [127:0] core_tx_data,
    input  wire [15:0]  core_tx_keep,
    input  wire         core_tx_sop,
    input  wire         core_tx_eop,
    input  wire [3:0]   core_tx_error,
    input  wire [1:0]   core_tx_type,
    input  wire [11:0]  core_tx_data_credits,

    output wire         dll_tx_valid,
    input  wire         dll_tx_ready,
    output wire [127:0] dll_tx_data,
    output wire [15:0]  dll_tx_keep,
    output wire         dll_tx_sop,
    output wire         dll_tx_eop,
    output wire [3:0]   dll_tx_error,
    output wire [1:0]   dll_tx_type,
    output wire [11:0]  dll_tx_data_credits,

    input  wire         core_release_valid,
    output wire         core_release_ready,
    input  wire [1:0]   core_release_type,
    input  wire [11:0]  core_release_data_credits,
    output wire         dll_release_valid,
    input  wire         dll_release_ready,
    output wire [1:0]   dll_release_type,
    output wire [11:0]  dll_release_data_credits,

    output wire         rx_overflow,
    output wire         rx_underflow,
    output wire         tx_overflow,
    output wire         tx_underflow,
    output wire         metadata_overflow,
    output wire         metadata_underflow,
    output wire         release_overflow,
    output wire         release_underflow
);
    wire [PKT_LGFIFO:0] rx_s_count_unused, rx_m_count_unused;
    wire [PKT_LGFIFO:0] tx_s_count_unused, tx_m_count_unused;
    wire tx_pkt_s_ready;
    wire tx_pkt_m_valid;
    wire tx_pkt_m_ready;
    wire [127:0] tx_pkt_m_data;
    wire [15:0] tx_pkt_m_keep;
    wire tx_pkt_m_sop, tx_pkt_m_eop;
    wire [3:0] tx_pkt_m_error;

    pcie_async_pkt_fifo #(.LGFIFO(PKT_LGFIFO)) u_rx_pkt_fifo (
        .s_clk(pipe_clk), .s_rst_n(pipe_rst_n),
        .s_valid(dll_rx_valid), .s_ready(dll_rx_ready),
        .s_data(dll_rx_data), .s_keep(dll_rx_keep),
        .s_sop(dll_rx_sop), .s_eop(dll_rx_eop), .s_error(dll_rx_error),
        .s_packet_count(rx_s_count_unused), .s_overflow(rx_overflow),
        .m_clk(core_clk), .m_rst_n(core_rst_n),
        .m_valid(core_rx_valid), .m_ready(core_rx_ready),
        .m_data(core_rx_data), .m_keep(core_rx_keep),
        .m_sop(core_rx_sop), .m_eop(core_rx_eop), .m_error(core_rx_error),
        .m_packet_count(rx_m_count_unused), .m_underflow(rx_underflow),
        .flush(1'b0)
    );

    wire metadata_s_ready;
    wire metadata_m_valid;
    wire metadata_m_ready;
    wire [13:0] metadata_m_data;
    wire tx_source_can_advance = tx_pkt_s_ready &&
                                 (!core_tx_sop || metadata_s_ready);
    assign core_tx_ready = tx_source_can_advance;

    pcie_async_pkt_fifo #(.LGFIFO(PKT_LGFIFO)) u_tx_pkt_fifo (
        .s_clk(core_clk), .s_rst_n(core_rst_n),
        .s_valid(core_tx_valid && (!core_tx_sop || metadata_s_ready)),
        .s_ready(tx_pkt_s_ready), .s_data(core_tx_data), .s_keep(core_tx_keep),
        .s_sop(core_tx_sop), .s_eop(core_tx_eop), .s_error(core_tx_error),
        .s_packet_count(tx_s_count_unused), .s_overflow(tx_overflow),
        .m_clk(pipe_clk), .m_rst_n(pipe_rst_n),
        .m_valid(tx_pkt_m_valid), .m_ready(tx_pkt_m_ready),
        .m_data(tx_pkt_m_data), .m_keep(tx_pkt_m_keep),
        .m_sop(tx_pkt_m_sop), .m_eop(tx_pkt_m_eop), .m_error(tx_pkt_m_error),
        .m_packet_count(tx_m_count_unused), .m_underflow(tx_underflow),
        .flush(1'b0)
    );

    pcie_async_event_fifo #(
        .WIDTH(14), .LGFIFO(EVENT_LGFIFO)
    ) u_tx_metadata_fifo (
        .s_clk(core_clk), .s_rst_n(core_rst_n),
        .s_valid(core_tx_valid && core_tx_ready && core_tx_sop),
        .s_ready(metadata_s_ready),
        .s_data({core_tx_type, core_tx_data_credits}),
        .s_overflow(metadata_overflow),
        .m_clk(pipe_clk), .m_rst_n(pipe_rst_n),
        .m_valid(metadata_m_valid), .m_ready(metadata_m_ready),
        .m_data(metadata_m_data), .m_underflow(metadata_underflow)
    );

    assign dll_tx_valid = tx_pkt_m_valid && metadata_m_valid;
    assign tx_pkt_m_ready = dll_tx_ready && metadata_m_valid;
    assign metadata_m_ready = dll_tx_valid && dll_tx_ready && tx_pkt_m_eop;
    assign dll_tx_data = tx_pkt_m_data;
    assign dll_tx_keep = tx_pkt_m_keep;
    assign dll_tx_sop = tx_pkt_m_sop;
    assign dll_tx_eop = tx_pkt_m_eop;
    assign dll_tx_error = tx_pkt_m_error;
    assign {dll_tx_type, dll_tx_data_credits} = metadata_m_data;

    pcie_async_event_fifo #(
        .WIDTH(14), .LGFIFO(EVENT_LGFIFO)
    ) u_release_fifo (
        .s_clk(core_clk), .s_rst_n(core_rst_n),
        .s_valid(core_release_valid), .s_ready(core_release_ready),
        .s_data({core_release_type, core_release_data_credits}),
        .s_overflow(release_overflow),
        .m_clk(pipe_clk), .m_rst_n(pipe_rst_n),
        .m_valid(dll_release_valid), .m_ready(dll_release_ready),
        .m_data({dll_release_type, dll_release_data_credits}),
        .m_underflow(release_underflow)
    );

    wire _unused = &{1'b0, rx_s_count_unused, rx_m_count_unused,
                     tx_s_count_unused, tx_m_count_unused};
endmodule

`default_nettype wire
