`timescale 1ns/1ps
`default_nettype none

// 单比特异步状态同步器。rst_n 属于目标时钟域。
module pcie_bit_sync #(
    parameter integer STAGES = 2
) (
    input  wire clk,
    input  wire rst_n,
    input  wire async_in,
    output wire sync_out
);

    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    logic [STAGES-1:0] sync_reg = '0;

    generate
        if (STAGES < 2) begin : g_invalid_stages
            initial $error("pcie_bit_sync: STAGES must be at least 2");
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_reg <= '0;
        end else begin
            sync_reg <= {sync_reg[STAGES-2:0], async_in};
        end
    end

    assign sync_out = sync_reg[STAGES-1];

endmodule

`default_nettype wire

