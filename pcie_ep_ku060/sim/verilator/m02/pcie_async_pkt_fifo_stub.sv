`timescale 1ns/1ps
`default_nettype none

// 故意错误的 Stub：首 Beat 一写入就对读侧可见，不等待 EOP。
module pcie_async_pkt_fifo #(
    parameter integer LGFIFO = 9,
    parameter integer AFIFO_NFF = 2,
    parameter integer RESET_SYNC_STAGES = 2
) (
    input  wire s_clk,
    input  wire s_rst_n,
    input  wire s_valid,
    output wire s_ready,
    input  wire [127:0] s_data,
    input  wire [15:0] s_keep,
    input  wire s_sop,
    input  wire s_eop,
    input  wire [3:0] s_error,
    output wire [LGFIFO:0] s_packet_count,
    output wire s_overflow,
    input  wire m_clk,
    input  wire m_rst_n,
    output wire m_valid,
    input  wire m_ready,
    output wire [127:0] m_data,
    output wire [15:0] m_keep,
    output wire m_sop,
    output wire m_eop,
    output wire [3:0] m_error,
    output wire [LGFIFO:0] m_packet_count,
    output wire m_underflow,
    input  wire flush
);

    logic have_beat;
    logic [149:0] beat_reg;

    always_ff @(posedge s_clk or negedge s_rst_n) begin
        if (!s_rst_n) begin
            have_beat <= 1'b0;
            beat_reg <= '0;
        end else if (flush) begin
            have_beat <= 1'b0;
        end else if (s_valid && s_ready && !have_beat) begin
            have_beat <= 1'b1;
            beat_reg <= {s_error, s_eop, s_sop, s_keep, s_data};
        end
    end

    assign s_ready = s_rst_n && m_rst_n && !flush;
    assign m_valid = have_beat && m_rst_n && !flush;
    assign {m_error, m_eop, m_sop, m_keep, m_data} = beat_reg;
    assign s_packet_count = '0;
    assign m_packet_count = '0;
    assign s_overflow = 1'b0;
    assign m_underflow = 1'b0;

endmodule

`default_nettype wire

