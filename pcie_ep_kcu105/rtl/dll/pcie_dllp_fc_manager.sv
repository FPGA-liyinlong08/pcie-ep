`timescale 1ns/1ps
`default_nettype none

module pcie_dllp_fc_manager #(
    parameter integer RX_PH_CREDITS   = 32,
    parameter integer RX_PD_CREDITS   = 128,
    parameter integer RX_NPH_CREDITS  = 32,
    parameter integer RX_NPD_CREDITS  = 16,
    parameter integer RX_CPLH_CREDITS = 8,
    parameter integer RX_CPLD_CREDITS = 32,
    parameter integer UPDATE_INTERVAL_CYCLES = 256
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        link_up,
    input  wire        rx_dllp_valid,
    input  wire [31:0] rx_dllp_data,
    input  wire        rx_dllp_crc_good,
    input  wire [3:0]  rx_dllp_error,
    output reg         tx_dllp_valid,
    input  wire        tx_dllp_ready,
    output reg  [31:0] tx_dllp_data,
    input  wire [1:0]  tx_tlp_check_type,
    input  wire [11:0] tx_tlp_check_data_credits,
    output wire        tx_tlp_credit_available,
    input  wire        tx_tlp_consume_valid,
    input  wire [1:0]  tx_tlp_consume_type,
    input  wire [11:0] tx_tlp_consume_data_credits,
    input  wire        rx_tlp_consume_valid,
    input  wire [1:0]  rx_tlp_consume_type,
    input  wire [11:0] rx_tlp_consume_data_credits,
    input  wire        rx_tlp_release_valid,
    input  wire [1:0]  rx_tlp_release_type,
    input  wire [11:0] rx_tlp_release_data_credits,
    output wire        dll_active,
    output reg  [1:0]  fc_state,
    output wire [7:0]  tx_ph_available,
    output wire [11:0] tx_pd_available,
    output wire [7:0]  tx_nph_available,
    output wire [11:0] tx_npd_available,
    output wire [7:0]  tx_cplh_available,
    output wire [11:0] tx_cpld_available,
    output wire [7:0]  rx_ph_occupied,
    output wire [11:0] rx_pd_occupied,
    output wire [7:0]  rx_nph_occupied,
    output wire [11:0] rx_npd_occupied,
    output wire [7:0]  rx_cplh_occupied,
    output wire [11:0] rx_cpld_occupied,
    output reg  [31:0] fc_protocol_error_count,
    output reg  [31:0] tx_fc_count,
    output reg  [31:0] rx_fc_count
);
    localparam [1:0] FC_DOWN   = 2'd0;
    localparam [1:0] FC_INIT1  = 2'd1;
    localparam [1:0] FC_INIT2  = 2'd2;
    localparam [1:0] FC_ACTIVE = 2'd3;
    localparam [1:0] TYPE_P    = 2'd0;
    localparam [1:0] TYPE_NP   = 2'd1;
    localparam [1:0] TYPE_CPL  = 2'd2;

    localparam [7:0] DLLP_INIT1_P   = 8'h40;
    localparam [7:0] DLLP_INIT1_NP  = 8'h50;
    localparam [7:0] DLLP_INIT1_CPL = 8'h60;
    localparam [7:0] DLLP_UPDATE_P  = 8'h80;
    localparam [7:0] DLLP_UPDATE_NP = 8'h90;
    localparam [7:0] DLLP_UPDATE_CPL= 8'ha0;
    localparam [7:0] DLLP_INIT2_P   = 8'hc0;
    localparam [7:0] DLLP_INIT2_NP  = 8'hd0;
    localparam [7:0] DLLP_INIT2_CPL = 8'he0;

    localparam integer UPDATE_COUNTER_WIDTH =
        (UPDATE_INTERVAL_CYCLES <= 2) ? 1 : $clog2(UPDATE_INTERVAL_CYCLES);
    localparam [UPDATE_COUNTER_WIDTH-1:0] UPDATE_LIMIT =
        UPDATE_INTERVAL_CYCLES[UPDATE_COUNTER_WIDTH-1:0] - 1'b1;

    function automatic [31:0] sat_inc32(input [31:0] value);
        sat_inc32 = (&value) ? value : value + 1'b1;
    endfunction

    function automatic [31:0] pack_fc;
        input [7:0] type_byte;
        input [7:0] header_credit;
        input [11:0] data_credit;
        begin
            pack_fc[7:0]   = type_byte;
            pack_fc[15:8]  = {2'b00, header_credit[7:2]};
            pack_fc[23:16] = {header_credit[1:0], 2'b00, data_credit[11:8]};
            pack_fc[31:24] = data_credit[7:0];
        end
    endfunction

    function automatic [7:0] type_for_class;
        input [1:0] kind;
        input [1:0] credit_class;
        begin
            case (kind)
                FC_INIT1: case (credit_class)
                    TYPE_P: type_for_class = DLLP_INIT1_P;
                    TYPE_NP: type_for_class = DLLP_INIT1_NP;
                    default: type_for_class = DLLP_INIT1_CPL;
                endcase
                FC_INIT2: case (credit_class)
                    TYPE_P: type_for_class = DLLP_INIT2_P;
                    TYPE_NP: type_for_class = DLLP_INIT2_NP;
                    default: type_for_class = DLLP_INIT2_CPL;
                endcase
                default: case (credit_class)
                    TYPE_P: type_for_class = DLLP_UPDATE_P;
                    TYPE_NP: type_for_class = DLLP_UPDATE_NP;
                    default: type_for_class = DLLP_UPDATE_CPL;
                endcase
            endcase
        end
    endfunction

    reg [7:0] tx_h_limit [0:2];
    reg [11:0] tx_d_limit [0:2];
    reg [7:0] tx_h_consumed [0:2];
    reg [11:0] tx_d_consumed [0:2];
    reg tx_h_infinite [0:2];
    reg tx_d_infinite [0:2];

    wire [7:0] tx_h_avail_0 = tx_h_infinite[0] ? 8'hff :
                              tx_h_limit[0] - tx_h_consumed[0];
    wire [7:0] tx_h_avail_1 = tx_h_infinite[1] ? 8'hff :
                              tx_h_limit[1] - tx_h_consumed[1];
    wire [7:0] tx_h_avail_2 = tx_h_infinite[2] ? 8'hff :
                              tx_h_limit[2] - tx_h_consumed[2];
    wire [11:0] tx_d_avail_0 = tx_d_infinite[0] ? 12'hfff :
                               tx_d_limit[0] - tx_d_consumed[0];
    wire [11:0] tx_d_avail_1 = tx_d_infinite[1] ? 12'hfff :
                               tx_d_limit[1] - tx_d_consumed[1];
    wire [11:0] tx_d_avail_2 = tx_d_infinite[2] ? 12'hfff :
                               tx_d_limit[2] - tx_d_consumed[2];

    assign tx_ph_available = tx_h_avail_0;
    assign tx_pd_available = tx_d_avail_0;
    assign tx_nph_available = tx_h_avail_1;
    assign tx_npd_available = tx_d_avail_1;
    assign tx_cplh_available = tx_h_avail_2;
    assign tx_cpld_available = tx_d_avail_2;

    reg [7:0] check_h_available;
    reg [11:0] check_d_available;
    always @* begin
        case (tx_tlp_check_type)
            TYPE_P: begin check_h_available = tx_h_avail_0; check_d_available = tx_d_avail_0; end
            TYPE_NP: begin check_h_available = tx_h_avail_1; check_d_available = tx_d_avail_1; end
            TYPE_CPL: begin check_h_available = tx_h_avail_2; check_d_available = tx_d_avail_2; end
            default: begin check_h_available = 0; check_d_available = 0; end
        endcase
    end
    assign dll_active = (fc_state == FC_ACTIVE);
    assign tx_tlp_credit_available = dll_active &&
        (tx_tlp_check_type != 2'b11) && (check_h_available != 0) &&
        (check_d_available >= tx_tlp_check_data_credits);

    reg [7:0] consume_h_available;
    reg [11:0] consume_d_available;
    always @* begin
        case (tx_tlp_consume_type)
            TYPE_P: begin consume_h_available = tx_h_avail_0; consume_d_available = tx_d_avail_0; end
            TYPE_NP: begin consume_h_available = tx_h_avail_1; consume_d_available = tx_d_avail_1; end
            TYPE_CPL: begin consume_h_available = tx_h_avail_2; consume_d_available = tx_d_avail_2; end
            default: begin consume_h_available = 0; consume_d_available = 0; end
        endcase
    end
    wire tx_consume_legal = dll_active && (tx_tlp_consume_type != 2'b11) &&
        (consume_h_available != 0) &&
        (consume_d_available >= tx_tlp_consume_data_credits);

    wire local_event_active = dll_active;
    wire p_consume = local_event_active && rx_tlp_consume_valid &&
                     (rx_tlp_consume_type == TYPE_P);
    wire np_consume = local_event_active && rx_tlp_consume_valid &&
                      (rx_tlp_consume_type == TYPE_NP);
    wire cpl_consume = local_event_active && rx_tlp_consume_valid &&
                       (rx_tlp_consume_type == TYPE_CPL);
    wire p_release = local_event_active && rx_tlp_release_valid &&
                     (rx_tlp_release_type == TYPE_P);
    wire np_release = local_event_active && rx_tlp_release_valid &&
                      (rx_tlp_release_type == TYPE_NP);
    wire cpl_release = local_event_active && rx_tlp_release_valid &&
                       (rx_tlp_release_type == TYPE_CPL);

    wire [7:0] p_h_alloc, np_h_alloc, cpl_h_alloc;
    wire [11:0] p_d_alloc, np_d_alloc, cpl_d_alloc;
    wire p_pool_error, np_pool_error, cpl_pool_error;
    wire p_release_accepted, np_release_accepted, cpl_release_accepted;
    wire clear_local_pools = !link_up || !dll_active;

    pcie_fc_local_credit_pool #(
        .HEADER_CREDITS(RX_PH_CREDITS), .DATA_CREDITS(RX_PD_CREDITS)
    ) u_p_pool (
        .clk(clk), .rst_n(rst_n), .clear(clear_local_pools),
        .consume_valid(p_consume), .consume_data_credits(rx_tlp_consume_data_credits),
        .release_valid(p_release), .release_data_credits(rx_tlp_release_data_credits),
        .header_occupied(rx_ph_occupied), .data_occupied(rx_pd_occupied),
        .header_allocated(p_h_alloc), .data_allocated(p_d_alloc),
        .event_error(p_pool_error), .release_accepted(p_release_accepted)
    );
    pcie_fc_local_credit_pool #(
        .HEADER_CREDITS(RX_NPH_CREDITS), .DATA_CREDITS(RX_NPD_CREDITS)
    ) u_np_pool (
        .clk(clk), .rst_n(rst_n), .clear(clear_local_pools),
        .consume_valid(np_consume), .consume_data_credits(rx_tlp_consume_data_credits),
        .release_valid(np_release), .release_data_credits(rx_tlp_release_data_credits),
        .header_occupied(rx_nph_occupied), .data_occupied(rx_npd_occupied),
        .header_allocated(np_h_alloc), .data_allocated(np_d_alloc),
        .event_error(np_pool_error), .release_accepted(np_release_accepted)
    );
    pcie_fc_local_credit_pool #(
        .HEADER_CREDITS(RX_CPLH_CREDITS), .DATA_CREDITS(RX_CPLD_CREDITS)
    ) u_cpl_pool (
        .clk(clk), .rst_n(rst_n), .clear(clear_local_pools),
        .consume_valid(cpl_consume), .consume_data_credits(rx_tlp_consume_data_credits),
        .release_valid(cpl_release), .release_data_credits(rx_tlp_release_data_credits),
        .header_occupied(rx_cplh_occupied), .data_occupied(rx_cpld_occupied),
        .header_allocated(cpl_h_alloc), .data_allocated(cpl_d_alloc),
        .event_error(cpl_pool_error), .release_accepted(cpl_release_accepted)
    );

    wire [7:0] rx_type_byte = rx_dllp_data[7:0];
    wire [7:0] rx_type_base = {rx_type_byte[7:3], 3'b000};
    wire [2:0] rx_vc = rx_type_byte[2:0];
    wire [1:0] rx_header_scale = rx_dllp_data[15:14];
    wire [7:0] rx_header_credit = {rx_dllp_data[13:8], rx_dllp_data[23:22]};
    wire [1:0] rx_data_scale = rx_dllp_data[21:20];
    wire [11:0] rx_data_credit = {rx_dllp_data[19:16], rx_dllp_data[31:24]};

    reg rx_fc_recognized;
    reg [1:0] rx_fc_kind;
    reg [1:0] rx_fc_class;
    always @* begin
        rx_fc_recognized = 1'b1;
        rx_fc_kind = FC_DOWN;
        rx_fc_class = TYPE_P;
        case (rx_type_base)
            DLLP_INIT1_P: begin rx_fc_kind=FC_INIT1; rx_fc_class=TYPE_P; end
            DLLP_INIT1_NP: begin rx_fc_kind=FC_INIT1; rx_fc_class=TYPE_NP; end
            DLLP_INIT1_CPL: begin rx_fc_kind=FC_INIT1; rx_fc_class=TYPE_CPL; end
            DLLP_INIT2_P: begin rx_fc_kind=FC_INIT2; rx_fc_class=TYPE_P; end
            DLLP_INIT2_NP: begin rx_fc_kind=FC_INIT2; rx_fc_class=TYPE_NP; end
            DLLP_INIT2_CPL: begin rx_fc_kind=FC_INIT2; rx_fc_class=TYPE_CPL; end
            DLLP_UPDATE_P: begin rx_fc_kind=FC_ACTIVE; rx_fc_class=TYPE_P; end
            DLLP_UPDATE_NP: begin rx_fc_kind=FC_ACTIVE; rx_fc_class=TYPE_NP; end
            DLLP_UPDATE_CPL: begin rx_fc_kind=FC_ACTIVE; rx_fc_class=TYPE_CPL; end
            default: begin rx_fc_recognized=1'b0; rx_fc_kind=FC_DOWN; rx_fc_class=TYPE_P; end
        endcase
    end
    wire rx_fc_fields_valid = (rx_vc == 0) && (rx_header_scale == 0) &&
                              (rx_data_scale == 0);
    wire rx_good_fc = rx_dllp_valid && rx_dllp_crc_good &&
                      (rx_dllp_error == 0) && rx_fc_recognized;

    reg [2:0] init1_seen;
    reg [1:0] init_tx_cursor;
    reg [2:0] update_dirty;
    reg [1:0] update_cursor;
    reg [1:0] tx_out_class;
    reg [UPDATE_COUNTER_WIDTH-1:0] update_timer;
    integer k;

    reg [1:0] selected_update_class;
    always @* begin
        selected_update_class = update_cursor;
        case (update_cursor)
            TYPE_P: begin
                if (update_dirty[0]) selected_update_class = TYPE_P;
                else if (update_dirty[1]) selected_update_class = TYPE_NP;
                else selected_update_class = TYPE_CPL;
            end
            TYPE_NP: begin
                if (update_dirty[1]) selected_update_class = TYPE_NP;
                else if (update_dirty[2]) selected_update_class = TYPE_CPL;
                else selected_update_class = TYPE_P;
            end
            default: begin
                if (update_dirty[2]) selected_update_class = TYPE_CPL;
                else if (update_dirty[0]) selected_update_class = TYPE_P;
                else selected_update_class = TYPE_NP;
            end
        endcase
    end

    reg [7:0] selected_local_h;
    reg [11:0] selected_local_d;
    always @* begin
        case ((fc_state == FC_ACTIVE) ? selected_update_class : init_tx_cursor)
            TYPE_P: begin selected_local_h=p_h_alloc; selected_local_d=p_d_alloc; end
            TYPE_NP: begin selected_local_h=np_h_alloc; selected_local_d=np_d_alloc; end
            default: begin selected_local_h=cpl_h_alloc; selected_local_d=cpl_d_alloc; end
        endcase
    end

    wire local_type_invalid =
        (rx_tlp_consume_valid && (rx_tlp_consume_type == 2'b11)) ||
        (rx_tlp_release_valid && (rx_tlp_release_type == 2'b11));
    wire local_event_wrong_state = !dll_active &&
        (rx_tlp_consume_valid || rx_tlp_release_valid);
    wire manager_error_event = p_pool_error || np_pool_error || cpl_pool_error ||
        local_type_invalid || local_event_wrong_state ||
        (tx_tlp_consume_valid && !tx_consume_legal);

    generate
        if (UPDATE_INTERVAL_CYCLES < 4) begin : g_bad_update_interval
            initial $error("pcie_dllp_fc_manager: UPDATE_INTERVAL_CYCLES must be >= 4");
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fc_state <= FC_DOWN;
            init1_seen <= 0;
            init_tx_cursor <= TYPE_P;
            update_dirty <= 0;
            update_cursor <= TYPE_P;
            update_timer <= 0;
            tx_dllp_valid <= 0;
            tx_dllp_data <= 0;
            tx_out_class <= TYPE_P;
            fc_protocol_error_count <= 0;
            tx_fc_count <= 0;
            rx_fc_count <= 0;
            for (k = 0; k < 3; k = k + 1) begin
                tx_h_limit[k] <= 0;
                tx_d_limit[k] <= 0;
                tx_h_consumed[k] <= 0;
                tx_d_consumed[k] <= 0;
                tx_h_infinite[k] <= 0;
                tx_d_infinite[k] <= 0;
            end
        end else begin
            if (!link_up) begin
                fc_state <= FC_DOWN;
                init1_seen <= 0;
                init_tx_cursor <= TYPE_P;
                update_dirty <= 0;
                update_cursor <= TYPE_P;
                update_timer <= 0;
                tx_dllp_valid <= 0;
                for (k = 0; k < 3; k = k + 1) begin
                    tx_h_limit[k] <= 0;
                    tx_d_limit[k] <= 0;
                    tx_h_consumed[k] <= 0;
                    tx_d_consumed[k] <= 0;
                    tx_h_infinite[k] <= 0;
                    tx_d_infinite[k] <= 0;
                end
            end else begin
                if (fc_state == FC_DOWN) begin
                    fc_state <= FC_INIT1;
                    init1_seen <= 0;
                    init_tx_cursor <= TYPE_P;
                end

                if (tx_dllp_valid && tx_dllp_ready) begin
                    tx_dllp_valid <= 1'b0;
                    tx_fc_count <= sat_inc32(tx_fc_count);
                    if ((fc_state == FC_INIT1) || (fc_state == FC_INIT2)) begin
                        init_tx_cursor <= (init_tx_cursor == TYPE_CPL) ? TYPE_P :
                                          init_tx_cursor + 1'b1;
                    end else if (fc_state == FC_ACTIVE) begin
                        update_dirty[tx_out_class] <= 1'b0;
                        update_cursor <= (tx_out_class == TYPE_CPL) ? TYPE_P :
                                         tx_out_class + 1'b1;
                    end
                end

                if (!tx_dllp_valid) begin
                    if ((fc_state == FC_INIT1) || (fc_state == FC_INIT2)) begin
                        tx_dllp_valid <= 1'b1;
                        tx_out_class <= init_tx_cursor;
                        tx_dllp_data <= pack_fc(
                            type_for_class(fc_state, init_tx_cursor),
                            selected_local_h, selected_local_d);
                    end else if ((fc_state == FC_ACTIVE) && (update_dirty != 0)) begin
                        tx_dllp_valid <= 1'b1;
                        tx_out_class <= selected_update_class;
                        tx_dllp_data <= pack_fc(
                            type_for_class(FC_ACTIVE, selected_update_class),
                            selected_local_h, selected_local_d);
                    end
                end

                if (fc_state == FC_ACTIVE) begin
                    if (update_timer == UPDATE_LIMIT) begin
                        update_timer <= 0;
                        update_dirty <= 3'b111;
                    end else begin
                        update_timer <= update_timer + 1'b1;
                    end
                    if (p_release_accepted) update_dirty[0] <= 1'b1;
                    if (np_release_accepted) update_dirty[1] <= 1'b1;
                    if (cpl_release_accepted) update_dirty[2] <= 1'b1;
                end else begin
                    update_timer <= 0;
                end

                if (rx_good_fc) begin
                    if (!rx_fc_fields_valid) begin
                        fc_protocol_error_count <= sat_inc32(fc_protocol_error_count);
                    end else begin
                        rx_fc_count <= sat_inc32(rx_fc_count);
                        case (fc_state)
                            FC_INIT1: begin
                                if ((rx_fc_kind == FC_INIT1) || (rx_fc_kind == FC_INIT2)) begin
                                    tx_h_limit[rx_fc_class] <= rx_header_credit;
                                    tx_d_limit[rx_fc_class] <= rx_data_credit;
                                    tx_h_consumed[rx_fc_class] <= 0;
                                    tx_d_consumed[rx_fc_class] <= 0;
                                    tx_h_infinite[rx_fc_class] <= (rx_header_credit == 0);
                                    tx_d_infinite[rx_fc_class] <= (rx_data_credit == 0);
                                    init1_seen[rx_fc_class] <= 1'b1;
                                    if ((init1_seen | (3'b001 << rx_fc_class)) == 3'b111) begin
                                        fc_state <= FC_INIT2;
                                        init_tx_cursor <= TYPE_P;
                                    end
                                end else begin
                                    fc_protocol_error_count <= sat_inc32(fc_protocol_error_count);
                                end
                            end
                            FC_INIT2: begin
                                if ((rx_fc_kind == FC_INIT2) || (rx_fc_kind == FC_ACTIVE)) begin
                                    fc_state <= FC_ACTIVE;
                                    update_dirty <= 3'b111;
                                    update_cursor <= TYPE_P;
                                    update_timer <= 0;
                                end
                            end
                            FC_ACTIVE: begin
                                if (rx_fc_kind == FC_ACTIVE) begin
                                    if ((tx_h_infinite[rx_fc_class] && (rx_header_credit != 0)) ||
                                        (tx_d_infinite[rx_fc_class] && (rx_data_credit != 0))) begin
                                        fc_protocol_error_count <= sat_inc32(fc_protocol_error_count);
                                    end else begin
                                        tx_h_limit[rx_fc_class] <= rx_header_credit;
                                        tx_d_limit[rx_fc_class] <= rx_data_credit;
                                    end
                                end
                            end
                            default: begin end
                        endcase
                    end
                end

                if (tx_tlp_consume_valid && tx_consume_legal) begin
                    if (!tx_h_infinite[tx_tlp_consume_type])
                        tx_h_consumed[tx_tlp_consume_type] <=
                            tx_h_consumed[tx_tlp_consume_type] + 1'b1;
                    if (!tx_d_infinite[tx_tlp_consume_type])
                        tx_d_consumed[tx_tlp_consume_type] <=
                            tx_d_consumed[tx_tlp_consume_type] +
                            tx_tlp_consume_data_credits;
                end

                if (manager_error_event)
                    fc_protocol_error_count <= sat_inc32(fc_protocol_error_count);
            end
        end
    end

    wire _unused_bad_dllp = &{1'b0, rx_dllp_valid, rx_dllp_crc_good,
                               rx_dllp_error};
endmodule

`default_nettype wire
