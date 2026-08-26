`timescale 1ns/1ps
`default_nettype none

// K11-B2 KCU105板级封装。完整状态保留在生产顶层内部，板级仅导出已冻结管脚。
module kcu105_pcie_ep_gen1_board_top #(
    parameter integer K11B2_ILA_DEBUG = 0,
    parameter integer K14_RATE_DEBUG = 0,
    parameter integer PHASE_E1_BOARD_DEBUG = 0,
    parameter integer PHASE_E1_FUNCTION_ONLY = 0,
    parameter integer PHASE_E2_RCVRLOCK_DEBUG = 0,
    parameter integer G9_WAIT_REMOTE_DETECT = 1,
    parameter integer G9_WAIT_REMOTE_DETECT_CYCLES = 6_250_000,
    parameter integer DETECT_QUIET_CYCLES = 1_500_000,
    parameter integer GEN3_RATE_CHANGE_ENABLE = 0,
    parameter integer GEN3_SPEED_TIMEOUT_CYCLES = 1_000_000,
    parameter integer GEN3_AUTO_RETRAIN_CYCLES = 0,
    parameter integer PHASE_E1_TIMING_DEBUG = 0
) (
    input  wire       pcie_refclk_p,
    input  wire       pcie_refclk_n,
    input  wire       pcie_perst_n,
    input  wire       pcie_rxp,
    input  wire       pcie_rxn,
    output wire       pcie_txp,
    output wire       pcie_txn,
    output wire [7:0] led
);
    wire        link_up;
    wire        dll_active;
    wire [5:0]  ltssm_state;
    wire [1:0]  dll_fc_state;
    wire [1:0]  negotiated_speed;
    wire [2:0]  negotiated_width;
    wire [15:0] captured_bdf;
    wire        bdf_valid;
    wire [31:0] bar0_base;
    wire        memory_space_enable;
    wire [7:0]  cdc_errors;

    kcu105_pcie_ep_gen1_top #(
        .K11B2_ILA_DEBUG(K11B2_ILA_DEBUG),
        .K14_RATE_DEBUG(K14_RATE_DEBUG),
        .PHASE_E1_BOARD_DEBUG(PHASE_E1_BOARD_DEBUG),
        .PHASE_E1_FUNCTION_ONLY(PHASE_E1_FUNCTION_ONLY),
        .PHASE_E2_RCVRLOCK_DEBUG(PHASE_E2_RCVRLOCK_DEBUG),
        .G9_WAIT_REMOTE_DETECT(G9_WAIT_REMOTE_DETECT),
        .G9_WAIT_REMOTE_DETECT_CYCLES(G9_WAIT_REMOTE_DETECT_CYCLES),
        .DETECT_QUIET_CYCLES(DETECT_QUIET_CYCLES),
        .GEN3_RATE_CHANGE_ENABLE(GEN3_RATE_CHANGE_ENABLE),
        .GEN3_SPEED_TIMEOUT_CYCLES(GEN3_SPEED_TIMEOUT_CYCLES),
        .GEN3_AUTO_RETRAIN_CYCLES(GEN3_AUTO_RETRAIN_CYCLES),
        .PHASE_E1_TIMING_DEBUG(PHASE_E1_TIMING_DEBUG)
    ) u_endpoint (
        .pcie_refclk_p(pcie_refclk_p),
        .pcie_refclk_n(pcie_refclk_n),
        .pcie_perst_n(pcie_perst_n),
        .pcie_rxp(pcie_rxp),
        .pcie_rxn(pcie_rxn),
        .pcie_txp(pcie_txp),
        .pcie_txn(pcie_txn),
        .led(led),
        .link_up(link_up),
        .dll_active(dll_active),
        .ltssm_state(ltssm_state),
        .dll_fc_state(dll_fc_state),
        .negotiated_speed(negotiated_speed),
        .negotiated_width(negotiated_width),
        .captured_bdf(captured_bdf),
        .bdf_valid(bdf_valid),
        .bar0_base(bar0_base),
        .memory_space_enable(memory_space_enable),
        .cdc_errors(cdc_errors)
    );

    wire _unused = &{1'b0, link_up, dll_active, ltssm_state, dll_fc_state,
        negotiated_speed, negotiated_width, captured_bdf, bdf_valid,
        bar0_base, memory_space_enable, cdc_errors};
endmodule

`default_nettype wire
