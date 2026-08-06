`timescale 1ns/1ps
`default_nettype none

// 故意错误：收到末拍后固定返回全 0 CRC。Checker 必须检出已知向量错误。
module k04_crc_test_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [31:0] data,
    input  wire [3:0]  keep,
    input  wire        last,
    input  wire        valid,
    output wire        ready16,
    output reg  [15:0] crc_result16,
    output reg         crc_valid16,
    output reg         crc_match16,
    output reg         protocol_error16,
    output reg         busy16,
    output wire        ready32,
    output reg  [31:0] crc_result32,
    output reg         crc_valid32,
    output reg         crc_match32,
    output reg         protocol_error32,
    output reg         busy32
);
    assign ready16 = rst_n;
    assign ready32 = rst_n;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_result16     <= 16'd0;
            crc_valid16      <= 1'b0;
            crc_match16      <= 1'b0;
            protocol_error16 <= 1'b0;
            busy16           <= 1'b0;
            crc_result32     <= 32'd0;
            crc_valid32      <= 1'b0;
            crc_match32      <= 1'b0;
            protocol_error32 <= 1'b0;
            busy32           <= 1'b0;
        end else begin
            crc_valid16      <= 1'b0;
            crc_valid32      <= 1'b0;
            protocol_error16 <= 1'b0;
            protocol_error32 <= 1'b0;
            if (valid) begin
                busy16 <= !last;
                busy32 <= !last;
                if (last) begin
                    crc_result16 <= 16'd0;
                    crc_result32 <= 32'd0;
                    crc_match16  <= 1'b0;
                    crc_match32  <= 1'b0;
                    crc_valid16  <= 1'b1;
                    crc_valid32  <= 1'b1;
                end
            end
        end
    end

    wire _unused = &{1'b0, start, data, keep};
endmodule

`default_nettype wire
