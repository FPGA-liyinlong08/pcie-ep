`timescale 1ns/1ps

module m00_smoke_tb;

    logic       clk = 1'b0;
    logic       rst_n = 1'b0;
    logic [7:0] count;

    m00_smoke dut (
        .clk   (clk),
        .rst_n (rst_n),
        .count (count)
    );

    always #5 clk = ~clk;

    initial begin
        repeat (3) @(posedge clk);
        if (count !== 8'h00) $fatal(1, "reset value mismatch: %0h", count);

        @(negedge clk);
        rst_n = 1'b1;
        repeat (32) @(posedge clk);
        #1;
        if (count !== 8'd32) $fatal(1, "counter mismatch: %0d", count);

        rst_n = 1'b0;
        #1;
        if (count !== 8'h00) $fatal(1, "asynchronous reset mismatch: %0h", count);

        $display("M00_VCS_PASS count=%0d", count);
        $finish;
    end

endmodule
