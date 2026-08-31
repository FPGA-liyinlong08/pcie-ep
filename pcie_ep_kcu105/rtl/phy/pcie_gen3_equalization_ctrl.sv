`timescale 1ns/1ps
`default_nettype none

// Upstream-port Gen3 Recovery.Equalization protocol engine.  The LTSSM owns
// the phase and this block owns phase-local PCIe semantics.  Raw PG239 pins
// remain exclusively owned by pcie_phy_command_ctrl.
module pcie_gen3_equalization_ctrl #(
    parameter integer PHASE_TIMEOUT_CYCLES = 1_000_000,
    parameter integer PORT_ROLE = 0
) (
    input  wire        clk, input wire rst_n,
    input  wire        phase_valid, input wire [1:0] phase,
    input  wire        ts1_valid, input wire ts2_valid,
    input  wire        ts_malformed,
    input  wire [7:0]  ts_eq_control,
    input  wire [23:0] ts_eq_data,
    input  wire        tx_ts_complete,
    input  wire        initial_preset_valid,
    input  wire [3:0]  initial_preset,
    input  wire        initial_coeff_valid,
    input  wire [17:0] initial_coeff,
    input  wire [5:0]  local_fs,
    input  wire [5:0]  local_lf,

    output reg         eq_req_valid,
    output reg  [2:0]  eq_req_kind,
    output reg  [3:0]  eq_req_preset,
    output reg  [17:0] eq_req_coeff,
    input  wire        eq_req_ready, input wire eq_busy,
    input  wire        eq_done, input wire [2:0] eq_result,
    input  wire        eq_rsp_preset_sel,
    input  wire [17:0] eq_rsp_coeff,

    output reg  [7:0]  tx_eq_control,
    output reg  [23:0] tx_eq_data,
    output reg         phase_done,
    output reg         phase_failed,
    output reg  [3:0]  phase_ts_count,
    output reg  [2:0]  operation_state
);
    localparam [2:0] EQ_TX_PRESET = 3'd0;
    localparam [2:0] EQ_TX_COEFF  = 3'd1;
    localparam [2:0] EQ_TX_QUERY  = 3'd2;
    localparam [2:0] EQ_RX_ADAPT  = 3'd3;
    localparam [2:0] EQ_RESULT_SUCCESS  = 3'd1;
    localparam [2:0] EQ_RESULT_PROPOSAL = 3'd2;

    localparam [2:0] OP_IDLE         = 3'd0;
    localparam [2:0] OP_WAIT_RX      = 3'd1;
    localparam [2:0] OP_WAIT_REFLECT = 3'd2;
    localparam [2:0] OP_WAIT_TX      = 3'd3;
    localparam [2:0] OP_WAIT_QUERY   = 3'd4;
    localparam [2:0] OP_WAIT_NEXT    = 3'd5;
    localparam [2:0] OP_COMPLETE     = 3'd6;
    localparam [2:0] OP_FAIL         = 3'd7;
    localparam integer TIMEOUT_LIMIT =
        (PHASE_TIMEOUT_CYCLES < 1) ? 1 : PHASE_TIMEOUT_CYCLES;

    function automatic [17:0] preset_coeff(input [3:0] preset);
        begin
            // Standard Gen3 ratios at the K02 observed FS=40 point.  The
            // canonical path replaces this fallback with the Query result.
            case (preset)
                4'd0: preset_coeff = {6'd0, 6'd30, 6'd10};
                4'd1: preset_coeff = {6'd0, 6'd33, 6'd7};
                4'd2: preset_coeff = {6'd0, 6'd32, 6'd8};
                4'd3: preset_coeff = {6'd0, 6'd35, 6'd5};
                4'd4: preset_coeff = {6'd0, 6'd40, 6'd0};
                4'd5: preset_coeff = {6'd4, 6'd36, 6'd0};
                4'd6: preset_coeff = {6'd5, 6'd35, 6'd0};
                4'd7: preset_coeff = {6'd4, 6'd28, 6'd8};
                4'd8: preset_coeff = {6'd5, 6'd30, 6'd5};
                4'd9: preset_coeff = {6'd7, 6'd33, 6'd0};
                4'd10: preset_coeff = {6'd0, 6'd27, 6'd13};
                default: preset_coeff = {6'd0, 6'd40, 6'd0};
            endcase
        end
    endfunction

    function automatic [23:0] encode_eq_data(
        input [7:0] control, input [17:0] coeff, input reject
    );
        reg [7:0] symbol7, symbol8;
        reg [6:0] symbol9_low;
        reg parity;
        begin
            symbol7 = {2'b00, coeff[17:12]};
            symbol8 = {2'b00, coeff[11:6]};
            symbol9_low = {reject, coeff[5:0]};
            parity = ^{control, symbol7, symbol8, symbol9_low};
            encode_eq_data = {{parity, symbol9_low}, symbol8, symbol7};
        end
    endfunction

    function automatic coeff_is_legal(
        input [17:0] coeff, input [5:0] fs, input [5:0] lf
    );
        reg [7:0] sum;
        reg signed [8:0] low_frequency;
        begin
            sum = {2'b00, coeff[17:12]} + {2'b00, coeff[11:6]} +
                  {2'b00, coeff[5:0]};
            low_frequency = $signed({3'b000, coeff[11:6]}) -
                            $signed({3'b000, coeff[17:12]}) -
                            $signed({3'b000, coeff[5:0]});
            coeff_is_legal = (sum == {2'b00, fs}) &&
                             (low_frequency >= $signed({3'b000, lf}));
        end
    endfunction

    wire [3:0] initial_preset_w = initial_preset_valid &&
                                  (initial_preset <= 4'd10) ?
                                  initial_preset : 4'd4;
    wire [17:0] initial_coeff_w = initial_coeff_valid ? initial_coeff :
                                  preset_coeff(initial_preset_w);
    wire [7:0] phase0_control = {1'b0, initial_preset_w, 1'b0, 2'b00};
    wire [7:0] phase1_control = {1'b0, initial_preset_w, 1'b0, 2'b01};
    wire [17:0] phase1_fields = {local_fs, local_lf,
                                 initial_coeff_w[5:0]};

    wire parity_ok = (^{ts_eq_control, ts_eq_data} == 1'b0);
    wire legal_ts1 = ts1_valid && parity_ok;
    wire [31:0] incoming_tuple = {ts_eq_control, ts_eq_data};
    wire [1:0] incoming_ec = ts_eq_control[1:0];
    wire incoming_use_preset = ts_eq_control[7];
    wire [3:0] incoming_preset = ts_eq_control[6:3];
    wire [17:0] incoming_coeff = {ts_eq_data[5:0],
                                  ts_eq_data[13:8],
                                  ts_eq_data[21:16]};
    wire incoming_reject = ts_eq_data[22];

    reg phase_valid_q;
    reg [1:0] phase_q;
    reg [31:0] timeout_count;
    reg consecutive_have;
    reg [31:0] consecutive_tuple;
    reg [31:0] transition_tuple;
    reg transition_tuple_valid;
    reg [31:0] last_processed_tuple;
    reg [31:0] request_tuple;
    reg request_pending;
    reg exit_pending;
    reg proposal_pending;
    reg proposal_preset_sel;
    reg [17:0] proposal_coeff;
    reg [3:0] selected_preset;
    reg [7:0] reflected_control;
    reg [23:0] reflected_data;

    wire phase_entry = phase_valid &&
                       (!phase_valid_q || (phase != phase_q));
    wire second_same_ts = legal_ts1 && consecutive_have &&
                          (incoming_tuple == consecutive_tuple);
    wire timeout_expired = timeout_count >= (TIMEOUT_LIMIT - 1);
    wire request_preset_legal = request_tuple[31] &&
                                (request_tuple[30:27] <= 4'd10);
    wire [17:0] request_coeff = {request_tuple[5:0],
                                 request_tuple[13:8],
                                 request_tuple[21:16]};
    wire request_coeff_legal = !request_tuple[31] &&
                               coeff_is_legal(request_coeff,
                                              local_fs, local_lf);
    wire request_legal = request_preset_legal || request_coeff_legal;
    wire proposal_content_matches =
        (incoming_ec == 2'b10) &&
        (incoming_use_preset == proposal_preset_sel) &&
        (proposal_preset_sel ?
         (incoming_preset == proposal_coeff[3:0]) :
         (incoming_coeff == proposal_coeff));

    always @* begin
        eq_req_valid = 1'b0;
        eq_req_kind = EQ_TX_PRESET;
        eq_req_preset = selected_preset;
        eq_req_coeff = request_coeff;
        // Also expose the qualified Phase-0 tuple while the LTSSM is in the
        // post-rate Receiver Lock bridge before phase_valid becomes true.
        tx_eq_control = phase0_control;
        tx_eq_data = encode_eq_data(phase0_control, initial_coeff_w, 1'b0);

        if (phase_valid) begin
            case (phase)
                2'd0: begin
                    tx_eq_control = phase0_control;
                    tx_eq_data = encode_eq_data(phase0_control,
                                                initial_coeff_w, 1'b0);
                end
                2'd1: begin
                    tx_eq_control = phase1_control;
                    tx_eq_data = encode_eq_data(phase1_control,
                                                phase1_fields, 1'b0);
                end
                2'd2: begin
                    if (proposal_pending) begin
                        tx_eq_control = proposal_preset_sel ?
                            {1'b1, proposal_coeff[3:0], 1'b0, 2'b10} :
                            {1'b0, selected_preset, 1'b0, 2'b10};
                        tx_eq_data = encode_eq_data(
                            tx_eq_control,
                            proposal_preset_sel ? initial_coeff_w :
                                                  proposal_coeff,
                            1'b0);
                    end else if (operation_state == OP_WAIT_NEXT) begin
                        tx_eq_control = {1'b0, selected_preset, 1'b0, 2'b11};
                        tx_eq_data = encode_eq_data(tx_eq_control,
                                                   initial_coeff_w, 1'b0);
                    end else begin
                        tx_eq_control = transition_tuple_valid ?
                                        transition_tuple[31:24] :
                                        {1'b1, selected_preset, 1'b0, 2'b10};
                        tx_eq_control[1:0] = 2'b10;
                        tx_eq_data = transition_tuple_valid ?
                                     transition_tuple[23:0] :
                                     encode_eq_data(tx_eq_control,
                                                    initial_coeff_w, 1'b0);
                    end
                    if ((operation_state == OP_IDLE) && eq_req_ready) begin
                        eq_req_valid = 1'b1;
                        eq_req_kind = EQ_RX_ADAPT;
                        eq_req_preset = selected_preset;
                    end
                end
                default: begin
                    tx_eq_control = reflected_control;
                    tx_eq_data = reflected_data;
                    if (request_pending && request_legal && eq_req_ready) begin
                        eq_req_valid = 1'b1;
                        eq_req_kind = request_tuple[31] ?
                                      EQ_TX_PRESET : EQ_TX_COEFF;
                        eq_req_preset = request_tuple[30:27];
                        eq_req_coeff = request_coeff;
                    end else if ((operation_state == OP_WAIT_QUERY) &&
                                 eq_req_ready) begin
                        eq_req_valid = 1'b1;
                        eq_req_kind = EQ_TX_QUERY;
                    end
                end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_valid_q <= 1'b0; phase_q <= 2'd0;
            timeout_count <= 32'd0;
            consecutive_have <= 1'b0; consecutive_tuple <= 32'd0;
            transition_tuple <= 32'd0; transition_tuple_valid <= 1'b0;
            last_processed_tuple <= 32'd0; request_tuple <= 32'd0;
            request_pending <= 1'b0; exit_pending <= 1'b0;
            proposal_pending <= 1'b0; proposal_preset_sel <= 1'b0;
            proposal_coeff <= 18'd0; selected_preset <= 4'd4;
            reflected_control <= 8'd0; reflected_data <= 24'd0;
            phase_done <= 1'b0; phase_failed <= 1'b0;
            phase_ts_count <= 4'd0; operation_state <= OP_IDLE;
        end else begin
            phase_valid_q <= phase_valid; phase_q <= phase;
            phase_done <= 1'b0; phase_failed <= 1'b0;
            if (!phase_valid) begin
                timeout_count <= 32'd0; consecutive_have <= 1'b0;
                phase_ts_count <= 4'd0; request_pending <= 1'b0;
                exit_pending <= 1'b0; proposal_pending <= 1'b0;
                operation_state <= OP_IDLE;
            end else if (phase_entry) begin
                timeout_count <= 32'd0; consecutive_have <= 1'b0;
                phase_ts_count <= 4'd0; request_pending <= 1'b0;
                exit_pending <= 1'b0; proposal_pending <= 1'b0;
                operation_state <= OP_IDLE;
                if (phase == 2'd2 && transition_tuple_valid) begin
                    selected_preset <= transition_tuple[30:27];
                end else if (phase == 2'd3 && transition_tuple_valid) begin
                    request_tuple <= transition_tuple;
                    last_processed_tuple <= transition_tuple;
                    request_pending <= 1'b1;
                    reflected_control <= transition_tuple[31:24];
                    reflected_data <= transition_tuple[23:0];
                end
            end else begin
                timeout_count <= timeout_count + 1'b1;
                if (legal_ts1) begin
                    if (!consecutive_have ||
                        (incoming_tuple != consecutive_tuple)) begin
                        consecutive_have <= 1'b1;
                        consecutive_tuple <= incoming_tuple;
                        phase_ts_count <= 4'd1;
                    end else phase_ts_count <= 4'd2;
                end else if (ts2_valid || ts_malformed || ts1_valid) begin
                    consecutive_have <= 1'b0;
                    phase_ts_count <= 4'd0;
                end

                case (phase)
                    2'd0: if (second_same_ts && (incoming_ec == 2'b01)) begin
                        transition_tuple <= incoming_tuple;
                        transition_tuple_valid <= 1'b1;
                        phase_done <= 1'b1; operation_state <= OP_COMPLETE;
                    end
                    2'd1: if (second_same_ts && (incoming_ec == 2'b10)) begin
                        transition_tuple <= incoming_tuple;
                        transition_tuple_valid <= 1'b1;
                        phase_done <= 1'b1; operation_state <= OP_COMPLETE;
                    end
                    2'd2: begin
                        if (eq_req_valid && eq_req_ready) begin
                            operation_state <= OP_WAIT_RX;
                            proposal_pending <= 1'b0;
                        end
                        if (eq_done && (operation_state == OP_WAIT_RX)) begin
                            if (eq_result == EQ_RESULT_SUCCESS)
                                operation_state <= OP_WAIT_NEXT;
                            else if (eq_result == EQ_RESULT_PROPOSAL) begin
                                proposal_pending <= 1'b1;
                                proposal_preset_sel <= eq_rsp_preset_sel;
                                proposal_coeff <= eq_rsp_coeff;
                                operation_state <= OP_WAIT_REFLECT;
                            end else begin
                                phase_failed <= 1'b1;
                                operation_state <= OP_FAIL;
                            end
                        end
                        if (proposal_pending && second_same_ts &&
                            proposal_content_matches) begin
                            if (incoming_reject) begin
                                phase_failed <= 1'b1;
                                operation_state <= OP_FAIL;
                            end else begin
                                if (proposal_preset_sel)
                                    selected_preset <= incoming_preset;
                                proposal_pending <= 1'b0;
                                operation_state <= OP_IDLE;
                            end
                        end
                        if ((operation_state == OP_WAIT_NEXT) &&
                            second_same_ts && (incoming_ec == 2'b11)) begin
                            transition_tuple <= incoming_tuple;
                            transition_tuple_valid <= 1'b1;
                            phase_done <= 1'b1; operation_state <= OP_COMPLETE;
                        end
                    end
                    default: begin
                        if (request_pending && !request_legal) begin
                            reflected_control <= request_tuple[31:24];
                            reflected_data <= encode_eq_data(
                                request_tuple[31:24], request_coeff, 1'b1);
                            request_pending <= 1'b0;
                            operation_state <= OP_WAIT_NEXT;
                        end else if (eq_req_valid && eq_req_ready) begin
                            request_pending <= 1'b0;
                            operation_state <= (eq_req_kind == EQ_TX_QUERY) ?
                                               OP_WAIT_QUERY : OP_WAIT_TX;
                        end
                        if (eq_done && (operation_state == OP_WAIT_TX)) begin
                            if (eq_result == EQ_RESULT_SUCCESS)
                                operation_state <= OP_WAIT_QUERY;
                            else begin
                                reflected_control <= request_tuple[31:24];
                                reflected_data <= encode_eq_data(
                                    request_tuple[31:24], request_coeff, 1'b1);
                                operation_state <= OP_WAIT_NEXT;
                            end
                        end else if (eq_done &&
                                     (operation_state == OP_WAIT_QUERY)) begin
                            if (eq_result == EQ_RESULT_SUCCESS) begin
                                reflected_control <= request_tuple[31:24];
                                reflected_data <= encode_eq_data(
                                    request_tuple[31:24], eq_rsp_coeff, 1'b0);
                                operation_state <= OP_WAIT_NEXT;
                                if (exit_pending ||
                                    (second_same_ts &&
                                     (incoming_ec == 2'b00))) begin
                                    phase_done <= 1'b1;
                                    operation_state <= OP_COMPLETE;
                                end
                            end else begin
                                phase_failed <= 1'b1;
                                operation_state <= OP_FAIL;
                            end
                        end
                        if (second_same_ts && (incoming_ec == 2'b00)) begin
                            if ((operation_state == OP_WAIT_TX) ||
                                (operation_state == OP_WAIT_QUERY) ||
                                (eq_req_valid && eq_req_ready))
                                exit_pending <= 1'b1;
                            else begin
                                phase_done <= 1'b1;
                                operation_state <= OP_COMPLETE;
                            end
                        end else if (second_same_ts &&
                                     (incoming_ec == 2'b11) &&
                                     (incoming_tuple != last_processed_tuple) &&
                                     (operation_state == OP_WAIT_NEXT)) begin
                            request_tuple <= incoming_tuple;
                            last_processed_tuple <= incoming_tuple;
                            request_pending <= 1'b1;
                            reflected_control <= incoming_tuple[31:24];
                            reflected_data <= incoming_tuple[23:0];
                            operation_state <= OP_IDLE;
                        end
                    end
                endcase

                if (timeout_expired &&
                    (operation_state != OP_COMPLETE) &&
                    (operation_state != OP_FAIL)) begin
                    phase_failed <= 1'b1;
                    operation_state <= OP_FAIL;
                end
            end
        end
    end

    wire _unused = &{1'b0, PORT_ROLE[0], tx_ts_complete, eq_busy};
endmodule

`default_nettype wire
