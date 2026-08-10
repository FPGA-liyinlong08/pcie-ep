`timescale 1ns/1ps
`default_nettype none

// K07 + K08 + K09 的独立 TLP 级集成顶层。
//
// 128-bit Packet Stream 替代尚未集成的 DLL；配置和 Memory TLP 均经过
// 生产 pcie_tlp_codec。配置请求进入生产 pcie_cfg_space，Memory 请求进入
// 生产 pcie_bar_axil_master，读 Completion 再由生产 pcie_tlp_codec 编码。
module k09_tlp_test_top #(
    parameter integer K11B2_ILA_DEBUG = 0
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         hot_reset,

    input  wire         link_up,
    input  wire         link_training,
    input  wire         dll_active,
    input  wire [1:0]   link_speed,
    input  wire [2:0]   link_width,

    input  wire         rx_tlp_valid,
    output wire         rx_tlp_ready,
    input  wire [127:0] rx_tlp_data,
    input  wire [15:0]  rx_tlp_keep,
    input  wire         rx_tlp_sop,
    input  wire         rx_tlp_eop,
    input  wire [3:0]   rx_tlp_error,

    output wire         tx_tlp_valid,
    input  wire         tx_tlp_ready,
    output wire [127:0] tx_tlp_data,
    output wire [15:0]  tx_tlp_keep,
    output wire         tx_tlp_sop,
    output wire         tx_tlp_eop,
    output wire [3:0]   tx_tlp_error,
    output wire [1:0]   tx_tlp_type,
    output wire [11:0]  tx_tlp_data_credits,

    output wire         rx_release_valid,
    input  wire         rx_release_ready,
    output wire [1:0]   rx_release_type,
    output wire [11:0]  rx_release_data_credits,

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

    output wire [15:0]  captured_bdf,
    output wire         bdf_valid,
    output wire [15:0]  local_completer_id,
    output wire [31:0]  bar0_base,
    output wire         bar0_probe_active,
    output wire         memory_space_enable,
    output wire         bar_busy,
    output wire         bar_ur_pulse,
    output wire         bar_ca_pulse,

    output wire [31:0]  codec_cfg_request_count,
    output wire [31:0]  codec_mem_request_count,
    output wire [31:0]  codec_tx_completion_count,
    output wire [31:0]  codec_ur_completion_count,
    output wire [31:0]  codec_malformed_count,
    output wire [31:0]  codec_unsupported_count,
    output wire [31:0]  codec_tx_protocol_error_count,
    output wire [31:0]  bar_mem_request_count,
    output wire [31:0]  bar_mem_read_count,
    output wire [31:0]  bar_mem_write_count,
    output wire [31:0]  bar_axi_read_count,
    output wire [31:0]  bar_axi_write_count,
    output wire [31:0]  bar_sc_completion_count,
    output wire [31:0]  bar_ur_completion_count,
    output wire [31:0]  bar_ca_completion_count
);
    wire        cfg_req_valid;
    wire        cfg_req_ready;
    wire        cfg_req_write;
    wire [9:0]  cfg_req_dw_addr;
    wire [3:0]  cfg_req_be;
    wire [31:0] cfg_req_wdata;
    wire [15:0] cfg_req_requester_id;
    wire [7:0]  cfg_req_tag;
    wire [15:0] cfg_req_target_bdf;
    wire        cfg_rsp_valid;
    wire        cfg_rsp_ready;
    wire [2:0]  cfg_rsp_status;
    wire [31:0] cfg_rsp_rdata;
    wire [15:0] cfg_rsp_completer_id;

    generate if (K11B2_ILA_DEBUG != 0) begin : g_ila_debug
        // K11-B3三级诊断：在固定192-bit宽度内保留TX Completion首拍原文，
        // 同时采集codec分类和配置请求/响应握手。
        (* mark_debug = "true", keep = "true" *)
        wire [191:0] dbg_core_detail = {
            8'd0,
            codec_malformed_count[7:0], codec_unsupported_count[7:0],
            codec_cfg_request_count[7:0],
            cfg_rsp_valid, cfg_rsp_ready, cfg_rsp_status,
            cfg_req_valid, cfg_req_ready, cfg_req_write,
            tx_tlp_valid, tx_tlp_ready, tx_tlp_sop, tx_tlp_eop,
            tx_tlp_error, tx_tlp_keep, tx_tlp_data
        };
    end endgenerate

    wire         mem_req_valid;
    wire         mem_req_ready;
    wire         mem_req_write;
    wire         mem_req_64bit;
    wire         mem_req_poisoned;
    wire [63:0]  mem_req_address;
    wire [10:0]  mem_req_length_dw;
    wire [3:0]   mem_req_first_be;
    wire [3:0]   mem_req_last_be;
    wire [15:0]  mem_req_requester_id;
    wire [7:0]   mem_req_tag;
    wire [2:0]   mem_req_tc;
    wire [2:0]   mem_req_attr;
    wire         mem_w_valid;
    wire         mem_w_ready;
    wire [127:0] mem_w_data;
    wire [15:0]  mem_w_keep;
    wire         mem_w_last;

    wire         cpl_req_valid;
    wire         cpl_req_ready;
    wire         cpl_req_has_data;
    wire         cpl_req_poisoned;
    wire [2:0]   cpl_req_status;
    wire         cpl_req_bcm;
    wire [12:0]  cpl_req_byte_count;
    wire [15:0]  cpl_req_completer_id;
    wire [15:0]  cpl_req_requester_id;
    wire [7:0]   cpl_req_tag;
    wire [6:0]   cpl_req_lower_address;
    wire [5:0]   cpl_req_length_dw;
    wire [2:0]   cpl_req_tc;
    wire [2:0]   cpl_req_attr;
    wire         cpl_data_valid;
    wire         cpl_data_ready;
    wire [127:0] cpl_data;
    wire [15:0]  cpl_data_keep;
    wire         cpl_data_last;

    /* verilator lint_off UNUSEDSIGNAL */
    wire         rx_cpl_valid_unused;
    wire         rx_cpl_has_data_unused;
    wire         rx_cpl_poisoned_unused;
    wire [2:0]   rx_cpl_status_unused;
    wire         rx_cpl_bcm_unused;
    wire [12:0]  rx_cpl_byte_count_unused;
    wire [15:0]  rx_cpl_completer_id_unused;
    wire [15:0]  rx_cpl_requester_id_unused;
    wire [7:0]   rx_cpl_tag_unused;
    wire [6:0]   rx_cpl_lower_address_unused;
    wire [5:0]   rx_cpl_length_dw_unused;
    wire [2:0]   rx_cpl_tc_unused;
    wire [2:0]   rx_cpl_attr_unused;
    wire         rx_cpl_data_valid_unused;
    wire [127:0] rx_cpl_data_unused;
    wire [15:0]  rx_cpl_data_keep_unused;
    wire         rx_cpl_data_last_unused;

    wire malformed_pulse_unused;
    wire unsupported_pulse_unused;
    wire poisoned_pulse_unused;
    wire unexpected_cpl_pulse_unused;
    wire [7:0] error_fmt_type_unused;
    wire [15:0] error_requester_id_unused;
    wire [7:0] error_tag_unused;
    wire [31:0] rx_packet_count_unused;
    wire [31:0] rx_completion_count_unused;
    wire [31:0] poisoned_count_unused;
    wire [31:0] unexpected_completion_count_unused;

    pcie_tlp_codec u_tlp_codec (
        .clk                         (clk),
        .rst_n                       (rst_n),
        .rx_tlp_valid                (rx_tlp_valid),
        .rx_tlp_ready                (rx_tlp_ready),
        .rx_tlp_data                 (rx_tlp_data),
        .rx_tlp_keep                 (rx_tlp_keep),
        .rx_tlp_sop                  (rx_tlp_sop),
        .rx_tlp_eop                  (rx_tlp_eop),
        .rx_tlp_error                (rx_tlp_error),
        .tx_tlp_valid                (tx_tlp_valid),
        .tx_tlp_ready                (tx_tlp_ready),
        .tx_tlp_data                 (tx_tlp_data),
        .tx_tlp_keep                 (tx_tlp_keep),
        .tx_tlp_sop                  (tx_tlp_sop),
        .tx_tlp_eop                  (tx_tlp_eop),
        .tx_tlp_error                (tx_tlp_error),
        .tx_tlp_type                 (tx_tlp_type),
        .tx_tlp_data_credits         (tx_tlp_data_credits),
        .rx_release_valid            (rx_release_valid),
        .rx_release_ready            (rx_release_ready),
        .rx_release_type             (rx_release_type),
        .rx_release_data_credits     (rx_release_data_credits),
        .local_completer_id          (local_completer_id),

        .cfg_req_valid               (cfg_req_valid),
        .cfg_req_ready               (cfg_req_ready),
        .cfg_req_write               (cfg_req_write),
        .cfg_req_dw_addr             (cfg_req_dw_addr),
        .cfg_req_be                  (cfg_req_be),
        .cfg_req_wdata               (cfg_req_wdata),
        .cfg_req_requester_id        (cfg_req_requester_id),
        .cfg_req_tag                 (cfg_req_tag),
        .cfg_req_target_bdf          (cfg_req_target_bdf),
        .cfg_rsp_valid               (cfg_rsp_valid),
        .cfg_rsp_ready               (cfg_rsp_ready),
        .cfg_rsp_status              (cfg_rsp_status),
        .cfg_rsp_rdata               (cfg_rsp_rdata),
        .cfg_rsp_completer_id        (cfg_rsp_completer_id),

        .mem_req_valid               (mem_req_valid),
        .mem_req_ready               (mem_req_ready),
        .mem_req_write               (mem_req_write),
        .mem_req_64bit               (mem_req_64bit),
        .mem_req_poisoned            (mem_req_poisoned),
        .mem_req_address             (mem_req_address),
        .mem_req_length_dw           (mem_req_length_dw),
        .mem_req_first_be            (mem_req_first_be),
        .mem_req_last_be             (mem_req_last_be),
        .mem_req_requester_id        (mem_req_requester_id),
        .mem_req_tag                 (mem_req_tag),
        .mem_req_tc                  (mem_req_tc),
        .mem_req_attr                (mem_req_attr),
        .mem_w_valid                 (mem_w_valid),
        .mem_w_ready                 (mem_w_ready),
        .mem_w_data                  (mem_w_data),
        .mem_w_keep                  (mem_w_keep),
        .mem_w_last                  (mem_w_last),

        .rx_cpl_valid                (rx_cpl_valid_unused),
        .rx_cpl_ready                (1'b1),
        .rx_cpl_has_data             (rx_cpl_has_data_unused),
        .rx_cpl_poisoned             (rx_cpl_poisoned_unused),
        .rx_cpl_status               (rx_cpl_status_unused),
        .rx_cpl_bcm                  (rx_cpl_bcm_unused),
        .rx_cpl_byte_count           (rx_cpl_byte_count_unused),
        .rx_cpl_completer_id         (rx_cpl_completer_id_unused),
        .rx_cpl_requester_id         (rx_cpl_requester_id_unused),
        .rx_cpl_tag                  (rx_cpl_tag_unused),
        .rx_cpl_lower_address        (rx_cpl_lower_address_unused),
        .rx_cpl_length_dw            (rx_cpl_length_dw_unused),
        .rx_cpl_tc                   (rx_cpl_tc_unused),
        .rx_cpl_attr                 (rx_cpl_attr_unused),
        .rx_cpl_data_valid           (rx_cpl_data_valid_unused),
        .rx_cpl_data_ready           (1'b1),
        .rx_cpl_data                 (rx_cpl_data_unused),
        .rx_cpl_data_keep            (rx_cpl_data_keep_unused),
        .rx_cpl_data_last            (rx_cpl_data_last_unused),

        .cpl_req_valid               (cpl_req_valid),
        .cpl_req_ready               (cpl_req_ready),
        .cpl_req_has_data            (cpl_req_has_data),
        .cpl_req_poisoned            (cpl_req_poisoned),
        .cpl_req_status              (cpl_req_status),
        .cpl_req_bcm                 (cpl_req_bcm),
        .cpl_req_byte_count          (cpl_req_byte_count),
        .cpl_req_completer_id        (cpl_req_completer_id),
        .cpl_req_requester_id        (cpl_req_requester_id),
        .cpl_req_tag                 (cpl_req_tag),
        .cpl_req_lower_address       (cpl_req_lower_address),
        .cpl_req_length_dw           (cpl_req_length_dw),
        .cpl_req_tc                  (cpl_req_tc),
        .cpl_req_attr                (cpl_req_attr),
        .cpl_data_valid              (cpl_data_valid),
        .cpl_data_ready              (cpl_data_ready),
        .cpl_data                    (cpl_data),
        .cpl_data_keep               (cpl_data_keep),
        .cpl_data_last               (cpl_data_last),

        .malformed_pulse             (malformed_pulse_unused),
        .unsupported_pulse           (unsupported_pulse_unused),
        .poisoned_pulse              (poisoned_pulse_unused),
        .unexpected_cpl_pulse        (unexpected_cpl_pulse_unused),
        .error_fmt_type              (error_fmt_type_unused),
        .error_requester_id          (error_requester_id_unused),
        .error_tag                   (error_tag_unused),
        .rx_packet_count             (rx_packet_count_unused),
        .cfg_request_count           (codec_cfg_request_count),
        .mem_request_count           (codec_mem_request_count),
        .rx_completion_count         (rx_completion_count_unused),
        .tx_completion_count         (codec_tx_completion_count),
        .ur_completion_count         (codec_ur_completion_count),
        .malformed_count             (codec_malformed_count),
        .unsupported_count           (codec_unsupported_count),
        .poisoned_count              (poisoned_count_unused),
        .unexpected_completion_count (unexpected_completion_count_unused),
        .tx_protocol_error_count     (codec_tx_protocol_error_count)
    );

    wire bus_master_enable_unused;
    wire [2:0] max_payload_size_unused;
    wire [2:0] max_read_request_size_unused;
    wire rcb_128b_unused;
    wire link_disable_unused;
    wire retrain_link_pulse_unused;
    wire [1:0] target_link_speed_unused;

    pcie_cfg_space u_cfg_space (
        .clk                       (clk),
        .rst_n                     (rst_n),
        .hot_reset                 (hot_reset),
        .link_up                   (link_up),
        .link_training             (link_training),
        .dll_active                (dll_active),
        .link_speed                (link_speed),
        .link_width                (link_width),
        .cfg_req_valid             (cfg_req_valid),
        .cfg_req_ready             (cfg_req_ready),
        .cfg_req_write             (cfg_req_write),
        .cfg_req_dw_addr           (cfg_req_dw_addr),
        .cfg_req_be                (cfg_req_be),
        .cfg_req_wdata             (cfg_req_wdata),
        .cfg_req_requester_id      (cfg_req_requester_id),
        .cfg_req_tag               (cfg_req_tag),
        .cfg_req_target_bdf        (cfg_req_target_bdf),
        .cfg_rsp_valid             (cfg_rsp_valid),
        .cfg_rsp_ready             (cfg_rsp_ready),
        .cfg_rsp_status            (cfg_rsp_status),
        .cfg_rsp_rdata             (cfg_rsp_rdata),
        .cfg_rsp_completer_id      (cfg_rsp_completer_id),
        .captured_bdf              (captured_bdf),
        .bdf_valid                 (bdf_valid),
        .local_completer_id        (local_completer_id),
        .bar0_base                 (bar0_base),
        .bar0_probe_active         (bar0_probe_active),
        .memory_space_enable       (memory_space_enable),
        .bus_master_enable         (bus_master_enable_unused),
        .max_payload_size          (max_payload_size_unused),
        .max_read_request_size     (max_read_request_size_unused),
        .rcb_128b                  (rcb_128b_unused),
        .link_disable              (link_disable_unused),
        .retrain_link_pulse        (retrain_link_pulse_unused),
        .target_link_speed         (target_link_speed_unused)
    );

    wire posted_drop_pulse_unused;
    wire axi_error_pulse_unused;
    wire payload_error_pulse_unused;
    wire [31:0] posted_drop_count_unused;
    wire [31:0] poisoned_write_count_unused;
    wire [31:0] axi_read_error_count_unused;
    wire [31:0] axi_write_error_count_unused;
    wire [31:0] payload_protocol_error_count_unused;

    pcie_bar_axil_master u_bar_axil (
        .clk                          (clk),
        .rst_n                        (rst_n),
        .hot_reset                    (hot_reset),
        .bar0_base                    (bar0_base),
        .bar0_probe_active            (bar0_probe_active),
        .memory_space_enable          (memory_space_enable),
        .local_completer_id           (local_completer_id),
        .mem_req_valid                (mem_req_valid),
        .mem_req_ready                (mem_req_ready),
        .mem_req_write                (mem_req_write),
        .mem_req_64bit                (mem_req_64bit),
        .mem_req_poisoned             (mem_req_poisoned),
        .mem_req_address              (mem_req_address),
        .mem_req_length_dw            (mem_req_length_dw),
        .mem_req_first_be             (mem_req_first_be),
        .mem_req_last_be              (mem_req_last_be),
        .mem_req_requester_id         (mem_req_requester_id),
        .mem_req_tag                  (mem_req_tag),
        .mem_req_tc                   (mem_req_tc),
        .mem_req_attr                 (mem_req_attr),
        .mem_w_valid                  (mem_w_valid),
        .mem_w_ready                  (mem_w_ready),
        .mem_w_data                   (mem_w_data),
        .mem_w_keep                   (mem_w_keep),
        .mem_w_last                   (mem_w_last),
        .cpl_req_valid                (cpl_req_valid),
        .cpl_req_ready                (cpl_req_ready),
        .cpl_req_has_data             (cpl_req_has_data),
        .cpl_req_poisoned             (cpl_req_poisoned),
        .cpl_req_status               (cpl_req_status),
        .cpl_req_bcm                  (cpl_req_bcm),
        .cpl_req_byte_count           (cpl_req_byte_count),
        .cpl_req_completer_id         (cpl_req_completer_id),
        .cpl_req_requester_id         (cpl_req_requester_id),
        .cpl_req_tag                  (cpl_req_tag),
        .cpl_req_lower_address        (cpl_req_lower_address),
        .cpl_req_length_dw            (cpl_req_length_dw),
        .cpl_req_tc                   (cpl_req_tc),
        .cpl_req_attr                 (cpl_req_attr),
        .cpl_data_valid               (cpl_data_valid),
        .cpl_data_ready               (cpl_data_ready),
        .cpl_data                     (cpl_data),
        .cpl_data_keep                (cpl_data_keep),
        .cpl_data_last                (cpl_data_last),
        .m_axil_awaddr                (m_axil_awaddr),
        .m_axil_awvalid               (m_axil_awvalid),
        .m_axil_awready               (m_axil_awready),
        .m_axil_wdata                 (m_axil_wdata),
        .m_axil_wstrb                 (m_axil_wstrb),
        .m_axil_wvalid                (m_axil_wvalid),
        .m_axil_wready                (m_axil_wready),
        .m_axil_bresp                 (m_axil_bresp),
        .m_axil_bvalid                (m_axil_bvalid),
        .m_axil_bready                (m_axil_bready),
        .m_axil_araddr                (m_axil_araddr),
        .m_axil_arvalid               (m_axil_arvalid),
        .m_axil_arready               (m_axil_arready),
        .m_axil_rdata                 (m_axil_rdata),
        .m_axil_rresp                 (m_axil_rresp),
        .m_axil_rvalid                (m_axil_rvalid),
        .m_axil_rready                (m_axil_rready),
        .busy                         (bar_busy),
        .ur_pulse                     (bar_ur_pulse),
        .ca_pulse                     (bar_ca_pulse),
        .posted_drop_pulse            (posted_drop_pulse_unused),
        .axi_error_pulse              (axi_error_pulse_unused),
        .payload_error_pulse          (payload_error_pulse_unused),
        .mem_request_count            (bar_mem_request_count),
        .mem_read_count               (bar_mem_read_count),
        .mem_write_count              (bar_mem_write_count),
        .axi_read_count               (bar_axi_read_count),
        .axi_write_count              (bar_axi_write_count),
        .sc_completion_count          (bar_sc_completion_count),
        .ur_completion_count          (bar_ur_completion_count),
        .ca_completion_count          (bar_ca_completion_count),
        .posted_drop_count            (posted_drop_count_unused),
        .poisoned_write_count         (poisoned_write_count_unused),
        .axi_read_error_count         (axi_read_error_count_unused),
        .axi_write_error_count        (axi_write_error_count_unused),
        .payload_protocol_error_count (payload_protocol_error_count_unused)
    );
    /* verilator lint_on UNUSEDSIGNAL */
endmodule

`default_nettype wire
