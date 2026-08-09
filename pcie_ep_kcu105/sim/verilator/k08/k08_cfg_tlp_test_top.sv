`timescale 1ns/1ps
`default_nettype none

// 仅用于K07+K08的TLP级集成验证。
//
// 本顶层有意不实例化K03～K06：cocotb中的SimPort适配器替代链路传输，
// 但每个配置请求和Completion都必须依次经过生产pcie_tlp_codec与
// 生产pcie_cfg_space。Memory/BAR/AXI路径属于K09及以后阶段，在此明确封闭。
module k08_cfg_tlp_test_top (
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

    output wire [15:0]  captured_bdf,
    output wire         bdf_valid,
    output wire [15:0]  local_completer_id,
    output wire [31:0]  bar0_base,
    output wire         bar0_probe_active,
    output wire         memory_space_enable,
    output wire         bus_master_enable,
    output wire [2:0]   max_payload_size,
    output wire [2:0]   max_read_request_size,
    output wire         rcb_128b,
    output wire         link_disable,
    output wire         retrain_link_pulse,
    output wire [1:0]   target_link_speed,

    // 这些观察点用于证明测试没有绕过K07结构化接口。
    output wire         cfg_path_req_valid,
    output wire         cfg_path_req_ready,
    output wire         cfg_path_rsp_valid,
    output wire         cfg_path_rsp_ready,
    output wire         cfg_path_req_write,
    output wire [9:0]   cfg_path_req_dw_addr,
    output wire [15:0]  cfg_path_req_target_bdf,

    output wire [31:0]  codec_cfg_request_count,
    output wire [31:0]  codec_tx_completion_count,
    output wire [31:0]  codec_ur_completion_count,
    output wire [31:0]  codec_malformed_count,
    output wire [31:0]  codec_unsupported_count,
    output wire [31:0]  codec_tx_protocol_error_count
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

    assign cfg_path_req_valid = cfg_req_valid;
    assign cfg_path_req_ready = cfg_req_ready;
    assign cfg_path_rsp_valid = cfg_rsp_valid;
    assign cfg_path_rsp_ready = cfg_rsp_ready;
    assign cfg_path_req_write = cfg_req_write;
    assign cfg_path_req_dw_addr = cfg_req_dw_addr;
    assign cfg_path_req_target_bdf = cfg_req_target_bdf;

    /* verilator lint_off UNUSEDSIGNAL */
    // K07中与当前配置集成用例无关的接收通道仍必须被正常消费，防止
    // 一个意外TLP令测试无期限停住；对应计数器会令用例失败。
    wire         mem_req_valid_unused;
    wire         mem_req_write_unused;
    wire         mem_req_64bit_unused;
    wire         mem_req_poisoned_unused;
    wire [63:0]  mem_req_address_unused;
    wire [10:0]  mem_req_length_dw_unused;
    wire [3:0]   mem_req_first_be_unused;
    wire [3:0]   mem_req_last_be_unused;
    wire [15:0]  mem_req_requester_id_unused;
    wire [7:0]   mem_req_tag_unused;
    wire [2:0]   mem_req_tc_unused;
    wire [2:0]   mem_req_attr_unused;
    wire         mem_w_valid_unused;
    wire [127:0] mem_w_data_unused;
    wire [15:0]  mem_w_keep_unused;
    wire         mem_w_last_unused;

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

    wire         rx_release_valid_unused;
    wire [1:0]   rx_release_type_unused;
    wire [11:0]  rx_release_data_credits_unused;
    wire         malformed_pulse_unused;
    wire         unsupported_pulse_unused;
    wire         poisoned_pulse_unused;
    wire         unexpected_cpl_pulse_unused;
    wire [7:0]   error_fmt_type_unused;
    wire [15:0]  error_requester_id_unused;
    wire [7:0]   error_tag_unused;
    wire [31:0]  rx_packet_count_unused;
    wire [31:0]  mem_request_count_unused;
    wire [31:0]  rx_completion_count_unused;
    wire [31:0]  poisoned_count_unused;
    wire [31:0]  unexpected_completion_count_unused;
    wire         cpl_req_ready_unused;
    wire         cpl_data_ready_unused;

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

        .rx_release_valid            (rx_release_valid_unused),
        .rx_release_ready            (1'b1),
        .rx_release_type             (rx_release_type_unused),
        .rx_release_data_credits     (rx_release_data_credits_unused),

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

        .mem_req_valid               (mem_req_valid_unused),
        .mem_req_ready               (1'b1),
        .mem_req_write               (mem_req_write_unused),
        .mem_req_64bit               (mem_req_64bit_unused),
        .mem_req_poisoned            (mem_req_poisoned_unused),
        .mem_req_address             (mem_req_address_unused),
        .mem_req_length_dw           (mem_req_length_dw_unused),
        .mem_req_first_be            (mem_req_first_be_unused),
        .mem_req_last_be             (mem_req_last_be_unused),
        .mem_req_requester_id        (mem_req_requester_id_unused),
        .mem_req_tag                 (mem_req_tag_unused),
        .mem_req_tc                  (mem_req_tc_unused),
        .mem_req_attr                (mem_req_attr_unused),
        .mem_w_valid                 (mem_w_valid_unused),
        .mem_w_ready                 (1'b1),
        .mem_w_data                  (mem_w_data_unused),
        .mem_w_keep                  (mem_w_keep_unused),
        .mem_w_last                  (mem_w_last_unused),

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

        .cpl_req_valid               (1'b0),
        .cpl_req_ready               (cpl_req_ready_unused),
        .cpl_req_has_data            (1'b0),
        .cpl_req_poisoned            (1'b0),
        .cpl_req_status              (3'd0),
        .cpl_req_bcm                 (1'b0),
        .cpl_req_byte_count          (13'd0),
        .cpl_req_completer_id        (16'd0),
        .cpl_req_requester_id        (16'd0),
        .cpl_req_tag                 (8'd0),
        .cpl_req_lower_address       (7'd0),
        .cpl_req_length_dw           (6'd0),
        .cpl_req_tc                  (3'd0),
        .cpl_req_attr                (3'd0),
        .cpl_data_valid              (1'b0),
        .cpl_data_ready              (cpl_data_ready_unused),
        .cpl_data                    (128'd0),
        .cpl_data_keep               (16'd0),
        .cpl_data_last               (1'b0),

        .malformed_pulse             (malformed_pulse_unused),
        .unsupported_pulse           (unsupported_pulse_unused),
        .poisoned_pulse              (poisoned_pulse_unused),
        .unexpected_cpl_pulse        (unexpected_cpl_pulse_unused),
        .error_fmt_type              (error_fmt_type_unused),
        .error_requester_id          (error_requester_id_unused),
        .error_tag                   (error_tag_unused),
        .rx_packet_count             (rx_packet_count_unused),
        .cfg_request_count           (codec_cfg_request_count),
        .mem_request_count           (mem_request_count_unused),
        .rx_completion_count         (rx_completion_count_unused),
        .tx_completion_count         (codec_tx_completion_count),
        .ur_completion_count         (codec_ur_completion_count),
        .malformed_count             (codec_malformed_count),
        .unsupported_count           (codec_unsupported_count),
        .poisoned_count              (poisoned_count_unused),
        .unexpected_completion_count (unexpected_completion_count_unused),
        .tx_protocol_error_count     (codec_tx_protocol_error_count)
    );
    /* verilator lint_on UNUSEDSIGNAL */

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
        .bus_master_enable         (bus_master_enable),
        .max_payload_size          (max_payload_size),
        .max_read_request_size     (max_read_request_size),
        .rcb_128b                  (rcb_128b),
        .link_disable              (link_disable),
        .retrain_link_pulse        (retrain_link_pulse),
        .target_link_speed         (target_link_speed)
    );
endmodule

`default_nettype wire
