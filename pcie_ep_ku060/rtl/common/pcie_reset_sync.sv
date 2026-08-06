`timescale 1ns/1ps
`default_nettype none

// 低有效复位同步器：异步置位，同步释放。
module pcie_reset_sync #(
    parameter integer STAGES = 4
) (
    input  wire clk,
    input  wire async_release_n,
    output wire sync_reset_n
);

    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    logic [STAGES-1:0] sync_reg = '0;

    generate
        if (STAGES < 2) begin : g_invalid_stages
            initial $error("pcie_reset_sync: STAGES must be at least 2");
        end
    endgenerate

    always_ff @(posedge clk or negedge async_release_n) begin
        if (!async_release_n) begin
            sync_reg <= '0;
        end else begin
            sync_reg <= {sync_reg[STAGES-2:0], 1'b1};
        end
    end

    assign sync_reset_n = sync_reg[STAGES-1];

endmodule

`default_nettype wire

