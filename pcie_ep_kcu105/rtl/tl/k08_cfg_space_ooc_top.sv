`timescale 1ns/1ps
`default_nettype none

// K08仅用于KU040 OOC签核的包装层。
// 生产集成的core_rst_n已经由K01同步释放；OOC边界补建同等四级同步链，
// 使复位拓扑、CDC和250 MHz时序能够独立检查。
module k08_cfg_space_ooc_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        hot_reset,
    input  wire        link_up,
    input  wire        link_training,
    input  wire        dll_active,
    input  wire [1:0]  link_speed,
    input  wire [2:0]  link_width,

    input  wire        cfg_req_valid,
    output wire        cfg_req_ready,
    input  wire        cfg_req_write,
    input  wire [9:0]  cfg_req_dw_addr,
    input  wire [3:0]  cfg_req_be,
    input  wire [31:0] cfg_req_wdata,
    input  wire [15:0] cfg_req_requester_id,
    input  wire [7:0]  cfg_req_tag,
    input  wire [15:0] cfg_req_target_bdf,

    output wire        cfg_rsp_valid,
    input  wire        cfg_rsp_ready,
    output wire [2:0]  cfg_rsp_status,
    output wire [31:0] cfg_rsp_rdata,
    output wire [15:0] cfg_rsp_completer_id,

    output wire [15:0] captured_bdf,
    output wire        bdf_valid,
    output wire [15:0] local_completer_id,
    output wire [31:0] bar0_base,
    output wire        bar0_probe_active,
    output wire        memory_space_enable,
    output wire        bus_master_enable,
    output wire [2:0]  max_payload_size,
    output wire [2:0]  max_read_request_size,
    output wire        rcb_128b,
    output wire        link_disable,
    output wire        retrain_link_pulse,
    output wire [1:0]  target_link_speed
);
    wire cfg_rst_n;

    pcie_reset_sync #(.STAGES(4)) u_ooc_reset_sync (
        .clk             (clk),
        .async_release_n (rst_n),
        .sync_reset_n    (cfg_rst_n)
    );

    pcie_cfg_space u_dut (
        .rst_n (cfg_rst_n),
        .*
    );
endmodule

`default_nettype wire
