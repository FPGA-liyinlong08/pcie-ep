`timescale 1ns/1ps

module m02_async_pkt_fifo_tb;

    localparam integer LGFIFO = 4;

    logic s_clk = 1'b0;
    logic s_rst_n = 1'b0;
    logic s_valid = 1'b0;
    wire  s_ready;
    logic [127:0] s_data = '0;
    logic [15:0] s_keep = '0;
    logic s_sop = 1'b0;
    logic s_eop = 1'b0;
    logic [3:0] s_error = '0;
    wire [LGFIFO:0] s_packet_count;
    wire s_overflow;

    logic m_clk = 1'b0;
    logic m_rst_n = 1'b0;
    wire m_valid;
    logic m_ready = 1'b0;
    wire [127:0] m_data;
    wire [15:0] m_keep;
    wire m_sop;
    wire m_eop;
    wire [3:0] m_error;
    wire [LGFIFO:0] m_packet_count;
    wire m_underflow;
    logic flush = 1'b0;

    always #4 s_clk = ~s_clk;
    always #2 m_clk = ~m_clk;

    pcie_async_pkt_fifo #(
        .LGFIFO (LGFIFO)
    ) dut (
        .s_clk, .s_rst_n, .s_valid, .s_ready, .s_data, .s_keep,
        .s_sop, .s_eop, .s_error, .s_packet_count, .s_overflow,
        .m_clk, .m_rst_n, .m_valid, .m_ready, .m_data, .m_keep,
        .m_sop, .m_eop, .m_error, .m_packet_count, .m_underflow,
        .flush
    );

    task automatic send_beat(
        input integer index,
        input logic sop_value,
        input logic eop_value
    );
        begin
            @(negedge s_clk);
            s_valid = 1'b1;
            s_data = {96'h01234567_89abcdef_55aa55aa, index[31:0]};
            s_keep = eop_value ? 16'h01ff : 16'hffff;
            s_sop = sop_value;
            s_eop = eop_value;
            s_error = index[3:0];
            do @(posedge s_clk); while (!s_ready);
        end
    endtask

    task automatic stop_source;
        begin
            @(negedge s_clk);
            s_valid = 1'b0;
            s_sop = 1'b0;
            s_eop = 1'b0;
        end
    endtask

    task automatic expect_beat(
        input integer index,
        input logic sop_value,
        input logic eop_value
    );
        logic [127:0] expected_data;
        begin
            expected_data = {96'h01234567_89abcdef_55aa55aa, index[31:0]};
            do @(posedge m_clk); while (!(m_valid && m_ready));
            if (m_data !== expected_data) $fatal(1, "M02 VCS data mismatch beat=%0d", index);
            if (m_sop !== sop_value) $fatal(1, "M02 VCS SOP mismatch beat=%0d", index);
            if (m_eop !== eop_value) $fatal(1, "M02 VCS EOP mismatch beat=%0d", index);
            if (m_keep !== (eop_value ? 16'h01ff : 16'hffff))
                $fatal(1, "M02 VCS KEEP mismatch beat=%0d", index);
            if (m_error !== index[3:0]) $fatal(1, "M02 VCS ERROR mismatch beat=%0d", index);
        end
    endtask

    initial begin : watchdog
        #200000;
        $fatal(1, "M02 VCS timeout");
    end

    initial begin : test_sequence
        repeat (5) @(posedge s_clk);
        s_rst_n = 1'b1;
        m_rst_n = 1'b1;
        repeat (5) @(posedge s_clk);
        repeat (5) @(posedge m_clk);

        // 三个 Beat 已进入数据 FIFO，但没有 EOP 描述符，读侧必须不可见。
        send_beat(0, 1'b1, 1'b0);
        send_beat(1, 1'b0, 1'b0);
        send_beat(2, 1'b0, 1'b0);
        stop_source();
        repeat (20) begin
            @(posedge m_clk);
            if (m_valid) $fatal(1, "M02 VCS exposed incomplete packet");
        end

        send_beat(3, 1'b0, 1'b1);
        stop_source();
        wait (m_packet_count != 0);
        @(negedge m_clk);
        m_ready = 1'b1;
        expect_beat(0, 1'b1, 1'b0);
        expect_beat(1, 1'b0, 1'b0);
        expect_beat(2, 1'b0, 1'b0);
        expect_beat(3, 1'b0, 1'b1);
        @(negedge m_clk);
        m_ready = 1'b0;

        // 只复位读侧也必须共同清空两侧，包括未完成 Packet。
        send_beat(10, 1'b1, 1'b0);
        stop_source();
        #1.3;
        m_rst_n = 1'b0;
        #0.1;
        if (m_valid) $fatal(1, "M02 VCS reset did not hide data");
        #9;
        m_rst_n = 1'b1;
        repeat (5) @(posedge s_clk);
        repeat (5) @(posedge m_clk);

        // Flush 覆盖另一个中间 Beat。
        send_beat(20, 1'b1, 1'b0);
        stop_source();
        flush = 1'b1;
        #10;
        flush = 1'b0;
        repeat (5) @(posedge s_clk);
        repeat (5) @(posedge m_clk);

        send_beat(30, 1'b1, 1'b1);
        stop_source();
        wait (m_valid);
        @(negedge m_clk);
        m_ready = 1'b1;
        expect_beat(30, 1'b1, 1'b1);
        @(negedge m_clk);
        m_ready = 1'b0;

        repeat (8) @(posedge s_clk);
        repeat (8) @(posedge m_clk);
        if (s_packet_count !== 0 || m_packet_count !== 0)
            $fatal(1, "M02 VCS packet count did not drain");
        if (s_overflow || m_underflow)
            $fatal(1, "M02 VCS unexpected sticky error");

        $display("M02_VCS_PASS s_period_ns=8 m_period_ns=4");
        $finish;
    end

endmodule

