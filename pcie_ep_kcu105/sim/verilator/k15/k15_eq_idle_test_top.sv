`timescale 1ns/1ps
`default_nettype none

module k15_eq_idle_test_top (
    input  wire clk,
    input  wire rst_n,
    input  wire phase_valid,
    input  wire [1:0] phase,
    input  wire ts1_valid,
    input  wire ts2_valid,
    input  wire [7:0] ts_eq_control,
    input  wire [23:0] ts_eq_data,
    input  wire tx_ts_complete,
    input  wire eq_req_ready,
    input  wire eq_busy,
    input  wire eq_done,
    input  wire [2:0] eq_result,
    input  wire eq_rsp_preset_sel,
    input  wire [17:0] eq_rsp_coeff,
    input  wire initial_preset_valid,
    input  wire [3:0] initial_preset,
    input  wire initial_coeff_valid,
    input  wire [17:0] initial_coeff,
    input  wire idle_enable,
    input  wire training_enable,
    input  wire [1:0] training_mode,
    output wire eq_req_valid,
    output wire [2:0] eq_req_kind,
    output wire [3:0] eq_req_preset,
    output wire [17:0] eq_req_coeff,
    output wire [7:0] tx_eq_control,
    output wire [23:0] tx_eq_data,
    output wire phase_done,
    output wire phase_failed,
    output wire phase1_exit_skip,
    output wire [3:0] phase_ts_count,
    output wire [2:0] operation_state,
    output wire idle_valid,
    output wire idle_malformed,
    output wire idle_block_complete,
    output wire [31:0] idle_data,
    output wire idle_data_valid,
    output wire idle_start_block,
    output wire [1:0] idle_sync_header,
    output wire [31:0] training_data,
    output wire training_valid,
    output wire training_start_block,
    output wire [1:0] training_sync_header,
    output wire training_os_complete
);
    wire [22:0] training_lfsr_after_word;

    pcie_gen3_equalization_ctrl #(
        .PHASE_TIMEOUT_CYCLES(128), .PORT_ROLE(0)
    ) u_eq (
        .clk(clk), .rst_n(rst_n), .phase_valid(phase_valid), .phase(phase),
        .ts1_valid(ts1_valid), .ts2_valid(ts2_valid),
        .ts_malformed(1'b0),
        .ts_eq_control(ts_eq_control), .ts_eq_data(ts_eq_data),
        .tx_ts_complete(tx_ts_complete),
        .initial_preset_valid(initial_preset_valid),
        .initial_preset(initial_preset),
        .initial_coeff_valid(initial_coeff_valid),
        .initial_coeff(initial_coeff),
        .local_fs(6'd40), .local_lf(6'd12),
        .eq_req_valid(eq_req_valid), .eq_req_kind(eq_req_kind),
        .eq_req_preset(eq_req_preset), .eq_req_coeff(eq_req_coeff),
        .eq_req_ready(eq_req_ready), .eq_busy(eq_busy),
        .eq_done(eq_done), .eq_result(eq_result),
        .eq_rsp_preset_sel(eq_rsp_preset_sel),
        .eq_rsp_coeff(eq_rsp_coeff), .tx_eq_control(tx_eq_control),
        .tx_eq_data(tx_eq_data), .phase_done(phase_done),
        .phase_failed(phase_failed), .phase1_exit_skip(phase1_exit_skip),
        .phase_ts_count(phase_ts_count),
        .operation_state(operation_state)
    );

    pcie_gen3_idle_tx u_idle_tx (
        .clk(clk), .rst_n(rst_n), .enable(idle_enable),
        .lfsr_state_in(training_lfsr_after_word),
        .out_data(idle_data), .out_valid(idle_data_valid),
        .start_block(idle_start_block), .sync_header(idle_sync_header),
        .idle_block_complete(idle_block_complete)
    );

    pcie_gen3_os_rx u_idle_rx (
        .clk(clk), .rst_n(rst_n), .enable(training_enable || idle_enable),
        .in_valid(training_enable ? training_valid : idle_data_valid),
        .start_block(training_enable ? training_start_block : idle_start_block),
        .sync_header(training_enable ? training_sync_header : idle_sync_header),
        .in_data(training_enable ? training_data : idle_data),
        .ts1_valid(), .ts2_valid(), .malformed(idle_malformed),
        .idle_valid(idle_valid), .link_number(), .link_is_pad(),
        .lane_number(), .lane_is_pad(), .n_fts(), .rate_id(),
        .training_control(), .eq_control(), .eq_data(), .eieos_start()
    );

    pcie_gen3_os_tx u_training_tx (
        .clk(clk), .rst_n(rst_n), .enable(training_enable),
        .mode(training_mode),
        .link_number(8'h9f), .link_is_pad(1'b0),
        .lane_number(8'd0), .lane_is_pad(1'b0), .n_fts(8'hff),
        .rate_id(8'h0e), .training_control(8'h00),
        .eq_control(8'h20), .eq_data(24'h802800),
        .eieos_suppress(1'b0),
        .out_data(training_data), .out_valid(training_valid),
        .start_block(training_start_block),
        .sync_header(training_sync_header),
        .os_complete(training_os_complete), .word_index_debug(),
        .eieos_active(), .eieos_start(),
        .lfsr_state_after_word(training_lfsr_after_word)
    );
endmodule

`default_nettype wire
