`timescale 1ns/1ps
`default_nettype none

module pcie_dll_mac_tx_arbiter (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,

    input  wire        dllp_valid,
    output wire        dllp_ready,
    input  wire [15:0] dllp_data,
    input  wire [1:0]  dllp_keep,
    input  wire        dllp_sop,
    input  wire        dllp_eop,
    input  wire        dllp_bad,

    input  wire        tlp_valid,
    output wire        tlp_ready,
    input  wire [15:0] tlp_data,
    input  wire [1:0]  tlp_keep,
    input  wire        tlp_sop,
    input  wire        tlp_eop,
    input  wire        tlp_bad,

    output reg         out_valid,
    input  wire        out_ready,
    output reg  [15:0] out_data,
    output reg  [1:0]  out_keep,
    output reg         out_sop,
    output reg         out_eop,
    output reg         out_is_dllp,
    output reg         out_bad
);
    localparam [1:0] SEL_IDLE = 2'd0;
    localparam [1:0] SEL_DLLP = 2'd1;
    localparam [1:0] SEL_TLP = 2'd2;
    reg [1:0] selection;

    wire choose_dllp = (selection == SEL_DLLP) ||
                       ((selection == SEL_IDLE) && dllp_valid);
    wire choose_tlp = (selection == SEL_TLP) ||
                      ((selection == SEL_IDLE) && !dllp_valid && tlp_valid);

    assign dllp_ready = enable && choose_dllp && out_ready;
    assign tlp_ready = enable && choose_tlp && out_ready;

    always @* begin
        out_valid = 1'b0;
        out_data = 16'd0;
        out_keep = 2'b00;
        out_sop = 1'b0;
        out_eop = 1'b0;
        out_is_dllp = 1'b0;
        out_bad = 1'b0;
        if (enable && choose_dllp) begin
            out_valid = dllp_valid;
            out_data = dllp_data;
            out_keep = dllp_keep;
            out_sop = dllp_sop;
            out_eop = dllp_eop;
            out_is_dllp = 1'b1;
            out_bad = dllp_bad;
        end else if (enable && choose_tlp) begin
            out_valid = tlp_valid;
            out_data = tlp_data;
            out_keep = tlp_keep;
            out_sop = tlp_sop;
            out_eop = tlp_eop;
            out_is_dllp = 1'b0;
            out_bad = tlp_bad;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            selection <= SEL_IDLE;
        end else if (!enable) begin
            selection <= SEL_IDLE;
        end else if (out_valid && out_ready) begin
            if (out_eop)
                selection <= SEL_IDLE;
            else if (selection == SEL_IDLE)
                selection <= choose_dllp ? SEL_DLLP : SEL_TLP;
        end
    end
endmodule

`default_nettype wire
