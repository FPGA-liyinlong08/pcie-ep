`timescale 1ns/1ps
`default_nettype none

// K03 16-bit framed stream 与 4-byte 原始 DLLP 之间的 Codec。
// RX/TX CRC 均复用 K04 pcie_crc16_dllp。
module pcie_dllp_codec (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,

    input  wire        mac_rx_valid,
    input  wire [15:0] mac_rx_data,
    input  wire [1:0]  mac_rx_keep,
    input  wire        mac_rx_sop,
    input  wire        mac_rx_eop,
    input  wire        mac_rx_is_dllp,
    input  wire [3:0]  mac_rx_error,

    output reg         mac_tx_valid,
    input  wire        mac_tx_ready,
    output reg  [15:0] mac_tx_data,
    output reg  [1:0]  mac_tx_keep,
    output reg         mac_tx_sop,
    output reg         mac_tx_eop,
    output reg         mac_tx_is_dllp,
    output reg         mac_tx_bad,

    output wire        rx_dllp_valid,
    output wire [31:0] rx_dllp_data,
    output wire        rx_dllp_crc_good,
    output wire [3:0]  rx_dllp_error,

    input  wire        tx_dllp_valid,
    output wire        tx_dllp_ready,
    input  wire [31:0] tx_dllp_data
);
    localparam [1:0] RX_IDLE    = 2'd0;
    localparam [1:0] RX_COLLECT = 2'd1;
    localparam [1:0] RX_DROP    = 2'd2;

    localparam [1:0] RXCRC_IDLE   = 2'd0;
    localparam [1:0] RXCRC_SECOND = 2'd1;
    localparam [1:0] RXCRC_WAIT   = 2'd2;

    localparam [2:0] TX_IDLE     = 3'd0;
    localparam [2:0] TX_WAIT_CRC = 3'd1;
    localparam [2:0] TX_SEND0    = 3'd2;
    localparam [2:0] TX_SEND1    = 3'd3;
    localparam [2:0] TX_SEND2    = 3'd4;

    wire crc_async_release_n = rst_n && enable;
    wire crc_rst_n;

    // link_up 下降时立即终止未完成 CRC；重新进入 L0 后同步释放，避免把
    // 会话 enable 直接作为 K04 状态寄存器的异步释放边沿。
    pcie_reset_sync #(
        .STAGES(2)
    ) u_crc_reset_sync (
        .clk(clk),
        .async_release_n(crc_async_release_n),
        .sync_reset_n(crc_rst_n)
    );

    reg [1:0]  rx_state;
    reg [47:0] rx_buffer;
    reg [3:0]  rx_count;
    reg        rx_frame_bad;
    reg [47:0] rx_job_data;
    reg        rx_job_valid;
    reg [1:0]  rx_crc_state;
    reg        bad_event_valid;
    reg [31:0] bad_event_data;
    reg [3:0]  bad_event_error;

    wire [1:0] rx_byte_count = (mac_rx_keep == 2'b11) ? 2'd2 :
                               (mac_rx_keep == 2'b01) ? 2'd1 : 2'd0;
    wire rx_keep_legal = (mac_rx_keep == 2'b00) ||
                         (mac_rx_keep == 2'b01) ||
                         (mac_rx_keep == 2'b11);
    wire [3:0] rx_base_count = (rx_state == RX_IDLE) ? 4'd0 : rx_count;
    wire [47:0] rx_base_buffer = (rx_state == RX_IDLE) ? 48'd0 : rx_buffer;

    reg [47:0] rx_appended_buffer;
    reg [3:0]  rx_appended_count;
    always @* begin
        rx_appended_buffer = rx_base_buffer;
        rx_appended_count  = rx_base_count;
        if (mac_rx_keep[0] && (rx_appended_count < 6)) begin
            rx_appended_buffer[rx_appended_count*8 +: 8] = mac_rx_data[7:0];
            rx_appended_count = rx_appended_count + 1'b1;
        end
        if (mac_rx_keep[1] && (rx_appended_count < 6)) begin
            rx_appended_buffer[rx_appended_count*8 +: 8] = mac_rx_data[15:8];
            rx_appended_count = rx_appended_count + 1'b1;
        end
    end

    wire rx_length_overflow = ({1'b0, rx_base_count} +
                               {3'd0, rx_byte_count}) > 5'd6;
    wire rx_current_bad = rx_frame_bad || (mac_rx_error != 0) ||
                          !rx_keep_legal ||
                          ((rx_byte_count == 0) && !mac_rx_eop) ||
                          rx_length_overflow;

    wire        rx_crc_ready;
    wire [15:0] rx_crc_result;
    wire        rx_crc_valid;
    wire        rx_crc_match;
    wire        rx_crc_protocol_error;
    wire        rx_crc_busy;
    wire        rx_crc_input_valid = enable && rx_job_valid &&
                                     ((rx_crc_state == RXCRC_IDLE) ||
                                      (rx_crc_state == RXCRC_SECOND));
    wire [31:0] rx_crc_input_data = (rx_crc_state == RXCRC_IDLE) ?
                                    rx_job_data[31:0] :
                                    {16'd0, rx_job_data[47:32]};
    wire [3:0] rx_crc_input_keep = (rx_crc_state == RXCRC_IDLE) ? 4'hf : 4'h3;
    wire rx_crc_input_start = (rx_crc_state == RXCRC_IDLE);
    wire rx_crc_input_last = (rx_crc_state == RXCRC_SECOND);

    pcie_crc16_dllp u_rx_crc16 (
        .clk(clk), .rst_n(crc_rst_n), .start(rx_crc_input_start),
        .data(rx_crc_input_data), .keep(rx_crc_input_keep),
        .last(rx_crc_input_last), .valid(rx_crc_input_valid),
        .ready(rx_crc_ready), .crc_result(rx_crc_result),
        .crc_valid(rx_crc_valid), .crc_match(rx_crc_match),
        .protocol_error(rx_crc_protocol_error), .busy(rx_crc_busy)
    );

    wire rx_job_completing = (rx_crc_state == RXCRC_WAIT) && rx_crc_valid;
    wire rx_job_available = !rx_job_valid || rx_job_completing;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state           <= RX_IDLE;
            rx_buffer          <= 48'd0;
            rx_count           <= 4'd0;
            rx_frame_bad       <= 1'b0;
            rx_job_data        <= 48'd0;
            rx_job_valid       <= 1'b0;
            rx_crc_state       <= RXCRC_IDLE;
            bad_event_valid    <= 1'b0;
            bad_event_data     <= 32'd0;
            bad_event_error    <= 4'd0;
        end else begin
            bad_event_valid <= 1'b0;

            if (!enable) begin
                rx_state       <= RX_IDLE;
                rx_buffer      <= 48'd0;
                rx_count       <= 4'd0;
                rx_frame_bad   <= 1'b0;
                rx_job_valid   <= 1'b0;
                rx_crc_state   <= RXCRC_IDLE;
            end else begin
                case (rx_crc_state)
                    RXCRC_IDLE: begin
                        if (rx_job_valid)
                            rx_crc_state <= RXCRC_SECOND;
                    end
                    RXCRC_SECOND: begin
                        rx_crc_state <= RXCRC_WAIT;
                    end
                    RXCRC_WAIT: begin
                        if (rx_crc_valid) begin
                            rx_crc_state <= RXCRC_IDLE;
                            rx_job_valid <= 1'b0;
                        end
                    end
                    default: begin
                        rx_crc_state <= RXCRC_IDLE;
                        rx_job_valid <= 1'b0;
                    end
                endcase

                if (mac_rx_valid) begin
                    case (rx_state)
                        RX_IDLE: begin
                            if (mac_rx_is_dllp) begin
                                if (!mac_rx_sop) begin
                                    bad_event_valid <= 1'b1;
                                    bad_event_data  <= 32'd0;
                                    bad_event_error <= 4'b0010;
                                    rx_state <= mac_rx_eop ? RX_IDLE : RX_DROP;
                                end else if (mac_rx_eop) begin
                                    if (!rx_current_bad && (rx_appended_count == 6)) begin
                                        if (rx_job_available) begin
                                            rx_job_data  <= rx_appended_buffer;
                                            rx_job_valid <= 1'b1;
                                        end else begin
                                            bad_event_valid <= 1'b1;
                                            bad_event_data  <= rx_appended_buffer[31:0];
                                            bad_event_error <= 4'b1000;
                                        end
                                    end else begin
                                        bad_event_valid <= 1'b1;
                                        bad_event_data  <= rx_appended_buffer[31:0];
                                        bad_event_error <= {(rx_job_available ? 1'b0 : 1'b1),
                                            1'b0, (mac_rx_error != 0) || !rx_keep_legal,
                                            (rx_appended_count != 6) || rx_length_overflow};
                                    end
                                    rx_state <= RX_IDLE;
                                end else begin
                                    rx_buffer    <= rx_appended_buffer;
                                    rx_count     <= rx_appended_count;
                                    rx_frame_bad <= rx_current_bad;
                                    rx_state     <= RX_COLLECT;
                                end
                            end
                        end
                        RX_COLLECT: begin
                            if (!mac_rx_is_dllp || mac_rx_sop) begin
                                bad_event_valid <= 1'b1;
                                bad_event_data  <= rx_buffer[31:0];
                                bad_event_error <= 4'b0010;
                                rx_state <= mac_rx_eop ? RX_IDLE : RX_DROP;
                            end else if (mac_rx_eop) begin
                                if (!rx_current_bad && (rx_appended_count == 6)) begin
                                    if (rx_job_available) begin
                                        rx_job_data  <= rx_appended_buffer;
                                        rx_job_valid <= 1'b1;
                                    end else begin
                                        bad_event_valid <= 1'b1;
                                        bad_event_data  <= rx_appended_buffer[31:0];
                                        bad_event_error <= 4'b1000;
                                    end
                                end else begin
                                    bad_event_valid <= 1'b1;
                                    bad_event_data  <= rx_appended_buffer[31:0];
                                    bad_event_error <= {1'b0, 1'b0,
                                        rx_frame_bad || (mac_rx_error != 0) || !rx_keep_legal,
                                        (rx_appended_count != 6) || rx_length_overflow};
                                end
                                rx_state     <= RX_IDLE;
                                rx_buffer    <= 48'd0;
                                rx_count     <= 4'd0;
                                rx_frame_bad <= 1'b0;
                            end else begin
                                rx_buffer    <= rx_appended_buffer;
                                rx_count     <= rx_appended_count;
                                rx_frame_bad <= rx_current_bad;
                            end
                        end
                        RX_DROP: begin
                            if (mac_rx_is_dllp && mac_rx_eop)
                                rx_state <= RX_IDLE;
                        end
                        default: rx_state <= RX_IDLE;
                    endcase
                end
            end
        end
    end

    // 深度2、每拍自动弹出一个事件；可同时接纳CRC结果和结构错误。
    reg [1:0] evt_count;
    reg [36:0] evt0;
    reg [36:0] evt1;
    reg [1:0] evt_count_next;
    reg [36:0] evt0_next;
    reg [36:0] evt1_next;
    reg [1:0] evt_work_count;

    wire crc_event_valid = enable && rx_job_valid && rx_crc_valid;
    wire [36:0] crc_event = {
        rx_crc_match ? 4'b0000 : 4'b0100,
        rx_crc_match,
        rx_job_data[31:0]
    };
    wire [36:0] bad_event = {bad_event_error, 1'b0, bad_event_data};

    always @* begin
        evt_count_next = evt_count;
        evt0_next = evt0;
        evt1_next = evt1;

        if (evt_count != 0) begin
            evt_count_next = evt_count - 1'b1;
            if (evt_count == 2)
                evt0_next = evt1;
        end

        evt_work_count = evt_count_next;
        if (crc_event_valid) begin
            if (evt_work_count == 0) begin
                evt0_next = crc_event;
                evt_work_count = 1;
            end else if (evt_work_count == 1) begin
                evt1_next = crc_event;
                evt_work_count = 2;
            end else begin
                evt1_next[36] = 1'b1;
            end
        end
        if (bad_event_valid) begin
            if (evt_work_count == 0) begin
                evt0_next = bad_event;
                evt_work_count = 1;
            end else if (evt_work_count == 1) begin
                evt1_next = bad_event;
                evt_work_count = 2;
            end else begin
                evt1_next[36] = 1'b1;
            end
        end
        evt_count_next = evt_work_count;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            evt_count <= 0;
            evt0 <= 0;
            evt1 <= 0;
        end else if (!enable) begin
            evt_count <= 0;
            evt0 <= 0;
            evt1 <= 0;
        end else begin
            evt_count <= evt_count_next;
            evt0 <= evt0_next;
            evt1 <= evt1_next;
        end
    end

    assign rx_dllp_valid    = (evt_count != 0);
    assign rx_dllp_data     = evt0[31:0];
    assign rx_dllp_crc_good = evt0[32];
    assign rx_dllp_error    = evt0[36:33];

    reg [2:0] tx_state;
    reg [31:0] tx_data_latched;
    reg [15:0] tx_crc_latched;
    wire tx_crc_ready;
    wire [15:0] tx_crc_result;
    wire tx_crc_valid;
    wire tx_crc_match;
    wire tx_crc_protocol_error;
    wire tx_crc_busy;
    wire tx_accept = tx_dllp_valid && tx_dllp_ready;

    assign tx_dllp_ready = crc_rst_n && (tx_state == TX_IDLE);

    pcie_crc16_dllp u_tx_crc16 (
        .clk(clk), .rst_n(crc_rst_n), .start(tx_accept),
        .data(tx_dllp_data), .keep(4'hf), .last(1'b1), .valid(tx_accept),
        .ready(tx_crc_ready), .crc_result(tx_crc_result),
        .crc_valid(tx_crc_valid), .crc_match(tx_crc_match),
        .protocol_error(tx_crc_protocol_error), .busy(tx_crc_busy)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state        <= TX_IDLE;
            tx_data_latched <= 32'd0;
            tx_crc_latched  <= 16'd0;
        end else if (!enable) begin
            tx_state <= TX_IDLE;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    if (tx_accept) begin
                        tx_data_latched <= tx_dllp_data;
                        tx_state <= TX_WAIT_CRC;
                    end
                end
                TX_WAIT_CRC: begin
                    if (tx_crc_valid) begin
                        tx_crc_latched <= tx_crc_result;
                        tx_state <= TX_SEND0;
                    end
                end
                TX_SEND0: if (mac_tx_valid && mac_tx_ready) tx_state <= TX_SEND1;
                TX_SEND1: if (mac_tx_valid && mac_tx_ready) tx_state <= TX_SEND2;
                TX_SEND2: if (mac_tx_valid && mac_tx_ready) tx_state <= TX_IDLE;
                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    always @* begin
        mac_tx_valid   = 1'b0;
        mac_tx_data    = 16'd0;
        mac_tx_keep    = 2'b00;
        mac_tx_sop     = 1'b0;
        mac_tx_eop     = 1'b0;
        mac_tx_is_dllp = 1'b0;
        mac_tx_bad     = 1'b0;
        if (enable) begin
            case (tx_state)
                TX_SEND0: begin
                    mac_tx_valid   = 1'b1;
                    mac_tx_data    = tx_data_latched[15:0];
                    mac_tx_keep    = 2'b11;
                    mac_tx_sop     = 1'b1;
                    mac_tx_is_dllp = 1'b1;
                end
                TX_SEND1: begin
                    mac_tx_valid   = 1'b1;
                    mac_tx_data    = tx_data_latched[31:16];
                    mac_tx_keep    = 2'b11;
                    mac_tx_is_dllp = 1'b1;
                end
                TX_SEND2: begin
                    mac_tx_valid   = 1'b1;
                    mac_tx_data    = tx_crc_latched;
                    mac_tx_keep    = 2'b11;
                    mac_tx_eop     = 1'b1;
                    mac_tx_is_dllp = 1'b1;
                end
                default: begin end
            endcase
        end
    end

    wire _unused_crc_status = &{1'b0, rx_crc_ready, rx_crc_result,
        rx_crc_protocol_error, rx_crc_busy, tx_crc_ready, tx_crc_match,
        tx_crc_protocol_error, tx_crc_busy};
endmodule

`default_nettype wire
