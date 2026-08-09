`timescale 1ns/1ps
`default_nettype none

module k10_bar_demo_top (
    input wire clk, input wire rst_n,
    input wire mem_req_valid, output wire mem_req_ready,
    input wire mem_req_write, input wire [63:0] mem_req_address,
    input wire [10:0] mem_req_length_dw,
    input wire [3:0] mem_req_first_be, input wire [3:0] mem_req_last_be,
    input wire [15:0] mem_req_requester_id, input wire [7:0] mem_req_tag,
    input wire mem_w_valid, output wire mem_w_ready,
    input wire [127:0] mem_w_data, input wire [15:0] mem_w_keep,
    input wire mem_w_last,
    output wire cpl_req_valid, input wire cpl_req_ready,
    output wire [2:0] cpl_req_status, output wire [12:0] cpl_req_byte_count,
    output wire [6:0] cpl_req_lower_address,
    output wire [5:0] cpl_req_length_dw,
    output wire cpl_data_valid, input wire cpl_data_ready,
    output wire [127:0] cpl_data, output wire [15:0] cpl_data_keep,
    output wire cpl_data_last,
    input wire link_up, input wire [1:0] link_speed,
    input wire [5:0] ltssm_state, input wire dll_active,
    input wire [3:0] dll_state,
    output wire bar_busy,
    output wire diagnostics_nonzero
);
    wire [31:0] awaddr, wdata, araddr, rdata;
    wire [3:0] wstrb;
    wire awvalid, awready, wvalid, wready, bvalid, bready;
    wire [1:0] bresp;
    wire arvalid, arready, rvalid, rready;
    wire [1:0] rresp;
    wire ur_pulse, ca_pulse, posted_drop_pulse, axi_error_pulse;
    wire payload_error_pulse;
    wire [31:0] mem_request_count, mem_read_count, mem_write_count;
    wire [31:0] axi_read_count, axi_write_count, sc_completion_count;
    wire [31:0] ur_completion_count, ca_completion_count, posted_drop_count;
    wire [31:0] poisoned_write_count, axi_read_error_count;
    wire [31:0] axi_write_error_count, payload_protocol_error_count;
    wire cpl_req_has_data, cpl_req_poisoned, cpl_req_bcm;
    wire [15:0] cpl_req_completer_id, cpl_req_requester_id;
    wire [7:0] cpl_req_tag;
    wire [2:0] cpl_req_tc, cpl_req_attr;

    assign diagnostics_nonzero = |{
        ur_pulse, ca_pulse, posted_drop_pulse, axi_error_pulse,
        payload_error_pulse, mem_request_count, mem_read_count,
        mem_write_count, axi_read_count, axi_write_count,
        sc_completion_count, posted_drop_count, poisoned_write_count,
        cpl_req_has_data, cpl_req_poisoned, cpl_req_bcm,
        cpl_req_completer_id, cpl_req_requester_id, cpl_req_tag,
        cpl_req_tc, cpl_req_attr
    };

    pcie_bar_axil_master u_bar (
        .clk(clk), .rst_n(rst_n), .hot_reset(1'b0),
        .bar0_base(32'hc000_0000), .bar0_probe_active(1'b0),
        .memory_space_enable(1'b1), .local_completer_id(16'h0100),
        .mem_req_valid(mem_req_valid), .mem_req_ready(mem_req_ready),
        .mem_req_write(mem_req_write), .mem_req_64bit(1'b0),
        .mem_req_poisoned(1'b0), .mem_req_address(mem_req_address),
        .mem_req_length_dw(mem_req_length_dw),
        .mem_req_first_be(mem_req_first_be), .mem_req_last_be(mem_req_last_be),
        .mem_req_requester_id(mem_req_requester_id), .mem_req_tag(mem_req_tag),
        .mem_req_tc(3'd0), .mem_req_attr(3'd0),
        .mem_w_valid(mem_w_valid), .mem_w_ready(mem_w_ready),
        .mem_w_data(mem_w_data), .mem_w_keep(mem_w_keep),
        .mem_w_last(mem_w_last),
        .cpl_req_valid(cpl_req_valid), .cpl_req_ready(cpl_req_ready),
        .cpl_req_has_data(cpl_req_has_data),
        .cpl_req_poisoned(cpl_req_poisoned), .cpl_req_status(cpl_req_status),
        .cpl_req_bcm(cpl_req_bcm), .cpl_req_byte_count(cpl_req_byte_count),
        .cpl_req_completer_id(cpl_req_completer_id),
        .cpl_req_requester_id(cpl_req_requester_id), .cpl_req_tag(cpl_req_tag),
        .cpl_req_lower_address(cpl_req_lower_address),
        .cpl_req_length_dw(cpl_req_length_dw), .cpl_req_tc(cpl_req_tc),
        .cpl_req_attr(cpl_req_attr),
        .cpl_data_valid(cpl_data_valid), .cpl_data_ready(cpl_data_ready),
        .cpl_data(cpl_data), .cpl_data_keep(cpl_data_keep),
        .cpl_data_last(cpl_data_last),
        .m_axil_awaddr(awaddr), .m_axil_awvalid(awvalid),
        .m_axil_awready(awready), .m_axil_wdata(wdata),
        .m_axil_wstrb(wstrb), .m_axil_wvalid(wvalid), .m_axil_wready(wready),
        .m_axil_bresp(bresp), .m_axil_bvalid(bvalid), .m_axil_bready(bready),
        .m_axil_araddr(araddr), .m_axil_arvalid(arvalid),
        .m_axil_arready(arready), .m_axil_rdata(rdata),
        .m_axil_rresp(rresp), .m_axil_rvalid(rvalid), .m_axil_rready(rready),
        .busy(bar_busy), .ur_pulse(ur_pulse), .ca_pulse(ca_pulse),
        .posted_drop_pulse(posted_drop_pulse),
        .axi_error_pulse(axi_error_pulse),
        .payload_error_pulse(payload_error_pulse),
        .mem_request_count(mem_request_count), .mem_read_count(mem_read_count),
        .mem_write_count(mem_write_count), .axi_read_count(axi_read_count),
        .axi_write_count(axi_write_count),
        .sc_completion_count(sc_completion_count),
        .ur_completion_count(ur_completion_count),
        .ca_completion_count(ca_completion_count),
        .posted_drop_count(posted_drop_count),
        .poisoned_write_count(poisoned_write_count),
        .axi_read_error_count(axi_read_error_count),
        .axi_write_error_count(axi_write_error_count),
        .payload_protocol_error_count(payload_protocol_error_count)
    );

    demo_axil_slave u_demo (
        .clk(clk), .rst_n(rst_n),
        .s_axil_awaddr(awaddr), .s_axil_awvalid(awvalid),
        .s_axil_awready(awready), .s_axil_wdata(wdata),
        .s_axil_wstrb(wstrb), .s_axil_wvalid(wvalid),
        .s_axil_wready(wready), .s_axil_bresp(bresp),
        .s_axil_bvalid(bvalid), .s_axil_bready(bready),
        .s_axil_araddr(araddr), .s_axil_arvalid(arvalid),
        .s_axil_arready(arready), .s_axil_rdata(rdata),
        .s_axil_rresp(rresp), .s_axil_rvalid(rvalid), .s_axil_rready(rready),
        .link_up(link_up), .link_speed(link_speed), .ltssm_state(ltssm_state),
        .dll_active(dll_active), .dll_state(dll_state),
        .rx_bad_symbol_count(32'd0), .ltssm_retrain_count(32'd0),
        .dll_lcrc_error_count(32'd0), .dll_nak_count(32'd0),
        .dll_replay_count(32'd0), .dll_replay_timeout_count(32'd0),
        .tl_malformed_count(32'd0), .tl_unsupported_count(32'd0),
        .bar_ur_count(ur_completion_count), .bar_ca_count(ca_completion_count),
        .bar_axi_error_count(axi_read_error_count + axi_write_error_count),
        .bar_payload_error_count(payload_protocol_error_count)
    );
endmodule

`default_nettype wire
