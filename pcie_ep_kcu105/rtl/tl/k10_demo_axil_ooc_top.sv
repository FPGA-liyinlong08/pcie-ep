`timescale 1ns/1ps
`default_nettype none

module k10_demo_axil_ooc_top (
    input wire clk, input wire rst_n,
    input wire [31:0] s_axil_awaddr, input wire s_axil_awvalid,
    output wire s_axil_awready,
    input wire [31:0] s_axil_wdata, input wire [3:0] s_axil_wstrb,
    input wire s_axil_wvalid, output wire s_axil_wready,
    output wire [1:0] s_axil_bresp, output wire s_axil_bvalid,
    input wire s_axil_bready,
    input wire [31:0] s_axil_araddr, input wire s_axil_arvalid,
    output wire s_axil_arready,
    output wire [31:0] s_axil_rdata, output wire [1:0] s_axil_rresp,
    output wire s_axil_rvalid, input wire s_axil_rready,
    input wire link_up, input wire [1:0] link_speed,
    input wire [5:0] ltssm_state, input wire dll_active,
    input wire [3:0] dll_state,
    input wire [31:0] rx_bad_symbol_count,
    input wire [31:0] ltssm_retrain_count,
    input wire [31:0] dll_lcrc_error_count,
    input wire [31:0] dll_nak_count,
    input wire [31:0] dll_replay_count,
    input wire [31:0] dll_replay_timeout_count,
    input wire [31:0] tl_malformed_count,
    input wire [31:0] tl_unsupported_count,
    input wire [31:0] bar_ur_count,
    input wire [31:0] bar_ca_count,
    input wire [31:0] bar_axi_error_count,
    input wire [31:0] bar_payload_error_count
);
    wire demo_rst_n;
    pcie_reset_sync #(.STAGES(4)) u_ooc_reset_sync (
        .clk(clk), .async_release_n(rst_n), .sync_reset_n(demo_rst_n)
    );
    demo_axil_slave u_dut (.rst_n(demo_rst_n), .*);
endmodule

`default_nettype wire
