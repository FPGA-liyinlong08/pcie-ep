`timescale 1ns/1ps
`default_nettype none

// 多位低频状态的原子快照CDC。源域在一次传输期间保持s_hold不变，
// 目标域看到已同步的请求翻转后再采样，避免计数器撕裂。
module pcie_cdc_snapshot #(
    parameter integer WIDTH = 1
) (
    input  wire             s_clk,
    input  wire             s_rst_n,
    input  wire [WIDTH-1:0] s_data,
    input  wire             d_clk,
    input  wire             d_rst_n,
    output reg  [WIDTH-1:0] d_data,
    output reg              d_valid
);
    reg [WIDTH-1:0] s_hold;
    reg s_request;
    reg d_acknowledge;

    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [1:0] s_ack_sync;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [1:0] d_request_sync;

    always @(posedge s_clk or negedge s_rst_n) begin
        if (!s_rst_n) begin
            s_hold     <= {WIDTH{1'b0}};
            s_request  <= 1'b0;
            s_ack_sync <= 2'b00;
        end else begin
            s_ack_sync <= {s_ack_sync[0], d_acknowledge};
            if ((s_ack_sync[1] == s_request) && (s_data != s_hold)) begin
                s_hold    <= s_data;
                s_request <= ~s_request;
            end
        end
    end

    always @(posedge d_clk or negedge d_rst_n) begin
        if (!d_rst_n) begin
            d_request_sync <= 2'b00;
            d_acknowledge  <= 1'b0;
            d_data         <= {WIDTH{1'b0}};
            d_valid        <= 1'b0;
        end else begin
            d_request_sync <= {d_request_sync[0], s_request};
            d_valid <= 1'b0;
            if (d_request_sync[1] != d_acknowledge) begin
                d_data        <= s_hold;
                d_acknowledge <= d_request_sync[1];
                d_valid       <= 1'b1;
            end
        end
    end
endmodule

`default_nettype wire
