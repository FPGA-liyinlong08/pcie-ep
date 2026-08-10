`timescale 1ns/1ps
`default_nettype none

// 稀疏事件的toggle同步器；相邻源脉冲至少间隔两个目标时钟周期。
module pcie_cdc_pulse (
    input  wire s_clk,
    input  wire s_rst_n,
    input  wire s_pulse,
    input  wire d_clk,
    input  wire d_rst_n,
    output reg  d_pulse
);
    reg s_toggle;
    reg d_seen;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [1:0] d_sync;

    always @(posedge s_clk or negedge s_rst_n) begin
        if (!s_rst_n)
            s_toggle <= 1'b0;
        else if (s_pulse)
            s_toggle <= ~s_toggle;
    end

    always @(posedge d_clk or negedge d_rst_n) begin
        if (!d_rst_n) begin
            d_sync  <= 2'b00;
            d_seen  <= 1'b0;
            d_pulse <= 1'b0;
        end else begin
            d_sync  <= {d_sync[0], s_toggle};
            d_pulse <= d_sync[1] ^ d_seen;
            d_seen  <= d_sync[1];
        end
    end
endmodule

`default_nettype wire
