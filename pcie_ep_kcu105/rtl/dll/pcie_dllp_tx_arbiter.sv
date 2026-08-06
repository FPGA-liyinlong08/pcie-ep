`timescale 1ns/1ps
`default_nettype none

// Raw DLLP一次握手即传输完整4 Byte。ACK/NAK具有固定高优先级。
module pcie_dllp_tx_arbiter (
    input  wire        ack_valid,
    output wire        ack_ready,
    input  wire [31:0] ack_data,
    input  wire        fc_valid,
    output wire        fc_ready,
    input  wire [31:0] fc_data,
    output wire        out_valid,
    input  wire        out_ready,
    output wire [31:0] out_data
);
    assign out_valid = ack_valid || fc_valid;
    assign out_data = ack_valid ? ack_data : fc_data;
    assign ack_ready = out_ready && ack_valid;
    assign fc_ready = out_ready && !ack_valid && fc_valid;
endmodule

`default_nettype wire
