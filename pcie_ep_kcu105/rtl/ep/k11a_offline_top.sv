`timescale 1ns/1ps
`default_nettype none

// K11-A/K11-B生产协议核心；保留冻结模块名k11a_offline_top。
// 边界位于K03 MAC Packet接口，不包含Xilinx PHY模型。
module k11a_offline_top #(
    parameter integer K11B2_ILA_DEBUG = 0
) (
    input  wire         pipe_clk,
    input  wire         pipe_rst_n,
    input  wire         core_clk,
    input  wire         core_rst_n,
    input  wire         link_up,
    input  wire [5:0]   ltssm_state,
    input  wire [1:0]   link_speed,
    input  wire [2:0]   link_width,
    input  wire         hot_reset,

    input  wire         mac_rx_valid,
    input  wire [15:0]  mac_rx_data,
    input  wire [1:0]   mac_rx_keep,
    input  wire         mac_rx_sop,
    input  wire         mac_rx_eop,
    input  wire         mac_rx_is_dllp,
    input  wire [3:0]   mac_rx_error,
    output wire         mac_tx_valid,
    input  wire         mac_tx_ready,
    output wire [15:0]  mac_tx_data,
    output wire [1:0]   mac_tx_keep,
    output wire         mac_tx_sop,
    output wire         mac_tx_eop,
    output wire         mac_tx_is_dllp,
    output wire         mac_tx_bad,

    output wire         dll_active,
    output wire [1:0]   dll_fc_state,
    output wire         recovery_req,
    output wire [15:0]  captured_bdf,
    output wire         bdf_valid,
    output wire [31:0]  bar0_base,
    output wire         memory_space_enable,
    output wire [7:0]   cdc_errors
);
    wire dll_rx_valid, dll_rx_ready, dll_rx_sop, dll_rx_eop;
    wire [127:0] dll_rx_data;
    wire [15:0] dll_rx_keep;
    wire [3:0] dll_rx_error;
    wire dll_tx_valid, dll_tx_ready, dll_tx_sop, dll_tx_eop;
    wire [127:0] dll_tx_data;
    wire [15:0] dll_tx_keep;
    wire [3:0] dll_tx_error;
    wire [1:0] dll_tx_type;
    wire [11:0] dll_tx_data_credits;
    wire dll_release_valid;
    wire [1:0] dll_release_type;
    wire [11:0] dll_release_data_credits;
    wire [11:0] next_tx_seq, next_rx_seq, last_acked_seq;
    wire [4:0] replay_occupancy;
    wire replay_active, replay_fatal;
    wire [31:0] malformed_dllp_count, bad_dllp_crc_count;
    wire [31:0] fc_protocol_error_count, tx_fc_count, rx_fc_count;
    wire [31:0] dll_tx_tlp_count, dll_rx_tlp_count, ack_tx_count;
    wire [31:0] nak_tx_count, replay_count, lcrc_error_count;
    wire [31:0] duplicate_tlp_count, sequence_error_count;
    wire [31:0] ack_error_count, buffer_error_count;

    generate if (K11B2_ILA_DEBUG != 0) begin : g_ila_debug_pipe
        // phy_pclk域事件级DLL诊断。计数器保留低4位并另给出非零标志。
        (* mark_debug = "true", keep = "true" *)
        wire [127:0] dbg_pipe_dll = {
            15'd0,
            |malformed_dllp_count, |bad_dllp_crc_count,
            |fc_protocol_error_count, |lcrc_error_count,
            |sequence_error_count, |duplicate_tlp_count,
            |buffer_error_count, |ack_error_count,
            dll_rx_tlp_count[3:0], dll_tx_tlp_count[3:0],
            lcrc_error_count[3:0], sequence_error_count[3:0],
            duplicate_tlp_count[3:0], buffer_error_count[3:0],
            ack_tx_count[3:0], nak_tx_count[3:0],
            next_tx_seq, next_rx_seq, last_acked_seq, replay_occupancy,
            dll_fc_state, dll_active, recovery_req, replay_active, replay_fatal,
            mac_rx_valid, mac_rx_sop, mac_rx_eop, mac_rx_is_dllp, mac_rx_error,
            dll_rx_valid, dll_rx_ready, dll_rx_sop, dll_rx_eop, dll_rx_error,
            dll_tx_valid, dll_tx_ready, dll_tx_sop, dll_tx_eop,
            mac_tx_valid, mac_tx_ready, mac_tx_sop, mac_tx_eop,
            mac_tx_is_dllp, mac_tx_bad
        };
    end endgenerate

    localparam integer DIAG_WIDTH = 143;
    wire [DIAG_WIDTH-1:0] pipe_diag = {
        ack_error_count, replay_count, nak_tx_count, lcrc_error_count,
        dll_fc_state, dll_active, ltssm_state, link_width, link_speed, link_up
    };
    wire [DIAG_WIDTH-1:0] core_diag;
    wire core_diag_valid;
    wire core_hot_reset;
    wire core_link_up = core_diag[0];
    wire [1:0] core_link_speed = core_diag[2:1];
    wire [2:0] core_link_width = core_diag[5:3];
    wire [5:0] core_ltssm_state = core_diag[11:6];
    wire core_dll_active = core_diag[12];
    wire [1:0] core_dll_fc_state = core_diag[14:13];
    wire [31:0] core_lcrc_error_count = core_diag[46:15];
    wire [31:0] core_nak_tx_count = core_diag[78:47];
    wire [31:0] core_replay_count = core_diag[110:79];
    wire [31:0] core_ack_error_count = core_diag[142:111];

    pcie_cdc_snapshot #(.WIDTH(DIAG_WIDTH)) u_diag_snapshot (
        .s_clk(pipe_clk), .s_rst_n(pipe_rst_n), .s_data(pipe_diag),
        .d_clk(core_clk), .d_rst_n(core_rst_n), .d_data(core_diag),
        .d_valid(core_diag_valid)
    );

    pcie_cdc_pulse u_hot_reset_sync (
        .s_clk(pipe_clk), .s_rst_n(pipe_rst_n), .s_pulse(hot_reset),
        .d_clk(core_clk), .d_rst_n(core_rst_n), .d_pulse(core_hot_reset)
    );

    pcie_dll u_dll (
        .clk(pipe_clk), .rst_n(pipe_rst_n), .link_up(link_up),
        .mac_rx_valid(mac_rx_valid), .mac_rx_data(mac_rx_data),
        .mac_rx_keep(mac_rx_keep), .mac_rx_sop(mac_rx_sop),
        .mac_rx_eop(mac_rx_eop), .mac_rx_is_dllp(mac_rx_is_dllp),
        .mac_rx_error(mac_rx_error), .mac_tx_valid(mac_tx_valid),
        .mac_tx_ready(mac_tx_ready), .mac_tx_data(mac_tx_data),
        .mac_tx_keep(mac_tx_keep), .mac_tx_sop(mac_tx_sop),
        .mac_tx_eop(mac_tx_eop), .mac_tx_is_dllp(mac_tx_is_dllp),
        .mac_tx_bad(mac_tx_bad),
        .tx_tlp_valid(dll_tx_valid), .tx_tlp_ready(dll_tx_ready),
        .tx_tlp_data(dll_tx_data), .tx_tlp_keep(dll_tx_keep),
        .tx_tlp_sop(dll_tx_sop), .tx_tlp_eop(dll_tx_eop),
        .tx_tlp_error(dll_tx_error), .tx_tlp_type(dll_tx_type),
        .tx_tlp_data_credits(dll_tx_data_credits),
        .rx_tlp_valid(dll_rx_valid), .rx_tlp_ready(dll_rx_ready),
        .rx_tlp_data(dll_rx_data), .rx_tlp_keep(dll_rx_keep),
        .rx_tlp_sop(dll_rx_sop), .rx_tlp_eop(dll_rx_eop),
        .rx_tlp_error(dll_rx_error),
        .rx_tlp_release_valid(dll_release_valid),
        .rx_tlp_release_type(dll_release_type),
        .rx_tlp_release_data_credits(dll_release_data_credits),
        .dll_active(dll_active), .fc_state(dll_fc_state),
        .recovery_req(recovery_req), .next_tx_seq(next_tx_seq),
        .next_rx_seq(next_rx_seq), .last_acked_seq(last_acked_seq),
        .replay_occupancy(replay_occupancy), .replay_active(replay_active),
        .replay_fatal(replay_fatal),
        .malformed_dllp_count(malformed_dllp_count),
        .bad_dllp_crc_count(bad_dllp_crc_count),
        .fc_protocol_error_count(fc_protocol_error_count),
        .tx_fc_count(tx_fc_count), .rx_fc_count(rx_fc_count),
        .tx_tlp_count(dll_tx_tlp_count), .rx_tlp_count(dll_rx_tlp_count),
        .ack_tx_count(ack_tx_count), .nak_tx_count(nak_tx_count),
        .replay_count(replay_count), .lcrc_error_count(lcrc_error_count),
        .duplicate_tlp_count(duplicate_tlp_count),
        .sequence_error_count(sequence_error_count),
        .ack_error_count(ack_error_count), .buffer_error_count(buffer_error_count)
    );

    wire core_rx_valid, core_rx_ready, core_rx_sop, core_rx_eop;
    wire [127:0] core_rx_data;
    wire [15:0] core_rx_keep;
    wire [3:0] core_rx_error;
    wire core_tx_valid, core_tx_ready, core_tx_sop, core_tx_eop;
    wire [127:0] core_tx_data;
    wire [15:0] core_tx_keep;
    wire [3:0] core_tx_error;
    wire [1:0] core_tx_type;
    wire [11:0] core_tx_data_credits;
    wire core_release_valid, core_release_ready;
    wire [1:0] core_release_type;
    wire [11:0] core_release_data_credits;

    pcie_tlp_async_bridge u_cdc (
        .pipe_clk(pipe_clk), .pipe_rst_n(pipe_rst_n),
        .core_clk(core_clk), .core_rst_n(core_rst_n),
        .dll_rx_valid(dll_rx_valid), .dll_rx_ready(dll_rx_ready),
        .dll_rx_data(dll_rx_data), .dll_rx_keep(dll_rx_keep),
        .dll_rx_sop(dll_rx_sop), .dll_rx_eop(dll_rx_eop),
        .dll_rx_error(dll_rx_error),
        .core_rx_valid(core_rx_valid), .core_rx_ready(core_rx_ready),
        .core_rx_data(core_rx_data), .core_rx_keep(core_rx_keep),
        .core_rx_sop(core_rx_sop), .core_rx_eop(core_rx_eop),
        .core_rx_error(core_rx_error),
        .core_tx_valid(core_tx_valid), .core_tx_ready(core_tx_ready),
        .core_tx_data(core_tx_data), .core_tx_keep(core_tx_keep),
        .core_tx_sop(core_tx_sop), .core_tx_eop(core_tx_eop),
        .core_tx_error(core_tx_error), .core_tx_type(core_tx_type),
        .core_tx_data_credits(core_tx_data_credits),
        .dll_tx_valid(dll_tx_valid), .dll_tx_ready(dll_tx_ready),
        .dll_tx_data(dll_tx_data), .dll_tx_keep(dll_tx_keep),
        .dll_tx_sop(dll_tx_sop), .dll_tx_eop(dll_tx_eop),
        .dll_tx_error(dll_tx_error), .dll_tx_type(dll_tx_type),
        .dll_tx_data_credits(dll_tx_data_credits),
        .core_release_valid(core_release_valid),
        .core_release_ready(core_release_ready),
        .core_release_type(core_release_type),
        .core_release_data_credits(core_release_data_credits),
        .dll_release_valid(dll_release_valid), .dll_release_ready(1'b1),
        .dll_release_type(dll_release_type),
        .dll_release_data_credits(dll_release_data_credits),
        .rx_overflow(cdc_errors[0]), .rx_underflow(cdc_errors[1]),
        .tx_overflow(cdc_errors[2]), .tx_underflow(cdc_errors[3]),
        .metadata_overflow(cdc_errors[4]),
        .metadata_underflow(cdc_errors[5]),
        .release_overflow(cdc_errors[6]),
        .release_underflow(cdc_errors[7])
    );

    wire [31:0] axil_awaddr, axil_wdata, axil_araddr, axil_rdata;
    wire [3:0] axil_wstrb;
    wire axil_awvalid, axil_awready, axil_wvalid, axil_wready;
    wire [1:0] axil_bresp, axil_rresp;
    wire axil_bvalid, axil_bready, axil_arvalid, axil_arready;
    wire axil_rvalid, axil_rready;
    wire [15:0] local_completer_id;
    wire bar0_probe_active;
    wire bar_busy, bar_ur_pulse, bar_ca_pulse;
    wire [31:0] codec_cfg_request_count, codec_mem_request_count;
    wire [31:0] codec_tx_completion_count, codec_ur_completion_count;
    wire [31:0] codec_malformed_count, codec_unsupported_count;
    wire [31:0] codec_tx_protocol_error_count;
    wire [31:0] bar_mem_request_count, bar_mem_read_count;
    wire [31:0] bar_mem_write_count, bar_axi_read_count, bar_axi_write_count;
    wire [31:0] bar_sc_completion_count, bar_ur_completion_count;
    wire [31:0] bar_ca_completion_count;

    generate if (K11B2_ILA_DEBUG != 0) begin : g_ila_debug_core
        (* mark_debug = "true", keep = "true" *)
        wire dbg_core_clk = core_clk;
        (* mark_debug = "true", keep = "true" *)
        wire dbg_core_tlp_trigger = core_rx_valid && core_rx_ready && core_rx_sop;
        (* mark_debug = "true", keep = "true" *)
        wire [127:0] dbg_core_stream = {
            10'd0,
            core_rst_n, core_diag_valid, core_link_up, core_dll_active,
            core_rx_valid, core_rx_ready, core_rx_sop, core_rx_eop, core_rx_error,
            core_tx_valid, core_tx_ready, core_tx_sop, core_tx_eop,
            core_tx_error, core_tx_type,
            core_release_valid, core_release_ready,
            captured_bdf, bdf_valid, bar0_base[31:12], memory_space_enable,
            codec_cfg_request_count[7:0], codec_mem_request_count[7:0],
            codec_tx_completion_count[7:0], codec_ur_completion_count[7:0],
            codec_malformed_count[7:0], codec_unsupported_count[7:0],
            cdc_errors
        };
    end endgenerate

    k09_tlp_test_top #(.K11B2_ILA_DEBUG(K11B2_ILA_DEBUG)) u_tl (
        .clk(core_clk), .rst_n(core_rst_n), .hot_reset(core_hot_reset),
        .link_up(core_link_up), .link_training(!core_link_up),
        .dll_active(core_dll_active), .link_speed(core_link_speed),
        .link_width(core_link_width),
        .rx_tlp_valid(core_rx_valid), .rx_tlp_ready(core_rx_ready),
        .rx_tlp_data(core_rx_data), .rx_tlp_keep(core_rx_keep),
        .rx_tlp_sop(core_rx_sop), .rx_tlp_eop(core_rx_eop),
        .rx_tlp_error(core_rx_error),
        .tx_tlp_valid(core_tx_valid), .tx_tlp_ready(core_tx_ready),
        .tx_tlp_data(core_tx_data), .tx_tlp_keep(core_tx_keep),
        .tx_tlp_sop(core_tx_sop), .tx_tlp_eop(core_tx_eop),
        .tx_tlp_error(core_tx_error), .tx_tlp_type(core_tx_type),
        .tx_tlp_data_credits(core_tx_data_credits),
        .rx_release_valid(core_release_valid),
        .rx_release_ready(core_release_ready),
        .rx_release_type(core_release_type),
        .rx_release_data_credits(core_release_data_credits),
        .m_axil_awaddr(axil_awaddr), .m_axil_awvalid(axil_awvalid),
        .m_axil_awready(axil_awready), .m_axil_wdata(axil_wdata),
        .m_axil_wstrb(axil_wstrb), .m_axil_wvalid(axil_wvalid),
        .m_axil_wready(axil_wready), .m_axil_bresp(axil_bresp),
        .m_axil_bvalid(axil_bvalid), .m_axil_bready(axil_bready),
        .m_axil_araddr(axil_araddr), .m_axil_arvalid(axil_arvalid),
        .m_axil_arready(axil_arready), .m_axil_rdata(axil_rdata),
        .m_axil_rresp(axil_rresp), .m_axil_rvalid(axil_rvalid),
        .m_axil_rready(axil_rready), .captured_bdf(captured_bdf),
        .bdf_valid(bdf_valid), .local_completer_id(local_completer_id),
        .bar0_base(bar0_base), .bar0_probe_active(bar0_probe_active),
        .memory_space_enable(memory_space_enable), .bar_busy(bar_busy),
        .bar_ur_pulse(bar_ur_pulse), .bar_ca_pulse(bar_ca_pulse),
        .codec_cfg_request_count(codec_cfg_request_count),
        .codec_mem_request_count(codec_mem_request_count),
        .codec_tx_completion_count(codec_tx_completion_count),
        .codec_ur_completion_count(codec_ur_completion_count),
        .codec_malformed_count(codec_malformed_count),
        .codec_unsupported_count(codec_unsupported_count),
        .codec_tx_protocol_error_count(codec_tx_protocol_error_count),
        .bar_mem_request_count(bar_mem_request_count),
        .bar_mem_read_count(bar_mem_read_count),
        .bar_mem_write_count(bar_mem_write_count),
        .bar_axi_read_count(bar_axi_read_count),
        .bar_axi_write_count(bar_axi_write_count),
        .bar_sc_completion_count(bar_sc_completion_count),
        .bar_ur_completion_count(bar_ur_completion_count),
        .bar_ca_completion_count(bar_ca_completion_count)
    );

    demo_axil_slave u_demo (
        .clk(core_clk), .rst_n(core_rst_n),
        .s_axil_awaddr(axil_awaddr), .s_axil_awvalid(axil_awvalid),
        .s_axil_awready(axil_awready), .s_axil_wdata(axil_wdata),
        .s_axil_wstrb(axil_wstrb), .s_axil_wvalid(axil_wvalid),
        .s_axil_wready(axil_wready), .s_axil_bresp(axil_bresp),
        .s_axil_bvalid(axil_bvalid), .s_axil_bready(axil_bready),
        .s_axil_araddr(axil_araddr), .s_axil_arvalid(axil_arvalid),
        .s_axil_arready(axil_arready), .s_axil_rdata(axil_rdata),
        .s_axil_rresp(axil_rresp), .s_axil_rvalid(axil_rvalid),
        .s_axil_rready(axil_rready), .link_up(core_link_up),
        .link_speed(core_link_speed), .ltssm_state(core_ltssm_state),
        .dll_active(core_dll_active), .dll_state({2'd0, core_dll_fc_state}),
        .rx_bad_symbol_count(32'd0), .ltssm_retrain_count(32'd0),
        .dll_lcrc_error_count(core_lcrc_error_count),
        .dll_nak_count(core_nak_tx_count),
        .dll_replay_count(core_replay_count),
        .dll_replay_timeout_count(core_ack_error_count),
        .tl_malformed_count(codec_malformed_count),
        .tl_unsupported_count(codec_unsupported_count),
        .bar_ur_count(bar_ur_completion_count),
        .bar_ca_count(bar_ca_completion_count),
        .bar_axi_error_count(32'd0), .bar_payload_error_count(32'd0)
    );

    wire _unused = &{1'b0, core_diag_valid, local_completer_id,
        bar0_probe_active, bar_busy,
        bar_ur_pulse, bar_ca_pulse, next_tx_seq, next_rx_seq, last_acked_seq,
        replay_occupancy, replay_active, replay_fatal, malformed_dllp_count,
        bad_dllp_crc_count, fc_protocol_error_count, tx_fc_count, rx_fc_count,
        dll_tx_tlp_count, dll_rx_tlp_count, ack_tx_count, duplicate_tlp_count,
        sequence_error_count, buffer_error_count, codec_cfg_request_count,
        codec_mem_request_count, codec_tx_completion_count,
        codec_ur_completion_count, codec_tx_protocol_error_count,
        bar_mem_request_count, bar_mem_read_count, bar_mem_write_count,
        bar_axi_read_count, bar_axi_write_count, bar_sc_completion_count};
endmodule

`default_nettype wire
