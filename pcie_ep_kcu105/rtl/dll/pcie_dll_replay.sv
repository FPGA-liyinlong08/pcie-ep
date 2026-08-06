`timescale 1ns/1ps
`default_nettype none

// 参数化存储器线性地址会把窄环形指针提升为integer；所有指针范围均由下方
// generate约束和显式容量比较保护，关闭Verilator对此类安全提升的重复提示。
/* verilator lint_off WIDTHEXPAND */

module pcie_dll_replay #(
    parameter integer REPLAY_DEPTH = 16,
    parameter integer RX_FRAME_SLOTS = 8,
    parameter integer MAX_TLP_BYTES = 144,
    parameter integer ACK_LATENCY_CYCLES = 128,
    parameter integer REPLAY_TIMEOUT_CYCLES = 2048,
    parameter integer REPLAY_RETRY_LIMIT = 3
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         dll_active,

    input  wire         mac_rx_valid,
    input  wire [15:0]  mac_rx_data,
    input  wire [1:0]   mac_rx_keep,
    input  wire         mac_rx_sop,
    input  wire         mac_rx_eop,
    input  wire         mac_rx_is_dllp,
    input  wire [3:0]   mac_rx_error,

    output reg          mac_tx_valid,
    input  wire         mac_tx_ready,
    output reg  [15:0]  mac_tx_data,
    output reg  [1:0]   mac_tx_keep,
    output reg          mac_tx_sop,
    output reg          mac_tx_eop,
    output reg          mac_tx_is_dllp,
    output reg          mac_tx_bad,

    input  wire         rx_dllp_valid,
    input  wire [31:0]  rx_dllp_data,
    input  wire         rx_dllp_crc_good,
    input  wire [3:0]   rx_dllp_error,

    output wire         tx_ack_dllp_valid,
    input  wire         tx_ack_dllp_ready,
    output wire [31:0]  tx_ack_dllp_data,

    input  wire         tx_tlp_valid,
    output wire         tx_tlp_ready,
    input  wire [127:0] tx_tlp_data,
    input  wire [15:0]  tx_tlp_keep,
    input  wire         tx_tlp_sop,
    input  wire         tx_tlp_eop,
    input  wire [3:0]   tx_tlp_error,
    input  wire [1:0]   tx_tlp_type,
    input  wire [11:0]  tx_tlp_data_credits,

    output reg          rx_tlp_valid,
    input  wire         rx_tlp_ready,
    output reg  [127:0] rx_tlp_data,
    output reg  [15:0]  rx_tlp_keep,
    output reg          rx_tlp_sop,
    output reg          rx_tlp_eop,
    output reg  [3:0]   rx_tlp_error,

    output reg  [1:0]   tx_fc_check_type,
    output reg  [11:0]  tx_fc_check_data_credits,
    input  wire         tx_fc_credit_available,
    output reg          tx_fc_consume_valid,
    output reg  [1:0]   tx_fc_consume_type,
    output reg  [11:0]  tx_fc_consume_data_credits,
    output reg          rx_fc_consume_valid,
    output reg  [1:0]   rx_fc_consume_type,
    output reg  [11:0]  rx_fc_consume_data_credits,

    output reg  [11:0]  next_tx_seq,
    output reg  [11:0]  next_rx_seq,
    output reg  [11:0]  last_acked_seq,
    output wire [$clog2(REPLAY_DEPTH+1)-1:0] replay_occupancy,
    output reg          replay_active,
    output reg          replay_fatal,
    output reg          recovery_req,
    output reg  [31:0]  tx_tlp_count,
    output reg  [31:0]  rx_tlp_count,
    output reg  [31:0]  ack_tx_count,
    output reg  [31:0]  nak_tx_count,
    output reg  [31:0]  replay_count,
    output reg  [31:0]  lcrc_error_count,
    output reg  [31:0]  duplicate_tlp_count,
    output reg  [31:0]  sequence_error_count,
    output reg  [31:0]  ack_error_count,
    output reg  [31:0]  buffer_error_count
);
    localparam integer REPLAY_PTR_W = $clog2(REPLAY_DEPTH);
    localparam integer RX_PTR_W = $clog2(RX_FRAME_SLOTS);
    localparam integer MAX_TLP_BEATS = (MAX_TLP_BYTES + 15) / 16;
    localparam integer MAX_FRAME_BYTES = MAX_TLP_BYTES + 6;
    localparam integer MAX_FRAME_WORDS = (MAX_FRAME_BYTES + 3) / 4;
    localparam integer TX_BEAT_W = (MAX_TLP_BEATS <= 2) ? 1 : $clog2(MAX_TLP_BEATS);
    localparam integer RX_LENGTH_W = $clog2(MAX_FRAME_BYTES + 1);
    localparam integer ACK_TIMER_W = (ACK_LATENCY_CYCLES <= 2) ? 1 :
                                     $clog2(ACK_LATENCY_CYCLES);
    localparam integer REPLAY_TIMER_W = (REPLAY_TIMEOUT_CYCLES <= 2) ? 1 :
                                        $clog2(REPLAY_TIMEOUT_CYCLES);
    localparam integer RETRY_W = (REPLAY_RETRY_LIMIT <= 1) ? 1 :
                                 $clog2(REPLAY_RETRY_LIMIT + 1);

    localparam [2:0] TX_IDLE      = 3'd0;
    localparam [2:0] TX_SEQUENCE  = 3'd1;
    localparam [2:0] TX_BODY      = 3'd2;
    localparam [2:0] TX_CRC_FINAL = 3'd3;
    localparam [2:0] TX_CRC_WAIT  = 3'd4;
    localparam [2:0] TX_LCRC0     = 3'd5;
    localparam [2:0] TX_LCRC1     = 3'd6;

    localparam [2:0] RXP_IDLE   = 3'd0;
    localparam [2:0] RXP_FEED   = 3'd1;
    localparam [2:0] RXP_WAIT   = 3'd2;
    localparam [2:0] RXP_DECIDE = 3'd3;
    localparam [2:0] RXP_OUTPUT = 3'd4;

    function automatic [31:0] sat_inc32(input [31:0] value);
        sat_inc32 = (&value) ? value : value + 1'b1;
    endfunction

    function automatic [4:0] keep_count16(input [15:0] keep);
        integer i;
        begin
            keep_count16 = 0;
            for (i = 0; i < 16; i = i + 1)
                keep_count16 = keep_count16 + keep[i];
        end
    endfunction

    function automatic keep_contiguous16(input [15:0] keep);
        reg [16:0] extended;
        begin
            extended = {1'b0, keep};
            keep_contiguous16 = (keep != 0) &&
                ((extended & (extended + 1'b1)) == 0);
        end
    endfunction

    function automatic [31:0] pack_ack_nak;
        input is_nak;
        input [11:0] seq_value;
        begin
            pack_ack_nak[7:0]   = is_nak ? 8'h10 : 8'h00;
            pack_ack_nak[15:8]  = 8'h00;
            pack_ack_nak[23:16] = {4'h0, seq_value[11:8]};
            pack_ack_nak[31:24] = seq_value[7:0];
        end
    endfunction

    generate
        if ((REPLAY_DEPTH < 2) || (REPLAY_DEPTH > 2048) ||
            ((REPLAY_DEPTH & (REPLAY_DEPTH-1)) != 0)) begin : g_bad_replay_depth
            initial $error("pcie_dll_replay: REPLAY_DEPTH必须是2～2048的2次幂");
        end
        if ((RX_FRAME_SLOTS < 2) ||
            ((RX_FRAME_SLOTS & (RX_FRAME_SLOTS-1)) != 0)) begin : g_bad_rx_slots
            initial $error("pcie_dll_replay: RX_FRAME_SLOTS必须是不小于2的2次幂");
        end
        if ((MAX_TLP_BYTES < 12) || ((MAX_TLP_BYTES & 3) != 0)) begin : g_bad_tlp_bytes
            initial $error("pcie_dll_replay: MAX_TLP_BYTES必须不小于12且DWORD对齐");
        end
        if ((ACK_LATENCY_CYCLES < 4) || (REPLAY_TIMEOUT_CYCLES < 8) ||
            (REPLAY_RETRY_LIMIT < 1)) begin : g_bad_timer
            initial $error("pcie_dll_replay: Timer参数过小");
        end
    endgenerate

    // ---------------------------------------------------------------------
    // TX Replay Window捕获
    // ---------------------------------------------------------------------
    reg [127:0] tx_memory
        [0:REPLAY_DEPTH*MAX_TLP_BEATS-1];
    reg [7:0]   tx_entry_length [0:REPLAY_DEPTH-1];
    reg [1:0]   tx_entry_type [0:REPLAY_DEPTH-1];
    reg [11:0]  tx_entry_data_credits [0:REPLAY_DEPTH-1];
    reg [11:0]  tx_entry_seq [0:REPLAY_DEPTH-1];

    reg [REPLAY_PTR_W:0] tx_write_count;
    reg [REPLAY_PTR_W:0] tx_send_count;
    reg [REPLAY_PTR_W:0] tx_free_count;
    reg [REPLAY_PTR_W:0] replay_cursor;
    reg [REPLAY_PTR_W:0] replay_end;
    wire [REPLAY_PTR_W:0] tx_entry_count = tx_write_count - tx_free_count;
    wire [REPLAY_PTR_W:0] tx_unsent_count = tx_write_count - tx_send_count;
    wire [REPLAY_PTR_W:0] tx_outstanding_count = tx_send_count - tx_free_count;
    assign replay_occupancy = tx_outstanding_count[$clog2(REPLAY_DEPTH+1)-1:0];

    reg tx_capture_active;
    reg tx_capture_bad;
    reg [TX_BEAT_W-1:0] tx_capture_beat;
    reg [7:0] tx_capture_length;
    reg [1:0] tx_capture_type;
    reg [11:0] tx_capture_data_credits;
    reg tx_capture_error_pulse;

    wire [4:0] tx_input_bytes = keep_count16(tx_tlp_keep);
    wire tx_input_keep_ok = keep_contiguous16(tx_tlp_keep) &&
                            (tx_tlp_eop || (tx_tlp_keep == 16'hffff));
    wire [8:0] tx_next_length = {1'b0, tx_capture_active ?
                                 tx_capture_length : 8'd0} + tx_input_bytes;
    wire tx_input_bad = !tx_input_keep_ok || (tx_tlp_error != 0) ||
                        (tx_tlp_type == 2'b11) ||
                        (tx_next_length > MAX_TLP_BYTES);

    assign tx_tlp_ready = rst_n && dll_active &&
        (tx_capture_active || (tx_entry_count < REPLAY_DEPTH));

    wire tx_input_handshake = tx_tlp_valid && tx_tlp_ready;
    wire tx_single_commit = tx_input_handshake && !tx_capture_active &&
        tx_tlp_sop && tx_tlp_eop && !tx_input_bad &&
        (tx_input_bytes >= 12) && ((tx_input_bytes & 3) == 0);
    wire tx_multi_commit = tx_input_handshake && tx_capture_active &&
        tx_tlp_eop && !tx_capture_bad && !tx_input_bad && !tx_tlp_sop &&
        (tx_next_length >= 12) && (tx_next_length <= MAX_TLP_BYTES) &&
        ((tx_next_length & 3) == 0);
    wire tx_entry_commit = tx_single_commit || tx_multi_commit;
    wire [7:0] tx_commit_length = tx_single_commit ?
        {{3{1'b0}}, tx_input_bytes} : tx_next_length[7:0];
    wire [1:0] tx_commit_type = tx_single_commit ?
        tx_tlp_type : tx_capture_type;
    wire [11:0] tx_commit_data_credits = tx_single_commit ?
        tx_tlp_data_credits : tx_capture_data_credits;

    wire tx_mem_write_en = tx_input_handshake && (tx_input_bytes != 0) &&
        ((tx_capture_active && (tx_capture_beat < MAX_TLP_BEATS)) ||
         (!tx_capture_active && tx_tlp_sop));
    wire [TX_BEAT_W-1:0] tx_mem_write_beat =
        tx_capture_active ? tx_capture_beat : {TX_BEAT_W{1'b0}};

    // 存储体和元数据不复位；环形计数器清零后旧内容不可见。独立时钟写口使
    // Vivado可以推断Block RAM，而不会把RAM纳入异步复位敏感进程。
    always @(posedge clk) begin
        if (tx_mem_write_en)
            tx_memory[tx_write_count[REPLAY_PTR_W-1:0]*MAX_TLP_BEATS +
                      tx_mem_write_beat] <= tx_tlp_data;
        if (tx_entry_commit) begin
            tx_entry_length[tx_write_count[REPLAY_PTR_W-1:0]] <= tx_commit_length;
            tx_entry_type[tx_write_count[REPLAY_PTR_W-1:0]] <= tx_commit_type;
            tx_entry_data_credits[tx_write_count[REPLAY_PTR_W-1:0]]
                <= tx_commit_data_credits;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_write_count <= 0;
            tx_capture_active <= 0;
            tx_capture_bad <= 0;
            tx_capture_beat <= 0;
            tx_capture_length <= 0;
            tx_capture_type <= 0;
            tx_capture_data_credits <= 0;
            tx_capture_error_pulse <= 0;
        end else begin
            tx_capture_error_pulse <= 0;
            if (!dll_active) begin
                tx_write_count <= 0;
                tx_capture_active <= 0;
                tx_capture_bad <= 0;
                tx_capture_beat <= 0;
                tx_capture_length <= 0;
            end else if (tx_tlp_valid && tx_tlp_ready) begin
                if (!tx_capture_active) begin
                    tx_capture_active <= !tx_tlp_eop;
                    tx_capture_bad <= tx_input_bad || !tx_tlp_sop;
                    tx_capture_beat <= tx_tlp_eop ? 0 : 1;
                    tx_capture_length <= tx_input_bytes;
                    tx_capture_type <= tx_tlp_type;
                    tx_capture_data_credits <= tx_tlp_data_credits;
                    if (tx_tlp_eop) begin
                        if (!tx_input_bad && tx_tlp_sop &&
                            (tx_input_bytes >= 12) && ((tx_input_bytes & 3) == 0)) begin
                            tx_write_count <= tx_write_count + 1'b1;
                        end else begin
                            tx_capture_error_pulse <= 1'b1;
                        end
                        tx_capture_active <= 0;
                    end
                end else begin
                    tx_capture_bad <= tx_capture_bad || tx_input_bad || tx_tlp_sop;
                    tx_capture_length <= tx_next_length[7:0];
                    tx_capture_beat <= tx_capture_beat + 1'b1;

                    if (tx_tlp_eop) begin
                        if (!tx_capture_bad && !tx_input_bad && !tx_tlp_sop &&
                            (tx_next_length >= 12) && (tx_next_length <= MAX_TLP_BYTES) &&
                            ((tx_next_length & 3) == 0)) begin
                            tx_write_count <= tx_write_count + 1'b1;
                        end else begin
                            tx_capture_error_pulse <= 1'b1;
                        end
                        tx_capture_active <= 0;
                        tx_capture_bad <= 0;
                        tx_capture_beat <= 0;
                        tx_capture_length <= 0;
                    end
                end
            end
        end
    end

    // ---------------------------------------------------------------------
    // TX Sequence、LCRC及16-bit序列化
    // ---------------------------------------------------------------------
    wire crc_session_async_n = rst_n && dll_active;
    wire tx_crc_rst_n;
    wire rx_crc_rst_n;
    reg [1:0] crc_logic_enable_pipe;
    wire crc_logic_ready = crc_logic_enable_pipe[1];
    pcie_reset_sync #(.STAGES(2)) u_tx_crc_reset (
        .clk(clk), .async_release_n(crc_session_async_n), .sync_reset_n(tx_crc_rst_n)
    );
    pcie_reset_sync #(.STAGES(2)) u_rx_crc_reset (
        .clk(clk), .async_release_n(crc_session_async_n), .sync_reset_n(rx_crc_rst_n)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            crc_logic_enable_pipe <= 0;
        else if (!dll_active)
            crc_logic_enable_pipe <= 0;
        else
            crc_logic_enable_pipe <= {crc_logic_enable_pipe[0], 1'b1};
    end

    reg [2:0] tx_state;
    reg [REPLAY_PTR_W-1:0] tx_current_ptr;
    reg [11:0] tx_current_seq;
    reg tx_current_is_replay;
    reg [7:0] tx_current_word_count;
    reg [7:0] tx_word_index;
    reg [15:0] tx_crc_half;
    reg tx_crc_half_valid;
    reg tx_crc_started;
    reg [31:0] tx_lcrc;
    reg initial_send_pulse;
    reg replay_packet_done_pulse;

    reg [127:0] tx_mem_read_data;
    reg tx_fc_credit_available_q;
    wire tx_select_replay = (tx_state == TX_IDLE) && crc_logic_ready &&
        replay_active && !replay_packet_done_pulse && (replay_cursor != replay_end);
    wire tx_select_initial = (tx_state == TX_IDLE) && crc_logic_ready &&
        !replay_active && (tx_unsent_count != 0) && tx_fc_credit_available_q;
    wire tx_mem_load_first = tx_select_replay || tx_select_initial;
    wire [REPLAY_PTR_W-1:0] tx_mem_load_ptr = tx_select_replay ?
        replay_cursor[REPLAY_PTR_W-1:0] : tx_send_count[REPLAY_PTR_W-1:0];
    wire tx_mac_handshake = mac_tx_valid && mac_tx_ready;
    wire tx_mem_load_next = (tx_state == TX_BODY) && tx_mac_handshake &&
        (tx_word_index[2:0] == 3'd7) &&
        (tx_word_index + 1'b1 < tx_current_word_count);

    always @(posedge clk) begin
        if (tx_mem_load_first)
            tx_mem_read_data <= tx_memory[tx_mem_load_ptr*MAX_TLP_BEATS];
        else if (tx_mem_load_next)
            tx_mem_read_data <= tx_memory[tx_current_ptr*MAX_TLP_BEATS +
                ((tx_word_index >> 3) + 1'b1)];
    end

    wire [15:0] tx_body_word =
        tx_mem_read_data[(tx_word_index[2:0]*16) +: 16];

    wire tx_crc_ready;
    wire [31:0] tx_crc_result;
    wire tx_crc_valid;
    wire tx_crc_match_unused;
    wire tx_crc_protocol_error;
    wire tx_crc_busy;
    wire tx_crc_body_feed = (tx_state == TX_BODY) && tx_mac_handshake &&
                            tx_crc_half_valid;
    wire tx_crc_final_feed = (tx_state == TX_CRC_FINAL);
    wire tx_crc_input_valid = tx_crc_rst_n &&
                              (tx_crc_body_feed || tx_crc_final_feed);
    wire [31:0] tx_crc_input_data = tx_crc_body_feed ?
        {tx_body_word, tx_crc_half} : {16'd0, tx_crc_half};
    wire [3:0] tx_crc_input_keep = tx_crc_body_feed ? 4'hf : 4'h3;
    wire tx_crc_input_start = !tx_crc_started;
    wire tx_crc_input_last = tx_crc_final_feed;

    pcie_crc32_lcrc u_tx_lcrc (
        .clk(clk), .rst_n(tx_crc_rst_n), .start(tx_crc_input_start),
        .data(tx_crc_input_data), .keep(tx_crc_input_keep),
        .last(tx_crc_input_last), .valid(tx_crc_input_valid),
        .ready(tx_crc_ready), .crc_result(tx_crc_result),
        .crc_valid(tx_crc_valid), .crc_match(tx_crc_match_unused),
        .protocol_error(tx_crc_protocol_error), .busy(tx_crc_busy)
    );

    // 信用查询结果打一拍后再启动新TLP，切断Replay指针、FC比较器和TX状态机
    // 之间的长组合路径。DLL只有一个TLP发送者，因此采样到的许可在消费前
    // 不会被其他本地请求抢占。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            tx_fc_credit_available_q <= 1'b0;
        else if (!dll_active || (tx_unsent_count == 0))
            tx_fc_credit_available_q <= 1'b0;
        else
            tx_fc_credit_available_q <= tx_fc_credit_available;
    end

    always @* begin
        // 空队列时读出的元数据不参与tx_select_initial；保持无门控地址可避免
        // tx_write_count穿过完整FC比较网络形成状态机使能长路径。
        tx_fc_check_type =
            tx_entry_type[tx_send_count[REPLAY_PTR_W-1:0]];
        tx_fc_check_data_credits =
            tx_entry_data_credits[tx_send_count[REPLAY_PTR_W-1:0]];

        mac_tx_valid = 1'b0;
        mac_tx_data = 16'd0;
        mac_tx_keep = 2'b00;
        mac_tx_sop = 1'b0;
        mac_tx_eop = 1'b0;
        mac_tx_is_dllp = 1'b0;
        mac_tx_bad = 1'b0;
        case (tx_state)
            TX_SEQUENCE: begin
                mac_tx_valid = dll_active;
                mac_tx_data = {tx_current_seq[7:0], 4'h0, tx_current_seq[11:8]};
                mac_tx_keep = 2'b11;
                mac_tx_sop = 1'b1;
            end
            TX_BODY: begin
                mac_tx_valid = dll_active;
                mac_tx_data = tx_body_word;
                mac_tx_keep = 2'b11;
            end
            TX_LCRC0: begin
                mac_tx_valid = dll_active;
                mac_tx_data = tx_lcrc[15:0];
                mac_tx_keep = 2'b11;
            end
            TX_LCRC1: begin
                mac_tx_valid = dll_active;
                mac_tx_data = tx_lcrc[31:16];
                mac_tx_keep = 2'b11;
                mac_tx_eop = 1'b1;
            end
            default: begin end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state <= TX_IDLE;
            tx_send_count <= 0;
            next_tx_seq <= 0;
            tx_current_ptr <= 0;
            tx_current_seq <= 0;
            tx_current_is_replay <= 0;
            tx_current_word_count <= 0;
            tx_word_index <= 0;
            tx_crc_half <= 0;
            tx_crc_half_valid <= 0;
            tx_crc_started <= 0;
            tx_lcrc <= 0;
            tx_fc_consume_valid <= 0;
            tx_fc_consume_type <= 0;
            tx_fc_consume_data_credits <= 0;
            initial_send_pulse <= 0;
            replay_packet_done_pulse <= 0;
            tx_tlp_count <= 0;
            replay_count <= 0;
        end else begin
            tx_fc_consume_valid <= 0;
            initial_send_pulse <= 0;
            replay_packet_done_pulse <= 0;
            if (!dll_active) begin
                tx_state <= TX_IDLE;
                tx_send_count <= 0;
                next_tx_seq <= 0;
                tx_crc_half_valid <= 0;
                tx_crc_started <= 0;
            end else begin
                case (tx_state)
                    TX_IDLE: begin
                        tx_crc_half_valid <= 0;
                        tx_crc_started <= 0;
                        tx_word_index <= 0;
                        if (tx_select_replay) begin
                            tx_current_ptr <= replay_cursor[REPLAY_PTR_W-1:0];
                            tx_current_seq <=
                                tx_entry_seq[replay_cursor[REPLAY_PTR_W-1:0]];
                            tx_current_word_count <=
                                tx_entry_length[replay_cursor[REPLAY_PTR_W-1:0]] >> 1;
                            tx_current_is_replay <= 1'b1;
                            tx_state <= TX_SEQUENCE;
                        end else if (tx_select_initial) begin
                            tx_current_ptr <= tx_send_count[REPLAY_PTR_W-1:0];
                            tx_current_seq <= next_tx_seq;
                            tx_current_word_count <=
                                tx_entry_length[tx_send_count[REPLAY_PTR_W-1:0]] >> 1;
                            tx_current_is_replay <= 1'b0;
                            tx_state <= TX_SEQUENCE;
                        end
                    end
                    TX_SEQUENCE: begin
                        if (tx_mac_handshake) begin
                            tx_crc_half <= mac_tx_data;
                            tx_crc_half_valid <= 1'b1;
                            tx_word_index <= 0;
                            tx_state <= TX_BODY;
                            if (!tx_current_is_replay) begin
                                tx_send_count <= tx_send_count + 1'b1;
                                next_tx_seq <= next_tx_seq + 1'b1;
                                tx_fc_consume_valid <= 1'b1;
                                tx_fc_consume_type <= tx_entry_type[tx_current_ptr];
                                tx_fc_consume_data_credits <=
                                    tx_entry_data_credits[tx_current_ptr];
                                initial_send_pulse <= 1'b1;
                                tx_tlp_count <= sat_inc32(tx_tlp_count);
                            end
                        end
                    end
                    TX_BODY: begin
                        if (tx_mac_handshake) begin
                            if (tx_crc_half_valid) begin
                                tx_crc_half_valid <= 1'b0;
                                tx_crc_started <= 1'b1;
                            end else begin
                                tx_crc_half <= tx_body_word;
                                tx_crc_half_valid <= 1'b1;
                            end
                            if (tx_word_index + 1'b1 == tx_current_word_count) begin
                                tx_state <= TX_CRC_FINAL;
                            end else begin
                                tx_word_index <= tx_word_index + 1'b1;
                            end
                        end
                    end
                    TX_CRC_FINAL: begin
                        tx_crc_started <= 1'b1;
                        tx_state <= TX_CRC_WAIT;
                    end
                    TX_CRC_WAIT: begin
                        if (tx_crc_valid) begin
                            tx_lcrc <= tx_crc_result;
                            tx_state <= TX_LCRC0;
                        end
                    end
                    TX_LCRC0: begin
                        if (tx_mac_handshake)
                            tx_state <= TX_LCRC1;
                    end
                    TX_LCRC1: begin
                        if (tx_mac_handshake) begin
                            tx_state <= TX_IDLE;
                            if (tx_current_is_replay) begin
                                replay_packet_done_pulse <= 1'b1;
                                replay_count <= sat_inc32(replay_count);
                            end
                        end
                    end
                    default: tx_state <= TX_IDLE;
                endcase
            end
        end
    end

    wire tx_sequence_commit = (tx_state == TX_SEQUENCE) && tx_mac_handshake &&
                              !tx_current_is_replay;
    always @(posedge clk) begin
        if (tx_sequence_commit)
            tx_entry_seq[tx_current_ptr] <= tx_current_seq;
    end

    // ---------------------------------------------------------------------
    // RX MAC Frame Slots：16-bit不可反压输入先打包成32-bit同步RAM。
    // ---------------------------------------------------------------------
    reg [31:0] rx_frame_memory
        [0:RX_FRAME_SLOTS*MAX_FRAME_WORDS-1];
    reg [127:0] rx_payload_memory
        [0:RX_FRAME_SLOTS*MAX_TLP_BEATS-1];
    reg [RX_LENGTH_W-1:0] rx_frame_length [0:RX_FRAME_SLOTS-1];
    reg [3:0] rx_frame_error [0:RX_FRAME_SLOTS-1];
    reg [RX_PTR_W:0] rx_write_count;
    reg [RX_PTR_W:0] rx_read_count;
    wire [RX_PTR_W:0] rx_slot_count = rx_write_count - rx_read_count;

    reg rx_capture_active;
    reg rx_capture_drop;
    reg [RX_LENGTH_W-1:0] rx_capture_length;
    reg [3:0] rx_capture_error;
    reg [31:0] rx_pack_word;
    reg [2:0] rx_pack_count;
    reg [$clog2(MAX_FRAME_WORDS)-1:0] rx_capture_word;
    reg rx_capture_error_pulse;

    wire [1:0] rx_input_bytes = (mac_rx_keep == 2'b11) ? 2'd2 :
                                (mac_rx_keep == 2'b01) ? 2'd1 : 2'd0;
    wire rx_input_keep_ok = (mac_rx_keep == 2'b01) ||
                            (mac_rx_keep == 2'b11) ||
                            ((mac_rx_keep == 2'b00) && mac_rx_eop);
    wire rx_start_accept = !rx_capture_active && mac_rx_sop &&
                           (rx_slot_count < RX_FRAME_SLOTS);
    wire rx_accept_bytes = mac_rx_valid && !mac_rx_is_dllp &&
                           ((rx_capture_active && !rx_capture_drop) ||
                            rx_start_accept);
    wire [RX_LENGTH_W-1:0] rx_base_length = rx_capture_active ?
        rx_capture_length : {RX_LENGTH_W{1'b0}};
    wire [2:0] rx_base_pack_count = rx_capture_active ? rx_pack_count : 3'd0;
    wire [31:0] rx_base_pack_word = rx_capture_active ? rx_pack_word : 32'd0;
    wire [$clog2(MAX_FRAME_WORDS)-1:0] rx_base_word_index =
        rx_capture_active ? rx_capture_word : 0;
    wire [RX_LENGTH_W:0] rx_next_length =
        {1'b0, rx_base_length} + {{(RX_LENGTH_W-1){1'b0}}, rx_input_bytes};

    reg [47:0] rx_pack_combined;
    reg [3:0] rx_pack_total;
    always @* begin
        rx_pack_combined = {16'd0, rx_base_pack_word};
        rx_pack_total = rx_base_pack_count + rx_input_bytes;
        if (mac_rx_keep[0])
            rx_pack_combined[rx_base_pack_count*8 +: 8] = mac_rx_data[7:0];
        if (mac_rx_keep[1])
            rx_pack_combined[(rx_base_pack_count + mac_rx_keep[0])*8 +: 8]
                = mac_rx_data[15:8];
    end

    wire rx_frame_overflow = rx_next_length > MAX_FRAME_BYTES;
    wire [3:0] rx_event_error = (rx_capture_active ? rx_capture_error : 4'd0) |
        mac_rx_error | ((!rx_input_keep_ok ||
        (rx_capture_active && mac_rx_sop) || rx_frame_overflow ||
        (mac_rx_eop && (rx_pack_total > 4))) ? 4'b0010 : 4'b0000);
    wire rx_frame_commit = rx_accept_bytes && mac_rx_eop;
    wire rx_frame_mem_write = rx_accept_bytes && !rx_frame_overflow &&
        ((rx_pack_total >= 4) || (mac_rx_eop && (rx_pack_total != 0)));

    // Processor read and payload write/read signals are declared below。
    reg rx_frame_mem_read_first;
    reg rx_frame_mem_read_next;
    reg [RX_PTR_W-1:0] rx_proc_slot;
    reg [RX_LENGTH_W-1:0] rx_crc_index;
    reg [31:0] rx_frame_read_data;
    reg rx_payload_write_pending;
    reg [$clog2(MAX_TLP_BEATS)-1:0] rx_payload_write_beat;
    reg [127:0] rx_payload_write_data;
    reg rx_payload_read_first;
    reg rx_payload_read_next;
    reg [RX_LENGTH_W-1:0] rx_output_offset;
    reg [127:0] rx_payload_read_data;

    // Frame RAM与Payload RAM均为一写一读同步端口，存储内容无需复位。
    always @(posedge clk) begin
        if (rx_frame_mem_write)
            rx_frame_memory[rx_write_count[RX_PTR_W-1:0]*MAX_FRAME_WORDS +
                            rx_base_word_index] <= rx_pack_combined[31:0];
        if (rx_frame_commit) begin
            rx_frame_length[rx_write_count[RX_PTR_W-1:0]]
                <= rx_next_length[RX_LENGTH_W-1:0];
            rx_frame_error[rx_write_count[RX_PTR_W-1:0]] <= rx_event_error;
        end
        if (rx_frame_mem_read_first)
            rx_frame_read_data <=
                rx_frame_memory[rx_read_count[RX_PTR_W-1:0]*MAX_FRAME_WORDS];
        else if (rx_frame_mem_read_next)
            rx_frame_read_data <=
                rx_frame_memory[rx_proc_slot*MAX_FRAME_WORDS +
                                ((rx_crc_index >> 2) + 1'b1)];

        if (rx_payload_write_pending)
            rx_payload_memory[rx_proc_slot*MAX_TLP_BEATS +
                              rx_payload_write_beat] <= rx_payload_write_data;
        if (rx_payload_read_first)
            rx_payload_read_data <=
                rx_payload_memory[rx_proc_slot*MAX_TLP_BEATS];
        else if (rx_payload_read_next)
            rx_payload_read_data <=
                rx_payload_memory[rx_proc_slot*MAX_TLP_BEATS +
                                  ((rx_output_offset >> 4) + 1'b1)];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_write_count <= 0;
            rx_capture_active <= 0;
            rx_capture_drop <= 0;
            rx_capture_length <= 0;
            rx_capture_error <= 0;
            rx_pack_word <= 0;
            rx_pack_count <= 0;
            rx_capture_word <= 0;
            rx_capture_error_pulse <= 0;
        end else begin
            rx_capture_error_pulse <= 0;
            if (!dll_active) begin
                rx_write_count <= 0;
                rx_capture_active <= 0;
                rx_capture_drop <= 0;
                rx_capture_length <= 0;
                rx_capture_error <= 0;
                rx_pack_word <= 0;
                rx_pack_count <= 0;
                rx_capture_word <= 0;
            end else if (mac_rx_valid && !mac_rx_is_dllp) begin
                if (!rx_capture_active) begin
                    if (!mac_rx_sop || (rx_slot_count >= RX_FRAME_SLOTS)) begin
                        rx_capture_active <= !mac_rx_eop;
                        rx_capture_drop <= !mac_rx_eop;
                        rx_capture_error_pulse <= 1'b1;
                    end else if (mac_rx_eop) begin
                        rx_write_count <= rx_write_count + 1'b1;
                    end else begin
                        rx_capture_active <= 1'b1;
                        rx_capture_drop <= 1'b0;
                        rx_capture_length <= rx_next_length[RX_LENGTH_W-1:0];
                        rx_capture_error <= rx_event_error;
                        if (rx_pack_total >= 4) begin
                            rx_pack_word <= rx_pack_combined[47:32];
                            rx_pack_count <= rx_pack_total[2:0] - 3'd4;
                            rx_capture_word <= 1;
                        end else begin
                            rx_pack_word <= rx_pack_combined[31:0];
                            rx_pack_count <= rx_pack_total[2:0];
                            rx_capture_word <= 0;
                        end
                    end
                end else if (rx_capture_drop) begin
                    if (mac_rx_eop) begin
                        rx_capture_active <= 0;
                        rx_capture_drop <= 0;
                    end
                end else if (mac_rx_eop) begin
                    rx_write_count <= rx_write_count + 1'b1;
                    rx_capture_active <= 0;
                    rx_capture_length <= 0;
                    rx_capture_error <= 0;
                    rx_pack_word <= 0;
                    rx_pack_count <= 0;
                    rx_capture_word <= 0;
                end else begin
                    rx_capture_length <= rx_next_length[RX_LENGTH_W-1:0];
                    rx_capture_error <= rx_event_error;
                    if (rx_pack_total >= 4) begin
                        rx_pack_word <= rx_pack_combined[47:32];
                        rx_pack_count <= rx_pack_total[2:0] - 3'd4;
                        rx_capture_word <= rx_capture_word + 1'b1;
                    end else begin
                        rx_pack_word <= rx_pack_combined[31:0];
                        rx_pack_count <= rx_pack_total[2:0];
                    end
                end
            end
        end
    end

    // ---------------------------------------------------------------------
    // RX LCRC、Sequence判定和128-bit输出
    // ---------------------------------------------------------------------
    reg [2:0] rx_proc_state;
    reg [RX_LENGTH_W-1:0] rx_proc_length;
    reg [3:0] rx_proc_frame_error;
    reg rx_crc_good_latched;
    reg [RX_LENGTH_W-1:0] rx_output_length;
    reg [31:0] rx_first_word;
    reg [31:0] rx_second_word;
    reg [159:0] rx_payload_pack;
    reg [5:0] rx_payload_pack_count;
    reg [$clog2(MAX_TLP_BEATS)-1:0] rx_payload_beat;

    reg rx_reply_request;
    reg rx_reply_is_nak;
    reg rx_reply_immediate;
    reg [11:0] rx_reply_seq;

    wire [RX_LENGTH_W:0] rx_crc_remaining =
        {1'b0, rx_proc_length} - rx_crc_index;
    reg [3:0] rx_crc_input_keep;
    integer rk;
    always @* begin
        rx_crc_input_keep = 0;
        for (rk = 0; rk < 4; rk = rk + 1)
            if ((rx_crc_index + rk) < rx_proc_length)
                rx_crc_input_keep[rk] = 1'b1;
    end

    wire rx_lcrc_ready;
    wire [31:0] rx_lcrc_result;
    wire rx_lcrc_valid;
    wire rx_lcrc_match_unused;
    wire rx_lcrc_protocol_error;
    wire rx_lcrc_busy;
    wire rx_crc_input_valid = rx_crc_rst_n && (rx_proc_state == RXP_FEED);
    wire rx_crc_input_last = (rx_crc_remaining <= 4);
    wire rx_crc_input_start = (rx_crc_index == 0);

    pcie_crc32_lcrc u_rx_lcrc (
        .clk(clk), .rst_n(rx_crc_rst_n), .start(rx_crc_input_start),
        .data(rx_frame_read_data), .keep(rx_crc_input_keep),
        .last(rx_crc_input_last), .valid(rx_crc_input_valid),
        .ready(rx_lcrc_ready), .crc_result(rx_lcrc_result),
        .crc_valid(rx_lcrc_valid), .crc_match(rx_lcrc_match_unused),
        .protocol_error(rx_lcrc_protocol_error), .busy(rx_lcrc_busy)
    );

    reg [31:0] rx_payload_append;
    reg [2:0] rx_payload_append_count;
    reg [159:0] rx_payload_combined;
    reg [6:0] rx_payload_combined_count;
    integer pa;
    always @* begin
        rx_payload_append = 0;
        rx_payload_append_count = 0;
        for (pa = 0; pa < 4; pa = pa + 1) begin
            if (((rx_crc_index + pa) >= 2) &&
                ((rx_crc_index + pa) < (rx_proc_length - 4))) begin
                rx_payload_append[rx_payload_append_count*8 +: 8] =
                    rx_frame_read_data[pa*8 +: 8];
                rx_payload_append_count = rx_payload_append_count + 1'b1;
            end
        end
        rx_payload_combined = rx_payload_pack;
        for (pa = 0; pa < 4; pa = pa + 1)
            if (pa < rx_payload_append_count)
                rx_payload_combined[(rx_payload_pack_count + pa)*8 +: 8] =
                    rx_payload_append[pa*8 +: 8];
        rx_payload_combined_count = rx_payload_pack_count +
                                    rx_payload_append_count;
    end

    wire rx_payload_write_request = (rx_proc_state == RXP_FEED) &&
        ((rx_payload_combined_count >= 16) ||
         (rx_crc_input_last && (rx_payload_combined_count != 0)));

    wire [11:0] rx_wire_seq = {rx_first_word[3:0], rx_first_word[15:8]};

    always @* begin
        rx_frame_mem_read_first = (rx_proc_state == RXP_IDLE) &&
            crc_logic_ready && (rx_write_count != rx_read_count) &&
            (rx_frame_length[rx_read_count[RX_PTR_W-1:0]] >= 6) &&
            (rx_frame_error[rx_read_count[RX_PTR_W-1:0]] == 0);
        rx_frame_mem_read_next = (rx_proc_state == RXP_FEED) &&
                                 !rx_crc_input_last;
        rx_payload_read_first = (rx_proc_state == RXP_DECIDE) &&
            rx_crc_good_latched && (rx_proc_frame_error == 0) &&
            (rx_proc_length >= 18) && (((rx_proc_length - 6) & 3) == 0) &&
            (rx_wire_seq == next_rx_seq);
        rx_payload_read_next = (rx_proc_state == RXP_OUTPUT) &&
            rx_tlp_valid && rx_tlp_ready && !rx_tlp_eop;
    end


    // Payload RAM写请求打一拍；RAM的WE、地址和数据只由寄存器驱动，避免
    // Frame长度比较、打包计数和LUTRAM写使能形成组合长路径。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_payload_write_pending <= 1'b0;
            rx_payload_write_beat <= 0;
            rx_payload_write_data <= 0;
        end else if (!dll_active) begin
            rx_payload_write_pending <= 1'b0;
        end else begin
            rx_payload_write_pending <= rx_payload_write_request;
            if (rx_payload_write_request) begin
                rx_payload_write_beat <= rx_payload_beat;
                rx_payload_write_data <= rx_payload_combined[127:0];
            end
        end
    end

    wire [11:0] rx_seq_behind = next_rx_seq - rx_wire_seq;
    wire rx_is_duplicate = (rx_wire_seq != next_rx_seq) &&
                           (rx_seq_behind < 12'h800);
    wire rx_frame_structurally_good = rx_crc_good_latched &&
        (rx_proc_frame_error == 0) && (rx_proc_length >= 18) &&
        (((rx_proc_length - 6) & 3) == 0);

    wire [7:0] rx_tlp_byte0 = rx_first_word[23:16];
    wire [7:0] rx_tlp_byte2 = rx_second_word[7:0];
    wire [7:0] rx_tlp_byte3 = rx_second_word[15:8];
    wire [4:0] rx_tlp_wire_type = rx_tlp_byte0[4:0];
    wire [10:0] rx_tlp_length_dw = ({rx_tlp_byte2[1:0], rx_tlp_byte3} == 0) ?
                                   11'd1024 : {1'b0, rx_tlp_byte2[1:0], rx_tlp_byte3};
    wire rx_tlp_has_data = rx_tlp_byte0[6];
    reg [1:0] rx_classified_type;
    always @* begin
        if (rx_tlp_wire_type == 5'h0a)
            rx_classified_type = 2'd2;
        else if (rx_tlp_wire_type == 5'h00)
            rx_classified_type = rx_tlp_has_data ? 2'd0 : 2'd1;
        else
            rx_classified_type = 2'd1;
    end
    wire [11:0] rx_classified_data_credits = rx_tlp_has_data ?
        ((rx_tlp_length_dw + 3) >> 2) : 12'd0;

    integer ok;
    reg [RX_LENGTH_W:0] rx_output_remaining;
    always @* begin
        rx_tlp_valid = (rx_proc_state == RXP_OUTPUT) && dll_active;
        rx_tlp_data = rx_payload_read_data;
        rx_tlp_keep = 0;
        rx_tlp_sop = (rx_output_offset == 0);
        rx_output_remaining = rx_output_length - rx_output_offset;
        rx_tlp_eop = (rx_output_remaining <= 16);
        rx_tlp_error = 0;
        for (ok = 0; ok < 16; ok = ok + 1)
            if (ok < rx_output_remaining)
                rx_tlp_keep[ok] = 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_proc_state <= RXP_IDLE;
            rx_read_count <= 0;
            rx_proc_slot <= 0;
            rx_proc_length <= 0;
            rx_proc_frame_error <= 0;
            rx_crc_index <= 0;
            rx_crc_good_latched <= 0;
            rx_output_offset <= 0;
            rx_output_length <= 0;
            rx_first_word <= 0;
            rx_second_word <= 0;
            rx_payload_pack <= 0;
            rx_payload_pack_count <= 0;
            rx_payload_beat <= 0;
            next_rx_seq <= 0;
            rx_fc_consume_valid <= 0;
            rx_fc_consume_type <= 0;
            rx_fc_consume_data_credits <= 0;
            rx_reply_request <= 0;
            rx_reply_is_nak <= 0;
            rx_reply_immediate <= 0;
            rx_reply_seq <= 0;
            rx_tlp_count <= 0;
            lcrc_error_count <= 0;
            duplicate_tlp_count <= 0;
            sequence_error_count <= 0;
        end else begin
            rx_fc_consume_valid <= 0;
            rx_reply_request <= 0;
            if (!dll_active) begin
                rx_proc_state <= RXP_IDLE;
                rx_read_count <= 0;
                rx_crc_index <= 0;
                rx_output_offset <= 0;
                rx_payload_pack <= 0;
                rx_payload_pack_count <= 0;
                rx_payload_beat <= 0;
                next_rx_seq <= 0;
            end else begin
                case (rx_proc_state)
                    RXP_IDLE: begin
                        if (crc_logic_ready && (rx_write_count != rx_read_count)) begin
                            rx_proc_slot <= rx_read_count[RX_PTR_W-1:0];
                            rx_proc_length <=
                                rx_frame_length[rx_read_count[RX_PTR_W-1:0]];
                            rx_proc_frame_error <=
                                rx_frame_error[rx_read_count[RX_PTR_W-1:0]];
                            rx_crc_index <= 0;
                            rx_payload_pack <= 0;
                            rx_payload_pack_count <= 0;
                            rx_payload_beat <= 0;
                            if ((rx_frame_length[rx_read_count[RX_PTR_W-1:0]] < 6) ||
                                (rx_frame_error[rx_read_count[RX_PTR_W-1:0]] != 0)) begin
                                rx_crc_good_latched <= 1'b0;
                                rx_proc_state <= RXP_DECIDE;
                            end else begin
                                rx_proc_state <= RXP_FEED;
                            end
                        end
                    end
                    RXP_FEED: begin
                        if (rx_crc_index == 0)
                            rx_first_word <= rx_frame_read_data;
                        if (rx_crc_index == 4)
                            rx_second_word <= rx_frame_read_data;
                        if (rx_payload_write_request) begin
                            if (rx_payload_combined_count >= 16) begin
                                rx_payload_pack <= rx_payload_combined >> 128;
                                rx_payload_pack_count <=
                                    rx_payload_combined_count[5:0] - 6'd16;
                            end else begin
                                rx_payload_pack <= 0;
                                rx_payload_pack_count <= 0;
                            end
                            rx_payload_beat <= rx_payload_beat + 1'b1;
                        end else begin
                            rx_payload_pack <= rx_payload_combined;
                            rx_payload_pack_count <=
                                rx_payload_combined_count[5:0];
                        end
                        if (rx_crc_input_last)
                            rx_proc_state <= RXP_WAIT;
                        else
                            rx_crc_index <= rx_crc_index + 4;
                    end
                    RXP_WAIT: begin
                        if (rx_lcrc_valid) begin
                            // crc_result是完整Frame余数的逐位取反值。先使用K04
                            // 已寄存结果，再在本级比较residue，避免CRC更新与
                            // 32-bit相等比较落在同一条250 MHz组合路径中。
                            rx_crc_good_latched <=
                                (rx_lcrc_result == 32'h2144DF1C);
                            rx_proc_state <= RXP_DECIDE;
                        end
                    end
                    RXP_DECIDE: begin
                        if (!rx_frame_structurally_good) begin
                            lcrc_error_count <= sat_inc32(lcrc_error_count);
                            rx_reply_request <= 1'b1;
                            rx_reply_is_nak <= 1'b1;
                            rx_reply_immediate <= 1'b1;
                            rx_reply_seq <= next_rx_seq - 1'b1;
                            rx_read_count <= rx_read_count + 1'b1;
                            rx_proc_state <= RXP_IDLE;
                        end else if (rx_wire_seq == next_rx_seq) begin
                            next_rx_seq <= next_rx_seq + 1'b1;
                            rx_output_length <= rx_proc_length - 6;
                            rx_output_offset <= 0;
                            rx_fc_consume_valid <= 1'b1;
                            rx_fc_consume_type <= rx_classified_type;
                            rx_fc_consume_data_credits <= rx_classified_data_credits;
                            rx_reply_request <= 1'b1;
                            rx_reply_is_nak <= 1'b0;
                            rx_reply_immediate <= 1'b0;
                            rx_reply_seq <= rx_wire_seq;
                            rx_tlp_count <= sat_inc32(rx_tlp_count);
                            rx_proc_state <= RXP_OUTPUT;
                        end else if (rx_is_duplicate) begin
                            duplicate_tlp_count <= sat_inc32(duplicate_tlp_count);
                            rx_reply_request <= 1'b1;
                            rx_reply_is_nak <= 1'b0;
                            rx_reply_immediate <= 1'b1;
                            rx_reply_seq <= next_rx_seq - 1'b1;
                            rx_read_count <= rx_read_count + 1'b1;
                            rx_proc_state <= RXP_IDLE;
                        end else begin
                            sequence_error_count <= sat_inc32(sequence_error_count);
                            rx_reply_request <= 1'b1;
                            rx_reply_is_nak <= 1'b1;
                            rx_reply_immediate <= 1'b1;
                            rx_reply_seq <= next_rx_seq - 1'b1;
                            rx_read_count <= rx_read_count + 1'b1;
                            rx_proc_state <= RXP_IDLE;
                        end
                    end
                    RXP_OUTPUT: begin
                        if (rx_tlp_valid && rx_tlp_ready) begin
                            if (rx_tlp_eop) begin
                                rx_read_count <= rx_read_count + 1'b1;
                                rx_proc_state <= RXP_IDLE;
                                rx_output_offset <= 0;
                            end else begin
                                rx_output_offset <= rx_output_offset + 16;
                            end
                        end
                    end
                    default: rx_proc_state <= RXP_IDLE;
                endcase
            end
        end
    end

    // ---------------------------------------------------------------------
    // RX累计ACK/NAK发送调度
    // ---------------------------------------------------------------------
    reg reply_pending;
    reg reply_is_nak;
    reg reply_ready;
    reg [11:0] reply_sequence;
    reg [ACK_TIMER_W-1:0] reply_timer;
    localparam [ACK_TIMER_W-1:0] ACK_TIMER_LIMIT =
        ACK_LATENCY_CYCLES[ACK_TIMER_W-1:0] - 1'b1;

    assign tx_ack_dllp_valid = dll_active && reply_pending && reply_ready;
    assign tx_ack_dllp_data = pack_ack_nak(reply_is_nak, reply_sequence);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reply_pending <= 0;
            reply_is_nak <= 0;
            reply_ready <= 0;
            reply_sequence <= 0;
            reply_timer <= 0;
            ack_tx_count <= 0;
            nak_tx_count <= 0;
        end else if (!dll_active) begin
            reply_pending <= 0;
            reply_is_nak <= 0;
            reply_ready <= 0;
            reply_timer <= 0;
        end else begin
            if (reply_pending && !reply_ready) begin
                if (reply_timer == ACK_TIMER_LIMIT)
                    reply_ready <= 1'b1;
                else
                    reply_timer <= reply_timer + 1'b1;
            end
            if (tx_ack_dllp_valid && tx_ack_dllp_ready) begin
                if (reply_is_nak)
                    nak_tx_count <= sat_inc32(nak_tx_count);
                else
                    ack_tx_count <= sat_inc32(ack_tx_count);
                reply_pending <= 1'b0;
                reply_is_nak <= 1'b0;
                reply_ready <= 1'b0;
                reply_timer <= 0;
            end
            if (rx_reply_request) begin
                if (rx_reply_is_nak) begin
                    reply_pending <= 1'b1;
                    reply_is_nak <= 1'b1;
                    reply_ready <= 1'b1;
                    reply_sequence <= rx_reply_seq;
                    reply_timer <= 0;
                end else if (!reply_pending || !reply_is_nak) begin
                    if (!reply_pending)
                        reply_timer <= 0;
                    reply_pending <= 1'b1;
                    reply_is_nak <= 1'b0;
                    reply_sequence <= rx_reply_seq;
                    if (rx_reply_immediate)
                        reply_ready <= 1'b1;
                end
            end
        end
    end

    // ---------------------------------------------------------------------
    // TX ACK/NAK接收、累计释放与Replay Timer
    // ---------------------------------------------------------------------
    wire rx_is_ack = rx_dllp_data[7:0] == 8'h00;
    wire rx_is_nak = rx_dllp_data[7:0] == 8'h10;
    wire rx_acknak_type = rx_is_ack || rx_is_nak;
    wire rx_acknak_fields_good = (rx_dllp_data[15:8] == 0) &&
                                 (rx_dllp_data[23:20] == 0);
    wire [11:0] rx_acknak_seq = {rx_dllp_data[19:16], rx_dllp_data[31:24]};
    wire rx_good_acknak = rx_dllp_valid && rx_dllp_crc_good &&
        (rx_dllp_error == 0) && rx_acknak_type && rx_acknak_fields_good;

    // ACK/NAK先进入一级事件寄存器，再修改Replay窗口和Timer。除改善250 MHz
    // 时序外，这也固定了“接收事件拍”上的窗口快照。实际DLLP Codec无法每拍
    // 连续输出ACK/NAK；下列base选择仍支持相邻两拍事件按顺序累计。
    reg ack_event_valid;
    reg ack_event_is_nak;
    reg ack_event_good;
    reg [11:0] ack_event_seq;
    reg [REPLAY_PTR_W:0] ack_event_advance;
    wire prior_ack_advances = ack_event_valid && ack_event_good &&
                              (ack_event_advance != 0);
    wire [11:0] rx_ack_base_seq = prior_ack_advances ?
        ack_event_seq : last_acked_seq;
    wire [REPLAY_PTR_W:0] rx_ack_base_outstanding = tx_outstanding_count -
        (prior_ack_advances ? ack_event_advance : 0);
    wire [11:0] rx_ack_input_advance = rx_acknak_seq - rx_ack_base_seq;
    wire rx_ack_input_range_good =
        rx_ack_input_advance <= rx_ack_base_outstanding;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ack_event_valid <= 1'b0;
            ack_event_is_nak <= 1'b0;
            ack_event_good <= 1'b0;
            ack_event_seq <= 0;
            ack_event_advance <= 0;
        end else if (!dll_active) begin
            ack_event_valid <= 1'b0;
            ack_event_good <= 1'b0;
        end else begin
            ack_event_valid <= rx_dllp_valid && rx_acknak_type;
            if (rx_dllp_valid && rx_acknak_type) begin
                ack_event_is_nak <= rx_is_nak;
                ack_event_good <= rx_good_acknak && rx_ack_input_range_good;
                ack_event_seq <= rx_acknak_seq;
                ack_event_advance <=
                    rx_ack_input_advance[REPLAY_PTR_W:0];
            end
        end
    end

    reg [REPLAY_TIMER_W-1:0] replay_timer;
    reg [RETRY_W-1:0] replay_timeout_retries;
    localparam [REPLAY_TIMER_W-1:0] REPLAY_TIMER_LIMIT =
        REPLAY_TIMEOUT_CYCLES[REPLAY_TIMER_W-1:0] - 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_free_count <= 0;
            last_acked_seq <= 12'hfff;
            replay_active <= 0;
            replay_cursor <= 0;
            replay_end <= 0;
            replay_timer <= 0;
            replay_timeout_retries <= 0;
            replay_fatal <= 0;
            recovery_req <= 0;
            ack_error_count <= 0;
        end else begin
            recovery_req <= 0;
            if (!dll_active) begin
                tx_free_count <= 0;
                last_acked_seq <= 12'hfff;
                replay_active <= 0;
                replay_cursor <= 0;
                replay_end <= 0;
                replay_timer <= 0;
                replay_timeout_retries <= 0;
                replay_fatal <= 0;
            end else begin
                if (tx_outstanding_count == 0) begin
                    replay_timer <= 0;
                    replay_timeout_retries <= 0;
                end else if (!replay_active) begin
                    if (replay_timer == REPLAY_TIMER_LIMIT) begin
                        replay_active <= 1'b1;
                        replay_cursor <= tx_free_count;
                        replay_end <= tx_send_count;
                        replay_timer <= 0;
                        if (replay_timeout_retries + 1'b1 >= REPLAY_RETRY_LIMIT) begin
                            replay_timeout_retries <= replay_timeout_retries;
                            replay_fatal <= 1'b1;
                            recovery_req <= 1'b1;
                        end else begin
                            replay_timeout_retries <= replay_timeout_retries + 1'b1;
                        end
                    end else begin
                        replay_timer <= replay_timer + 1'b1;
                    end
                end

                if (initial_send_pulse && (tx_outstanding_count == 0))
                    replay_timer <= 0;

                if (replay_packet_done_pulse && replay_active) begin
                    if (replay_cursor + 1'b1 == replay_end) begin
                        replay_active <= 1'b0;
                        replay_timer <= 0;
                    end else begin
                        replay_cursor <= replay_cursor + 1'b1;
                    end
                end

                if (ack_event_valid) begin
                    if (ack_event_good) begin
                        if (ack_event_advance != 0) begin
                            tx_free_count <= tx_free_count +
                                ack_event_advance;
                            last_acked_seq <= ack_event_seq;
                            replay_timer <= 0;
                            replay_timeout_retries <= 0;
                        end
                        if (ack_event_is_nak) begin
                            if (tx_outstanding_count > ack_event_advance) begin
                                replay_active <= 1'b1;
                                replay_cursor <= tx_free_count +
                                    ack_event_advance;
                                replay_end <= tx_send_count;
                            end else begin
                                replay_active <= 1'b0;
                            end
                        end else if (replay_active) begin
                            if (tx_outstanding_count <= ack_event_advance) begin
                                replay_active <= 1'b0;
                            end else begin
                                replay_cursor <= tx_free_count +
                                    ack_event_advance;
                                replay_end <= tx_send_count;
                            end
                        end
                    end else begin
                        ack_error_count <= sat_inc32(ack_error_count);
                    end
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buffer_error_count <= 0;
        end else if (tx_capture_error_pulse || rx_capture_error_pulse) begin
            buffer_error_count <= sat_inc32(buffer_error_count);
        end
    end

    wire [75:0] _unused_crc_status = {tx_crc_ready, tx_crc_match_unused,
        tx_crc_protocol_error, tx_crc_busy, rx_lcrc_ready,
        rx_lcrc_match_unused, rx_lcrc_result,
        rx_lcrc_protocol_error, rx_lcrc_busy, rx_tlp_byte2[7:2],
        rx_tlp_byte0[7], rx_tlp_byte0[5], rx_first_word[31:24],
        rx_first_word[7:4], rx_second_word[31:16]};
endmodule

/* verilator lint_on WIDTHEXPAND */
`default_nettype wire
