`timescale 1ns/1ps
`default_nettype none

// 多位 Gray 编码状态同步器。调用方必须保证相邻源状态最多变化一位。
module pcie_gray_sync #(
    parameter integer WIDTH  = 4,
    parameter integer STAGES = 2
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire [WIDTH-1:0] async_gray,
    output wire [WIDTH-1:0] sync_gray
);

    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    logic [WIDTH-1:0] sync_reg [0:STAGES-1];
    integer index;

    generate
        if ((WIDTH < 1) || (STAGES < 2)) begin : g_invalid_parameters
            initial $error("pcie_gray_sync: WIDTH >= 1 and STAGES >= 2 required");
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (index = 0; index < STAGES; index = index + 1)
                sync_reg[index] <= '0;
        end else begin
            sync_reg[0] <= async_gray;
            for (index = 1; index < STAGES; index = index + 1)
                sync_reg[index] <= sync_reg[index-1];
        end
    end

    assign sync_gray = sync_reg[STAGES-1];

endmodule

`default_nettype wire

