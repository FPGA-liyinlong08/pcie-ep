`timescale 1ns/1ps
`default_nettype none

// 128-bit Packet Stream 异步 FIFO。
// 底层数据和描述符 CDC 直接复用未修改的 WB2AXIP afifo.v。
module pcie_async_pkt_fifo #(
    parameter integer LGFIFO           = 9,
    parameter integer AFIFO_NFF        = 2,
    parameter integer RESET_SYNC_STAGES = 2
) (
    input  wire         s_clk,
    input  wire         s_rst_n,
    input  wire         s_valid,
    output wire         s_ready,
    input  wire [127:0] s_data,
    input  wire [15:0]  s_keep,
    input  wire         s_sop,
    input  wire         s_eop,
    input  wire [3:0]   s_error,
    output wire [LGFIFO:0] s_packet_count,
    output logic        s_overflow,

    input  wire         m_clk,
    input  wire         m_rst_n,
    output wire         m_valid,
    input  wire         m_ready,
    output wire [127:0] m_data,
    output wire [15:0]  m_keep,
    output wire         m_sop,
    output wire         m_eop,
    output wire [3:0]   m_error,
    output wire [LGFIFO:0] m_packet_count,
    output logic        m_underflow,

    input  wire         flush
);

    localparam integer BEAT_WIDTH  = 150;
    localparam integer COUNT_WIDTH = LGFIFO + 1;
    localparam logic [COUNT_WIDTH-1:0] FIFO_DEPTH_COUNT = (1 << LGFIFO);

    wire fifo_async_release_n;
    wire s_fifo_rst_n;
    wire m_fifo_rst_n;

    wire [BEAT_WIDTH-1:0] s_packed_beat;
    wire [BEAT_WIDTH-1:0] data_rd_beat;
    wire data_wr_full;
    wire data_rd_empty;
    wire data_wr;
    wire data_rd;

    wire [COUNT_WIDTH-1:0] descriptor_wr_data;
    wire [COUNT_WIDTH-1:0] descriptor_rd_data;
    wire descriptor_wr_full;
    wire descriptor_rd_empty;
    wire descriptor_wr;
    wire descriptor_rd;

    logic s_in_packet;
    logic [COUNT_WIDTH-1:0] s_beat_count;
    wire packet_length_block;

    logic m_in_packet;
    logic [COUNT_WIDTH-1:0] m_beats_remaining;

    logic s_stalled;
    logic [BEAT_WIDTH-1:0] s_stalled_beat;

    logic [COUNT_WIDTH-1:0] commit_count_bin;
    logic [COUNT_WIDTH-1:0] commit_count_gray;
    logic [COUNT_WIDTH-1:0] claim_count_bin;
    logic [COUNT_WIDTH-1:0] claim_count_gray;
    wire [COUNT_WIDTH-1:0] commit_count_gray_m;
    wire [COUNT_WIDTH-1:0] claim_count_gray_s;
    wire [COUNT_WIDTH-1:0] commit_count_bin_m;
    wire [COUNT_WIDTH-1:0] claim_count_bin_s;

    function automatic [COUNT_WIDTH-1:0] bin_to_gray(
        input [COUNT_WIDTH-1:0] binary_value
    );
        bin_to_gray = (binary_value >> 1) ^ binary_value;
    endfunction

    function automatic [COUNT_WIDTH-1:0] gray_to_bin(
        input [COUNT_WIDTH-1:0] gray_value
    );
        integer bit_index;
        begin
            gray_to_bin[COUNT_WIDTH-1] = gray_value[COUNT_WIDTH-1];
            for (bit_index = COUNT_WIDTH-2; bit_index >= 0; bit_index = bit_index - 1)
                gray_to_bin[bit_index] = gray_to_bin[bit_index+1] ^ gray_value[bit_index];
        end
    endfunction

    generate
        if ((LGFIFO < 4) || (LGFIFO > 10)) begin : g_invalid_lgfifo
            initial $error("pcie_async_pkt_fifo: LGFIFO must be in range 4..10");
        end
        if ((AFIFO_NFF < 2) || (AFIFO_NFF > 4)) begin : g_invalid_afifo_nff
            initial $error("pcie_async_pkt_fifo: AFIFO_NFF must be in range 2..4");
        end
        if ((RESET_SYNC_STAGES < 2) || (RESET_SYNC_STAGES > 4)) begin : g_invalid_reset_stages
            initial $error("pcie_async_pkt_fifo: RESET_SYNC_STAGES must be in range 2..4");
        end
    endgenerate

    // 任一侧复位或公共 Flush 都异步清空两个 afifo；释放分别同步到本地时钟。
    assign fifo_async_release_n = s_rst_n && m_rst_n && !flush;

    pcie_reset_sync #(
        .STAGES (RESET_SYNC_STAGES)
    ) u_s_reset_sync (
        .clk             (s_clk),
        .async_release_n (fifo_async_release_n),
        .sync_reset_n    (s_fifo_rst_n)
    );

    pcie_reset_sync #(
        .STAGES (RESET_SYNC_STAGES)
    ) u_m_reset_sync (
        .clk             (m_clk),
        .async_release_n (fifo_async_release_n),
        .sync_reset_n    (m_fifo_rst_n)
    );

    assign s_packed_beat = {s_error, s_eop, s_sop, s_keep, s_data};
    assign packet_length_block = s_in_packet
                               && (s_beat_count == FIFO_DEPTH_COUNT - 1'b1)
                               && !s_eop;

    // EOP 只有在数据和描述符两者都有空间时才允许握手。
    assign s_ready = s_fifo_rst_n
                   && !data_wr_full
                   && (!s_eop || !descriptor_wr_full)
                   && !packet_length_block;
    assign data_wr = s_valid && s_ready;
    assign descriptor_wr = data_wr && s_eop;
    assign descriptor_wr_data = s_in_packet ? (s_beat_count + 1'b1)
                                             : {{(COUNT_WIDTH-1){1'b0}}, 1'b1};

    afifo #(
        .LGFIFO             (LGFIFO),
        .WIDTH              (BEAT_WIDTH),
        .NFF                (AFIFO_NFF),
        .WRITE_ON_POSEDGE   (1'b1),
        .OPT_REGISTER_READS (1'b1)
    ) u_data_afifo (
        .i_wclk      (s_clk),
        .i_wr_reset_n(s_fifo_rst_n),
        .i_wr        (data_wr),
        .i_wr_data   (s_packed_beat),
        .o_wr_full   (data_wr_full),
        .i_rclk      (m_clk),
        .i_rd_reset_n(m_fifo_rst_n),
        .i_rd        (data_rd),
        .o_rd_data   (data_rd_beat),
        .o_rd_empty  (data_rd_empty)
    );

    afifo #(
        .LGFIFO             (LGFIFO),
        .WIDTH              (COUNT_WIDTH),
        .NFF                (AFIFO_NFF),
        .WRITE_ON_POSEDGE   (1'b1),
        .OPT_REGISTER_READS (1'b1)
    ) u_descriptor_afifo (
        .i_wclk      (s_clk),
        .i_wr_reset_n(s_fifo_rst_n),
        .i_wr        (descriptor_wr),
        .i_wr_data   (descriptor_wr_data),
        .o_wr_full   (descriptor_wr_full),
        .i_rclk      (m_clk),
        .i_rd_reset_n(m_fifo_rst_n),
        .i_rd        (descriptor_rd),
        .o_rd_data   (descriptor_rd_data),
        .o_rd_empty  (descriptor_rd_empty)
    );

    // 写侧 Packet 边界和 Sticky Overflow/协议错误。
    always_ff @(posedge s_clk or negedge s_fifo_rst_n) begin
        if (!s_fifo_rst_n) begin
            s_in_packet   <= 1'b0;
            s_beat_count  <= '0;
            s_overflow    <= 1'b0;
            s_stalled     <= 1'b0;
            s_stalled_beat <= '0;
        end else begin
            if (s_stalled) begin
                if (!s_valid || (s_packed_beat != s_stalled_beat))
                    s_overflow <= 1'b1;
                if (s_valid && s_ready)
                    s_stalled <= 1'b0;
            end else if (s_valid && !s_ready) begin
                s_stalled <= 1'b1;
                s_stalled_beat <= s_packed_beat;
            end

            if (s_valid && packet_length_block)
                s_overflow <= 1'b1;
            if ((data_wr && data_wr_full) || (descriptor_wr && descriptor_wr_full))
                s_overflow <= 1'b1;

            if (data_wr) begin
                if (!s_in_packet) begin
                    if (!s_sop)
                        s_overflow <= 1'b1;
                    if (s_eop) begin
                        s_in_packet  <= 1'b0;
                        s_beat_count <= '0;
                    end else begin
                        if (s_keep != 16'hffff)
                            s_overflow <= 1'b1;
                        s_in_packet  <= 1'b1;
                        s_beat_count <= {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
                    end
                end else begin
                    if (s_sop)
                        s_overflow <= 1'b1;
                    if (s_eop) begin
                        if (s_keep == 16'h0000)
                            s_overflow <= 1'b1;
                        s_in_packet  <= 1'b0;
                        s_beat_count <= '0;
                    end else begin
                        if (s_keep != 16'hffff)
                            s_overflow <= 1'b1;
                        s_beat_count <= s_beat_count + 1'b1;
                    end
                end
            end
        end
    end

    // 只有描述符可用时才能开始一个 Packet；包内由已 Claim 的长度继续门控。
    assign m_valid = m_fifo_rst_n
                   && !data_rd_empty
                   && (m_in_packet || !descriptor_rd_empty);
    assign data_rd = m_valid && m_ready;
    assign descriptor_rd = data_rd && !m_in_packet;
    assign {m_error, m_eop, m_sop, m_keep, m_data} = data_rd_beat;

    always_ff @(posedge m_clk or negedge m_fifo_rst_n) begin
        if (!m_fifo_rst_n) begin
            m_in_packet      <= 1'b0;
            m_beats_remaining <= '0;
            m_underflow      <= 1'b0;
        end else begin
            if (m_in_packet && data_rd_empty)
                m_underflow <= 1'b1;
            if ((data_rd && data_rd_empty) || (descriptor_rd && descriptor_rd_empty))
                m_underflow <= 1'b1;

            if (data_rd) begin
                if (!m_in_packet) begin
                    if (!m_sop || (descriptor_rd_data == '0))
                        m_underflow <= 1'b1;

                    if (descriptor_rd_data <= 1) begin
                        if (!m_eop)
                            m_underflow <= 1'b1;
                        m_in_packet       <= 1'b0;
                        m_beats_remaining <= '0;
                    end else begin
                        if (m_eop)
                            m_underflow <= 1'b1;
                        m_in_packet       <= 1'b1;
                        m_beats_remaining <= descriptor_rd_data - 1'b1;
                    end
                end else if (m_beats_remaining <= 1) begin
                    if (!m_eop)
                        m_underflow <= 1'b1;
                    m_in_packet       <= 1'b0;
                    m_beats_remaining <= '0;
                end else begin
                    if (m_eop) begin
                        m_underflow      <= 1'b1;
                        m_in_packet       <= 1'b0;
                        m_beats_remaining <= '0;
                    end else begin
                        m_beats_remaining <= m_beats_remaining - 1'b1;
                    end
                end
            end
        end
    end

    // Commit/Claim Gray 计数仅用于状态显示，不参与数据流控。
    always_ff @(posedge s_clk or negedge s_fifo_rst_n) begin
        if (!s_fifo_rst_n) begin
            commit_count_bin  <= '0;
            commit_count_gray <= '0;
        end else if (descriptor_wr) begin
            commit_count_bin  <= commit_count_bin + 1'b1;
            commit_count_gray <= bin_to_gray(commit_count_bin + 1'b1);
        end
    end

    always_ff @(posedge m_clk or negedge m_fifo_rst_n) begin
        if (!m_fifo_rst_n) begin
            claim_count_bin  <= '0;
            claim_count_gray <= '0;
        end else if (descriptor_rd) begin
            claim_count_bin  <= claim_count_bin + 1'b1;
            claim_count_gray <= bin_to_gray(claim_count_bin + 1'b1);
        end
    end

    pcie_gray_sync #(
        .WIDTH  (COUNT_WIDTH),
        .STAGES (AFIFO_NFF)
    ) u_commit_count_sync (
        .clk        (m_clk),
        .rst_n      (m_fifo_rst_n),
        .async_gray (commit_count_gray),
        .sync_gray  (commit_count_gray_m)
    );

    pcie_gray_sync #(
        .WIDTH  (COUNT_WIDTH),
        .STAGES (AFIFO_NFF)
    ) u_claim_count_sync (
        .clk        (s_clk),
        .rst_n      (s_fifo_rst_n),
        .async_gray (claim_count_gray),
        .sync_gray  (claim_count_gray_s)
    );

    assign commit_count_bin_m = gray_to_bin(commit_count_gray_m);
    assign claim_count_bin_s  = gray_to_bin(claim_count_gray_s);
    assign s_packet_count = commit_count_bin - claim_count_bin_s;
    assign m_packet_count = commit_count_bin_m - claim_count_bin;

endmodule

`default_nettype wire

