`timescale 1ns/1ps
`default_nettype none

// K13 production-path integration harness.  The DUT is the real LTSSM plus
// the real K13 controller and the same boundary muxes used by the board top.
// Gen1 PIPE input is driven by cocotb; after Rate=Gen3, a separate ordered-set
// transmitter acts as the behavioral PHY partner.
module k13_ltssm_partner_top #(
    parameter integer K13_RXEQ_BOOTSTRAP     = 1,
    parameter integer GEN1_RELEASE_GAP_CYCLES = 4   // 仿真加速：80 拍测试里压到 4 cycle
) (
    input  wire        phy_pclk,
    input  wire        core_clk,
    input  wire        pipe_rst_n,
    input  wire        core_rst_n,

    input  wire [31:0] phy_rxdata,
    input  wire [1:0]  phy_rxdatak,
    input  wire        phy_rxdata_valid,
    input  wire        phy_rxstart_block,
    input  wire [1:0]  phy_rxsync_header,
    input  wire        phy_rxvalid,
    input  wire        phy_phystatus,
    input  wire        phy_rxelecidle,
    input  wire [2:0]  phy_rxstatus,
    input  wire        phy_cdr_lost,
    input  wire        phy_txeq_done,
    input  wire        phy_rxeq_adapt_done,
    input  wire        phy_rxeq_done,
    input  wire        retrain_pulse,
    input  wire [1:0]  target_speed,
    input  wire        gen3_partner_enable,

    output wire [31:0] phy_txdata,
    output wire [1:0]  phy_txdatak,
    output wire        phy_txdata_valid,
    output wire        phy_txstart_block,
    output wire [1:0]  phy_txsync_header,
    output wire        phy_txdetectrx,
    output wire        phy_txelecidle,
    output wire [1:0]  phy_powerdown,
    output wire [1:0]  phy_rate,        // LTSSM 视图 = k13 active_rate (完成才变)
    output wire [1:0]  phy_rate_cmd,   // 仿真专用：contract 原始命令 (responder 触发源)
    output wire [1:0]  phy_txeq_ctrl,
    output wire [1:0]  phy_rxeq_ctrl,
    output wire [5:0]  ltssm_state,
    output wire        link_up,
    output wire [2:0]  negotiated_width,
    output wire [1:0]  negotiated_speed,
    output wire [4:0]  rx_ts_count,
    output wire [7:0]  dut_link_number,
    output wire [31:0] training_error_count,
    output wire [31:0] timeout_count,
    output wire [2:0]  speed_state,
    output wire        recovery_active,
    output wire        as_cdr_hold_req,
    output wire        eq_active,
    output wire        eq_done,
    output wire        eq_failed,
    output wire [2:0]  eq_phase,
    output wire        ts_accept,
    output wire        ts_reject,
    output wire        fallback_sticky,
    output wire        recovery_speed_ready,
    output wire        recovery_speed_done,    // 新 contract 架构下为 production_ctrl 输出
    output wire        recovery_speed_changed, // LTSSM 内部寄存器: RECOVERY_SPEED 状态已进入过
    output wire        speed_retrain_active,   // harness_recovery_force, 喂给 LTSSM 决定走 speed 路径
    output wire        os_ts1_valid,
    output wire        os_ts2_valid,
    output wire        os_malformed,
    // === os_rx 内部 FSM 调试探针 ===
    output wire        os_dbg_active,
    output wire [2:0]  os_dbg_word_index,
    // 新增 contract 调试信号
    output wire [1:0]  k13_active_rate,
    output wire [3:0]  rate_contract_state,
    output wire        rate_contract_busy,
    output wire        rate_contract_done,
    output wire        rate_contract_failed
);
    wire [7:0] link_number, os_link_number, os_lane_number;
    wire [7:0] os_rate_id, os_training_control;
    wire os_tx_complete;
    wire [1:0] ltssm_phy_rate;
    wire ltssm_phy_txelecidle;
    wire [1:0] ltssm_txeq_ctrl, ltssm_rxeq_ctrl;
    wire [3:0] ltssm_txeq_preset, ltssm_rxeq_txpreset;
    wire [5:0] ltssm_txeq_coeff;
    wire phy_txcompliance, phy_rxpolarity;
    wire [2:0] phy_txmargin;
    wire phy_txswing, phy_txdeemph;
    wire as_mac_in_detect;
    wire [15:0] rx_pkt_data;
    wire [1:0] rx_pkt_keep;
    wire rx_pkt_valid, rx_pkt_sop, rx_pkt_eop, rx_pkt_is_dllp;
    wire [3:0] rx_pkt_error;
    wire tx_pkt_ready;

    // 新接口：phy_rate_cmd (raw) + active_rate (only changes on completion)
    wire [1:0] k13_rate_cmd, k13_active_rate_w, k13_txeq_ctrl, k13_rxeq_ctrl;
    wire k13_txelecidle, traffic_quiesce;
    wire [1:0] phy_rate_w, phy_txeq_ctrl_w, phy_rxeq_ctrl_w;
    wire phy_txelecidle_w;
    wire [3:0] k13_txeq_preset, k13_rxeq_txpreset;
    wire [5:0] k13_txeq_coeff;
    wire [1:0] k13_negotiated_speed;
    wire cdr_loss_sticky, speed_timeout_sticky, illegal_ts_sticky;
    wire [3:0] ctrl_rate_state;
    wire ctrl_rate_busy, ctrl_rate_done, ctrl_rate_failed;
    // In the OFF A/B harness, EQ begins in the same cycle as Recovery.Idle.
    // Use the registered speed-state indication for LTSSM force-recovery so
    // that this test-only mux does not create a zero-time EQ feedback loop.
    //
    // 关键修正：force_recovery 必须覆盖整个 LTSSM Recovery 状态机
    // (RCVRLOCK=11 / RCVRCFG=12 / RECOVERY_SPEED=18 / RECOVERY_IDLE=13)。
    // 若仅靠 recovery_active，contract 在 RECOVERY_IDLE 看到第一个 ts_accept
    // 就跳回 L0，recovery_active↓→speed_retrain_active=0→RCVRCFG handler
    // 走 RECOVERY_IDLE 分支，永远到不了 RECOVERY_SPEED。
    wire ltssm_in_recovery = (ltssm_state == 6'd11) ||
                             (ltssm_state == 6'd12) ||
                             (ltssm_state == 6'd13) ||
                             (ltssm_state == 6'd18);
    wire harness_recovery_force = ltssm_in_recovery ||
                                  ((K13_RXEQ_BOOTSTRAP == 0) ?
                                   (speed_state != 3'd0) : recovery_active);
    // partner_enable: 主开关 = gen3_partner_enable (测试输入)
    // 仅在 RECOVERY_SPEED (18) / RECOVERY_IDLE (13) 启用——
    // RCVRLOCK (11) / RCVRCFG (12) 期间 LTSSM 用 Gen1 os_rx 解析 TS1/TS2,
    // 它没有解扰器, 必须接收 test 侧 send_ts() 发的未加扰 raw symbols。
    // partner 的 pcie_gen3_os_tx 加扰了 TS, 喂给 Gen1 os_rx 会被当作非法符号。
    wire partner_enable = gen3_partner_enable &&
                          ((ltssm_state == 6'd13) ||
                           (ltssm_state == 6'd18));
    // partner_mode 决定 Gen3 os_tx 发 TS1 还是 TS2:
    //   RCVRCFG(12)  -> TS2 (test 侧 send_ts 才是真正的 TS2, partner 此时未启用)
    //   RECOVERY_SPEED(18) -> TS2: speed_ctrl 的 peer_speed_ok 只在 ts2_accept_w
    //       (即 ts_guard 对 TS2 合法才置 1) 时完成. 之前 partner_mode=TS1 导致
    //       partner 只发 TS1, speed_ctrl 等不到 TS2, 永远卡在 ST_RECOVERY_IDLE.
    //   RECOVERY_IDLE(13) -> TS1 (LTSSM 期望 IDL, partner IDL 状态由 IDLE 模式处理)
    wire [1:0] partner_mode = ((ltssm_state == 6'd12) || (ltssm_state == 6'd18)) ? 2'd2 : 2'd1;
    wire [31:0] partner_data;
    wire partner_valid, partner_start;
    wire [1:0] partner_header;

    pcie_gen3_os_tx u_partner_tx (
        .clk(phy_pclk), .rst_n(pipe_rst_n), .enable(partner_enable),
        .mode(partner_mode), .link_number(link_number), .link_is_pad(1'b0),
        .lane_number(8'd0), .lane_is_pad(1'b0), .n_fts(8'hff),
        .rate_id(8'h0e), .training_control(8'h00),
        .out_data(partner_data), .out_valid(partner_valid),
        .start_block(partner_start), .sync_header(partner_header),
        .os_complete(), .word_index_debug()
    );

    wire [31:0] lt_rxdata = partner_enable ? partner_data : phy_rxdata;
    wire [1:0] lt_rxdatak = partner_enable ? 2'b00 : phy_rxdatak;
    wire lt_rxdata_valid = partner_enable ? partner_valid : phy_rxdata_valid;
    wire lt_rxstart_block = partner_enable ? partner_start : phy_rxstart_block;
    wire [1:0] lt_rxsync_header = partner_enable ? partner_header :
                                                           phy_rxsync_header;
    wire lt_rxvalid = partner_enable ? partner_valid : phy_rxvalid;
    wire lt_rxelecidle = partner_enable ? !partner_valid : phy_rxelecidle;

    function [1:0] decode_ts_rate(input [7:0] raw_rate_id);
        begin
            if (raw_rate_id[3]) decode_ts_rate = 2'b10;
            else if (raw_rate_id[2]) decode_ts_rate = 2'b01;
            else if (raw_rate_id[1]) decode_ts_rate = 2'b00;
            else decode_ts_rate = 2'b11;
        end
    endfunction

    wire partner_retrain_valid = link_up && os_ts1_valid && os_rate_id[7] &&
                                  (decode_ts_rate(os_rate_id) != 2'b11);

    pcie_k13_production_ctrl #(
        .K13_ENABLE(1), .K13_RXEQ_BOOTSTRAP(K13_RXEQ_BOOTSTRAP),
        .SPEED_TIMEOUT_CYCLES(2048),
        .EQ_TIMEOUT_CYCLES(64),
        .GEN1_RELEASE_GAP_CYCLES(GEN1_RELEASE_GAP_CYCLES)
    ) u_k13_ctrl (
        .core_clk(core_clk), .core_rst_n(core_rst_n),
        .phy_clk(phy_pclk), .phy_rst_n(pipe_rst_n), .link_up(link_up),
        .ltssm_speed_ready(recovery_speed_ready),
        .retrain_pulse(retrain_pulse), .target_speed(target_speed),
        .partner_retrain_valid(partner_retrain_valid),
        .partner_target_speed(decode_ts_rate(os_rate_id)),
        .phy_phystatus(phy_phystatus), .phy_cdr_lost(phy_cdr_lost),
        .phy_txeq_done(phy_txeq_done),
        .phy_rxeq_adapt_done(phy_rxeq_adapt_done),
        .phy_rxeq_done(phy_rxeq_done),
        // ts_valid: 原 os_rx 的 TS 1/2 解析完成脉冲，给 ts_guard 标记窗口。
        // ts_complete: 必须叠加 LTSSM recovery_speed_ready 门控——speed_ctrl
        //   在 ST_RECOVERY_IDLE 用 peer_speed_ok (=ts_accept_w) 跳回 L0;
        //   若不门控, RCVRCFG 内就能触发 peer_speed_ok, 合同在 RATE_WAIT
        //   尾拍 (rate_op_done 当拍) 就被推到 L0, recovery_active↓→
        //   speed_retrain_active=0→RCVRCFG 走 RECOVERY_IDLE 分支, 永远到不了
        //   RECOVERY_SPEED。等 LTSSM 真进 RECOVERY_SPEED (18) 才允许
        //   ts_accept_w 上升, contract 才能正确进入 ST_RECOVERY_IDLE 等
        //   RXEQ → 再走 peer_speed_ok → L0。
        .ts_valid(os_ts1_valid || os_ts2_valid),
        .ts_complete((os_ts1_valid || os_ts2_valid) &&
                     recovery_speed_ready),
        .ts_is_ts1(os_ts1_valid), .ts_is_ts2(os_ts2_valid),
        .ts_lane(os_lane_number[2:0]), .ts_link(os_link_number),
        .ts_rate(decode_ts_rate(os_rate_id)),
        .ts_eq_request((os_ts1_valid || os_ts2_valid) && os_rate_id[3]),
        .expected_lane(3'd0), .expected_link(link_number),
        // === 新 contract 接口 ===
        .phy_rate_cmd(k13_rate_cmd),
        .active_rate(k13_active_rate_w),
        .phy_txelecidle(k13_txelecidle),
        .phy_txeq_ctrl(k13_txeq_ctrl), .phy_txeq_preset(k13_txeq_preset),
        .phy_txeq_coeff(k13_txeq_coeff), .phy_rxeq_ctrl(k13_rxeq_ctrl),
        .phy_rxeq_txpreset(k13_rxeq_txpreset),
        .traffic_quiesce(traffic_quiesce), .recovery_active(recovery_active),
        .negotiated_speed(k13_negotiated_speed), .speed_state(speed_state),
        .eq_active(eq_active), .eq_done(eq_done), .eq_failed(eq_failed),
        .eq_phase(eq_phase), .ts_accept(ts_accept), .ts_reject(ts_reject),
        .cdr_loss_sticky(cdr_loss_sticky),
        .speed_timeout_sticky(speed_timeout_sticky),
        .fallback_sticky(fallback_sticky),
        .illegal_ts_sticky(illegal_ts_sticky),
        .recovery_speed_done(recovery_speed_done),
        // === contract 调试信号 ===
        .rate_contract_state(ctrl_rate_state),
        .rate_contract_busy(ctrl_rate_busy),
        .rate_contract_done(ctrl_rate_done),
        .rate_contract_failed(ctrl_rate_failed)
    );

    // 物理层契约：LTSSM 的 os_rx 解扰器必须用 raw phy_rate_cmd (我们要 PHY 切的速率)
    // 不能用 active_rate (只在 completion 后才更新)——否则 transition 期间
    // 解扰器仍按旧速率解扰, partner 发的 TS 全部 CRC 错。
    // active_rate 仅用于逻辑层 "已提交速率" 的查询, 不参与物理层信号选择。
    //
    // 例外：首次 RCVRLOCK/RCVRCFG 期间 TS1/TS2 按当前速率 (Gen1) 格式交换，
    // 不能切到 gen3_mode——否则 LTSSM 用 gen3_os_rx (处于 reset 状态,
    // link_is_pad=1, link_number=K_PAD) 解析 Gen1 TS, 永远返回 PAD,
    // RCVRLOCK handler 的 !os_link_is_pad 条件永假, rx_ts_count 卡在 0。
    // 第二次进 RCVRLOCK/RCVRCFG 时 TS 已经按 Gen3 加扰, 必须用 k13_rate_cmd
    // 让 gen3_os_rx 解扰。
    // 判定"是否第二次"用 k13_negotiated_speed：
    //   - speed_ctrl 在 RECOVERY_SPEED 看到对端 TS1/TS2 (peer_speed_ok)
    //     后才把 negotiated_speed 写到 Gen3, 并切回 L0;
    //   - LTSSM 同拍从 RECOVERY_SPEED→RCVRLOCK, 第二次 RCVRLOCK
    //     一开始 negotiated_speed 就已经 = Gen3, 此刻切到 k13_rate_cmd
    //     正好对应 Gen3 os_rx 接管。
    //   - contract active_rate 更早提交, 用它会把首次 RCVRLOCK 误判为
    //     第二次, 切到 Gen3 os_rx 但收到的还是 Gen1 raw TS, rx_ts_count 卡 0。
    wire ltssm_in_rcvr_lock_cfg = (ltssm_state == 6'd11) ||
                                   (ltssm_state == 6'd12);
    wire rate_committed = (k13_negotiated_speed != 2'b00);
    assign phy_rate_w = (ltssm_in_rcvr_lock_cfg && !rate_committed) ?
                        ltssm_phy_rate : k13_rate_cmd;
    assign phy_txelecidle_w = recovery_active ? k13_txelecidle :
                                              ltssm_phy_txelecidle;
    assign phy_txeq_ctrl_w = recovery_active ? k13_txeq_ctrl : ltssm_txeq_ctrl;
    assign phy_rxeq_ctrl_w = recovery_active ? k13_rxeq_ctrl : ltssm_rxeq_ctrl;
    assign phy_rate = phy_rate_w;
    assign phy_txelecidle = phy_txelecidle_w;
    assign phy_txeq_ctrl = phy_txeq_ctrl_w;
    assign phy_rxeq_ctrl = phy_rxeq_ctrl_w;
    assign negotiated_speed = (k13_negotiated_speed != 2'b00) ?
                              k13_negotiated_speed : 2'b00;
    assign k13_active_rate     = k13_active_rate_w;
    assign phy_rate_cmd        = k13_rate_cmd;
    assign rate_contract_state = ctrl_rate_state;
    assign rate_contract_busy  = ctrl_rate_busy;
    assign rate_contract_done  = ctrl_rate_done;
    assign rate_contract_failed = ctrl_rate_failed;

    pcie_ltssm_mac_gen1 #(
        .DETECT_QUIET_CYCLES(4), .DETECT_TIMEOUT_CYCLES(64),
        .TRAIN_TIMEOUT_CYCLES(10000), .HOT_RESET_CYCLES(8),
        .TX_RATE_ID(8'h0e),
        .K13_TEST_GEN1_OS_ONLY(1)
    ) u_ltssm (
        .phy_pclk(phy_pclk), .pipe_rst_n(pipe_rst_n),
        .phy_rxdata(lt_rxdata), .phy_rxdatak(lt_rxdatak),
        .phy_rxdata_valid(lt_rxdata_valid),
        .phy_rxstart_block(lt_rxstart_block),
        .phy_rxsync_header(lt_rxsync_header), .phy_rxvalid(lt_rxvalid),
        .phy_phystatus(phy_phystatus), .phy_rxelecidle(lt_rxelecidle),
        .phy_rxstatus(phy_rxstatus), .active_phy_rate(phy_rate_w),
        .phy_txdata(phy_txdata), .phy_txdatak(phy_txdatak),
        .phy_txdata_valid(phy_txdata_valid),
        .phy_txstart_block(phy_txstart_block),
        .phy_txsync_header(phy_txsync_header),
        .phy_txdetectrx(phy_txdetectrx),
        .phy_txelecidle(ltssm_phy_txelecidle),
        .phy_txcompliance(phy_txcompliance), .phy_rxpolarity(phy_rxpolarity),
        .phy_powerdown(phy_powerdown), .phy_rate(ltssm_phy_rate),
        .phy_txmargin(phy_txmargin), .phy_txswing(phy_txswing),
        .phy_txdeemph(phy_txdeemph), .phy_txeq_ctrl(ltssm_txeq_ctrl),
        .phy_txeq_preset(ltssm_txeq_preset),
        .phy_txeq_coeff(ltssm_txeq_coeff), .phy_rxeq_ctrl(ltssm_rxeq_ctrl),
        .phy_rxeq_txpreset(ltssm_rxeq_txpreset),
        .as_mac_in_detect(as_mac_in_detect),
        .as_cdr_hold_req(as_cdr_hold_req), .tx_pkt_valid(1'b0),
        .tx_pkt_ready(tx_pkt_ready), .tx_pkt_data(16'd0),
        .tx_pkt_keep(2'd0), .tx_pkt_sop(1'b0), .tx_pkt_eop(1'b0),
        .tx_pkt_is_dllp(1'b0), .tx_pkt_bad(1'b0),
        .rx_pkt_valid(rx_pkt_valid), .rx_pkt_data(rx_pkt_data),
        .rx_pkt_keep(rx_pkt_keep), .rx_pkt_sop(rx_pkt_sop),
        .rx_pkt_eop(rx_pkt_eop), .rx_pkt_is_dllp(rx_pkt_is_dllp),
        .rx_pkt_error(rx_pkt_error), .link_disable(1'b0),
        .hot_reset_req(1'b0), .force_recovery(harness_recovery_force),
        .speed_retrain_active(harness_recovery_force),
        .recovery_speed_done(recovery_speed_done),
        .recovery_speed_ready(recovery_speed_ready),
        .recovery_speed_changed(recovery_speed_changed),
        .ltssm_state(ltssm_state), .link_up(link_up),
        .negotiated_width(negotiated_width), .negotiated_speed(),
        .link_number(link_number), .rx_ts_count(rx_ts_count),
        .training_error_count(training_error_count),
        .timeout_count(timeout_count), .frame_error_count(),
        .hot_reset_seen(), .os_ts1_valid(os_ts1_valid),
        .os_ts2_valid(os_ts2_valid), .os_malformed(os_malformed),
        .os_dbg_active(os_dbg_active),
        .os_dbg_word_index(os_dbg_word_index),
        .os_link_number(os_link_number), .os_lane_number(os_lane_number),
        .os_rate_id(os_rate_id),
        .os_training_control(os_training_control),
        .os_tx_complete(os_tx_complete)
    );

    assign dut_link_number = link_number;
    assign speed_retrain_active = harness_recovery_force;
    wire _unused = &{1'b0, traffic_quiesce, cdr_loss_sticky,
        speed_timeout_sticky, illegal_ts_sticky, phy_txcompliance,
        phy_rxpolarity, phy_txmargin, phy_txswing, phy_txdeemph,
        as_mac_in_detect, as_cdr_hold_req, k13_txeq_preset,
        k13_txeq_coeff, k13_rxeq_txpreset, ltssm_txeq_preset,
        ltssm_txeq_coeff, ltssm_rxeq_txpreset, rx_pkt_valid, rx_pkt_data,
        rx_pkt_keep, rx_pkt_sop, rx_pkt_eop, rx_pkt_is_dllp, rx_pkt_error,
        tx_pkt_ready, os_training_control, os_tx_complete};
endmodule

`default_nettype wire
