`timescale 1ns/1ps
`default_nettype none

module pcie_crc32_lcrc (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [31:0] data,
    input  wire [3:0]  keep,
    input  wire        last,
    input  wire        valid,
    output wire        ready,
    output wire [31:0] crc_result,
    output wire        crc_valid,
    output wire        crc_match,
    output wire        protocol_error,
    output wire        busy
);
    pcie_crc_stream #(
        .CRC_WIDTH     (32),
        .POLY          (32'hEDB88320),
        .INITIAL_VALUE (32'hFFFFFFFF),
        .CHECK_RESIDUE (32'hDEBB20E3)
    ) u_crc_stream (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (start),
        .data           (data),
        .keep           (keep),
        .last           (last),
        .valid          (valid),
        .ready          (ready),
        .crc_result     (crc_result),
        .crc_valid      (crc_valid),
        .crc_match      (crc_match),
        .protocol_error (protocol_error),
        .busy           (busy)
    );
endmodule

`default_nettype wire
