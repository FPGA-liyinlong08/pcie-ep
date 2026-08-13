`timescale 1ns/1ps
`default_nettype none

// K12-A：把Core域的Retrain脉冲和目标速率作为一个原子命令送入PHY域。
// 单深度request/ack mailbox；源域在ack返回前保持payload不变。
module pcie_retrain_cdc_mailbox (
    input  wire       s_clk,
    input  wire       s_rst_n,
    input  wire       s_retrain_pulse,
    input  wire [1:0] s_target_speed,
    output wire       s_busy,
    output reg        s_overflow_sticky,

    input  wire       d_clk,
    input  wire       d_rst_n,
    output reg        d_retrain_valid,
    output reg  [1:0] d_target_speed,
    input  wire       d_retrain_accept
);
    reg [1:0] s_payload;
    reg       s_request_toggle;
    reg       d_ack_toggle;

    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [1:0] s_ack_sync;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [1:0] d_request_sync;

    assign s_busy = s_request_toggle != s_ack_sync[1];

    // Source domain: accept only when the previous payload has been acknowledged.
    // A pulse while busy is not silently merged with the outstanding command.
    always @(posedge s_clk or negedge s_rst_n) begin
        if (!s_rst_n) begin
            s_payload         <= 2'b00;
            s_request_toggle  <= 1'b0;
            s_ack_sync        <= 2'b00;
            s_overflow_sticky <= 1'b0;
        end else begin
            s_ack_sync <= {s_ack_sync[0], d_ack_toggle};
            if (s_retrain_pulse) begin
                if (!s_busy) begin
                    s_payload        <= s_target_speed;
                    s_request_toggle <= ~s_request_toggle;
                end else begin
                    s_overflow_sticky <= 1'b1;
                end
            end
        end
    end

    // Destination domain: valid is level-based and remains asserted until the
    // Recovery controller accepts the complete command.
    always @(posedge d_clk or negedge d_rst_n) begin
        if (!d_rst_n) begin
            d_request_sync  <= 2'b00;
            d_ack_toggle    <= 1'b0;
            d_retrain_valid <= 1'b0;
            d_target_speed  <= 2'b00;
        end else begin
            d_request_sync <= {d_request_sync[0], s_request_toggle};
            if (d_retrain_valid) begin
                if (d_retrain_accept) begin
                    d_retrain_valid <= 1'b0;
                    d_ack_toggle    <= d_request_sync[1];
                end
            end else if (d_request_sync[1] != d_ack_toggle) begin
                // s_payload is stable from request toggle until ack returns.
                d_target_speed  <= s_payload;
                d_retrain_valid <= 1'b1;
            end
        end
    end
endmodule

`default_nettype wire
