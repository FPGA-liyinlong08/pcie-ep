`timescale 1ns/1ps
`default_nettype none

// mode: 0=Logical Idle, 1=TS1, 2=TS2, 3=EIOS. Active ordered sets always
// finish on their natural boundary before a new non-idle mode is accepted.
module pcie_gen1_os_tx (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire [1:0]  mode,
    input  wire [7:0]  link_number,
    input  wire        link_is_pad,
    input  wire [7:0]  lane_number,
    input  wire        lane_is_pad,
    input  wire [7:0]  n_fts,
    input  wire [7:0]  rate_id,
    input  wire [7:0]  training_control,
    output reg  [31:0] out_data,
    output reg  [1:0]  out_datak,
    output reg         out_valid,
    output wire        os_complete,
    output wire        eios_complete,
    output wire [2:0]  word_index_debug,
    output wire [2:0]  active_word_index_debug
);
    localparam [7:0] K_COM  = 8'hbc;
    localparam [7:0] K_PAD  = 8'hf7;
    localparam [7:0] D_IDLE = 8'h00;
    localparam [7:0] D_TS1  = 8'h4a;
    localparam [7:0] D_TS2  = 8'h45;
    localparam [7:0] K_EIOS = 8'h7c;
    localparam [1:0] MODE_EIOS = 2'd3;

    reg [2:0] word_index;
    reg [1:0] previous_mode;

    // A mode request may arrive in the middle of a TS. Finish the active TS
    // before accepting TS1, TS2, or EIOS. EIOS itself is four Symbols/two
    // PHY16 beats and is never reported as an eight-beat TS completion.
    wire ordered_set_change = (mode != previous_mode) &&
                              (mode != 2'd0) && (previous_mode != 2'd0);
    wire [1:0] output_mode = ordered_set_change ? previous_mode : mode;
    wire [2:0] active_index = ((mode != previous_mode) &&
                               !ordered_set_change) ? 3'd0 : word_index;
    wire [2:0] final_index = (output_mode == MODE_EIOS) ? 3'd1 : 3'd7;
    wire [7:0] identifier = (output_mode == 2'd1) ? D_TS1 : D_TS2;

    assign os_complete = enable && ((output_mode == 2'd1) ||
                                    (output_mode == 2'd2)) &&
                         (word_index == 3'd7);
    assign eios_complete = enable && (output_mode == MODE_EIOS) &&
                           (word_index == 3'd1);
    assign word_index_debug = word_index;
    assign active_word_index_debug = active_index;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            word_index    <= 3'd0;
            previous_mode <= 2'd0;
        end else if (!enable || (mode == 2'd0)) begin
            word_index    <= 3'd0;
            previous_mode <= mode;
        end else if (ordered_set_change) begin
            if (word_index == final_index) begin
                previous_mode <= mode;
                word_index    <= 3'd0;
            end else begin
                word_index <= word_index + 1'b1;
            end
        end else if (mode != previous_mode) begin
            previous_mode <= mode;
            word_index    <= 3'd1;
        end else if (word_index == final_index) begin
            word_index <= 3'd0;
        end else begin
            word_index <= word_index + 1'b1;
        end
    end

    always @* begin
        out_data  = 32'd0;
        out_datak = 2'b00;
        out_valid = enable;
        if (!enable) begin
            out_valid = 1'b0;
        end else if (output_mode == 2'd0) begin
            out_data[15:0] = {D_IDLE, D_IDLE};
            out_datak      = 2'b00;
        end else if (output_mode == MODE_EIOS) begin
            // PCIe EIOS is COM followed by three K28.3 Symbols.
            out_data[15:0] = (active_index == 3'd0) ?
                              {K_EIOS, K_COM} : {K_EIOS, K_EIOS};
            out_datak = 2'b11;
        end else begin
            case (active_index)
                3'd0: begin
                    out_data[7:0]  = K_COM;
                    out_data[15:8] = link_is_pad ? K_PAD : link_number;
                    out_datak      = {link_is_pad, 1'b1};
                end
                3'd1: begin
                    out_data[7:0]  = lane_is_pad ? K_PAD : lane_number;
                    out_data[15:8] = n_fts;
                    out_datak      = {1'b0, lane_is_pad};
                end
                3'd2: begin
                    out_data[7:0]  = rate_id;
                    out_data[15:8] = training_control;
                end
                default: out_data[15:0] = {identifier, identifier};
            endcase
        end
    end
endmodule

`default_nettype wire
