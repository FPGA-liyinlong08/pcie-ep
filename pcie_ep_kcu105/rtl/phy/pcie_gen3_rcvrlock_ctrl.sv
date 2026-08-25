`timescale 1ns/1ps
`default_nettype none

// Phase E2 semantic Recovery.RcvrLock gate. This block consumes only decoded
// Gen3 block/Ordered-Set events; it never observes or drives raw PHY commands.
module pcie_gen3_rcvrlock_ctrl #(
    parameter [4:0] TS_REQUIRED = 5'd8
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       enable,
    input  wire       block_locked,
    input  wire       lock_lost,
    input  wire       ts1_valid,
    input  wire       ts1_fields_match,
    input  wire       ts2_valid,
    input  wire       malformed,
    output reg        complete,
    output reg        failed,
    output reg  [4:0] ts1_count
);
    localparam [4:0] REQUIRED_COUNT =
        (TS_REQUIRED == 5'd0) ? 5'd1 : TS_REQUIRED;
    localparam [4:0] REQUIRED_MINUS_ONE = REQUIRED_COUNT - 1'b1;
    reg terminal_hold;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            complete <= 1'b0;
            failed <= 1'b0;
            ts1_count <= 5'd0;
            terminal_hold <= 1'b0;
        end else begin
            complete <= 1'b0;
            failed <= 1'b0;
            if (!enable) begin
                ts1_count <= 5'd0;
                terminal_hold <= 1'b0;
            end else if (!terminal_hold) begin
                if (lock_lost || malformed || ts2_valid) begin
                    failed <= 1'b1;
                    ts1_count <= 5'd0;
                    terminal_hold <= 1'b1;
                end else if (!block_locked) begin
                    // TS pulses are structurally impossible before EIEOS in
                    // the E1 parser, but remain non-consumable at this gate.
                    ts1_count <= 5'd0;
                end else if (ts1_valid) begin
                    if (!ts1_fields_match) begin
                        failed <= 1'b1;
                        ts1_count <= 5'd0;
                        terminal_hold <= 1'b1;
                    end else if (ts1_count == REQUIRED_MINUS_ONE) begin
                        complete <= 1'b1;
                        ts1_count <= 5'd0;
                        terminal_hold <= 1'b1;
                    end else begin
                        ts1_count <= ts1_count + 1'b1;
                    end
                end
            end
        end
    end
endmodule

`default_nettype wire
