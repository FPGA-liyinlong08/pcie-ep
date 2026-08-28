`timescale 1ns/1ps
`default_nettype none

// K15 upstream-port Gen3 Recovery.Equalization protocol engine.  LTSSM owns
// the phase; this block owns only phase-local TS responses and semantic PHY
// operations.  No raw PIPE/PHY pin is driven here.
module pcie_gen3_equalization_ctrl #(
    parameter integer PHASE_TIMEOUT_CYCLES = 1_000_000,
    parameter integer TS_REQUIRED = 8,
    parameter integer PORT_ROLE = 0  // 0=Upstream, reserved otherwise
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        phase_valid,
    input  wire [1:0]  phase,
    input  wire        ts1_valid,
    input  wire        ts2_valid,
    input  wire [7:0]  ts_eq_control,
    input  wire [23:0] ts_eq_data,
    input  wire        tx_ts_complete,

    output reg         eq_req_valid,
    output reg  [2:0]  eq_req_kind,
    output reg  [3:0]  eq_req_preset,
    output reg  [17:0] eq_req_coeff,
    input  wire        eq_req_ready,
    input  wire        eq_busy,
    input  wire        eq_done,
    input  wire [2:0]  eq_result,
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
    localparam [2:0] EQ_TX_QUERY  = 3'd2;
    localparam [2:0] EQ_RX_ADAPT  = 3'd3;
    localparam [2:0] EQ_RESULT_SUCCESS = 3'd1;
    localparam [2:0] EQ_RESULT_PROPOSAL = 3'd2;

    localparam [2:0] OP_IDLE = 3'd0;
    localparam [2:0] OP_WAIT_RX = 3'd1;
    localparam [2:0] OP_WAIT_PEER = 3'd2;
    localparam [2:0] OP_WAIT_TX = 3'd3;
    localparam [2:0] OP_WAIT_QUERY = 3'd4;
    localparam [2:0] OP_COMPLETE = 3'd5;
    localparam [2:0] OP_FAIL = 3'd6;

    localparam integer TIMEOUT_LIMIT =
        (PHASE_TIMEOUT_CYCLES < 1) ? 1 : PHASE_TIMEOUT_CYCLES;
    localparam [3:0] TS_LIMIT = (TS_REQUIRED < 1) ? 4'd1 :
                               TS_REQUIRED[3:0];

    reg phase_valid_q;
    reg [1:0] phase_q;
    reg [31:0] timeout_count;
    reg response_ready;
    reg response_sent;
    reg proposal_pending;
    reg proposal_preset_sel;
    reg [17:0] proposal_coeff;
    reg [3:0] selected_preset;
    wire phase_entry = phase_valid &&
                       (!phase_valid_q || (phase != phase_q));
    wire legal_ts = ts1_valid || ts2_valid;
    wire peer_phase1_request = ts1_valid &&
                               (ts_eq_control == 8'h01) &&
                               (ts_eq_data == 24'h8a0c28);
    wire timeout_expired = timeout_count >= (TIMEOUT_LIMIT - 1);
    // Gen3 TS equalization tuple places the transmitter preset in the high
    // nibble of the last EQ byte (symbol 8), i.e. EQ_DATA[23:20].  The low
    // byte carries FS/LF (for example 8a0c28); using EQ_DATA[3:0] happens to
    // pass that sample but is not a legal decoder for other partner presets.
    wire [3:0] peer_preset = (ts_eq_data[23:20] <= 4'd9) ?
                             ts_eq_data[23:20] : 4'd5;

    always @* begin
        eq_req_valid = 1'b0;
        eq_req_kind = EQ_TX_PRESET;
        eq_req_preset = selected_preset;
        eq_req_coeff = proposal_coeff;
        tx_eq_control = 8'h00;
        tx_eq_data = 24'h454545;

        if (phase_valid) begin
            case (phase)
                2'd0: begin
                    // Initial upstream response: advertise preset 4 and the
                    // lane's initial coefficient tuple.
                    tx_eq_control = 8'h20;
                    tx_eq_data = 24'h802800;
                end
                2'd1: begin
                    tx_eq_control = response_ready ? 8'h21 : 8'h20;
                    tx_eq_data = response_ready ? 24'h000c28 : 24'h802800;
                end
                2'd2: begin
                    // Upstream Port RX Adapt belongs to Phase 2.
                    tx_eq_control = proposal_pending ?
                                    (proposal_preset_sel ? 8'h22 : 8'h23) :
                                    8'h21;
                    tx_eq_data = proposal_pending ?
                                 (proposal_preset_sel ?
                                  {20'd0, proposal_coeff[3:0]} :
                                  {6'd0, proposal_coeff}) : 24'h000c28;
                    // Do not launch RX Adapt at phase entry.  The partner's
                    // TS1 carries the requested transmitter preset; wait
                    // until at least one legal TS has been sampled so the
                    // selected_preset register contains that tuple.
                    if ((operation_state == OP_IDLE) &&
                        (phase_ts_count != 4'd0) && eq_req_ready) begin
                        eq_req_valid = 1'b1;
                        eq_req_kind = EQ_RX_ADAPT;
                        eq_req_preset = selected_preset;
                    end
                end
                default: begin
                    // Upstream Port TX Adapt belongs to Phase 3.  Apply the
                    // requested preset, then query the committed coefficient.
                    tx_eq_control = 8'h23;
                    tx_eq_data = {6'd0, proposal_coeff};
                    if (operation_state == OP_IDLE && eq_req_ready) begin
                        eq_req_valid = 1'b1;
                        eq_req_kind = EQ_TX_PRESET;
                        eq_req_preset = selected_preset;
                    end else if (operation_state == OP_WAIT_QUERY &&
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
            phase_valid_q <= 1'b0;
            phase_q <= 2'd0;
            timeout_count <= 32'd0;
            phase_ts_count <= 4'd0;
            response_ready <= 1'b0;
            response_sent <= 1'b0;
            proposal_pending <= 1'b0;
            proposal_preset_sel <= 1'b0;
            proposal_coeff <= 18'd0;
            selected_preset <= 4'd5;
            phase_done <= 1'b0;
            phase_failed <= 1'b0;
            operation_state <= OP_IDLE;
        end else begin
            phase_valid_q <= phase_valid;
            phase_q <= phase;
            phase_done <= 1'b0;
            phase_failed <= 1'b0;

            if (!phase_valid) begin
                timeout_count <= 32'd0;
                phase_ts_count <= 4'd0;
                response_ready <= 1'b0;
                response_sent <= 1'b0;
                proposal_pending <= 1'b0;
                operation_state <= OP_IDLE;
            end else if (phase_entry) begin
                timeout_count <= 32'd0;
                phase_ts_count <= 4'd0;
                response_ready <= 1'b0;
                response_sent <= 1'b0;
                proposal_pending <= 1'b0;
                selected_preset <= 4'd5;
                operation_state <= OP_IDLE;
            end else begin
                timeout_count <= timeout_count + 1'b1;
                if (legal_ts) begin
                    if (phase_ts_count != 4'hf)
                        phase_ts_count <= phase_ts_count + 1'b1;
                    selected_preset <= peer_preset;
                end

                case (phase)
                    2'd0: begin
                        if (phase_ts_count >= (TS_LIMIT - 1'b1)) begin
                            phase_done <= 1'b1;
                            operation_state <= OP_COMPLETE;
                        end
                    end
                    2'd1: begin
                        if (phase_ts_count >= (TS_LIMIT - 1'b1))
                            response_ready <= 1'b1;
                        if (response_ready && tx_ts_complete)
                            response_sent <= 1'b1;
                        // Hold the 21/000c28 response until the downstream
                        // port actually leaves its Phase-1 request tuple.
                        // Counting our own transmitted TSs is not a protocol
                        // acknowledgement and can race a slower partner.
                        if (response_sent && legal_ts &&
                            !peer_phase1_request) begin
                            phase_done <= 1'b1;
                            operation_state <= OP_COMPLETE;
                        end
                    end
                    2'd2: begin
                        if (eq_req_valid && eq_req_ready) begin
                            operation_state <= OP_WAIT_RX;
                            proposal_pending <= 1'b0;
                        end
                        if (eq_done && operation_state == OP_WAIT_RX) begin
                            if (eq_result == EQ_RESULT_SUCCESS) begin
                                phase_done <= 1'b1;
                                operation_state <= OP_COMPLETE;
                            end else if (eq_result == EQ_RESULT_PROPOSAL) begin
                                proposal_pending <= 1'b1;
                                proposal_preset_sel <= eq_rsp_preset_sel;
                                proposal_coeff <= eq_rsp_coeff;
                                operation_state <= OP_WAIT_PEER;
                            end else begin
                                phase_failed <= 1'b1;
                                operation_state <= OP_FAIL;
                            end
                        end
                        if (proposal_pending && legal_ts) begin
                            proposal_pending <= 1'b0;
                            operation_state <= OP_IDLE;
                        end
                    end
                    default: begin
                        if (eq_req_valid && eq_req_ready) begin
                            operation_state <= (eq_req_kind == EQ_TX_QUERY) ?
                                               OP_WAIT_QUERY : OP_WAIT_TX;
                        end
                        if (eq_done && operation_state == OP_WAIT_TX) begin
                            if (eq_result == EQ_RESULT_SUCCESS)
                                operation_state <= OP_WAIT_QUERY;
                            else begin
                                phase_failed <= 1'b1;
                                operation_state <= OP_FAIL;
                            end
                        end else if (eq_done &&
                                     operation_state == OP_WAIT_QUERY) begin
                            if (eq_result == EQ_RESULT_SUCCESS) begin
                                proposal_coeff <= eq_rsp_coeff;
                                phase_done <= 1'b1;
                                operation_state <= OP_COMPLETE;
                            end else begin
                                phase_failed <= 1'b1;
                                operation_state <= OP_FAIL;
                            end
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

    wire _unused = &{1'b0, PORT_ROLE[0], ts_eq_control, eq_busy};
endmodule

`default_nettype wire
