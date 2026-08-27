`timescale 1ns/1ps
`default_nettype none

// Converts a qualified partner speed-change request into a reliable semantic
// valid/accept transaction.  Repeated TS1 ordered sets from one Recovery
// transaction are suppressed until the caller observes a protocol rearm
// boundary (or reset/PERST).
module pcie_partner_retrain_pending (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       request_valid,
    input  wire [1:0] request_target,
    input  wire       rearm,
    input  wire       accept,
    output reg        pending,
    output reg  [1:0] pending_target,
    output reg        armed
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending        <= 1'b0;
            pending_target <= 2'b00;
            armed          <= 1'b1;
        end else begin
            if (rearm && !pending)
                armed <= 1'b1;

            if (pending) begin
                if (accept) begin
                    pending <= 1'b0;
                    armed   <= 1'b0;
                end
            end else if (armed && request_valid) begin
                pending        <= 1'b1;
                pending_target <= request_target;
            end
        end
    end
endmodule

`default_nettype wire
