`timescale 1ns/1ps
`default_nettype none

// K12-A负向Stub：故意把valid做成单拍，Checker必须检出。
module pcie_retrain_cdc_mailbox (
    input  wire       s_clk,
    input  wire       s_rst_n,
    input  wire       s_retrain_pulse,
    input  wire [1:0] s_target_speed,
    output wire       s_busy,
    output reg        s_overflow_sticky,
    input  wire       d_clk,
    input  wire       d_rst_n,
    output reg        d_retrain_valid,
    output reg  [1:0] d_target_speed,
    input  wire       d_retrain_accept
);
    reg request;
    reg d_seen;
    assign s_busy = 1'b0;
    always @(posedge s_clk or negedge s_rst_n) begin
        if (!s_rst_n) begin
            request <= 1'b0;
            s_overflow_sticky <= 1'b0;
        end else if (s_retrain_pulse) begin
            request <= ~request;
        end
    end
    always @(posedge d_clk or negedge d_rst_n) begin
        if (!d_rst_n) begin
            d_retrain_valid <= 1'b0;
            d_target_speed <= 2'b00;
            d_seen <= 1'b0;
        end else begin
            d_retrain_valid <= request ^ d_seen;
            d_seen <= request;
            if (request ^ d_seen)
                d_target_speed <= s_target_speed;
        end
    end
endmodule

`default_nettype wire
