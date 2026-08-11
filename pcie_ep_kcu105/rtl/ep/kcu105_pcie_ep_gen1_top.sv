`timescale 1ns/1ps
`default_nettype none

// K11-B2完整Gen1 x1 Endpoint：真实standalone PHY + K03 MAC + K11-A协议核心。
module kcu105_pcie_ep_gen1_top #(
    parameter integer DETECT_QUIET_CYCLES   = 1_500_000,
    parameter integer DETECT_TIMEOUT_CYCLES = 3_000_000,
    parameter integer TRAIN_TIMEOUT_CYCLES  = 6_000_000,
    parameter integer HOT_RESET_CYCLES      = 250_000,
    parameter integer K11B2_ILA_DEBUG        = 0,
    parameter integer G7_RX_P0_QUIET         = 0
) (
    input  wire        pcie_refclk_p,
    input  wire        pcie_refclk_n,
    input  wire        pcie_perst_n,
    input  wire        pcie_rxp,
    input  wire        pcie_rxn,
    output wire        pcie_txp,
    output wire        pcie_txn,
    output wire [7:0]  led,
    output wire        link_up,
    output wire        dll_active,
    output wire [5:0]  ltssm_state,
    output wire [1:0]  dll_fc_state,
    output wire [1:0]  negotiated_speed,
    output wire [2:0]  negotiated_width,
    output wire [15:0] captured_bdf,
    output wire        bdf_valid,
    output wire [31:0] bar0_base,
    output wire        memory_space_enable,
    output wire [7:0]  cdc_errors
);
    wire phy_coreclk, phy_userclk, phy_mcapclk, phy_pclk;
    wire pipe_rst_n, core_rst_n;
    wire [31:0] phy_rxdata, phy_txdata;
    wire [1:0] phy_rxdatak, phy_txdatak;
    wire phy_rxdata_valid, phy_rxstart_block, phy_rxvalid;
    wire [1:0] phy_rxsync_header;
    wire phy_phystatus, phy_phystatus_rst, phy_rxelecidle;
    wire [2:0] phy_rxstatus;
    wire [5:0] phy_txeq_fs, phy_txeq_lf;
    wire [17:0] phy_txeq_new_coeff, phy_rxeq_new_txcoeff;
    wire phy_txeq_done, phy_rxeq_preset_sel;
    wire phy_rxeq_adapt_done, phy_rxeq_done;

    wire phy_txdata_valid, phy_txstart_block, phy_txdetectrx;
    wire [1:0] phy_txsync_header;
    wire phy_txelecidle, phy_txcompliance, phy_rxpolarity;
    wire [1:0] phy_powerdown, phy_rate;
    wire [2:0] phy_txmargin;
    wire phy_txswing, phy_txdeemph;
    wire [1:0] phy_txeq_ctrl, phy_rxeq_ctrl;
    wire [3:0] phy_txeq_preset, phy_rxeq_txpreset;
    wire [5:0] phy_txeq_coeff;
    wire as_mac_in_detect, as_cdr_hold_req;

    wire mac_rx_valid, mac_rx_sop, mac_rx_eop, mac_rx_is_dllp;
    wire [15:0] mac_rx_data;
    wire [1:0] mac_rx_keep;
    wire [3:0] mac_rx_error;
    wire mac_tx_valid, mac_tx_ready, mac_tx_sop, mac_tx_eop;
    wire mac_tx_is_dllp, mac_tx_bad;
    wire [15:0] mac_tx_data;
    wire [1:0] mac_tx_keep;
    wire recovery_req, hot_reset_seen;
    wire [7:0] link_number;
    wire [4:0] rx_ts_count;
    wire [31:0] training_error_count, timeout_count, frame_error_count;
    reg [24:0] heartbeat_count;

    wire dbg_operational_seen;
    wire dbg_link_loss_seen;
    wire dbg_link_loss_pipe;
    wire dbg_link_loss_core;

    generate if (K11B2_ILA_DEBUG != 0) begin : g_link_loss_debug
        pcie_link_loss_trigger u_link_loss_trigger (
            .clk              (phy_pclk),
            .rst_n            (pipe_rst_n),
            .link_up          (link_up),
            .dll_active       (dll_active),
            .operational_seen (dbg_operational_seen),
            .link_loss_seen   (dbg_link_loss_seen),
            .link_loss_pulse  (dbg_link_loss_pipe)
        );
        pcie_cdc_pulse u_link_loss_cdc (
            .s_clk   (phy_pclk),
            .s_rst_n (pipe_rst_n),
            .s_pulse (dbg_link_loss_pipe),
            .d_clk   (phy_coreclk),
            .d_rst_n (core_rst_n),
            .d_pulse (dbg_link_loss_core)
        );
    end else begin : g_link_loss_debug_disabled
        assign dbg_operational_seen = 1'b0;
        assign dbg_link_loss_seen   = 1'b0;
        assign dbg_link_loss_pipe   = 1'b0;
        assign dbg_link_loss_core   = 1'b0;
    end endgenerate

    generate if (K11B2_ILA_DEBUG != 0) begin : g_ila_debug
        // K11-B3事件级诊断总线。默认参数为0，正式构建完全裁掉。
        (* mark_debug = "true", keep = "true" *)
        wire dbg_pipe_clk = phy_pclk;
        (* mark_debug = "true", keep = "true" *)
        wire dbg_pipe_tlp_trigger = mac_rx_valid && mac_rx_sop &&
                                    !mac_rx_is_dllp;
        (* mark_debug = "true", keep = "true" *)
        wire dbg_pipe_link_loss_trigger = dbg_link_loss_pipe;
        // K11-B3.1：PHY在报告Electrical Idle时仍报告RxValid的矛盾事件。
        // 仅用于取证，不参与LTSSM或协议功能判定。
        (* mark_debug = "true", keep = "true" *)
        wire dbg_phy_rxidle_conflict = dbg_operational_seen && link_up &&
                                       phy_rxelecidle && phy_rxvalid;
        // PERST# 是异步输入；仅把两级同步后的电平送入 ILA，避免把
        // 原始异步复位直接接到 TX/PIPE 时钟域调试核而制造 CDC-1。
        (* mark_debug = "true", keep = "true" *)
        reg [1:0] dbg_perst_sync;
        (* mark_debug = "true", keep = "true" *)
        reg dbg_perst_sync_d;
        (* mark_debug = "true", keep = "true" *)
        reg dbg_phystatus_rst_d;
        always @(posedge phy_pclk or negedge pcie_perst_n) begin
            if (!pcie_perst_n) begin
                dbg_perst_sync <= 2'b00;
            end else begin
                dbg_perst_sync <= {dbg_perst_sync[0], 1'b1};
            end
        end
        // 仅用于生成PERST#释放事件；不使用异步复位，避免调试寄存器制造CDC-7。
        always @(posedge phy_pclk)
            dbg_perst_sync_d <= dbg_perst_sync[1];
        always @(posedge phy_pclk)
            dbg_phystatus_rst_d <= phy_phystatus_rst;
        (* mark_debug = "true", keep = "true" *)
        wire dbg_perst_n_pipe = dbg_perst_sync[1];
        (* mark_debug = "true", keep = "true" *)
        wire dbg_perst_rise_pipe = dbg_perst_sync[1] && !dbg_perst_sync_d;
        (* mark_debug = "true", keep = "true" *)
        wire dbg_phystatus_rst_fall_pipe = dbg_phystatus_rst_d && !phy_phystatus_rst;
        (* mark_debug = "true", keep = "true" *)
        wire [63:0] dbg_pipe_top = {
            13'd0,
            dbg_link_loss_seen, dbg_operational_seen, dbg_link_loss_pipe,
            heartbeat_count[24],
            phy_rxdata_valid, phy_rxvalid, phy_rxelecidle, phy_rxstatus,
            phy_phystatus, phy_phystatus_rst,
            pipe_rst_n, core_rst_n,
            link_up, dll_active, dll_fc_state, ltssm_state,
            negotiated_speed, negotiated_width,
            recovery_req, hot_reset_seen,
            |training_error_count, |timeout_count, |frame_error_count,
            mac_rx_valid, mac_rx_sop, mac_rx_eop, mac_rx_is_dllp, mac_rx_error,
            mac_tx_valid, mac_tx_ready, mac_tx_sop, mac_tx_eop,
            mac_tx_is_dllp, mac_tx_bad,
            |cdc_errors, bdf_valid, memory_space_enable
        };
    end endgenerate

    kcu105_pcie_phy_wrapper u_phy_wrapper (
        .pcie_refclk_p(pcie_refclk_p), .pcie_refclk_n(pcie_refclk_n),
        .pcie_perst_n(pcie_perst_n), .pcie_rxp(pcie_rxp), .pcie_rxn(pcie_rxn),
        .pcie_txp(pcie_txp), .pcie_txn(pcie_txn),
        .phy_txdata(phy_txdata), .phy_txdatak(phy_txdatak),
        .phy_txdata_valid(phy_txdata_valid), .phy_txstart_block(phy_txstart_block),
        .phy_txsync_header(phy_txsync_header), .phy_txdetectrx(phy_txdetectrx),
        .phy_txelecidle(phy_txelecidle), .phy_txcompliance(phy_txcompliance),
        .phy_rxpolarity(phy_rxpolarity), .phy_powerdown(phy_powerdown),
        .phy_rate(phy_rate), .phy_txmargin(phy_txmargin), .phy_txswing(phy_txswing),
        .phy_txdeemph(phy_txdeemph), .phy_txeq_ctrl(phy_txeq_ctrl),
        .phy_txeq_preset(phy_txeq_preset), .phy_txeq_coeff(phy_txeq_coeff),
        .phy_rxeq_ctrl(phy_rxeq_ctrl), .phy_rxeq_txpreset(phy_rxeq_txpreset),
        .as_mac_in_detect(as_mac_in_detect), .as_cdr_hold_req(as_cdr_hold_req),
        .phy_coreclk(phy_coreclk), .phy_userclk(phy_userclk),
        .phy_mcapclk(phy_mcapclk), .phy_pclk(phy_pclk),
        .pipe_rst_n(pipe_rst_n), .core_rst_n(core_rst_n),
        .phy_rxdata(phy_rxdata), .phy_rxdatak(phy_rxdatak),
        .phy_rxdata_valid(phy_rxdata_valid), .phy_rxstart_block(phy_rxstart_block),
        .phy_rxsync_header(phy_rxsync_header), .phy_rxvalid(phy_rxvalid),
        .phy_phystatus(phy_phystatus), .phy_phystatus_rst(phy_phystatus_rst),
        .phy_rxelecidle(phy_rxelecidle), .phy_rxstatus(phy_rxstatus),
        .phy_txeq_fs(phy_txeq_fs), .phy_txeq_lf(phy_txeq_lf),
        .phy_txeq_new_coeff(phy_txeq_new_coeff), .phy_txeq_done(phy_txeq_done),
        .phy_rxeq_preset_sel(phy_rxeq_preset_sel),
        .phy_rxeq_new_txcoeff(phy_rxeq_new_txcoeff),
        .phy_rxeq_adapt_done(phy_rxeq_adapt_done), .phy_rxeq_done(phy_rxeq_done)
    );

    pcie_ltssm_mac_gen1 #(
        .DETECT_QUIET_CYCLES(DETECT_QUIET_CYCLES),
        .DETECT_TIMEOUT_CYCLES(DETECT_TIMEOUT_CYCLES),
        .TRAIN_TIMEOUT_CYCLES(TRAIN_TIMEOUT_CYCLES),
        .HOT_RESET_CYCLES(HOT_RESET_CYCLES),
        .K11B2_ILA_DEBUG(K11B2_ILA_DEBUG),
        .G7_RX_P0_QUIET(G7_RX_P0_QUIET)
    ) u_ltssm_mac (
        .phy_pclk(phy_pclk), .pipe_rst_n(pipe_rst_n),
        .phy_rxdata(phy_rxdata), .phy_rxdatak(phy_rxdatak),
        .phy_rxdata_valid(phy_rxdata_valid), .phy_rxvalid(phy_rxvalid),
        .phy_phystatus(phy_phystatus), .phy_rxelecidle(phy_rxelecidle),
        .phy_rxstatus(phy_rxstatus), .phy_txdata(phy_txdata),
        .phy_txdatak(phy_txdatak), .phy_txdata_valid(phy_txdata_valid),
        .phy_txstart_block(phy_txstart_block), .phy_txsync_header(phy_txsync_header),
        .phy_txdetectrx(phy_txdetectrx), .phy_txelecidle(phy_txelecidle),
        .phy_txcompliance(phy_txcompliance), .phy_rxpolarity(phy_rxpolarity),
        .phy_powerdown(phy_powerdown), .phy_rate(phy_rate),
        .phy_txmargin(phy_txmargin), .phy_txswing(phy_txswing),
        .phy_txdeemph(phy_txdeemph), .phy_txeq_ctrl(phy_txeq_ctrl),
        .phy_txeq_preset(phy_txeq_preset), .phy_txeq_coeff(phy_txeq_coeff),
        .phy_rxeq_ctrl(phy_rxeq_ctrl), .phy_rxeq_txpreset(phy_rxeq_txpreset),
        .as_mac_in_detect(as_mac_in_detect), .as_cdr_hold_req(as_cdr_hold_req),
        .tx_pkt_valid(mac_tx_valid), .tx_pkt_ready(mac_tx_ready),
        .tx_pkt_data(mac_tx_data), .tx_pkt_keep(mac_tx_keep),
        .tx_pkt_sop(mac_tx_sop), .tx_pkt_eop(mac_tx_eop),
        .tx_pkt_is_dllp(mac_tx_is_dllp), .tx_pkt_bad(mac_tx_bad),
        .rx_pkt_valid(mac_rx_valid), .rx_pkt_data(mac_rx_data),
        .rx_pkt_keep(mac_rx_keep), .rx_pkt_sop(mac_rx_sop),
        .rx_pkt_eop(mac_rx_eop), .rx_pkt_is_dllp(mac_rx_is_dllp),
        .rx_pkt_error(mac_rx_error), .link_disable(1'b0),
        .hot_reset_req(1'b0), .force_recovery(recovery_req),
        .ltssm_state(ltssm_state), .link_up(link_up),
        .negotiated_width(negotiated_width), .negotiated_speed(negotiated_speed),
        .link_number(link_number), .rx_ts_count(rx_ts_count),
        .training_error_count(training_error_count), .timeout_count(timeout_count),
        .frame_error_count(frame_error_count), .hot_reset_seen(hot_reset_seen)
    );

    k11a_offline_top #(.K11B2_ILA_DEBUG(K11B2_ILA_DEBUG)) u_protocol_core (
        .pipe_clk(phy_pclk), .pipe_rst_n(pipe_rst_n),
        .core_clk(phy_coreclk), .core_rst_n(core_rst_n),
        .link_up(link_up), .ltssm_state(ltssm_state),
        .link_speed(negotiated_speed), .link_width(negotiated_width),
        .hot_reset(hot_reset_seen),
        .dbg_link_loss_trigger(dbg_link_loss_core),
        .mac_rx_valid(mac_rx_valid), .mac_rx_data(mac_rx_data),
        .mac_rx_keep(mac_rx_keep), .mac_rx_sop(mac_rx_sop),
        .mac_rx_eop(mac_rx_eop), .mac_rx_is_dllp(mac_rx_is_dllp),
        .mac_rx_error(mac_rx_error), .mac_tx_valid(mac_tx_valid),
        .mac_tx_ready(mac_tx_ready), .mac_tx_data(mac_tx_data),
        .mac_tx_keep(mac_tx_keep), .mac_tx_sop(mac_tx_sop),
        .mac_tx_eop(mac_tx_eop), .mac_tx_is_dllp(mac_tx_is_dllp),
        .mac_tx_bad(mac_tx_bad), .dll_active(dll_active),
        .dll_fc_state(dll_fc_state), .recovery_req(recovery_req),
        .captured_bdf(captured_bdf), .bdf_valid(bdf_valid),
        .bar0_base(bar0_base), .memory_space_enable(memory_space_enable),
        .cdc_errors(cdc_errors)
    );

    always @(posedge phy_pclk or negedge pipe_rst_n) begin
        if (!pipe_rst_n)
            heartbeat_count <= 25'd0;
        else
            heartbeat_count <= heartbeat_count + 1'b1;
    end

    assign led[0] = pipe_rst_n && !phy_phystatus_rst;
    assign led[1] = link_up;
    assign led[2] = dll_active;
    assign led[3] = core_rst_n;
    assign led[4] = memory_space_enable;
    assign led[5] = bdf_valid;
    assign led[6] = (|cdc_errors) || recovery_req ||
                    (|training_error_count) || (|timeout_count) || (|frame_error_count);
    assign led[7] = heartbeat_count[24];

    wire _unused = &{1'b0, phy_userclk, phy_mcapclk, phy_rxstart_block,
        phy_rxsync_header, phy_txeq_fs, phy_txeq_lf, phy_txeq_new_coeff,
        phy_txeq_done, phy_rxeq_preset_sel, phy_rxeq_new_txcoeff,
        phy_rxeq_adapt_done, phy_rxeq_done, link_number, rx_ts_count};
endmodule

`default_nettype wire
