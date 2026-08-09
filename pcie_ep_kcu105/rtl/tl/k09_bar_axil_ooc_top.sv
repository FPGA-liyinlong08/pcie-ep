`timescale 1ns/1ps
`default_nettype none

// K09仅用于KU040 250 MHz OOC签核的包装层。
// 生产集成的core_rst_n已经由K01同步释放；OOC边界补建同等四级同步链，
// 使异步置位/同步释放的真实复位拓扑能够参与CDC和布局布线检查。
module k09_bar_axil_ooc_top (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         hot_reset,

    input  wire [31:0]  bar0_base,
    input  wire         bar0_probe_active,
    input  wire         memory_space_enable,
    input  wire [15:0]  local_completer_id,

    input  wire         mem_req_valid,
    output wire         mem_req_ready,
    input  wire         mem_req_write,
    input  wire         mem_req_64bit,
    input  wire         mem_req_poisoned,
    input  wire [63:0]  mem_req_address,
    input  wire [10:0]  mem_req_length_dw,
    input  wire [3:0]   mem_req_first_be,
    input  wire [3:0]   mem_req_last_be,
    input  wire [15:0]  mem_req_requester_id,
    input  wire [7:0]   mem_req_tag,
    input  wire [2:0]   mem_req_tc,
    input  wire [2:0]   mem_req_attr,

    input  wire         mem_w_valid,
    output wire         mem_w_ready,
    input  wire [127:0] mem_w_data,
    input  wire [15:0]  mem_w_keep,
    input  wire         mem_w_last,

    output wire         cpl_req_valid,
    input  wire         cpl_req_ready,
    output wire         cpl_req_has_data,
    output wire         cpl_req_poisoned,
    output wire [2:0]   cpl_req_status,
    output wire         cpl_req_bcm,
    output wire [12:0]  cpl_req_byte_count,
    output wire [15:0]  cpl_req_completer_id,
    output wire [15:0]  cpl_req_requester_id,
    output wire [7:0]   cpl_req_tag,
    output wire [6:0]   cpl_req_lower_address,
    output wire [5:0]   cpl_req_length_dw,
    output wire [2:0]   cpl_req_tc,
    output wire [2:0]   cpl_req_attr,

    output wire         cpl_data_valid,
    input  wire         cpl_data_ready,
    output wire [127:0] cpl_data,
    output wire [15:0]  cpl_data_keep,
    output wire         cpl_data_last,

    output wire [31:0]  m_axil_awaddr,
    output wire         m_axil_awvalid,
    input  wire         m_axil_awready,
    output wire [31:0]  m_axil_wdata,
    output wire [3:0]   m_axil_wstrb,
    output wire         m_axil_wvalid,
    input  wire         m_axil_wready,
    input  wire [1:0]   m_axil_bresp,
    input  wire         m_axil_bvalid,
    output wire         m_axil_bready,

    output wire [31:0]  m_axil_araddr,
    output wire         m_axil_arvalid,
    input  wire         m_axil_arready,
    input  wire [31:0]  m_axil_rdata,
    input  wire [1:0]   m_axil_rresp,
    input  wire         m_axil_rvalid,
    output wire         m_axil_rready,

    output wire         busy,
    output wire         ur_pulse,
    output wire         ca_pulse,
    output wire         posted_drop_pulse,
    output wire         axi_error_pulse,
    output wire         payload_error_pulse,

    output wire [31:0]  mem_request_count,
    output wire [31:0]  mem_read_count,
    output wire [31:0]  mem_write_count,
    output wire [31:0]  axi_read_count,
    output wire [31:0]  axi_write_count,
    output wire [31:0]  sc_completion_count,
    output wire [31:0]  ur_completion_count,
    output wire [31:0]  ca_completion_count,
    output wire [31:0]  posted_drop_count,
    output wire [31:0]  poisoned_write_count,
    output wire [31:0]  axi_read_error_count,
    output wire [31:0]  axi_write_error_count,
    output wire [31:0]  payload_protocol_error_count
);
    wire bar_rst_n;

    pcie_reset_sync #(.STAGES(4)) u_ooc_reset_sync (
        .clk             (clk),
        .async_release_n (rst_n),
        .sync_reset_n    (bar_rst_n)
    );

    pcie_bar_axil_master u_dut (
        .rst_n (bar_rst_n),
        .*
    );
endmodule

`default_nettype wire
