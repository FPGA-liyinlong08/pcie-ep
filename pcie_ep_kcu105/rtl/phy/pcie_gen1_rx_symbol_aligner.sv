`timescale 1ns/1ps
`default_nettype none

// GT 的 16-bit Gen1 接口允许 COM 出现在两个 Symbol 位置之一。上层统一要求
// Ordered Set/Packet delimiter 从低 Symbol 开始；当首次观察到高 Symbol COM 时，
// 用一字节寄存器把当前高 Symbol 与下一拍低 Symbol重组成一个输出拍。
module pcie_gen1_rx_symbol_aligner (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [15:0] in_data,
    input  wire [1:0]  in_datak,
    output wire        out_valid,
    output wire [15:0] out_data,
    output wire [1:0]  out_datak
);
    localparam [7:0] K_COM = 8'hbc;

    reg       shift_one_symbol;
    reg [7:0] saved_high_data;
    reg       saved_high_k;
    wire      high_com = in_datak[1] && (in_data[15:8] == K_COM) &&
                         !(in_datak[0] && (in_data[7:0] == K_COM));

    assign out_valid = in_valid && (shift_one_symbol || !high_com);
    assign out_data  = shift_one_symbol ? {in_data[7:0], saved_high_data} :
                                          in_data;
    assign out_datak = shift_one_symbol ? {in_datak[0], saved_high_k} :
                                          in_datak;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_one_symbol <= 1'b0;
            saved_high_data  <= 8'd0;
            saved_high_k     <= 1'b0;
        end else begin
            if (!in_valid) begin
                shift_one_symbol <= 1'b0;
                saved_high_data  <= 8'd0;
                saved_high_k     <= 1'b0;
            end else if (shift_one_symbol) begin
                saved_high_data <= in_data[15:8];
                saved_high_k    <= in_datak[1];
            end else if (high_com) begin
                shift_one_symbol <= 1'b1;
                saved_high_data  <= in_data[15:8];
                saved_high_k     <= in_datak[1];
            end
        end
    end
endmodule

`default_nettype wire
