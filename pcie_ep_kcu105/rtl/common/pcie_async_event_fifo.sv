`timescale 1ns/1ps
`default_nettype none

// K11-A：小宽度事件/元数据异步FIFO。底层继续复用未修改的afifo.v。
module pcie_async_event_fifo #(
    parameter integer WIDTH = 16,
    parameter integer LGFIFO = 4,
    parameter integer AFIFO_NFF = 2
) (
    input  wire             s_clk,
    input  wire             s_rst_n,
    input  wire             s_valid,
    output wire             s_ready,
    input  wire [WIDTH-1:0] s_data,
    output reg              s_overflow,

    input  wire             m_clk,
    input  wire             m_rst_n,
    output wire             m_valid,
    input  wire             m_ready,
    output wire [WIDTH-1:0] m_data,
    output reg              m_underflow
);
    wire fifo_rst_n = s_rst_n && m_rst_n;
    wire wr_full;
    wire rd_empty;
    wire wr = s_valid && s_ready;
    wire rd = m_valid && m_ready;

    assign s_ready = fifo_rst_n && !wr_full;
    assign m_valid = fifo_rst_n && !rd_empty;

    afifo #(
        .LGFIFO(LGFIFO), .WIDTH(WIDTH), .NFF(AFIFO_NFF),
        .WRITE_ON_POSEDGE(1'b1), .OPT_REGISTER_READS(1'b1)
    ) u_afifo (
        .i_wclk(s_clk), .i_wr_reset_n(fifo_rst_n),
        .i_wr(wr), .i_wr_data(s_data), .o_wr_full(wr_full),
        .i_rclk(m_clk), .i_rd_reset_n(fifo_rst_n),
        .i_rd(rd), .o_rd_data(m_data), .o_rd_empty(rd_empty)
    );

    always @(posedge s_clk or negedge fifo_rst_n) begin
        if (!fifo_rst_n)
            s_overflow <= 1'b0;
        else if (s_valid && !s_ready)
            s_overflow <= 1'b1;
    end

    always @(posedge m_clk or negedge fifo_rst_n) begin
        if (!fifo_rst_n)
            m_underflow <= 1'b0;
        else if (rd && rd_empty)
            m_underflow <= 1'b1;
    end
endmodule

`default_nettype wire
