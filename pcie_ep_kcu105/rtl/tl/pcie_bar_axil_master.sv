`timescale 1ns/1ps
`default_nettype none

// K09：单Outstanding、32-bit AXI4-Lite的4 KiB BAR0 Completer。
module pcie_bar_axil_master (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         hot_reset,

    input  wire [31:0]  bar0_base,
    input  wire         bar0_probe_active,
    input  wire         memory_space_enable,
    input  wire [15:0]  local_completer_id,

    input  wire         mem_req_valid,
    output wire         mem_req_ready,
    input  wire         mem_req_write,
    input  wire         mem_req_64bit,
    input  wire         mem_req_poisoned,
    input  wire [63:0]  mem_req_address,
    input  wire [10:0]  mem_req_length_dw,
    input  wire [3:0]   mem_req_first_be,
    input  wire [3:0]   mem_req_last_be,
    input  wire [15:0]  mem_req_requester_id,
    input  wire [7:0]   mem_req_tag,
    input  wire [2:0]   mem_req_tc,
    input  wire [2:0]   mem_req_attr,

    input  wire         mem_w_valid,
    output wire         mem_w_ready,
    input  wire [127:0] mem_w_data,
    input  wire [15:0]  mem_w_keep,
    input  wire         mem_w_last,

    output wire         cpl_req_valid,
    input  wire         cpl_req_ready,
    output wire         cpl_req_has_data,
    output wire         cpl_req_poisoned,
    output wire [2:0]   cpl_req_status,
    output wire         cpl_req_bcm,
    output wire [12:0]  cpl_req_byte_count,
    output wire [15:0]  cpl_req_completer_id,
    output wire [15:0]  cpl_req_requester_id,
    output wire [7:0]   cpl_req_tag,
    output wire [6:0]   cpl_req_lower_address,
    output wire [5:0]   cpl_req_length_dw,
    output wire [2:0]   cpl_req_tc,
    output wire [2:0]   cpl_req_attr,

    output wire         cpl_data_valid,
    input  wire         cpl_data_ready,
    output wire [127:0] cpl_data,
    output wire [15:0]  cpl_data_keep,
    output wire         cpl_data_last,

    output reg  [31:0]  m_axil_awaddr,
    output reg          m_axil_awvalid,
    input  wire         m_axil_awready,
    output reg  [31:0]  m_axil_wdata,
    output reg  [3:0]   m_axil_wstrb,
    output reg          m_axil_wvalid,
    input  wire         m_axil_wready,
    input  wire [1:0]   m_axil_bresp,
    input  wire         m_axil_bvalid,
    output wire         m_axil_bready,

    output reg  [31:0]  m_axil_araddr,
    output reg          m_axil_arvalid,
    input  wire         m_axil_arready,
    input  wire [31:0]  m_axil_rdata,
    input  wire [1:0]   m_axil_rresp,
    input  wire         m_axil_rvalid,
    output wire         m_axil_rready,

    output wire         busy,
    output reg          ur_pulse,
    output reg          ca_pulse,
    output reg          posted_drop_pulse,
    output reg          axi_error_pulse,
    output reg          payload_error_pulse,

    output reg  [31:0]  mem_request_count,
    output reg  [31:0]  mem_read_count,
    output reg  [31:0]  mem_write_count,
    output reg  [31:0]  axi_read_count,
    output reg  [31:0]  axi_write_count,
    output reg  [31:0]  sc_completion_count,
    output reg  [31:0]  ur_completion_count,
    output reg  [31:0]  ca_completion_count,
    output reg  [31:0]  posted_drop_count,
    output reg  [31:0]  poisoned_write_count,
    output reg  [31:0]  axi_read_error_count,
    output reg  [31:0]  axi_write_error_count,
    output reg  [31:0]  payload_protocol_error_count
);
    localparam [3:0] S_IDLE       = 4'd0;
    localparam [3:0] S_W_FETCH    = 4'd1;
    localparam [3:0] S_W_AXI      = 4'd2;
    localparam [3:0] S_W_B        = 4'd3;
    localparam [3:0] S_W_DRAIN    = 4'd4;
    localparam [3:0] S_R_PLAN     = 4'd5;
    localparam [3:0] S_R_AR       = 4'd6;
    localparam [3:0] S_R_R        = 4'd7;
    localparam [3:0] S_CPL_DESC   = 4'd8;
    localparam [3:0] S_CPL_DATA   = 4'd9;

    localparam [2:0] CPL_SC = 3'b000;
    localparam [2:0] CPL_UR = 3'b001;
    localparam [2:0] CPL_CA = 3'b100;

    function automatic [31:0] sat_inc32(input [31:0] value);
        begin
            sat_inc32 = (&value) ? value : value + 1'b1;
        end
    endfunction

    function automatic [1:0] first_offset(input [3:0] be);
        begin
            if (be[0])      first_offset = 2'd0;
            else if (be[1]) first_offset = 2'd1;
            else if (be[2]) first_offset = 2'd2;
            else if (be[3]) first_offset = 2'd3;
            else            first_offset = 2'd0;
        end
    endfunction

    function automatic [1:0] trailing_disabled(input [3:0] be);
        begin
            if (be[3])      trailing_disabled = 2'd0;
            else if (be[2]) trailing_disabled = 2'd1;
            else if (be[1]) trailing_disabled = 2'd2;
            else if (be[0]) trailing_disabled = 2'd3;
            else            trailing_disabled = 2'd0;
        end
    endfunction

    function automatic [12:0] request_byte_count(
        input [10:0] length_dw,
        input [3:0] first_be,
        input [3:0] last_be
    );
        reg [12:0] full_bytes;
        begin
            full_bytes = {length_dw, 2'b00};
            if ((length_dw == 1) && (first_be == 0))
                request_byte_count = 13'd1;
            else if (length_dw == 1)
                request_byte_count = full_bytes -
                                     {11'd0, first_offset(first_be)} -
                                     {11'd0, trailing_disabled(first_be)};
            else
                request_byte_count = full_bytes -
                                     {11'd0, first_offset(first_be)} -
                                     {11'd0, trailing_disabled(last_be)};
        end
    endfunction

    function automatic [3:0] request_dw_be(
        input [10:0] index,
        input [10:0] length_dw,
        input [3:0] first_be,
        input [3:0] last_be
    );
        begin
            if (length_dw == 1)
                request_dw_be = first_be;
            else if (index == 0)
                request_dw_be = first_be;
            else if (index == (length_dw - 1'b1))
                request_dw_be = last_be;
            else
                request_dw_be = 4'hf;
        end
    endfunction

    function automatic [31:0] mask_read_data(
        input [31:0] data,
        input [3:0] be
    );
        begin
            mask_read_data = {
                be[3] ? data[31:24] : 8'd0,
                be[2] ? data[23:16] : 8'd0,
                be[1] ? data[15:8]  : 8'd0,
                be[0] ? data[7:0]   : 8'd0
            };
        end
    endfunction

    function automatic [15:0] dword_keep(input [1:0] length_mod);
        begin
            case (length_mod)
                2'd1: dword_keep = 16'h000f;
                2'd2: dword_keep = 16'h00ff;
                2'd3: dword_keep = 16'h0fff;
                default: dword_keep = 16'hffff;
            endcase
        end
    endfunction

    function automatic [3:0] completion_beats(input [5:0] length_dw);
        begin
            completion_beats = length_dw[5:2];
            if (|length_dw[1:0])
                completion_beats = completion_beats + 4'd1;
        end
    endfunction

    function automatic [31:0] select_beat_dw(
        input [127:0] beat,
        input [1:0] index
    );
        begin
            case (index)
                2'd0: select_beat_dw = beat[31:0];
                2'd1: select_beat_dw = beat[63:32];
                2'd2: select_beat_dw = beat[95:64];
                default: select_beat_dw = beat[127:96];
            endcase
        end
    endfunction

    reg [3:0] state;

    reg [10:0] req_length_reg;
    reg [3:0] req_first_be_reg;
    reg [3:0] req_last_be_reg;
    reg [15:0] req_requester_id_reg;
    reg [7:0] req_tag_reg;
    reg [2:0] req_tc_reg;
    reg [2:0] req_attr_reg;
    reg [15:0] req_completer_id_reg;

    reg [127:0] write_beat_data;
    reg [2:0] write_beat_dw_count;
    reg write_beat_last;
    reg [1:0] write_subindex;
    reg [10:0] write_dw_index;
    reg [10:0] write_remaining_dw;
    reg [11:0] write_relative_address;
    reg write_aw_done;
    reg write_w_done;

    reg [31:0] read_buffer [0:31];
    reg [31:0] read_current_address;
    reg [11:0] read_relative_address;
    reg [10:0] read_remaining_dw;
    reg [10:0] read_dw_index;
    reg [12:0] read_remaining_byte_count;
    reg [1:0] read_first_offset;
    reg [1:0] read_last_tail;
    reg [5:0] read_chunk_dw;
    reg [5:0] read_chunk_index;

    reg cpl_has_data_reg;
    reg [2:0] cpl_status_reg;
    reg [12:0] cpl_byte_count_reg;
    reg [6:0] cpl_lower_address_reg;
    reg [5:0] cpl_length_dw_reg;
    reg cpl_terminal_reg;
    reg [12:0] cpl_span_bytes_reg;
    reg [3:0] cpl_beat_index;

    wire mem_req_fire = mem_req_valid && mem_req_ready;
    wire mem_w_fire = mem_w_valid && mem_w_ready;
    wire cpl_req_fire = cpl_req_valid && cpl_req_ready;
    wire cpl_data_fire = cpl_data_valid && cpl_data_ready;
    wire aw_fire = m_axil_awvalid && m_axil_awready;
    wire w_fire = m_axil_wvalid && m_axil_wready;
    wire b_fire = m_axil_bvalid && m_axil_bready;
    wire ar_fire = m_axil_arvalid && m_axil_arready;
    wire r_fire = m_axil_rvalid && m_axil_rready;

    wire incoming_read_length_valid =
        (mem_req_length_dw >= 1) && (mem_req_length_dw <= 1024);
    wire incoming_write_length_valid =
        (mem_req_length_dw >= 1) && (mem_req_length_dw <= 32);
    wire [12:0] incoming_span_bytes =
        ({2'd0, mem_req_length_dw} << 2);
    wire [12:0] incoming_bar_end_offset =
        {1'b0, mem_req_address[11:0]} + incoming_span_bytes;
    wire incoming_format_ok =
        mem_req_64bit || (mem_req_address[63:32] == 0);
    wire incoming_bar_range_hit =
        incoming_format_ok && (mem_req_address[1:0] == 0) &&
        (mem_req_address[63:32] == 0) &&
        (mem_req_address[31:12] == bar0_base[31:12]) &&
        (incoming_bar_end_offset <= 13'd4096);
    wire incoming_config_hit =
        memory_space_enable && !bar0_probe_active;
    wire incoming_request_hit = incoming_config_hit && incoming_bar_range_hit;
    wire incoming_zero_length =
        (mem_req_length_dw == 1) && (mem_req_first_be == 0);

    wire [2:0] expected_write_beat_dw =
        (write_remaining_dw >= 4) ? 3'd4 : write_remaining_dw[2:0];
    wire [15:0] expected_write_keep =
        (write_remaining_dw >= 4) ? 16'hffff :
                                    dword_keep(write_remaining_dw[1:0]);
    wire expected_write_last = (write_remaining_dw <= 4);

    wire [5:0] read_dw_to_128 =
        6'd32 - {1'b0, read_current_address[6:2]};
    wire [10:0] read_dw_to_4k =
        11'd1024 - {1'b0, read_current_address[11:2]};
    reg [10:0] planned_chunk_dw_wide;
    always @* begin
        if (read_remaining_dw <= 32) begin
            planned_chunk_dw_wide = read_remaining_dw;
            if (planned_chunk_dw_wide > read_dw_to_4k)
                planned_chunk_dw_wide = read_dw_to_4k;
        end else begin
            planned_chunk_dw_wide = 11'd32;
            if (planned_chunk_dw_wide > {5'd0, read_dw_to_128})
                planned_chunk_dw_wide = {5'd0, read_dw_to_128};
            if (planned_chunk_dw_wide > read_dw_to_4k)
                planned_chunk_dw_wide = read_dw_to_4k;
        end
    end
    wire [5:0] planned_chunk_dw = planned_chunk_dw_wide[5:0];

    wire [10:0] current_read_global_index =
        read_dw_index + {5'd0, read_chunk_index};
    wire [3:0] current_read_be = request_dw_be(
        current_read_global_index, req_length_reg,
        req_first_be_reg, req_last_be_reg);

    wire [3:0] next_write_be = request_dw_be(
        write_dw_index + 1'b1, req_length_reg,
        req_first_be_reg, req_last_be_reg);

    wire [3:0] cpl_total_beats = completion_beats(cpl_length_dw_reg);
    assign cpl_data_last =
        ((cpl_beat_index + 1'b1) == cpl_total_beats);
    assign cpl_data_keep = cpl_data_last ?
        dword_keep(cpl_length_dw_reg[1:0]) : 16'hffff;
    wire [4:0] cpl_buffer_base = {cpl_beat_index[2:0], 2'b00};
    assign cpl_data = {
        read_buffer[cpl_buffer_base + 3],
        read_buffer[cpl_buffer_base + 2],
        read_buffer[cpl_buffer_base + 1],
        read_buffer[cpl_buffer_base]
    };

    assign mem_req_ready = rst_n && !hot_reset && (state == S_IDLE);
    assign mem_w_ready = rst_n &&
        ((state == S_W_FETCH) || (state == S_W_DRAIN));
    assign busy = (state != S_IDLE);

    assign cpl_req_valid = rst_n && (state == S_CPL_DESC);
    assign cpl_req_has_data = cpl_has_data_reg;
    assign cpl_req_poisoned = 1'b0;
    assign cpl_req_status = cpl_status_reg;
    assign cpl_req_bcm = 1'b0;
    assign cpl_req_byte_count = cpl_byte_count_reg;
    assign cpl_req_completer_id = req_completer_id_reg;
    assign cpl_req_requester_id = req_requester_id_reg;
    assign cpl_req_tag = req_tag_reg;
    assign cpl_req_lower_address = cpl_lower_address_reg;
    assign cpl_req_length_dw = cpl_length_dw_reg;
    assign cpl_req_tc = req_tc_reg;
    assign cpl_req_attr = req_attr_reg;

    assign cpl_data_valid = rst_n && (state == S_CPL_DATA);
    assign m_axil_bready = rst_n && (state == S_W_B);
    assign m_axil_rready = rst_n && (state == S_R_R);

    // read_buffer按架构约定不复位。把阵列写端口与带异步复位的主状态机
    // 分离，避免综合器把“仅在非复位分支赋值”误判为阵列Set/Reset。
    // 状态和握手信号会在rst_n=0时异步回到IDLE/无效，因此无需额外门控。
    always @(posedge clk) begin
        // miss/poison的零长度Read不会进入CPL_DATA，允许同样写入无效缓存；
        // 这样dummy写使能无需串过完整BAR命中比较，避免形成高扇出深路径。
        if ((state == S_IDLE) && mem_req_fire && !mem_req_write &&
            incoming_zero_length) begin
            read_buffer[0] <= 32'd0;
        end else if ((state == S_R_R) && r_fire &&
                     (m_axil_rresp != 2'b10) &&
                     (m_axil_rresp != 2'b11)) begin
            read_buffer[read_chunk_index[4:0]] <=
                mask_read_data(m_axil_rdata, current_read_be);
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            req_length_reg <= 0;
            req_first_be_reg <= 0;
            req_last_be_reg <= 0;
            req_requester_id_reg <= 0;
            req_tag_reg <= 0;
            req_tc_reg <= 0;
            req_attr_reg <= 0;
            req_completer_id_reg <= 0;

            write_beat_data <= 0;
            write_beat_dw_count <= 0;
            write_beat_last <= 0;
            write_subindex <= 0;
            write_dw_index <= 0;
            write_remaining_dw <= 0;
            write_relative_address <= 0;
            write_aw_done <= 0;
            write_w_done <= 0;

            read_current_address <= 0;
            read_relative_address <= 0;
            read_remaining_dw <= 0;
            read_dw_index <= 0;
            read_remaining_byte_count <= 0;
            read_first_offset <= 0;
            read_last_tail <= 0;
            read_chunk_dw <= 0;
            read_chunk_index <= 0;

            cpl_has_data_reg <= 0;
            cpl_status_reg <= CPL_SC;
            cpl_byte_count_reg <= 0;
            cpl_lower_address_reg <= 0;
            cpl_length_dw_reg <= 0;
            cpl_terminal_reg <= 0;
            cpl_span_bytes_reg <= 0;
            cpl_beat_index <= 0;

            m_axil_awaddr <= 0;
            m_axil_awvalid <= 0;
            m_axil_wdata <= 0;
            m_axil_wstrb <= 0;
            m_axil_wvalid <= 0;
            m_axil_araddr <= 0;
            m_axil_arvalid <= 0;

            ur_pulse <= 0;
            ca_pulse <= 0;
            posted_drop_pulse <= 0;
            axi_error_pulse <= 0;
            payload_error_pulse <= 0;

            mem_request_count <= 0;
            mem_read_count <= 0;
            mem_write_count <= 0;
            axi_read_count <= 0;
            axi_write_count <= 0;
            sc_completion_count <= 0;
            ur_completion_count <= 0;
            ca_completion_count <= 0;
            posted_drop_count <= 0;
            poisoned_write_count <= 0;
            axi_read_error_count <= 0;
            axi_write_error_count <= 0;
            payload_protocol_error_count <= 0;
        end else begin
            ur_pulse <= 1'b0;
            ca_pulse <= 1'b0;
            posted_drop_pulse <= 1'b0;
            axi_error_pulse <= 1'b0;
            payload_error_pulse <= 1'b0;

            case (state)
                S_IDLE: begin
                    m_axil_awvalid <= 1'b0;
                    m_axil_wvalid <= 1'b0;
                    m_axil_arvalid <= 1'b0;
                    if (mem_req_fire) begin
                        mem_request_count <= sat_inc32(mem_request_count);
                        req_length_reg <= mem_req_length_dw;
                        req_first_be_reg <= mem_req_first_be;
                        req_last_be_reg <= mem_req_last_be;
                        req_requester_id_reg <= mem_req_requester_id;
                        req_tag_reg <= mem_req_tag;
                        req_tc_reg <= mem_req_tc;
                        req_attr_reg <= mem_req_attr;
                        req_completer_id_reg <= local_completer_id;

                        if (mem_req_write) begin
                            mem_write_count <= sat_inc32(mem_write_count);
                            write_dw_index <= 0;
                            write_remaining_dw <= mem_req_length_dw;
                            write_relative_address <=
                                mem_req_address[11:0] - bar0_base[11:0];

                            if (mem_req_poisoned ||
                                !incoming_write_length_valid ||
                                !incoming_request_hit) begin
                                state <= S_W_DRAIN;
                                posted_drop_pulse <= 1'b1;
                                posted_drop_count <= sat_inc32(posted_drop_count);
                                if (mem_req_poisoned)
                                    poisoned_write_count <=
                                        sat_inc32(poisoned_write_count);
                            end else if (incoming_zero_length) begin
                                // 合法零长度Write只消费Payload，不产生副作用或错误。
                                state <= S_W_DRAIN;
                            end else begin
                                state <= S_W_FETCH;
                            end
                        end else begin
                            mem_read_count <= sat_inc32(mem_read_count);
                            read_current_address <= mem_req_address[31:0];
                            read_relative_address <=
                                mem_req_address[11:0] - bar0_base[11:0];
                            read_remaining_dw <= mem_req_length_dw;
                            read_dw_index <= 0;
                            read_remaining_byte_count <= request_byte_count(
                                mem_req_length_dw, mem_req_first_be,
                                mem_req_last_be);
                            read_first_offset <= first_offset(mem_req_first_be);
                            read_last_tail <= trailing_disabled(
                                (mem_req_length_dw == 1) ?
                                    mem_req_first_be : mem_req_last_be);

                            if (mem_req_poisoned) begin
                                cpl_has_data_reg <= 1'b0;
                                cpl_status_reg <= CPL_CA;
                                cpl_byte_count_reg <= 0;
                                cpl_lower_address_reg <= 0;
                                cpl_length_dw_reg <= 0;
                                cpl_terminal_reg <= 1'b1;
                                state <= S_CPL_DESC;
                            end else if (!incoming_read_length_valid ||
                                         !incoming_request_hit) begin
                                cpl_has_data_reg <= 1'b0;
                                cpl_status_reg <= CPL_UR;
                                cpl_byte_count_reg <= 0;
                                cpl_lower_address_reg <= 0;
                                cpl_length_dw_reg <= 0;
                                cpl_terminal_reg <= 1'b1;
                                state <= S_CPL_DESC;
                            end else if (incoming_zero_length) begin
                                read_chunk_dw <= 6'd1;
                                cpl_has_data_reg <= 1'b1;
                                cpl_status_reg <= CPL_SC;
                                cpl_byte_count_reg <= 13'd1;
                                cpl_lower_address_reg <=
                                    mem_req_address[6:0];
                                cpl_length_dw_reg <= 6'd1;
                                cpl_terminal_reg <= 1'b1;
                                cpl_span_bytes_reg <= 13'd1;
                                state <= S_CPL_DESC;
                            end else begin
                                state <= S_R_PLAN;
                            end
                        end
                    end
                end

                S_W_FETCH: begin
                    if (mem_w_fire) begin
                        if ((mem_w_keep != expected_write_keep) ||
                            (mem_w_last != expected_write_last)) begin
                            payload_error_pulse <= 1'b1;
                            payload_protocol_error_count <=
                                sat_inc32(payload_protocol_error_count);
                            posted_drop_pulse <= 1'b1;
                            posted_drop_count <= sat_inc32(posted_drop_count);
                            if (mem_w_last)
                                state <= S_IDLE;
                            else
                                state <= S_W_DRAIN;
                        end else begin
                            write_beat_data <= mem_w_data;
                            write_beat_dw_count <= expected_write_beat_dw;
                            write_beat_last <= mem_w_last;
                            write_subindex <= 0;
                            write_aw_done <= 1'b0;
                            write_w_done <= 1'b0;
                            m_axil_awaddr <= {20'd0, write_relative_address};
                            m_axil_awvalid <= 1'b1;
                            m_axil_wdata <= mem_w_data[31:0];
                            m_axil_wstrb <= request_dw_be(
                                write_dw_index, req_length_reg,
                                req_first_be_reg, req_last_be_reg);
                            m_axil_wvalid <= 1'b1;
                            state <= S_W_AXI;
                        end
                    end
                end

                S_W_AXI: begin
                    if (aw_fire) begin
                        m_axil_awvalid <= 1'b0;
                        write_aw_done <= 1'b1;
                    end
                    if (w_fire) begin
                        m_axil_wvalid <= 1'b0;
                        write_w_done <= 1'b1;
                    end
                    if ((write_aw_done || aw_fire) &&
                        (write_w_done || w_fire))
                        state <= S_W_B;
                end

                S_W_B: begin
                    if (b_fire) begin
                        axi_write_count <= sat_inc32(axi_write_count);
                        if ((m_axil_bresp == 2'b10) ||
                            (m_axil_bresp == 2'b11)) begin
                            axi_error_pulse <= 1'b1;
                            axi_write_error_count <=
                                sat_inc32(axi_write_error_count);
                            posted_drop_pulse <= 1'b1;
                            posted_drop_count <= sat_inc32(posted_drop_count);
                            if (write_beat_last)
                                state <= S_IDLE;
                            else
                                state <= S_W_DRAIN;
                        end else if ((write_subindex + 1'b1) <
                                     write_beat_dw_count) begin
                            write_subindex <= write_subindex + 1'b1;
                            write_dw_index <= write_dw_index + 1'b1;
                            write_relative_address <=
                                write_relative_address + 4;
                            write_aw_done <= 1'b0;
                            write_w_done <= 1'b0;
                            m_axil_awaddr <=
                                {20'd0, write_relative_address + 12'd4};
                            m_axil_awvalid <= 1'b1;
                            m_axil_wdata <= select_beat_dw(
                                write_beat_data, write_subindex + 1'b1);
                            m_axil_wstrb <= next_write_be;
                            m_axil_wvalid <= 1'b1;
                            state <= S_W_AXI;
                        end else begin
                            // 本拍内前面的 DWORD 已在每次 AXI B 响应后逐个推进；
                            // 到达这里时，地址和索引正指向本拍最后一个 DWORD。
                            // 因此只再推进一次，不能重复加整拍 DWORD 数。
                            write_dw_index <= write_dw_index + 1'b1;
                            write_remaining_dw <=
                                write_remaining_dw -
                                {8'd0, write_beat_dw_count};
                            write_relative_address <=
                                write_relative_address + 12'd4;
                            if (write_beat_last)
                                state <= S_IDLE;
                            else
                                state <= S_W_FETCH;
                        end
                    end
                end

                S_W_DRAIN: begin
                    if (mem_w_fire && mem_w_last)
                        state <= S_IDLE;
                end

                S_R_PLAN: begin
                    read_chunk_dw <= planned_chunk_dw;
                    read_chunk_index <= 0;
                    m_axil_araddr <= {20'd0, read_relative_address};
                    m_axil_arvalid <= 1'b1;
                    state <= S_R_AR;
                end

                S_R_AR: begin
                    if (ar_fire) begin
                        m_axil_arvalid <= 1'b0;
                        state <= S_R_R;
                    end
                end

                S_R_R: begin
                    if (r_fire) begin
                        axi_read_count <= sat_inc32(axi_read_count);
                        if ((m_axil_rresp == 2'b10) ||
                            (m_axil_rresp == 2'b11)) begin
                            axi_error_pulse <= 1'b1;
                            axi_read_error_count <=
                                sat_inc32(axi_read_error_count);
                            cpl_has_data_reg <= 1'b0;
                            cpl_status_reg <= CPL_CA;
                            cpl_byte_count_reg <= 0;
                            cpl_lower_address_reg <= 0;
                            cpl_length_dw_reg <= 0;
                            cpl_terminal_reg <= 1'b1;
                            state <= S_CPL_DESC;
                        end else begin
                            if ((read_chunk_index + 1'b1) == read_chunk_dw) begin
                                cpl_has_data_reg <= 1'b1;
                                cpl_status_reg <= CPL_SC;
                                cpl_byte_count_reg <=
                                    read_remaining_byte_count;
                                cpl_lower_address_reg <=
                                    (read_dw_index == 0) ?
                                    (read_current_address[6:0] +
                                     {5'd0, read_first_offset}) : 7'd0;
                                cpl_length_dw_reg <= read_chunk_dw;
                                cpl_terminal_reg <=
                                    (read_remaining_dw ==
                                     {5'd0, read_chunk_dw});
                                cpl_span_bytes_reg <=
                                    ({7'd0, read_chunk_dw} << 2) -
                                    ((read_dw_index == 0) ?
                                        {11'd0, read_first_offset} : 13'd0) -
                                    ((read_remaining_dw ==
                                      {5'd0, read_chunk_dw}) ?
                                        {11'd0, read_last_tail} : 13'd0);
                                state <= S_CPL_DESC;
                            end else begin
                                read_chunk_index <= read_chunk_index + 1'b1;
                                m_axil_araddr <= {20'd0,
                                    read_relative_address +
                                    ({6'd0, read_chunk_index + 1'b1} << 2)};
                                m_axil_arvalid <= 1'b1;
                                state <= S_R_AR;
                            end
                        end
                    end
                end

                S_CPL_DESC: begin
                    if (cpl_req_fire) begin
                        if (cpl_status_reg == CPL_SC)
                            sc_completion_count <=
                                sat_inc32(sc_completion_count);
                        else if (cpl_status_reg == CPL_UR) begin
                            ur_pulse <= 1'b1;
                            ur_completion_count <=
                                sat_inc32(ur_completion_count);
                        end else begin
                            ca_pulse <= 1'b1;
                            ca_completion_count <=
                                sat_inc32(ca_completion_count);
                        end

                        if (cpl_has_data_reg) begin
                            cpl_beat_index <= 0;
                            state <= S_CPL_DATA;
                        end else begin
                            state <= S_IDLE;
                        end
                    end
                end

                S_CPL_DATA: begin
                    if (cpl_data_fire) begin
                        if (cpl_data_last) begin
                            if (cpl_terminal_reg) begin
                                read_remaining_byte_count <= 0;
                                state <= S_IDLE;
                            end else begin
                                read_current_address <= read_current_address +
                                    ({26'd0, read_chunk_dw} << 2);
                                read_relative_address <= read_relative_address +
                                    ({6'd0, read_chunk_dw} << 2);
                                read_remaining_dw <=
                                    read_remaining_dw -
                                    {5'd0, read_chunk_dw};
                                read_dw_index <= read_dw_index +
                                    {5'd0, read_chunk_dw};
                                read_remaining_byte_count <=
                                    read_remaining_byte_count -
                                    cpl_span_bytes_reg;
                                state <= S_R_PLAN;
                            end
                        end else begin
                            cpl_beat_index <= cpl_beat_index + 1'b1;
                        end
                    end
                end

                default: begin
                    state <= S_IDLE;
                    m_axil_awvalid <= 1'b0;
                    m_axil_wvalid <= 1'b0;
                    m_axil_arvalid <= 1'b0;
                end
            endcase
        end
    end
endmodule

`default_nettype wire
