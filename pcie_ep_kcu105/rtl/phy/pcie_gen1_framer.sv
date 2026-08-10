`timescale 1ns/1ps
`default_nettype none

module pcie_gen1_framer #(
    parameter integer TX_BUFFER_BYTES = 160
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,

    input  wire        tx_pkt_valid,
    output wire        tx_pkt_ready,
    input  wire [15:0] tx_pkt_data,
    input  wire [1:0]  tx_pkt_keep,
    input  wire        tx_pkt_sop,
    input  wire        tx_pkt_eop,
    input  wire        tx_pkt_is_dllp,
    input  wire        tx_pkt_bad,

    input  wire        rx_phy_valid,
    input  wire [15:0] rx_phy_data,
    input  wire [1:0]  rx_phy_datak,

    output reg  [31:0] tx_phy_data,
    output reg  [1:0]  tx_phy_datak,
    output reg         tx_phy_valid,

    output reg         rx_pkt_valid,
    output reg  [15:0] rx_pkt_data,
    output reg  [1:0]  rx_pkt_keep,
    output reg         rx_pkt_sop,
    output reg         rx_pkt_eop,
    output reg         rx_pkt_is_dllp,
    output reg  [3:0]  rx_pkt_error,
    output wire        frame_error_pulse
);
    localparam [7:0] K_STP = 8'hfb;
    localparam [7:0] K_SDP = 8'h5c;
    localparam [7:0] K_END = 8'hfd;
    localparam [7:0] K_EDB = 8'hfe;
    localparam [7:0] D_IDL = 8'h00;
    localparam integer COUNT_WIDTH = $clog2(TX_BUFFER_BYTES + 1);

    localparam [2:0] TX_COLLECT = 3'd0;
    localparam [2:0] TX_DROP    = 3'd1;
    localparam [2:0] TX_START   = 3'd2;
    localparam [2:0] TX_DATA    = 3'd3;
    localparam [2:0] TX_END     = 3'd4;
    localparam [COUNT_WIDTH:0] TX_BUFFER_LIMIT = TX_BUFFER_BYTES[COUNT_WIDTH:0];
    localparam integer TX_BUFFER_WORDS = (TX_BUFFER_BYTES + 1) / 2;
    localparam integer TX_MEMORY_WORDS = 1 << $clog2(TX_BUFFER_WORDS);

    // 偶/奇 byte 分银行，每个银行每拍只有一个写口；TX_DATA 的两个异步读也分别
    // 落在不同银行，便于 Vivado 推断 distributed RAM。
    reg [7:0] tx_memory_even [0:TX_MEMORY_WORDS-1];
    reg [7:0] tx_memory_odd  [0:TX_MEMORY_WORDS-1];
    reg [COUNT_WIDTH-1:0] tx_write_count;
    reg [COUNT_WIDTH-1:0] tx_length;
    reg [COUNT_WIDTH-1:0] tx_read_index;
    reg [2:0] tx_state;
    reg       tx_is_dllp;
    reg       tx_bad_latched;

    reg       rx_in_frame;
    reg       rx_type_latched;
    reg       rx_sop_pending;
    reg       tx_error_pulse;
    reg       rx_error_pulse;

    wire [7:0] rx_symbol0 = rx_phy_data[7:0];
    wire [7:0] rx_symbol1 = rx_phy_data[15:8];
    wire       rx_symbol0_k = rx_phy_datak[0];
    wire       rx_symbol1_k = rx_phy_datak[1];
    wire       rx0_start = rx_symbol0_k && ((rx_symbol0 == K_STP) || (rx_symbol0 == K_SDP));
    wire       rx1_start = rx_symbol1_k && ((rx_symbol1 == K_STP) || (rx_symbol1 == K_SDP));
    wire       rx0_end = rx_symbol0_k && ((rx_symbol0 == K_END) || (rx_symbol0 == K_EDB));
    wire       rx1_end = rx_symbol1_k && ((rx_symbol1 == K_END) || (rx_symbol1 == K_EDB));
    wire [COUNT_WIDTH:0] tx_remaining = tx_length - tx_read_index;
    wire [1:0] tx_input_byte_count = tx_pkt_keep[1] ? 2'd2 :
                                           (tx_pkt_keep[0] ? 2'd1 : 2'd0);
    wire [COUNT_WIDTH:0] tx_next_count =
        {1'b0, tx_write_count} + {{(COUNT_WIDTH-1){1'b0}}, tx_input_byte_count};
    wire [COUNT_WIDTH-1:0] tx_read_plus_one = tx_read_index + 1'b1;
    wire [7:0] tx_read_byte0 = tx_read_index[0] ?
        tx_memory_odd[tx_read_index[COUNT_WIDTH-1:1]] :
        tx_memory_even[tx_read_index[COUNT_WIDTH-1:1]];
    wire [7:0] tx_read_byte1 = tx_read_plus_one[0] ?
        tx_memory_odd[tx_read_plus_one[COUNT_WIDTH-1:1]] :
        tx_memory_even[tx_read_plus_one[COUNT_WIDTH-1:1]];
    wire tx_input_legal = (tx_input_byte_count != 0) &&
                          (tx_pkt_keep != 2'b10) &&
                          ((tx_write_count == 0) == tx_pkt_sop) &&
                          !((tx_write_count != 0) && tx_pkt_sop) &&
                          (tx_pkt_eop || (tx_pkt_keep == 2'b11)) &&
                          (tx_next_count <= TX_BUFFER_LIMIT);

    assign tx_pkt_ready = enable && ((tx_state == TX_COLLECT) || (tx_state == TX_DROP));
    assign frame_error_pulse = tx_error_pulse | rx_error_pulse;

    // 存储阵列不带复位；有效长度和 FSM 被复位后旧内容不可见。
    always @(posedge clk) begin
        if (enable && (tx_state == TX_COLLECT) &&
            tx_pkt_valid && tx_pkt_ready && tx_input_legal) begin
            tx_memory_even[tx_write_count[COUNT_WIDTH-1:1]] <= tx_pkt_data[7:0];
            tx_memory_odd[tx_write_count[COUNT_WIDTH-1:1]]  <= tx_pkt_data[15:8];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_write_count  <= {COUNT_WIDTH{1'b0}};
            tx_length       <= {COUNT_WIDTH{1'b0}};
            tx_read_index   <= {COUNT_WIDTH{1'b0}};
            tx_state        <= TX_COLLECT;
            tx_is_dllp      <= 1'b0;
            tx_bad_latched  <= 1'b0;
            tx_error_pulse <= 1'b0;
        end else begin
            tx_error_pulse <= 1'b0;
            if (!enable) begin
                tx_write_count <= {COUNT_WIDTH{1'b0}};
                tx_length      <= {COUNT_WIDTH{1'b0}};
                tx_read_index  <= {COUNT_WIDTH{1'b0}};
                tx_state       <= TX_COLLECT;
            end else begin
                case (tx_state)
                    TX_COLLECT: begin
                        if (tx_pkt_valid && tx_pkt_ready) begin
                            if (!tx_input_legal) begin
                                tx_error_pulse <= 1'b1;
                                tx_write_count <= {COUNT_WIDTH{1'b0}};
                                tx_state <= tx_pkt_eop ? TX_COLLECT : TX_DROP;
                            end else begin
                                if (tx_write_count == 0)
                                    tx_is_dllp <= tx_pkt_is_dllp;
                                tx_write_count <= tx_next_count[COUNT_WIDTH-1:0];
                                if (tx_pkt_eop) begin
                                    tx_length      <= tx_next_count[COUNT_WIDTH-1:0];
                                    tx_read_index  <= {COUNT_WIDTH{1'b0}};
                                    tx_bad_latched <= tx_pkt_bad;
                                    tx_state       <= TX_START;
                                end else if (tx_next_count == TX_BUFFER_LIMIT) begin
                                    tx_error_pulse <= 1'b1;
                                    tx_write_count <= {COUNT_WIDTH{1'b0}};
                                    tx_state <= TX_DROP;
                                end
                            end
                        end
                    end
                    TX_DROP: begin
                        if (tx_pkt_valid && tx_pkt_ready && tx_pkt_eop) begin
                            tx_write_count <= {COUNT_WIDTH{1'b0}};
                            tx_state <= TX_COLLECT;
                        end
                    end
                    TX_START: begin
                        tx_read_index <= {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
                        tx_state <= (tx_length == 1) ? TX_END : TX_DATA;
                    end
                    TX_DATA: begin
                        if (tx_remaining == 1) begin
                            tx_write_count <= {COUNT_WIDTH{1'b0}};
                            tx_state <= TX_COLLECT;
                        end else if (tx_remaining == 2) begin
                            tx_read_index <= tx_read_index + {{(COUNT_WIDTH-2){1'b0}}, 2'd2};
                            tx_state <= TX_END;
                        end else begin
                            tx_read_index <= tx_read_index + {{(COUNT_WIDTH-2){1'b0}}, 2'd2};
                        end
                    end
                    default: begin
                        tx_write_count <= {COUNT_WIDTH{1'b0}};
                        tx_state <= TX_COLLECT;
                    end
                endcase
            end
        end
    end

    always @* begin
        tx_phy_data  = {16'd0, D_IDL, D_IDL};
        tx_phy_datak = 2'b00;
        tx_phy_valid = enable;
        if (!enable) begin
            tx_phy_data  = 32'd0;
            tx_phy_datak = 2'b00;
            tx_phy_valid = 1'b0;
        end else begin
            case (tx_state)
                TX_START: begin
                    tx_phy_data[7:0]  = tx_is_dllp ? K_SDP : K_STP;
                    tx_phy_data[15:8] = tx_memory_even[0];
                    tx_phy_datak      = 2'b01;
                end
                TX_DATA: begin
                    tx_phy_data[7:0] = tx_read_byte0;
                    if (tx_remaining == 1) begin
                        tx_phy_data[15:8] = tx_bad_latched ? K_EDB : K_END;
                        tx_phy_datak = 2'b10;
                    end else begin
                        tx_phy_data[15:8] = tx_read_byte1;
                        tx_phy_datak = 2'b00;
                    end
                end
                TX_END: begin
                    tx_phy_data[7:0]  = tx_bad_latched ? K_EDB : K_END;
                    tx_phy_data[15:8] = D_IDL;
                    tx_phy_datak      = 2'b01;
                end
                default: begin end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_in_frame      <= 1'b0;
            rx_type_latched  <= 1'b0;
            rx_sop_pending   <= 1'b0;
            rx_pkt_valid     <= 1'b0;
            rx_pkt_data      <= 16'd0;
            rx_pkt_keep      <= 2'b00;
            rx_pkt_sop       <= 1'b0;
            rx_pkt_eop       <= 1'b0;
            rx_pkt_is_dllp   <= 1'b0;
            rx_pkt_error     <= 4'd0;
            rx_error_pulse   <= 1'b0;
        end else begin
            rx_pkt_valid <= 1'b0;
            rx_pkt_keep  <= 2'b00;
            rx_pkt_sop   <= 1'b0;
            rx_pkt_eop   <= 1'b0;
            rx_pkt_error <= 4'd0;
            rx_error_pulse <= 1'b0;

            if (!enable) begin
                if (rx_in_frame) begin
                    rx_pkt_valid   <= 1'b1;
                    rx_pkt_eop     <= 1'b1;
                    rx_pkt_error   <= 4'b1000;
                    rx_pkt_is_dllp <= rx_type_latched;
                    rx_error_pulse <= 1'b1;
                end
                rx_in_frame    <= 1'b0;
                rx_sop_pending <= 1'b0;
            end else if (rx_phy_valid) begin
                if (!rx_in_frame) begin
                    if (rx0_start) begin
                        rx_type_latched <= (rx_symbol0 == K_SDP);
                        rx_pkt_is_dllp  <= (rx_symbol0 == K_SDP);
                        if (!rx_symbol1_k) begin
                            rx_in_frame    <= 1'b1;
                            rx_sop_pending <= 1'b0;
                            rx_pkt_valid   <= 1'b1;
                            rx_pkt_data    <= {8'd0, rx_symbol1};
                            rx_pkt_keep    <= 2'b01;
                            rx_pkt_sop     <= 1'b1;
                        end else begin
                            rx_pkt_valid <= 1'b1;
                            rx_pkt_sop   <= 1'b1;
                            rx_pkt_eop   <= 1'b1;
                            rx_pkt_error <= rx1_start ? 4'b0100 : 4'b0010;
                            rx_error_pulse <= 1'b1;
                        end
                    end else if (rx1_start) begin
                        rx_in_frame     <= 1'b1;
                        rx_type_latched <= (rx_symbol1 == K_SDP);
                        rx_sop_pending  <= 1'b1;
                    end else if (rx0_end || rx1_end) begin
                        rx_error_pulse <= 1'b1;
                    end
                end else if (rx0_start || rx1_start) begin
                    rx_pkt_valid   <= 1'b1;
                    rx_pkt_eop     <= 1'b1;
                    rx_pkt_error   <= 4'b0100;
                    rx_pkt_is_dllp <= rx_type_latched;
                    rx_in_frame    <= 1'b0;
                    rx_sop_pending <= 1'b0;
                    rx_error_pulse <= 1'b1;
                end else if (rx0_end) begin
                    rx_pkt_valid   <= 1'b1;
                    rx_pkt_keep    <= 2'b00;
                    rx_pkt_sop     <= rx_sop_pending;
                    rx_pkt_eop     <= 1'b1;
                    rx_pkt_is_dllp <= rx_type_latched;
                    rx_pkt_error   <= (rx_symbol0 == K_EDB) ? 4'b0001 : 4'b0000;
                    rx_in_frame    <= 1'b0;
                    rx_sop_pending <= 1'b0;
                    if (rx_symbol0 == K_EDB)
                        rx_error_pulse <= 1'b1;
                end else if (rx1_end && !rx_symbol0_k) begin
                    rx_pkt_valid   <= 1'b1;
                    rx_pkt_data    <= {8'd0, rx_symbol0};
                    rx_pkt_keep    <= 2'b01;
                    rx_pkt_sop     <= rx_sop_pending;
                    rx_pkt_eop     <= 1'b1;
                    rx_pkt_is_dllp <= rx_type_latched;
                    rx_pkt_error   <= (rx_symbol1 == K_EDB) ? 4'b0001 : 4'b0000;
                    rx_in_frame    <= 1'b0;
                    rx_sop_pending <= 1'b0;
                    if (rx_symbol1 == K_EDB)
                        rx_error_pulse <= 1'b1;
                end else if (!rx_symbol0_k && !rx_symbol1_k) begin
                    rx_pkt_valid   <= 1'b1;
                    rx_pkt_data    <= rx_phy_data;
                    rx_pkt_keep    <= 2'b11;
                    rx_pkt_sop     <= rx_sop_pending;
                    rx_pkt_is_dllp <= rx_type_latched;
                    rx_sop_pending <= 1'b0;
                end else begin
                    rx_pkt_valid   <= 1'b1;
                    rx_pkt_eop     <= 1'b1;
                    rx_pkt_error   <= 4'b0010;
                    rx_pkt_is_dllp <= rx_type_latched;
                    rx_in_frame    <= 1'b0;
                    rx_sop_pending <= 1'b0;
                    rx_error_pulse <= 1'b1;
                end
            end
        end
    end
endmodule

`default_nettype wire
