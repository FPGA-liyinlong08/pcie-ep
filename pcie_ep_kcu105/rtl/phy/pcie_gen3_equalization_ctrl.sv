`timescale 1ns/1ps
`default_nettype none

// Upstream-port Gen3 Recovery.Equalization protocol engine.  The LTSSM owns
// the phase and this block owns phase-local PCIe semantics.  Raw PG239 pins
// remain exclusively owned by pcie_phy_command_ctrl.
//
// Phase semantics (PCIe Base Spec r3.1a 4.2.6.4.2.2, upstream port lanes):
//   Phase 0: announce FS/LF + the preset received in the EQ TS2s (EC=00);
//     leave after the partner's EC=01 pair (the downstream starts Phase 1
//     unilaterally -- downstream lanes have no Phase 0).
//   Phase 1: pure announcement (EC=01 with our preset and FS/LF/PostC).
//     The partner's EC=01 stream is the advertisement of ITS transmitter,
//     not a request, so nothing is applied here.  Leave after its EC=10
//     pair (it moved to its Phase 2; the SVT VIP never sends EC=00 here)
//     or its EC=00 pair (it skipped Phase 2/3 straight to RcvrLock).
//   Phase 2: all of our EC=10 TS1s are requests targeting the DOWNSTREAM
//     transmitter (4.2.6.4.2.2.3).  The first request reflects the EC=10
//     pair that caused the transition ("maintain current settings");
//     afterwards the EQ_RX_ADAPT engine proposes presets/coefficients and
//     acceptance is the partner's advertisement matching the request for
//     two consecutive TS1s with Reject=0.  When our RX is satisfied the
//     phase concludes by transmitting EC=11, which moves the downstream
//     from its Phase 2 to its Phase 3 -- EC=00 is never sent here (the
//     SVT VIP timed out in its Phase 2 waiting for our EC=11).
//   Phase 3: we transmit EC=11 and APPLY the downstream's EC=11 requests
//     (preset or coefficient, Use Preset selects which) to our own TX,
//     reflecting the applied settings (or the requested values with
//     Reject=1 when illegal/unsupported, per 4.2.3.1).  The downstream's
//     first request reflects our EC=11 pair (a maintain request) and is
//     deduplicated against our own base tuple.  Leave after its EC=00
//     pair, which ends the whole equalization procedure.
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
    // Phase 1 completed because the downstream sent the EC=00 RcvrLock
    // stream (it skipped Phase 2/3, 4.2.6.4.2.2.2) -- the LTSSM must go to
    // Recovery.RcvrLock, not Phase 2.
    output reg         phase1_exit_skip,
    output reg  [3:0]  phase_ts_count,
    output reg  [2:0]  operation_state,
    // Observation-only Phase-2 state.  Keep the protocol outputs above
    // unchanged; this packed bus lets the board ILA distinguish a PHY RXEQ
    // stall from a proposal/TS1 matching failure.
    output wire [31:0] phase2_debug
);
    localparam [2:0] EQ_TX_PRESET = 3'd0;
    localparam [2:0] EQ_TX_COEFF  = 3'd1;
    localparam [2:0] EQ_RX_ADAPT  = 3'd3;
    localparam [2:0] EQ_RESULT_SUCCESS  = 3'd1;
    localparam [2:0] EQ_RESULT_PROPOSAL = 3'd2;

    localparam [2:0] OP_IDLE         = 3'd0;
    localparam [2:0] OP_WAIT_RX      = 3'd1;
    localparam [2:0] OP_WAIT_REFLECT = 3'd2;
    localparam [2:0] OP_WAIT_TX      = 3'd3;
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
                             (low_frequency >= $signed({3'b000, lf})) &&
                             ({2'b00, coeff[17:12]} <=
                              {3'b000, fs[5:2]});  // |C-1| <= Floor(FS/4)
        end
    endfunction

    wire [3:0] initial_preset_w = initial_preset_valid &&
                                  (initial_preset <= 4'd10) ?
                                  initial_preset : 4'd4;
    wire [17:0] initial_coeff_w = initial_coeff_valid ? initial_coeff :
                                  preset_coeff(initial_preset_w);
    wire [7:0] phase0_control_w = {1'b0, initial_preset_w, 1'b0, 2'b00};
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
    reg [3:0] ec00_count;       // consecutive EC=00 TS1s in Phase 1
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
    reg [3:0] selected_preset;   // preset our own TX is currently at
    reg [17:0] tx_coeff;         // coefficients our own TX is currently at
    reg [3:0] partner_preset;    // preset the partner TX is believed at
    reg [7:0] reflected_control;
    reg [23:0] reflected_data;
    reg last_accepted_valid;
    reg last_accepted_preset_sel;
    reg [17:0] last_accepted_coeff;
    reg [31:0] last_accepted_tuple;

    wire phase_entry = phase_valid &&
                       (!phase_valid_q || (phase != phase_q));
    wire second_same_ts = legal_ts1 && consecutive_have &&
                          (incoming_tuple == consecutive_tuple);
    wire timeout_expired = timeout_count >= (TIMEOUT_LIMIT - 1);
    // EC semantics of a stored request tuple (Symbol 6 [1:0]):
    //   Phase-3 requests arrive with EC=11b; the Use Preset bit selects a
    //   preset request (1b, preset field valid) from a coefficient request
    //   (0b, coefficient fields valid) per 4.2.3.1.
    wire request_is_preset = request_tuple[31];
    wire request_is_coeff  = !request_tuple[31];
    wire [17:0] request_coeff = {request_tuple[5:0],
                                 request_tuple[13:8],
                                 request_tuple[21:16]};
    wire request_preset_legal = request_is_preset &&
                                (request_tuple[30:27] <= 4'd10);
    wire request_coeff_legal = request_is_coeff &&
                               coeff_is_legal(request_coeff,
                                              local_fs, local_lf);
    wire request_legal = request_preset_legal || request_coeff_legal;
    wire [3:0] partner_preset_w =
        (partner_preset <= 4'd10) ? partner_preset : 4'd4;
    // The partner's EC=10 Phase-2 advertisement is accepted as the reply to
    // our request when it matches the proposal's identity for two
    // consecutive TS1s.  SVT VIP ground truth (261.9us symbol log): the
    // downstream applies a preset proposal to its own transmitter and
    // advertises EC=10 with Use Preset=0, the applied preset number in the
    // preset field, and its own transmitter coefficients -- it does not
    // echo the request tuple bit-exactly, so only the preset number (preset
    // requests) or the coefficient fields (coefficient requests) are
    // compared.  Reject is evaluated separately at the accept site.
    wire proposal_content_matches =
        (incoming_ec == 2'b10) &&
        (proposal_preset_sel ?
         (incoming_preset == proposal_coeff[3:0]) :
         (incoming_coeff == proposal_coeff));
    assign phase2_debug = {
        proposal_coeff,          // [31:14]
        exit_pending,            // [13]
        request_pending,         // [12]
        transition_tuple_valid,  // [11]
        timeout_expired,         // [10]
        last_accepted_valid,     // [9]
        incoming_ec,             // [8:7]
        legal_ts1,               // [6]
        incoming_reject,         // [5]
        proposal_content_matches,// [4]
        second_same_ts,          // [3]
        consecutive_have,        // [2]
        proposal_preset_sel,     // [1]
        proposal_pending         // [0]
    };

    always @* begin
        eq_req_valid = 1'b0;
        eq_req_kind = EQ_TX_PRESET;
        eq_req_preset = partner_preset_w;
        eq_req_coeff = request_coeff;
        // Also expose the qualified Phase-0 tuple while the LTSSM is in the
        // post-rate Receiver Lock bridge before phase_valid becomes true.
        tx_eq_control = phase0_control_w;
        tx_eq_data = encode_eq_data(phase0_control_w, initial_coeff_w, 1'b0);

        if (phase_valid) begin
            case (phase)
                2'd0: begin
                    tx_eq_control = phase0_control_w;
                    tx_eq_data = encode_eq_data(phase0_control_w,
                                                initial_coeff_w, 1'b0);
                end
                2'd1: begin
                    // Pure announcement: our preset, FS, LF and PostC
                    // (4.2.6.4.2.2.2).  No requests are received here --
                    // the partner's EC=01 stream advertises its own TX.
                    tx_eq_control = {1'b0, selected_preset, 1'b0, 2'b01};
                    tx_eq_data = encode_eq_data(tx_eq_control,
                                                phase1_fields, 1'b0);
                end
                2'd2: begin
                    if (operation_state == OP_COMPLETE) begin
                        // Concluding Phase 2: EC=11 moves the link -- and
                        // the downstream port out of its Phase 2 -- into
                        // Phase 3 (4.2.6.4.2.2.3 "moves the Link to Phase 3
                        // by transmitting TS1 Ordered Sets with EC=11b").
                        tx_eq_control = {1'b0, selected_preset, 1'b0, 2'b11};
                        tx_eq_data = encode_eq_data(tx_eq_control,
                                                    tx_coeff, 1'b0);
                    end else if (proposal_pending) begin
                        tx_eq_control = proposal_preset_sel ?
                            {1'b1, proposal_coeff[3:0], 1'b0, 2'b10} :
                            {1'b0, partner_preset_w, 1'b0, 2'b10};
                        tx_eq_data = encode_eq_data(
                            tx_eq_control,
                            proposal_preset_sel ? initial_coeff_w :
                                                  proposal_coeff,
                            1'b0);
                    end else begin
                        // Before the first proposal completes (and between
                        // proposals): the current request stream -- seeded
                        // at Phase-1 exit with the maintain-reflection of
                        // the partner's advertisement.
                        tx_eq_control = reflected_control;
                        tx_eq_data = reflected_data;
                    end
                    if ((operation_state == OP_IDLE) && eq_req_ready) begin
                        eq_req_valid = 1'b1;
                        eq_req_kind = EQ_RX_ADAPT;
                        eq_req_preset = partner_preset_w;
                    end
                end
                default: begin
                    // Phase 3: reflect our transmitter settings (base) or
                    // the applied/rejected request outcome while the
                    // downstream evaluates us.
                    tx_eq_control = reflected_control;
                    tx_eq_data = reflected_data;
                    if (request_pending && request_legal && eq_req_ready) begin
                        eq_req_valid = 1'b1;
                        eq_req_kind = request_is_preset ?
                                      EQ_TX_PRESET : EQ_TX_COEFF;
                        eq_req_preset = request_tuple[30:27];
                        eq_req_coeff = request_coeff;
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
            tx_coeff <= 18'd0;
            partner_preset <= 4'd4;
            reflected_control <= 8'd0; reflected_data <= 24'd0;
            last_accepted_valid <= 1'b0;
            last_accepted_preset_sel <= 1'b0;
            last_accepted_coeff <= 18'd0;
            last_accepted_tuple <= 32'd0;
            phase_done <= 1'b0; phase_failed <= 1'b0;
            phase1_exit_skip <= 1'b0;
            ec00_count <= 4'd0;
            phase_ts_count <= 4'd0; operation_state <= OP_IDLE;
        end else begin
            phase_valid_q <= phase_valid; phase_q <= phase;
            phase_done <= 1'b0; phase_failed <= 1'b0;
            if (!phase_valid) begin
                timeout_count <= 32'd0; consecutive_have <= 1'b0;
                phase1_exit_skip <= 1'b0; ec00_count <= 4'd0;
                phase_ts_count <= 4'd0; request_pending <= 1'b0;
                exit_pending <= 1'b0; proposal_pending <= 1'b0;
                transition_tuple_valid <= 1'b0;
                last_accepted_valid <= 1'b0;
                operation_state <= OP_IDLE;
            end else if (phase_entry) begin
                timeout_count <= 32'd0; consecutive_have <= 1'b0;
                phase1_exit_skip <= 1'b0; ec00_count <= 4'd0;
                phase_ts_count <= 4'd0; request_pending <= 1'b0;
                exit_pending <= 1'b0; proposal_pending <= 1'b0;
                last_accepted_valid <= 1'b0;
                operation_state <= OP_IDLE;
                if (phase == 2'd2) begin
                    // Capture the queried transmitter coefficients as the
                    // baseline for the Phase-3 reflection stream; successful
                    // applies overwrite it below.
                    tx_coeff <= initial_coeff_w;
                    if (!transition_tuple_valid) begin
                        // Entered without a partner advertisement (no EC=10
                        // pair ended Phase 1): seed the request stream with
                        // a maintain request for the partner's advertised
                        // preset.
                        reflected_control <=
                            {1'b1, partner_preset_w, 1'b0, 2'b10};
                        reflected_data <= encode_eq_data(
                            {1'b1, partner_preset_w, 1'b0, 2'b10},
                            initial_coeff_w, 1'b0);
                    end
                end else if (phase == 2'd3) begin
                    // Phase 3 (4.2.6.4.2.2.4): base stream carries our
                    // current transmitter settings with EC=11.  Seed
                    // last_processed with our own base tuple so the
                    // downstream's first request -- a maintain-reflection of
                    // this very stream -- is not re-applied.
                    reflected_control <= {1'b0, selected_preset, 1'b0, 2'b11};
                    reflected_data <= encode_eq_data(
                        {1'b0, selected_preset, 1'b0, 2'b11},
                        tx_coeff, 1'b0);
                    last_processed_tuple <=
                        {{1'b0, selected_preset, 1'b0, 2'b11},
                         encode_eq_data(
                             {1'b0, selected_preset, 1'b0, 2'b11},
                             tx_coeff, 1'b0)};
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
                    2'd0: begin
                        // Track the preset the partner's TX advertises
                        // (EC=00 from a downstream still in its Phase 0, or
                        // EC=01 from one already in Phase 1 -- the SVT VIP
                        // and Xilinx RP stream EC=01 while we are in Phase
                        // 0).  The first Phase-2 RX adaptation needs it as
                        // the rxeq_txpreset hint.
                        if (legal_ts1 && ((incoming_ec == 2'b00) ||
                                          (incoming_ec == 2'b01)))
                            partner_preset <= incoming_preset;
                        if (second_same_ts && (incoming_ec == 2'b01)) begin
                            transition_tuple_valid <= 1'b0;
                            phase_done <= 1'b1; operation_state <= OP_COMPLETE;
                        end
                    end
                    2'd1: begin
                        // The partner's EC=01 stream is the advertisement of
                        // ITS transmitter (preset field = its own TX preset
                        // per 4.2.6.4.2.1.1) -- track it, apply nothing.
                        if (legal_ts1 && (incoming_ec == 2'b01))
                            partner_preset <= incoming_preset;
                        if (second_same_ts && (incoming_ec == 2'b10)) begin
                            // The downstream moved to its Phase 2; its
                            // EC=10 stream advertises its transmitter
                            // settings (4.2.6.4.2.1.2).  Spec
                            // 4.2.6.4.2.2.3: our first Phase-2 request
                            // reflects these settings ("maintain"),
                            // so build that stream here.
                            transition_tuple <= incoming_tuple;
                            transition_tuple_valid <= 1'b1;
                            reflected_control <=
                                {incoming_tuple[31],
                                 incoming_tuple[30:27], 1'b0, 2'b10};
                            reflected_data <= encode_eq_data(
                                {incoming_tuple[31],
                                 incoming_tuple[30:27], 1'b0, 2'b10},
                                {incoming_tuple[5:0],
                                 incoming_tuple[13:8],
                                 incoming_tuple[21:16]}, 1'b0);
                            phase_done <= 1'b1;
                            operation_state <= OP_COMPLETE;
                        end
                        // 4.2.6.4.2.2.2 skip exit: the downstream ended
                        // equalization without running Phase 2/3 and went
                        // straight to Recovery.RcvrLock; its RcvrLock TS1
                        // stream carries EC=00.  The upstream leaves Phase 1
                        // after EIGHT consecutive EC=00 TS1s (a partner that
                        // merely still advertises EC=01/10 must not trip
                        // this).  EIEOS beats are neither TS1 nor TS2 and do
                        // not reset the count -- the spec's own post-EQ flow
                        // intersperses an EIEOS every 32 TS1/TS2s.
                        if (legal_ts1 && (incoming_ec == 2'b00)) begin
                            if (ec00_count == 4'd7) begin
                                transition_tuple_valid <= 1'b0;
                                phase_done <= 1'b1;
                                phase1_exit_skip <= 1'b1;
                                operation_state <= OP_COMPLETE;
                            end else
                                ec00_count <= ec00_count + 1'b1;
                        end else if (legal_ts1 || ts2_valid || ts_malformed)
                            ec00_count <= 4'd0;
                    end
                    2'd2: begin
                        if (eq_req_valid && eq_req_ready) begin
                            operation_state <= OP_WAIT_RX;
                            proposal_pending <= 1'b0;
                        end
                        if (eq_done && (operation_state == OP_WAIT_RX)) begin
                            if (eq_result == EQ_RESULT_SUCCESS) begin
                                // Our RX is satisfied with the partner's
                                // current transmission: conclude the phase
                                // with EC=11, which moves the downstream
                                // port from its Phase 2 into Phase 3
                                // (4.2.6.4.2.2.3).  EC=00 is reserved for
                                // the END of Phase 3 -- sending it here
                                // left the SVT VIP timing out in its own
                                // Phase 2 (32 us, 2026-09-01).
                                phase_done <= 1'b1;
                                operation_state <= OP_COMPLETE;
                            end else if (eq_result == EQ_RESULT_PROPOSAL) begin
                                if (last_accepted_valid &&
                                    (eq_rsp_preset_sel ==
                                     last_accepted_preset_sel) &&
                                    (eq_rsp_coeff == last_accepted_coeff)) begin
                                    // The PHY re-proposed the setting the
                                    // partner already accepted; no further
                                    // progress is possible -- conclude.
                                    phase_done <= 1'b1;
                                    operation_state <= OP_COMPLETE;
                                end else begin
                                    proposal_pending <= 1'b1;
                                    proposal_preset_sel <= eq_rsp_preset_sel;
                                    proposal_coeff <= eq_rsp_coeff;
                                    operation_state <= OP_WAIT_REFLECT;
                                end
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
                                // The accepted proposal is now the active
                                // request to the downstream transmitter.
                                // Keep streaming that request while the PHY
                                // performs the follow-up RX adaptation.  If
                                // reflected_control is left at the Phase-1
                                // transition tuple, the wire asks the peer
                                // to return to the old preset while
                                // phy_rxeq_txpreset names the new one.
                                reflected_control <= proposal_preset_sel ?
                                    {1'b1, proposal_coeff[3:0], 1'b0, 2'b10} :
                                    {1'b0, partner_preset_w, 1'b0, 2'b10};
                                reflected_data <= encode_eq_data(
                                    proposal_preset_sel ?
                                        {1'b1, proposal_coeff[3:0],
                                         1'b0, 2'b10} :
                                        {1'b0, partner_preset_w,
                                         1'b0, 2'b10},
                                    proposal_preset_sel ? initial_coeff_w :
                                                          proposal_coeff,
                                    1'b0);
                                last_accepted_valid <= 1'b1;
                                last_accepted_preset_sel <= proposal_preset_sel;
                                last_accepted_coeff <= proposal_coeff;
                                last_accepted_tuple <= incoming_tuple;
                                if (proposal_preset_sel)
                                    partner_preset <= incoming_preset;
                                proposal_pending <= 1'b0;
                                operation_state <= OP_IDLE;
                            end
                        end
                    end
                    default: begin
                        // Phase 3 (4.2.6.4.2.2.4): the downstream's EC=11
                        // requests are applied to OUR transmitter and the
                        // outcome is reflected until it concludes with
                        // EC=00.
                        if (request_pending && !request_legal) begin
                            // Illegal/unsupported request: reflect the
                            // requested values with Reject=1, change
                            // nothing (4.2.6.4.2.2.4 + 4.2.3.1).
                            reflected_control <= request_tuple[31:24];
                            reflected_data <= encode_eq_data(
                                request_tuple[31:24], request_coeff, 1'b1);
                            request_pending <= 1'b0;
                            operation_state <= OP_WAIT_NEXT;
                        end else if (eq_req_valid && eq_req_ready) begin
                            request_pending <= 1'b0;
                            operation_state <= OP_WAIT_TX;
                        end
                        if (eq_done && (operation_state == OP_WAIT_TX)) begin
                            if (eq_result == EQ_RESULT_SUCCESS) begin
                                // Reflect the applied settings: the preset
                                // field carries the requested preset (for
                                // a preset request; unchanged for a
                                // coefficient request) and the coefficient
                                // fields carry the transmitter settings.
                                if (request_is_preset) begin
                                    selected_preset <= request_tuple[30:27];
                                    tx_coeff <=
                                        preset_coeff(request_tuple[30:27]);
                                    reflected_control <=
                                        {1'b0, request_tuple[30:27],
                                         1'b0, 2'b11};
                                    reflected_data <= encode_eq_data(
                                        {1'b0, request_tuple[30:27],
                                         1'b0, 2'b11},
                                        preset_coeff(request_tuple[30:27]),
                                        1'b0);
                                end else begin
                                    tx_coeff <= eq_rsp_coeff;
                                    reflected_control <=
                                        {1'b0, selected_preset,
                                         1'b0, 2'b11};
                                    reflected_data <= encode_eq_data(
                                        {1'b0, selected_preset,
                                         1'b0, 2'b11},
                                        eq_rsp_coeff, 1'b0);
                                end
                                operation_state <= OP_WAIT_NEXT;
                            end else begin
                                // The PHY refused the apply: reflect the
                                // request with Reject=1.
                                reflected_control <= request_tuple[31:24];
                                reflected_data <= encode_eq_data(
                                    request_tuple[31:24], request_coeff,
                                    1'b1);
                                operation_state <= OP_WAIT_NEXT;
                            end
                        end
                        if (second_same_ts && (incoming_ec == 2'b00)) begin
                            // EC=00 pair ends Phase 3 and the whole
                            // equalization procedure.
                            if ((operation_state == OP_WAIT_TX) ||
                                (eq_req_valid && eq_req_ready))
                                exit_pending <= 1'b1;
                            else begin
                                transition_tuple_valid <= 1'b0;
                                phase_done <= 1'b1;
                                operation_state <= OP_COMPLETE;
                            end
                        end else if (second_same_ts && !request_pending &&
                                     ((operation_state == OP_WAIT_NEXT) ||
                                      (operation_state == OP_IDLE)) &&
                                     (incoming_ec == 2'b11) &&
                                     (incoming_tuple !=
                                      last_processed_tuple)) begin
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
