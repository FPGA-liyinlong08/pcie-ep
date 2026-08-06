`timescale 1ns/1ps

module m00_smoke (
    input  logic       clk,
    input  logic       rst_n,
    output logic [7:0] count
);

    logic clk_int;

`ifdef XILINX_SIM
    BUFG u_bufg (
        .I(clk),
        .O(clk_int)
    );
`else
    assign clk_int = clk;
`endif

    always_ff @(posedge clk_int or negedge rst_n) begin
        if (!rst_n) begin
            count <= 8'h00;
        end else begin
            count <= count + 1'b1;
        end
    end

endmodule

