`timescale 1ns/1ps
`default_nettype none

// 仅用于 K04 KU040 OOC 资源和 250 MHz 时序签核。
module k04_crc_ooc_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [31:0] data,
    input  wire [3:0]  keep,
    input  wire        last,
    input  wire        valid,
    output wire        ready16,
    output wire [15:0] crc_result16,
    output wire        crc_valid16,
    output wire        crc_match16,
    output wire        protocol_error16,
    output wire        busy16,
    output wire        ready32,
    output wire [31:0] crc_result32,
    output wire        crc_valid32,
    output wire        crc_match32,
    output wire        protocol_error32,
    output wire        busy32
);
    wire crc_rst_n;

    // K01 规定各时钟域复位异步置位、同步释放。OOC 顶层保留同样的
    // 集成边界，避免把外部异步 PERST# 直接作为 CRC 状态机释放信号。
    pcie_reset_sync #(
        .STAGES(4)
    ) u_reset_sync (
        .clk(clk),
        .async_release_n(rst_n),
        .sync_reset_n(crc_rst_n)
    );

    pcie_crc16_dllp u_crc16 (
        .clk(clk), .rst_n(crc_rst_n), .start(start), .data(data), .keep(keep),
        .last(last), .valid(valid), .ready(ready16), .crc_result(crc_result16),
        .crc_valid(crc_valid16), .crc_match(crc_match16),
        .protocol_error(protocol_error16), .busy(busy16)
    );

    pcie_crc32_lcrc u_crc32 (
        .clk(clk), .rst_n(crc_rst_n), .start(start), .data(data), .keep(keep),
        .last(last), .valid(valid), .ready(ready32), .crc_result(crc_result32),
        .crc_valid(crc_valid32), .crc_match(crc_match32),
        .protocol_error(protocol_error32), .busy(busy32)
    );
endmodule

`default_nettype wire
