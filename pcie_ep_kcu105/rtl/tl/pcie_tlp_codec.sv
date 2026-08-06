`timescale 1ns/1ps
`default_nettype none

module pcie_tlp_codec (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         rx_tlp_valid,
    output wire         rx_tlp_ready,
    input  wire [127:0] rx_tlp_data,
    input  wire [15:0]  rx_tlp_keep,
    input  wire         rx_tlp_sop,
    input  wire         rx_tlp_eop,
    input  wire [3:0]   rx_tlp_error,

    output wire         tx_tlp_valid,
    input  wire         tx_tlp_ready,
    output wire [127:0] tx_tlp_data,
    output wire [15:0]  tx_tlp_keep,
    output wire         tx_tlp_sop,
    output wire         tx_tlp_eop,
    output wire [3:0]   tx_tlp_error,
    output wire [1:0]   tx_tlp_type,
    output wire [11:0]  tx_tlp_data_credits,

    output wire         rx_release_valid,
    input  wire         rx_release_ready,
    output wire [1:0]   rx_release_type,
    output wire [11:0]  rx_release_data_credits,

    input  wire [15:0]  local_completer_id,

    output wire         cfg_req_valid,
    input  wire         cfg_req_ready,
    output wire         cfg_req_write,
    output wire [9:0]   cfg_req_dw_addr,
    output wire [3:0]   cfg_req_be,
    output wire [31:0]  cfg_req_wdata,
    output wire [15:0]  cfg_req_requester_id,
    output wire [7:0]   cfg_req_tag,
    output wire [15:0]  cfg_req_target_bdf,
    input  wire         cfg_rsp_valid,
    output wire         cfg_rsp_ready,
    input  wire [2:0]   cfg_rsp_status,
    input  wire [31:0]  cfg_rsp_rdata,
    input  wire [15:0]  cfg_rsp_completer_id,

    output wire         mem_req_valid,
    input  wire         mem_req_ready,
    output wire         mem_req_write,
    output wire         mem_req_64bit,
    output wire         mem_req_poisoned,
    output wire [63:0]  mem_req_address,
    output wire [10:0]  mem_req_length_dw,
    output wire [3:0]   mem_req_first_be,
    output wire [3:0]   mem_req_last_be,
    output wire [15:0]  mem_req_requester_id,
    output wire [7:0]   mem_req_tag,
    output wire [2:0]   mem_req_tc,
    output wire [2:0]   mem_req_attr,
    output wire         mem_w_valid,
    input  wire         mem_w_ready,
    output wire [127:0] mem_w_data,
    output wire [15:0]  mem_w_keep,
    output wire         mem_w_last,

    output wire         rx_cpl_valid,
    input  wire         rx_cpl_ready,
    output wire         rx_cpl_has_data,
    output wire         rx_cpl_poisoned,
    output wire [2:0]   rx_cpl_status,
    output wire         rx_cpl_bcm,
    output wire [12:0]  rx_cpl_byte_count,
    output wire [15:0]  rx_cpl_completer_id,
    output wire [15:0]  rx_cpl_requester_id,
    output wire [7:0]   rx_cpl_tag,
    output wire [6:0]   rx_cpl_lower_address,
    output wire [5:0]   rx_cpl_length_dw,
    output wire [2:0]   rx_cpl_tc,
    output wire [2:0]   rx_cpl_attr,
    output wire         rx_cpl_data_valid,
    input  wire         rx_cpl_data_ready,
    output wire [127:0] rx_cpl_data,
    output wire [15:0]  rx_cpl_data_keep,
    output wire         rx_cpl_data_last,

    input  wire         cpl_req_valid,
    output wire         cpl_req_ready,
    input  wire         cpl_req_has_data,
    input  wire         cpl_req_poisoned,
    input  wire [2:0]   cpl_req_status,
    input  wire         cpl_req_bcm,
    input  wire [12:0]  cpl_req_byte_count,
    input  wire [15:0]  cpl_req_completer_id,
    input  wire [15:0]  cpl_req_requester_id,
    input  wire [7:0]   cpl_req_tag,
    input  wire [6:0]   cpl_req_lower_address,
    input  wire [5:0]   cpl_req_length_dw,
    input  wire [2:0]   cpl_req_tc,
    input  wire [2:0]   cpl_req_attr,
    input  wire         cpl_data_valid,
    output wire         cpl_data_ready,
    input  wire [127:0] cpl_data,
    input  wire [15:0]  cpl_data_keep,
    input  wire         cpl_data_last,

    output reg          malformed_pulse,
    output reg          unsupported_pulse,
    output reg          poisoned_pulse,
    output reg          unexpected_cpl_pulse,
    output reg  [7:0]   error_fmt_type,
    output reg  [15:0]  error_requester_id,
    output reg  [7:0]   error_tag,
    output reg  [31:0]  rx_packet_count,
    output reg  [31:0]  cfg_request_count,
    output reg  [31:0]  mem_request_count,
    output reg  [31:0]  rx_completion_count,
    output reg  [31:0]  tx_completion_count,
    output reg  [31:0]  ur_completion_count,
    output reg  [31:0]  malformed_count,
    output reg  [31:0]  unsupported_count,
    output reg  [31:0]  poisoned_count,
    output reg  [31:0]  unexpected_completion_count,
    output reg  [31:0]  tx_protocol_error_count
);
    function automatic [31:0] sat_inc32(input [31:0] value);
        sat_inc32 = (&value) ? value : value + 1'b1;
    endfunction

    function automatic [4:0] popcount16(input [15:0] value);
        integer n;
        begin
            popcount16 = 0;
            for (n = 0; n < 16; n = n + 1)
                popcount16 = popcount16 + {4'd0, value[n]};
        end
    endfunction

    function automatic keep_contiguous16(input [15:0] value);
        begin
            keep_contiguous16 = (value != 0) && ((value & (value + 1'b1)) == 0);
        end
    endfunction

    function automatic status_valid(input [2:0] status);
        begin
            status_valid = (status == 3'd0) || (status == 3'd1) ||
                           (status == 3'd2) || (status == 3'd4);
        end
    endfunction

    function automatic [15:0] payload_keep(input [1:0] length_dw_mod4);
        reg [5:0] last_bytes;
        begin
            last_bytes = {2'b00, length_dw_mod4, 2'b00};
            if (last_bytes == 0)
                payload_keep = 16'hffff;
            else
                payload_keep = (16'h0001 << last_bytes) - 1'b1;
        end
    endfunction

    function automatic [5:0] payload_last_beat(input [5:0] length_dw);
        begin
            payload_last_beat = (length_dw - 1'b1) >> 2;
        end
    endfunction

    function automatic [5:0] completion_word_count(input [5:0] length_dw);
        begin
            completion_word_count = (length_dw + 6'd6) >> 2;
        end
    endfunction

    function automatic [95:0] make_cpl_header(
        input has_data,
        input poisoned,
        input [2:0] status,
        input bcm,
        input [12:0] byte_count,
        input [15:0] completer_id,
        input [15:0] requester_id,
        input [7:0] tag,
        input [6:0] lower_address,
        input [10:0] length_dw,
        input [2:0] tc,
        input [2:0] attr
    );
        reg [9:0] length_raw;
        reg [11:0] byte_count_raw;
        begin
            length_raw = (length_dw == 11'd1024) ? 10'd0 : length_dw[9:0];
            byte_count_raw = (byte_count == 13'd4096) ? 12'd0 :
                             byte_count[11:0];
            make_cpl_header = 96'd0;
            make_cpl_header[7:0] = has_data ? 8'h4a : 8'h0a;
            make_cpl_header[15:8] = {1'b0, tc, 1'b0, attr[2], 2'b00};
            make_cpl_header[23:16] = {1'b0, poisoned, attr[1:0], 2'b00,
                                              length_raw[9:8]};
            make_cpl_header[31:24] = length_raw[7:0];
            make_cpl_header[39:32] = completer_id[15:8];
            make_cpl_header[47:40] = completer_id[7:0];
            make_cpl_header[55:48] = {status, bcm, byte_count_raw[11:8]};
            make_cpl_header[63:56] = byte_count_raw[7:0];
            make_cpl_header[71:64] = requester_id[15:8];
            make_cpl_header[79:72] = requester_id[7:0];
            make_cpl_header[87:80] = tag;
            make_cpl_header[95:88] = {1'b0, lower_address};
        end
    endfunction

    localparam [3:0] RX_IDLE         = 4'd0;
    localparam [3:0] RX_CAPTURE      = 4'd1;
    localparam [3:0] RX_PARSE        = 4'd2;
    localparam [3:0] RX_CFG_REQ      = 4'd3;
    localparam [3:0] RX_CFG_RSP      = 4'd4;
    localparam [3:0] RX_MEM_DESC     = 4'd5;
    localparam [3:0] RX_MEM_PAYLOAD  = 4'd6;
    localparam [3:0] RX_CPL_DESC     = 4'd7;
    localparam [3:0] RX_CPL_PAYLOAD  = 4'd8;
    localparam [3:0] RX_INTERNAL_CPL = 4'd9;
    localparam [3:0] RX_DISPATCH     = 4'd10;

    localparam [2:0] PK_NONE = 3'd0;
    localparam [2:0] PK_CFG  = 3'd1;
    localparam [2:0] PK_MEM  = 3'd2;
    localparam [2:0] PK_CPL  = 3'd3;
    localparam [2:0] PK_INT  = 3'd4;

    reg [3:0] rx_state;
    reg [7:0] rx_mem [0:143];
    reg [1023:0] rx_payload_flat;
    reg [3:0] rx_beat_index;
    reg [8:0] rx_byte_count;
    reg [8:0] rx_packet_bytes;
    reg rx_capture_bad;
    reg rx_fc_header_valid;
    reg [7:0] rx_fc_b0;
    reg [9:0] rx_fc_length_raw;
    reg [5:0] rx_payload_index;

    reg release_pending;
    reg [1:0] release_type_reg;
    reg [11:0] release_data_credits_reg;
    reg [2:0] internal_status;
    reg [2:0] parse_kind_q;
    reg parse_malformed_q;
    reg parse_unsupported_q;
    reg parse_poisoned_q;
    reg [2:0] parse_internal_status_q;

    wire [4:0] rx_keep_count = popcount16(rx_tlp_keep);
    wire [9:0] rx_byte_sum = {1'b0, rx_byte_count} +
                              {5'd0, rx_keep_count};
    assign rx_tlp_ready = rst_n &&
        (((rx_state == RX_IDLE) && !release_pending) ||
         (rx_state == RX_CAPTURE));
    wire rx_tlp_fire = rx_tlp_valid && rx_tlp_ready;

    assign rx_release_valid = release_pending;
    assign rx_release_type = release_type_reg;
    assign rx_release_data_credits = release_data_credits_reg;

    wire [7:0] p_b0  = rx_mem[0];
    wire [7:0] p_b1  = rx_mem[1];
    wire [7:0] p_b2  = rx_mem[2];
    wire [7:0] p_b3  = rx_mem[3];
    wire [7:0] p_b4  = rx_mem[4];
    wire [7:0] p_b5  = rx_mem[5];
    wire [7:0] p_b6  = rx_mem[6];
    wire [7:0] p_b7  = rx_mem[7];
    wire [7:0] p_b8  = rx_mem[8];
    wire [7:0] p_b9  = rx_mem[9];
    wire [7:0] p_b10 = rx_mem[10];
    wire [7:0] p_b11 = rx_mem[11];
    wire [7:0] p_b12 = rx_mem[12];
    wire [7:0] p_b13 = rx_mem[13];
    wire [7:0] p_b14 = rx_mem[14];
    wire [7:0] p_b15 = rx_mem[15];

    wire [2:0] p_fmt = p_b0[7:5];
    wire [4:0] p_type = p_b0[4:0];
    wire p_has_data = p_b0[6];
    wire p_is_4dw = p_b0[5];
    wire [9:0] p_length_raw = {p_b2[1:0], p_b3};
    wire [10:0] p_length_eff = (p_length_raw == 0) ? 11'd1024 :
                                                   {1'b0, p_length_raw};
    wire [2:0] p_tc = p_b1[6:4];
    wire [2:0] p_attr = {p_b1[2], p_b2[5:4]};
    wire p_td = p_b2[7];
    wire p_ep = p_b2[6];
    wire [1:0] p_at = p_b2[3:2];
    wire [15:0] p_requester_id = {p_b4, p_b5};
    wire [7:0] p_tag = p_b6;
    wire [3:0] p_first_be = p_b7[3:0];
    wire [3:0] p_last_be = p_b7[7:4];
    wire [31:0] p_address_32 = {p_b8, p_b9, p_b10, p_b11[7:2], 2'b00};
    wire [63:0] p_address_64 = {p_b8, p_b9, p_b10, p_b11,
                                p_b12, p_b13, p_b14, p_b15[7:2], 2'b00};
    wire [63:0] p_address = p_is_4dw ? p_address_64 : {32'd0, p_address_32};
    wire [11:0] p_byte_count_raw = {p_b6[3:0], p_b7};
    wire [12:0] p_byte_count_eff = (p_byte_count_raw == 0) ? 13'd4096 :
                                                           {1'b0, p_byte_count_raw};
    wire [2:0] p_cpl_status = p_b6[7:5];
    wire p_is_completion = (p_type == 5'h0a) || (p_type == 5'h0b);
    wire [15:0] p_diag_requester_id = p_is_completion ? {p_b8, p_b9} :
                                                          p_requester_id;
    wire [7:0] p_diag_tag = p_is_completion ? p_b10 : p_tag;
    wire p_common_unsupported = p_b1[1] || p_b1[0] || p_td ||
        (p_at == 2'd1) || (p_at == 2'd2);

    reg [2:0] parse_kind;
    reg parse_malformed;
    reg parse_unsupported;
    reg parse_ur_eligible;
    reg parse_poisoned;
    reg [2:0] parse_internal_status;
    integer parse_expected_bytes;
    integer parse_span_end;

    always @* begin
        parse_kind = PK_NONE;
        parse_malformed = rx_capture_bad;
        parse_unsupported = 1'b0;
        parse_ur_eligible = 1'b0;
        parse_poisoned = 1'b0;
        parse_internal_status = 3'd0;
        parse_expected_bytes = 0;
        parse_span_end = 0;

        if (!parse_malformed) begin
            if (p_fmt == 3'b100) begin
                if (((p_b0 == 8'h80) || (p_b0 == 8'h8e) ||
                     (p_b0 == 8'h8f) || (p_b0 == 8'h90) ||
                     (p_b0 == 8'h9e) || (p_b0 == 8'h9f)) &&
                    (rx_packet_bytes >= 4) &&
                    (rx_packet_bytes[1:0] == 0)) begin
                    parse_unsupported = 1'b1;
                end else begin
                    parse_malformed = 1'b1;
                end
            end else if (rx_packet_bytes < 12) begin
                parse_malformed = 1'b1;
            end else if (p_at == 2'd3) begin
                parse_malformed = 1'b1;
            end else begin
                case (p_b0)
                    8'h04, 8'h44: begin
                        parse_expected_bytes = (p_b0 == 8'h44) ? 16 : 12;
                        if (p_td)
                            parse_expected_bytes = parse_expected_bytes + 4;
                        if ((p_b1[7] != 0) || (p_b1[3] != 0) ||
                            (p_length_raw != 10'd1) || (p_last_be != 0) ||
                            (p_b10[7:4] != 0) || (p_b11[1:0] != 0) ||
                            (rx_packet_bytes != parse_expected_bytes[8:0])) begin
                            parse_malformed = 1'b1;
                        end else if (p_common_unsupported) begin
                            parse_unsupported = 1'b1;
                            parse_ur_eligible = 1'b1;
                        end else if (p_ep) begin
                            if (p_b0 == 8'h44) begin
                                parse_kind = PK_INT;
                                parse_internal_status = 3'd4;
                                parse_poisoned = 1'b1;
                            end else begin
                                parse_malformed = 1'b1;
                            end
                        end else begin
                            parse_kind = PK_CFG;
                        end
                    end

                    8'h00, 8'h20, 8'h40, 8'h60: begin
                        parse_expected_bytes = p_is_4dw ? 16 : 12;
                        if (p_has_data)
                            parse_expected_bytes = parse_expected_bytes +
                                                   p_length_eff * 4;
                        if (p_td)
                            parse_expected_bytes = parse_expected_bytes + 4;
                        parse_span_end = {20'd0, p_address[11:0]} +
                                         {19'd0, p_length_eff, 2'b00};
                        if ((p_b1[7] != 0) || (p_b1[3] != 0) ||
                            (!p_b1[0] && ((p_is_4dw ? p_b15[1:0] :
                                                     p_b11[1:0]) != 0)) ||
                            (p_has_data && (p_length_eff > 32)) ||
                            (rx_packet_bytes != parse_expected_bytes[8:0]) ||
                            (parse_span_end > 4096) ||
                            ((p_length_eff == 1) && (p_last_be != 0)) ||
                            ((p_length_eff > 1) &&
                             ((p_first_be == 0) || (p_last_be == 0)))) begin
                            parse_malformed = 1'b1;
                        end else if (p_common_unsupported) begin
                            parse_unsupported = 1'b1;
                            parse_ur_eligible = !p_has_data;
                        end else if (p_ep && !p_has_data) begin
                            parse_malformed = 1'b1;
                        end else begin
                            parse_kind = PK_MEM;
                            parse_poisoned = p_ep;
                        end
                    end

                    8'h0a, 8'h4a: begin
                        parse_expected_bytes = 12;
                        if (p_b0 == 8'h4a)
                            parse_expected_bytes = parse_expected_bytes +
                                                   p_length_eff * 4;
                        if (p_td)
                            parse_expected_bytes = parse_expected_bytes + 4;
                        parse_span_end = {19'd0, p_byte_count_eff} +
                                         {30'd0, p_b11[1:0]} + 32'd3;
                        if ((p_b1[7] != 0) || (p_b1[3] != 0) ||
                            p_b11[7] || !status_valid(p_cpl_status) ||
                            (rx_packet_bytes != parse_expected_bytes[8:0]) ||
                            ((p_b0 == 8'h0a) &&
                             ((p_length_raw != 0) || p_ep)) ||
                            ((p_b0 == 8'h4a) &&
                             ((p_length_raw == 0) || (p_length_eff > 32) ||
                              (p_cpl_status != 0) ||
                              (parse_span_end < p_length_eff * 4)))) begin
                            parse_malformed = 1'b1;
                        end else if (p_common_unsupported) begin
                            parse_unsupported = 1'b1;
                        end else begin
                            parse_kind = PK_CPL;
                            parse_poisoned = p_ep;
                        end
                    end

                    // Cfg Type-1和I/O：格式完整时都是Unsupported NP。
                    8'h05, 8'h45, 8'h02, 8'h42: begin
                        parse_expected_bytes = p_has_data ? 16 : 12;
                        if (p_td)
                            parse_expected_bytes = parse_expected_bytes + 4;
                        if ((p_b1[7] != 0) || (p_b1[3] != 0) || p_ep ||
                            (p_length_raw != 1) || (p_last_be != 0) ||
                            (((p_b0 == 8'h05) || (p_b0 == 8'h45)) &&
                             ((p_b10[7:4] != 0) || (p_b11[1:0] != 0))) ||
                            (((p_b0 == 8'h02) || (p_b0 == 8'h42)) &&
                             (p_b11[1:0] != 0)) ||
                            (rx_packet_bytes != parse_expected_bytes[8:0])) begin
                            parse_malformed = 1'b1;
                        end else begin
                            parse_unsupported = 1'b1;
                            parse_ur_eligible = 1'b1;
                        end
                    end

                    // Locked Memory Read。
                    8'h01, 8'h21: begin
                        parse_expected_bytes = p_is_4dw ? 16 : 12;
                        if (p_td)
                            parse_expected_bytes = parse_expected_bytes + 4;
                        parse_span_end = {20'd0, p_address[11:0]} +
                                         {19'd0, p_length_eff, 2'b00};
                        if ((p_b1[7] != 0) || (p_b1[3] != 0) || p_ep ||
                            (!p_b1[0] && ((p_is_4dw ? p_b15[1:0] :
                                                     p_b11[1:0]) != 0)) ||
                            (rx_packet_bytes != parse_expected_bytes[8:0]) ||
                            (parse_span_end > 4096) ||
                            ((p_length_eff == 1) && (p_last_be != 0)) ||
                            ((p_length_eff > 1) &&
                             ((p_first_be == 0) || (p_last_be == 0)))) begin
                            parse_malformed = 1'b1;
                        end else begin
                            parse_unsupported = 1'b1;
                            parse_ur_eligible = 1'b1;
                        end
                    end

                    // AtomicOp：具有Payload但仍为Non-Posted。
                    8'h4c, 8'h6c, 8'h4d, 8'h6d, 8'h4e, 8'h6e: begin
                        parse_expected_bytes = (p_is_4dw ? 16 : 12) +
                                               p_length_eff * 4;
                        if (p_td)
                            parse_expected_bytes = parse_expected_bytes + 4;
                        parse_span_end = {20'd0, p_address[11:0]} +
                                         {19'd0, p_length_eff, 2'b00};
                        if ((p_b1[7] != 0) || (p_b1[3] != 0) || p_ep ||
                            (!p_b1[0] && ((p_is_4dw ? p_b15[1:0] :
                                                     p_b11[1:0]) != 0)) ||
                            (p_length_eff > 32) ||
                            (rx_packet_bytes != parse_expected_bytes[8:0]) ||
                            (parse_span_end > 4096)) begin
                            parse_malformed = 1'b1;
                        end else begin
                            parse_unsupported = 1'b1;
                            parse_ur_eligible = 1'b1;
                        end
                    end

                    // Locked Completion：语法完整但K07不支持，且绝不回Completion。
                    8'h0b, 8'h4b: begin
                        parse_expected_bytes = 12;
                        if (p_b0 == 8'h4b)
                            parse_expected_bytes = parse_expected_bytes +
                                                   p_length_eff * 4;
                        if (p_td)
                            parse_expected_bytes = parse_expected_bytes + 4;
                        parse_span_end = {19'd0, p_byte_count_eff} +
                                         {30'd0, p_b11[1:0]} + 32'd3;
                        if ((p_b1[7] != 0) || (p_b1[3] != 0) ||
                            p_b11[7] || !status_valid(p_cpl_status) ||
                            (rx_packet_bytes != parse_expected_bytes[8:0]) ||
                            ((p_b0 == 8'h0b) &&
                             ((p_length_raw != 0) || p_ep)) ||
                            ((p_b0 == 8'h4b) &&
                             ((p_length_raw == 0) || (p_length_eff > 32) ||
                              (p_cpl_status != 0) ||
                              (parse_span_end < p_length_eff * 4)))) begin
                            parse_malformed = 1'b1;
                        end else begin
                            parse_unsupported = 1'b1;
                        end
                    end

                    // Message为Posted；无数据Message Wire Length必须为0。
                    8'h30, 8'h31, 8'h32, 8'h33, 8'h34, 8'h35,
                    8'h70, 8'h71, 8'h72, 8'h73, 8'h74, 8'h75: begin
                        parse_expected_bytes = 16;
                        if (p_has_data)
                            parse_expected_bytes = parse_expected_bytes +
                                                   p_length_eff * 4;
                        if (p_td)
                            parse_expected_bytes = parse_expected_bytes + 4;
                        if ((!p_has_data && (p_length_raw != 0)) ||
                            (p_has_data && ((p_length_raw == 0) ||
                                            (p_length_eff > 32))) ||
                            (rx_packet_bytes != parse_expected_bytes[8:0])) begin
                            parse_malformed = 1'b1;
                        end else begin
                            parse_unsupported = 1'b1;
                        end
                    end

                    // 已知Prefix首DW。K07不解析Prefix链，只安全丢弃并计数。
                    8'h80, 8'h8e, 8'h8f, 8'h90, 8'h9e, 8'h9f: begin
                        if ((rx_packet_bytes < 4) || (rx_packet_bytes[1:0] != 0))
                            parse_malformed = 1'b1;
                        else
                            parse_unsupported = 1'b1;
                    end

                    default: parse_malformed = 1'b1;
                endcase
            end
        end

        if (parse_unsupported && parse_ur_eligible) begin
            parse_kind = PK_INT;
            parse_internal_status = 3'd1;
        end
    end

    assign cfg_req_valid = (rx_state == RX_CFG_REQ);
    assign cfg_req_write = (p_b0 == 8'h44);
    assign cfg_req_dw_addr = {p_b10[3:0], p_b11[7:2]};
    assign cfg_req_be = p_first_be;
    assign cfg_req_wdata = {p_b15, p_b14, p_b13, p_b12};
    assign cfg_req_requester_id = p_requester_id;
    assign cfg_req_tag = p_tag;
    assign cfg_req_target_bdf = {p_b8, p_b9};

    assign mem_req_valid = (rx_state == RX_MEM_DESC);
    assign mem_req_write = p_has_data;
    assign mem_req_64bit = p_is_4dw;
    assign mem_req_poisoned = p_ep;
    assign mem_req_address = p_address;
    assign mem_req_length_dw = p_length_eff;
    assign mem_req_first_be = p_first_be;
    assign mem_req_last_be = p_last_be;
    assign mem_req_requester_id = p_requester_id;
    assign mem_req_tag = p_tag;
    assign mem_req_tc = p_tc;
    assign mem_req_attr = p_attr;

    wire [5:0] rx_payload_last_index =
        payload_last_beat(p_length_eff[5:0]);
    assign mem_w_valid = (rx_state == RX_MEM_PAYLOAD);
    assign mem_w_data = rx_payload_flat[rx_payload_index*128 +: 128];
    assign mem_w_last = (rx_payload_index == rx_payload_last_index);
    assign mem_w_keep = mem_w_last ? payload_keep(p_length_eff[1:0]) :
                                     16'hffff;

    assign rx_cpl_valid = (rx_state == RX_CPL_DESC);
    assign rx_cpl_has_data = (p_b0 == 8'h4a);
    assign rx_cpl_poisoned = p_ep;
    assign rx_cpl_status = p_cpl_status;
    assign rx_cpl_bcm = p_b6[4];
    assign rx_cpl_byte_count = (p_b0 == 8'h4a) ? p_byte_count_eff :
                               {1'b0, p_byte_count_raw};
    assign rx_cpl_completer_id = {p_b4, p_b5};
    assign rx_cpl_requester_id = {p_b8, p_b9};
    assign rx_cpl_tag = p_b10;
    assign rx_cpl_lower_address = p_b11[6:0];
    assign rx_cpl_length_dw = (p_b0 == 8'h4a) ? p_length_eff[5:0] : 6'd0;
    assign rx_cpl_tc = p_tc;
    assign rx_cpl_attr = p_attr;
    assign rx_cpl_data_valid = (rx_state == RX_CPL_PAYLOAD);
    assign rx_cpl_data = rx_payload_flat[rx_payload_index*128 +: 128];
    assign rx_cpl_data_last = (rx_payload_index == rx_payload_last_index);
    assign rx_cpl_data_keep = rx_cpl_data_last ?
                              payload_keep(p_length_eff[1:0]) : 16'hffff;

    localparam [1:0] TX_IDLE    = 2'd0;
    localparam [1:0] TX_PAYLOAD = 2'd1;
    localparam [1:0] TX_DRAIN   = 2'd2;
    localparam [1:0] TX_SEND    = 2'd3;

    reg [1:0] tx_state;
    reg [127:0] tx_words [0:8];
    reg [5:0] tx_word_index;
    reg [5:0] tx_word_count;
    reg [15:0] tx_last_keep;
    reg [11:0] tx_data_credits_reg;
    reg [5:0] tx_payload_length_dw;
    reg [5:0] tx_payload_beat;

    wire tx_idle = (tx_state == TX_IDLE);
    wire internal_cpl_valid = (rx_state == RX_INTERNAL_CPL);
    wire cfg_cpl_valid = (rx_state == RX_CFG_RSP) && cfg_rsp_valid;
    wire any_internal_cpl_valid = internal_cpl_valid || cfg_cpl_valid;
    wire internal_cpl_fire = tx_idle && internal_cpl_valid;
    wire cfg_cpl_fire = tx_idle && cfg_cpl_valid;
    assign cfg_rsp_ready = rst_n && (rx_state == RX_CFG_RSP) && tx_idle;
    assign cpl_req_ready = rst_n && tx_idle && !any_internal_cpl_valid;
    wire cpl_req_fire = cpl_req_valid && cpl_req_ready;
    assign cpl_data_ready = rst_n &&
                            ((tx_state == TX_PAYLOAD) || (tx_state == TX_DRAIN));

    assign tx_tlp_valid = (tx_state == TX_SEND);
    assign tx_tlp_data = tx_words[tx_word_index[3:0]];
    assign tx_tlp_keep = (tx_word_index + 1'b1 == tx_word_count) ?
                         tx_last_keep : 16'hffff;
    assign tx_tlp_sop = (tx_state == TX_SEND) && (tx_word_index == 0);
    assign tx_tlp_eop = (tx_state == TX_SEND) &&
                        (tx_word_index + 1'b1 == tx_word_count);
    assign tx_tlp_error = 4'd0;
    assign tx_tlp_type = 2'd2;
    assign tx_tlp_data_credits = tx_data_credits_reg;

    wire cfg_status_is_valid = status_valid(cfg_rsp_status);
    wire cfg_response_has_data = cfg_status_is_valid &&
        (cfg_rsp_status == 0) && !cfg_req_write;
    wire [2:0] cfg_response_status = cfg_status_is_valid ? cfg_rsp_status : 3'd4;

    wire [13:0] external_byte_count_span =
        {1'b0, cpl_req_byte_count} + {12'd0, cpl_req_lower_address[1:0]} +
        14'd3;
    wire [13:0] external_payload_bytes =
        {6'd0, cpl_req_length_dw, 2'b00};
    wire external_descriptor_good = status_valid(cpl_req_status) &&
        (cpl_req_byte_count <= 13'd4096) &&
        (cpl_req_has_data ?
            ((cpl_req_status == 0) &&
             (cpl_req_length_dw >= 1) && (cpl_req_length_dw <= 32) &&
             (cpl_req_byte_count >= 1) &&
             (external_byte_count_span >= external_payload_bytes)) :
            ((cpl_req_length_dw == 0) && !cpl_req_poisoned));

    integer rx_store_i;
    integer rx_payload_i;

    // 整包RAM不参与异步复位。有效性完全由rx_state和长度寄存器限定；
    // 这样既符合“复位丢弃半包”的契约，也避免给144 Byte阵列推导复位网络。
    always @(posedge clk) begin
        if (rx_tlp_fire && (rx_state == RX_IDLE)) begin
            for (rx_store_i = 0; rx_store_i < 16;
                 rx_store_i = rx_store_i + 1)
                if (rx_tlp_keep[rx_store_i])
                    rx_mem[rx_store_i] <=
                        rx_tlp_data[rx_store_i*8 +: 8];
        end else if (rx_tlp_fire && (rx_state == RX_CAPTURE) &&
                     (rx_beat_index < 9)) begin
            for (rx_store_i = 0; rx_store_i < 16;
                 rx_store_i = rx_store_i + 1)
                if (rx_tlp_keep[rx_store_i])
                    rx_mem[rx_beat_index*16+rx_store_i] <=
                        rx_tlp_data[rx_store_i*8 +: 8];
        end
    end

    // EOP提交后的PARSE周期统一完成Payload对齐。即使Packet最终被丢弃也允许
    // 覆写数据阵列；下游valid仍由解析结果和状态机独立控制。无条件搬运可避免
    // malformed/type判定形成1024-bit公共CE的长组合路径。
    always @(posedge clk) begin
        if (rx_state == RX_PARSE) begin
            if (p_is_4dw) begin
                for (rx_payload_i = 0; rx_payload_i < 128;
                     rx_payload_i = rx_payload_i + 1)
                    rx_payload_flat[rx_payload_i*8 +: 8] <=
                        rx_mem[rx_payload_i+16];
            end else begin
                for (rx_payload_i = 0; rx_payload_i < 128;
                     rx_payload_i = rx_payload_i + 1)
                    rx_payload_flat[rx_payload_i*8 +: 8] <=
                        rx_mem[rx_payload_i+12];
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state <= RX_IDLE;
            rx_beat_index <= 0;
            rx_byte_count <= 0;
            rx_packet_bytes <= 0;
            rx_capture_bad <= 0;
            rx_fc_header_valid <= 0;
            rx_fc_b0 <= 0;
            rx_fc_length_raw <= 0;
            rx_payload_index <= 0;
            release_pending <= 0;
            release_type_reg <= 0;
            release_data_credits_reg <= 0;
            internal_status <= 0;
            parse_kind_q <= PK_NONE;
            parse_malformed_q <= 0;
            parse_unsupported_q <= 0;
            parse_poisoned_q <= 0;
            parse_internal_status_q <= 0;
            malformed_pulse <= 0;
            unsupported_pulse <= 0;
            poisoned_pulse <= 0;
            unexpected_cpl_pulse <= 0;
            error_fmt_type <= 0;
            error_requester_id <= 0;
            error_tag <= 0;
            rx_packet_count <= 0;
            cfg_request_count <= 0;
            mem_request_count <= 0;
            rx_completion_count <= 0;
            malformed_count <= 0;
            unsupported_count <= 0;
            poisoned_count <= 0;
            unexpected_completion_count <= 0;
        end else begin
            malformed_pulse <= 1'b0;
            unsupported_pulse <= 1'b0;
            poisoned_pulse <= 1'b0;
            unexpected_cpl_pulse <= 1'b0;

            if (release_pending && rx_release_ready)
                release_pending <= 1'b0;

            case (rx_state)
                RX_IDLE: begin
                    if (rx_tlp_fire) begin
                        rx_beat_index <= 1;
                        rx_byte_count <= {4'd0, rx_keep_count};
                        rx_fc_header_valid <= rx_tlp_sop &&
                                              (&rx_tlp_keep[3:0]);
                        rx_fc_b0 <= rx_tlp_data[7:0];
                        rx_fc_length_raw <= {rx_tlp_data[17:16],
                                             rx_tlp_data[31:24]};
                        rx_capture_bad <= !rx_tlp_sop ||
                            (rx_tlp_error != 0) ||
                            (rx_tlp_eop ? !keep_contiguous16(rx_tlp_keep) :
                                          (rx_tlp_keep != 16'hffff));
                        if (rx_tlp_eop) begin
                            rx_packet_bytes <= {4'd0, rx_keep_count};
                            rx_state <= RX_PARSE;
                        end else begin
                            rx_state <= RX_CAPTURE;
                        end
                    end
                end

                RX_CAPTURE: begin
                    if (rx_tlp_fire) begin
                        if (rx_byte_sum > 10'd144)
                            rx_byte_count <= 9'd145;
                        else
                            rx_byte_count <= rx_byte_sum[8:0];
                        if (rx_beat_index < 9)
                            rx_beat_index <= rx_beat_index + 1'b1;
                        rx_capture_bad <= rx_capture_bad || rx_tlp_sop ||
                            (rx_tlp_error != 0) || (rx_beat_index >= 9) ||
                            (rx_byte_sum > 10'd144) ||
                            (rx_tlp_eop ? !keep_contiguous16(rx_tlp_keep) :
                                          (rx_tlp_keep != 16'hffff));
                        if (rx_tlp_eop) begin
                            if (rx_byte_sum > 10'd144)
                                rx_packet_bytes <= 9'd145;
                            else
                                rx_packet_bytes <= rx_byte_sum[8:0];
                            rx_state <= RX_PARSE;
                        end
                    end
                end

                RX_PARSE: begin
                    rx_packet_count <= sat_inc32(rx_packet_count);
                    release_pending <= 1'b1;
                    if (!rx_fc_header_valid)
                        release_type_reg <= 2'd1;
                    else if (rx_fc_b0[4:0] == 5'h0a)
                        release_type_reg <= 2'd2;
                    else if ((rx_fc_b0[4:0] == 0) && rx_fc_b0[6])
                        release_type_reg <= 2'd0;
                    else
                        release_type_reg <= 2'd1;
                    if (rx_fc_header_valid && rx_fc_b0[6]) begin
                        if (rx_fc_length_raw == 0)
                            release_data_credits_reg <= 12'd256;
                        else
                            release_data_credits_reg <=
                                ({2'd0, rx_fc_length_raw} + 12'd3) >> 2;
                    end else begin
                        release_data_credits_reg <= 12'd0;
                    end

                    // 深组合解析只在此处进入低扇出的流水寄存器；下一拍再更新
                    // 诊断、计数器和下游状态，确保250 MHz下没有公共CE长路径。
                    parse_kind_q <= parse_kind;
                    parse_malformed_q <= parse_malformed;
                    parse_unsupported_q <= parse_unsupported;
                    parse_poisoned_q <= parse_poisoned;
                    parse_internal_status_q <= parse_internal_status;
                    rx_state <= RX_DISPATCH;
                end

                RX_DISPATCH: begin
                    if (parse_malformed_q) begin
                        malformed_pulse <= 1'b1;
                        malformed_count <= sat_inc32(malformed_count);
                        error_fmt_type <= rx_fc_header_valid ? rx_fc_b0 : 8'd0;
                        error_requester_id <= (rx_packet_bytes >= 12) ?
                                              p_diag_requester_id : 16'd0;
                        error_tag <= (rx_packet_bytes >= 12) ?
                                     p_diag_tag : 8'd0;
                        rx_state <= RX_IDLE;
                    end else begin
                        if (parse_unsupported_q) begin
                            unsupported_pulse <= 1'b1;
                            unsupported_count <= sat_inc32(unsupported_count);
                            error_fmt_type <= p_b0;
                            error_requester_id <= (rx_packet_bytes >= 12) ?
                                                  p_diag_requester_id : 16'd0;
                            error_tag <= (rx_packet_bytes >= 12) ?
                                         p_diag_tag : 8'd0;
                        end
                        if (parse_poisoned_q) begin
                            poisoned_pulse <= 1'b1;
                            poisoned_count <= sat_inc32(poisoned_count);
                            error_fmt_type <= p_b0;
                            error_requester_id <= (rx_packet_bytes >= 12) ?
                                                  p_diag_requester_id : 16'd0;
                            error_tag <= (rx_packet_bytes >= 12) ?
                                         p_diag_tag : 8'd0;
                        end

                        case (parse_kind_q)
                            PK_CFG: rx_state <= RX_CFG_REQ;
                            PK_MEM: rx_state <= RX_MEM_DESC;
                            PK_CPL: begin
                                unexpected_cpl_pulse <= 1'b1;
                                unexpected_completion_count <=
                                    sat_inc32(unexpected_completion_count);
                                error_fmt_type <= p_b0;
                                error_requester_id <= p_diag_requester_id;
                                error_tag <= p_diag_tag;
                                rx_state <= RX_CPL_DESC;
                            end
                            PK_INT: begin
                                internal_status <= parse_internal_status_q;
                                rx_state <= RX_INTERNAL_CPL;
                            end
                            default: rx_state <= RX_IDLE;
                        endcase
                    end
                end

                RX_CFG_REQ: begin
                    if (cfg_req_valid && cfg_req_ready) begin
                        cfg_request_count <= sat_inc32(cfg_request_count);
                        rx_state <= RX_CFG_RSP;
                    end
                end

                RX_CFG_RSP: begin
                    if (cfg_cpl_fire)
                        rx_state <= RX_IDLE;
                end

                RX_MEM_DESC: begin
                    if (mem_req_valid && mem_req_ready) begin
                        mem_request_count <= sat_inc32(mem_request_count);
                        rx_payload_index <= 0;
                        if (p_has_data)
                            rx_state <= RX_MEM_PAYLOAD;
                        else
                            rx_state <= RX_IDLE;
                    end
                end

                RX_MEM_PAYLOAD: begin
                    if (mem_w_valid && mem_w_ready) begin
                        if (mem_w_last)
                            rx_state <= RX_IDLE;
                        else
                            rx_payload_index <= rx_payload_index + 1'b1;
                    end
                end

                RX_CPL_DESC: begin
                    if (rx_cpl_valid && rx_cpl_ready) begin
                        rx_completion_count <= sat_inc32(rx_completion_count);
                        rx_payload_index <= 0;
                        if (p_b0 == 8'h4a)
                            rx_state <= RX_CPL_PAYLOAD;
                        else
                            rx_state <= RX_IDLE;
                    end
                end

                RX_CPL_PAYLOAD: begin
                    if (rx_cpl_data_valid && rx_cpl_data_ready) begin
                        if (rx_cpl_data_last)
                            rx_state <= RX_IDLE;
                        else
                            rx_payload_index <= rx_payload_index + 1'b1;
                    end
                end

                RX_INTERNAL_CPL: begin
                    if (internal_cpl_fire)
                        rx_state <= RX_IDLE;
                end

                default: rx_state <= RX_IDLE;
            endcase
        end
    end

    integer tx_store_w;
    reg [15:0] expected_payload_keep;
    reg expected_payload_last;
    reg [10:0] payload_bytes_remaining;
    always @* begin
        payload_bytes_remaining = tx_payload_length_dw * 4 -
                                  tx_payload_beat * 16;
        expected_payload_last = (payload_bytes_remaining <= 16);
        if (payload_bytes_remaining >= 16)
            expected_payload_keep = 16'hffff;
        else
            expected_payload_keep = (16'h0001 << payload_bytes_remaining) - 1'b1;
    end

    // TX Packet阵列同样不需要复位；tx_state/word_count是唯一有效性标志。
    // 独立的无复位写进程避免Vivado把条件写推导为set/reset同优先级。
    always @(posedge clk) begin
        if (tx_state == TX_IDLE) begin
            if (cfg_cpl_fire) begin
                for (tx_store_w = 1; tx_store_w < 9;
                     tx_store_w = tx_store_w + 1)
                    tx_words[tx_store_w] <= 0;
                tx_words[0] <= {cfg_response_has_data ? cfg_rsp_rdata : 32'd0,
                    make_cpl_header(cfg_response_has_data, 1'b0,
                        cfg_response_status, 1'b0,
                        cfg_response_has_data ? 13'd4 : 13'd0,
                        cfg_rsp_completer_id, p_requester_id, p_tag, 7'd0,
                        cfg_response_has_data ? 11'd1 : 11'd0, p_tc, p_attr)};
            end else if (internal_cpl_fire) begin
                for (tx_store_w = 1; tx_store_w < 9;
                     tx_store_w = tx_store_w + 1)
                    tx_words[tx_store_w] <= 0;
                tx_words[0] <= {32'd0,
                    make_cpl_header(1'b0, 1'b0, internal_status, 1'b0,
                        13'd0, local_completer_id, p_requester_id, p_tag,
                        7'd0, 11'd0, p_tc, p_attr)};
            end else if (cpl_req_fire && external_descriptor_good) begin
                for (tx_store_w = 1; tx_store_w < 9;
                     tx_store_w = tx_store_w + 1)
                    tx_words[tx_store_w] <= 0;
                tx_words[0] <= {32'd0,
                    make_cpl_header(cpl_req_has_data, cpl_req_poisoned,
                        cpl_req_status, cpl_req_bcm, cpl_req_byte_count,
                        cpl_req_completer_id, cpl_req_requester_id,
                        cpl_req_tag, cpl_req_lower_address,
                        {5'd0, cpl_req_length_dw}, cpl_req_tc, cpl_req_attr)};
            end
        end else if ((tx_state == TX_PAYLOAD) && cpl_data_valid &&
                     cpl_data_ready) begin
            tx_words[tx_payload_beat[3:0]][127:96] <= cpl_data[31:0];
            tx_words[tx_payload_beat[3:0]+1'b1][95:0] <= cpl_data[127:32];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state <= TX_IDLE;
            tx_word_index <= 0;
            tx_word_count <= 0;
            tx_last_keep <= 0;
            tx_data_credits_reg <= 0;
            tx_payload_length_dw <= 0;
            tx_payload_beat <= 0;
            tx_completion_count <= 0;
            ur_completion_count <= 0;
            tx_protocol_error_count <= 0;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    tx_word_index <= 0;
                    tx_payload_beat <= 0;
                    if (cfg_cpl_fire) begin
                        tx_word_count <= 1;
                        tx_last_keep <= cfg_response_has_data ? 16'hffff :
                                                               16'h0fff;
                        tx_data_credits_reg <= cfg_response_has_data ? 12'd1 :
                                                                     12'd0;
                        if (cfg_rsp_status == 3'd1)
                            ur_completion_count <= sat_inc32(ur_completion_count);
                        if (!cfg_status_is_valid)
                            tx_protocol_error_count <=
                                sat_inc32(tx_protocol_error_count);
                        tx_state <= TX_SEND;
                    end else if (internal_cpl_fire) begin
                        tx_word_count <= 1;
                        tx_last_keep <= 16'h0fff;
                        tx_data_credits_reg <= 0;
                        if (internal_status == 3'd1)
                            ur_completion_count <= sat_inc32(ur_completion_count);
                        tx_state <= TX_SEND;
                    end else if (cpl_req_fire) begin
                        if (!external_descriptor_good) begin
                                tx_protocol_error_count <=
                                sat_inc32(tx_protocol_error_count);
                            if (cpl_req_has_data)
                                tx_state <= TX_DRAIN;
                        end else begin
                            tx_data_credits_reg <= cpl_req_has_data ?
                                {6'd0, payload_last_beat(cpl_req_length_dw) +
                                       1'b1} : 12'd0;
                            if (cpl_req_has_data) begin
                                tx_payload_length_dw <= cpl_req_length_dw;
                                tx_state <= TX_PAYLOAD;
                            end else begin
                                tx_word_count <= 1;
                                tx_last_keep <= 16'h0fff;
                                if (cpl_req_status == 3'd1)
                                    ur_completion_count <=
                                        sat_inc32(ur_completion_count);
                                tx_state <= TX_SEND;
                            end
                        end
                    end
                end

                TX_PAYLOAD: begin
                    if (cpl_data_valid && cpl_data_ready) begin
                        if ((cpl_data_keep != expected_payload_keep) ||
                            (cpl_data_last != expected_payload_last)) begin
                            tx_protocol_error_count <=
                                sat_inc32(tx_protocol_error_count);
                            if (cpl_data_last)
                                tx_state <= TX_IDLE;
                            else
                                tx_state <= TX_DRAIN;
                        end else if (expected_payload_last) begin
                            tx_word_count <=
                                completion_word_count(tx_payload_length_dw);
                            case (tx_payload_length_dw[1:0])
                                2'd0: tx_last_keep <= 16'h0fff;
                                2'd1: tx_last_keep <= 16'hffff;
                                2'd2: tx_last_keep <= 16'h000f;
                                default: tx_last_keep <= 16'h00ff;
                            endcase
                            tx_state <= TX_SEND;
                        end else begin
                            tx_payload_beat <= tx_payload_beat + 1'b1;
                        end
                    end
                end

                TX_DRAIN: begin
                    if (cpl_data_valid && cpl_data_ready && cpl_data_last)
                        tx_state <= TX_IDLE;
                end

                TX_SEND: begin
                    if (tx_tlp_valid && tx_tlp_ready) begin
                        if (tx_tlp_eop) begin
                            tx_completion_count <=
                                sat_inc32(tx_completion_count);
                            tx_state <= TX_IDLE;
                        end else begin
                            tx_word_index <= tx_word_index + 1'b1;
                        end
                    end
                end

                default: tx_state <= TX_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
