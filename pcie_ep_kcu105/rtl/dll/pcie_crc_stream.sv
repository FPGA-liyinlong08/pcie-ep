`timescale 1ns/1ps
`default_nettype none

// PCIe CRC 公共流式内核。POLY 使用右移/LSB-first 的反射表示。
module pcie_crc_stream #(
    parameter integer CRC_WIDTH = 32,
    parameter [CRC_WIDTH-1:0] POLY = 32'hEDB88320,
    parameter [CRC_WIDTH-1:0] INITIAL_VALUE = {CRC_WIDTH{1'b1}},
    parameter [CRC_WIDTH-1:0] CHECK_RESIDUE = 32'hDEBB20E3
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 start,
    input  wire [31:0]          data,
    input  wire [3:0]           keep,
    input  wire                 last,
    input  wire                 valid,
    output wire                 ready,
    output reg  [CRC_WIDTH-1:0] crc_result,
    output reg                  crc_valid,
    output reg                  crc_match,
    output reg                  protocol_error,
    output reg                  busy
);
    reg [CRC_WIDTH-1:0] crc_state;
    reg [CRC_WIDTH-1:0] accepted_crc;
    integer byte_index;

    function automatic [CRC_WIDTH-1:0] update_byte;
        input [CRC_WIDTH-1:0] crc_in;
        input [7:0] byte_in;
        integer bit_index;
        reg [CRC_WIDTH-1:0] value;
        begin
            value = crc_in;
            value[7:0] = value[7:0] ^ byte_in;
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                if (value[0])
                    value = (value >> 1) ^ POLY;
                else
                    value = value >> 1;
            end
            update_byte = value;
        end
    endfunction

    // Packet 首拍从 seed 开始；其余拍从寄存状态继续。keep 的有效 lane 按
    // 0→3 的线路 Byte 顺序串行展开。
    always @* begin
        accepted_crc = start ? INITIAL_VALUE : crc_state;
        for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1) begin
            if (keep[byte_index])
                accepted_crc = update_byte(accepted_crc,
                    data[byte_index*8 +: 8]);
        end
    end

    wire packet_position_ok = busy ? !start : start;
    wire keep_ok = (keep != 4'b0000) && (last || (keep == 4'b1111));
    wire transfer_ok = packet_position_ok && keep_ok;

    assign ready = rst_n;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_state      <= INITIAL_VALUE;
            crc_result     <= {CRC_WIDTH{1'b0}};
            crc_valid      <= 1'b0;
            crc_match      <= 1'b0;
            protocol_error <= 1'b0;
            busy           <= 1'b0;
        end else begin
            crc_valid      <= 1'b0;
            crc_match      <= 1'b0;
            protocol_error <= 1'b0;

            if (valid && ready) begin
                if (!transfer_ok) begin
                    crc_state      <= INITIAL_VALUE;
                    protocol_error <= 1'b1;
                    busy           <= 1'b0;
                end else if (last) begin
                    crc_state  <= INITIAL_VALUE;
                    crc_result <= ~accepted_crc;
                    crc_valid  <= 1'b1;
                    crc_match  <= (accepted_crc == CHECK_RESIDUE);
                    busy       <= 1'b0;
                end else begin
                    crc_state <= accepted_crc;
                    busy      <= 1'b1;
                end
            end
        end
    end
endmodule

`default_nettype wire
