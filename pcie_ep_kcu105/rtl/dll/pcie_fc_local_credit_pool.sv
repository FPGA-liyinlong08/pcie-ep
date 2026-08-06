`timescale 1ns/1ps
`default_nettype none

// 单个 P/NP/Cpl 本地接收信用池；UpdateFC 字段保存累计 allocated 值。
module pcie_fc_local_credit_pool #(
    parameter integer HEADER_CREDITS = 8,
    parameter integer DATA_CREDITS   = 32
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,
    input  wire        consume_valid,
    input  wire [11:0] consume_data_credits,
    input  wire        release_valid,
    input  wire [11:0] release_data_credits,
    output reg  [7:0]  header_occupied,
    output reg  [11:0] data_occupied,
    output reg  [7:0]  header_allocated,
    output reg  [11:0] data_allocated,
    output reg         event_error,
    output reg         release_accepted
);
    localparam [8:0] H_CAP = HEADER_CREDITS[8:0];
    localparam [12:0] D_CAP = DATA_CREDITS[12:0];

    wire [8:0] header_after_consume = {1'b0, header_occupied} +
        {{8{1'b0}}, consume_valid};
    wire [12:0] data_after_consume = {1'b0, data_occupied} +
        (consume_valid ? {1'b0, consume_data_credits} : 13'd0);
    wire header_release_ok = !release_valid || (header_after_consume >= 1);
    wire data_release_ok = !release_valid ||
        (data_after_consume >= {1'b0, release_data_credits});
    wire [8:0] header_next = header_after_consume -
        {{8{1'b0}}, release_valid};
    wire [12:0] data_next = data_after_consume -
        (release_valid ? {1'b0, release_data_credits} : 13'd0);
    wire event_legal = header_release_ok && data_release_ok &&
                       (header_next <= H_CAP) && (data_next <= D_CAP);

    generate
        if ((HEADER_CREDITS < 1) || (HEADER_CREDITS > 255)) begin : g_bad_h
            initial $error("pcie_fc_local_credit_pool: HEADER_CREDITS must be 1..255");
        end
        if ((DATA_CREDITS < 1) || (DATA_CREDITS > 4095)) begin : g_bad_d
            initial $error("pcie_fc_local_credit_pool: DATA_CREDITS must be 1..4095");
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            header_occupied <= 8'd0;
            data_occupied <= 12'd0;
            header_allocated <= HEADER_CREDITS[7:0];
            data_allocated <= DATA_CREDITS[11:0];
            event_error <= 1'b0;
            release_accepted <= 1'b0;
        end else begin
            event_error <= 1'b0;
            release_accepted <= 1'b0;
            if (clear) begin
                header_occupied <= 8'd0;
                data_occupied <= 12'd0;
                header_allocated <= HEADER_CREDITS[7:0];
                data_allocated <= DATA_CREDITS[11:0];
            end else if (consume_valid || release_valid) begin
                if (event_legal) begin
                    header_occupied <= header_next[7:0];
                    data_occupied <= data_next[11:0];
                    if (release_valid) begin
                        header_allocated <= header_allocated + 1'b1;
                        data_allocated <= data_allocated + release_data_credits;
                        release_accepted <= 1'b1;
                    end
                end else begin
                    event_error <= 1'b1;
                end
            end
        end
    end
endmodule

`default_nettype wire
