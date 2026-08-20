`timescale 1ns/1ps
`default_nettype none

module pcie_ltssm_mac_gen1 #(
    // PIPE时钟硬件默认值；仿真通过参数覆盖缩短。
    parameter integer DETECT_QUIET_CYCLES   = 1_500_000,
    parameter integer DETECT_TIMEOUT_CYCLES = 3_000_000,
    parameter integer TRAIN_TIMEOUT_CYCLES  = 6_000_000,
    parameter integer HOT_RESET_CYCLES      = 250_000,
    parameter integer TX_BUFFER_BYTES       = 160,
    parameter integer K11B2_ILA_DEBUG       = 0,
    parameter [7:0]  TX_RATE_ID             = 8'h02,
    // G7仅用于上板A/B：Detect.Quiet保持P0，让Root Port在首次Detect前
    // 有完整窗口观察Endpoint接收终端；Detect.Active仍切到P1执行本端Detect。
    parameter integer G7_RX_P0_QUIET        = 0,
    // G9仅用于上板诊断：本端Receiver Detect成功并切到P0后，暂不发TS1，
    // 保持Detect assist，等待Root Port的RX activity。默认关闭。
    parameter integer G9_WAIT_REMOTE_DETECT = 0,
    // 默认按250 MHz PIPE时钟等待25 ms；上板若确认phy_pclk不同，可由构建参数覆盖。
    parameter integer G9_WAIT_REMOTE_DETECT_CYCLES = 6_250_000
) (
    input  wire        phy_pclk,
    input  wire        pipe_rst_n,
    input  wire [31:0] phy_rxdata,
    input  wire [1:0]  phy_rxdatak,
    input  wire        phy_rxdata_valid,
    input  wire        phy_rxstart_block,
    input  wire [1:0]  phy_rxsync_header,
    input  wire        phy_rxvalid,
    input  wire        phy_phystatus,
    input  wire        phy_rxelecidle,
    input  wire [2:0]  phy_rxstatus,
    input  wire [1:0]  active_phy_rate,
    input  wire [1:0]  recovery_target_rate,
    input  wire        recovery_fallback_active,

    output wire [31:0] phy_txdata,
    output wire [1:0]  phy_txdatak,
    output wire        phy_txdata_valid,
    output wire        phy_txstart_block,
    output wire [1:0]  phy_txsync_header,
    output wire        phy_txdetectrx,
    output wire        phy_txelecidle,
    output wire        phy_txcompliance,
    output wire        phy_rxpolarity,
    output wire [1:0]  phy_powerdown,
    output wire [1:0]  phy_rate,
    output wire [2:0]  phy_txmargin,
    output wire        phy_txswing,
    output wire        phy_txdeemph,
    output wire [1:0]  phy_txeq_ctrl,
    output wire [3:0]  phy_txeq_preset,
    output wire [5:0]  phy_txeq_coeff,
    output wire [1:0]  phy_rxeq_ctrl,
    output wire [3:0]  phy_rxeq_txpreset,
    output wire        as_mac_in_detect,
    output wire        as_cdr_hold_req,

    input  wire        tx_pkt_valid,
    output wire        tx_pkt_ready,
    input  wire [15:0] tx_pkt_data,
    input  wire [1:0]  tx_pkt_keep,
    input  wire        tx_pkt_sop,
    input  wire        tx_pkt_eop,
    input  wire        tx_pkt_is_dllp,
    input  wire        tx_pkt_bad,

    output wire        rx_pkt_valid,
    output wire [15:0] rx_pkt_data,
    output wire [1:0]  rx_pkt_keep,
    output wire        rx_pkt_sop,
    output wire        rx_pkt_eop,
    output wire        rx_pkt_is_dllp,
    output wire [3:0]  rx_pkt_error,

    input  wire        link_disable,
    input  wire        hot_reset_req,
    input  wire        force_recovery,
    input  wire        speed_retrain_active,
    input  wire        recovery_speed_done,
    output wire        recovery_speed_ready,
    output reg  [5:0]  ltssm_state,
    output wire        link_up,
    output wire [2:0]  negotiated_width,
    output wire [1:0]  negotiated_speed,
    output reg  [7:0]  link_number,
    output reg  [4:0]  rx_ts_count,
    output reg  [31:0] training_error_count,
    output reg  [31:0] timeout_count,
    output reg  [31:0] frame_error_count,
    output reg         hot_reset_seen,
    output wire        os_ts1_valid,
    output wire        os_ts2_valid,
    output wire        os_malformed,
    output wire [7:0]  os_link_number,
    output wire [7:0]  os_lane_number,
    output wire [7:0]  os_rate_id,
    output wire [7:0]  os_training_control,
    output wire        os_tx_complete,
    // Gen3 TS EQ tuple decoded by the ordered-set receiver.  Expose the
    // semantic fields to the K13 controller; callers must not infer an EQ
    // request from a Rate ID capability bit.
    output wire [7:0]  os_eq_control,
    output wire [23:0] os_eq_data
);
    localparam [5:0] DETECT_QUIET         = 6'd0;
    localparam [5:0] DETECT_ACTIVE        = 6'd1;
    localparam [5:0] POLLING_ACTIVE       = 6'd2;
    localparam [5:0] POLLING_CONFIG       = 6'd3;
    localparam [5:0] CFG_LINKWIDTH_START  = 6'd4;
    localparam [5:0] CFG_LINKWIDTH_ACCEPT = 6'd5;
    localparam [5:0] CFG_LANENUM_WAIT     = 6'd6;
    localparam [5:0] CFG_LANENUM_ACCEPT   = 6'd7;
    localparam [5:0] CFG_COMPLETE         = 6'd8;
    localparam [5:0] CFG_IDLE             = 6'd9;
    localparam [5:0] STATE_L0             = 6'd10;
    localparam [5:0] RECOVERY_RCVRLOCK    = 6'd11;
    localparam [5:0] RECOVERY_RCVRCFG     = 6'd12;
    localparam [5:0] RECOVERY_IDLE        = 6'd13;
    localparam [5:0] HOT_RESET            = 6'd14;
    // standalone PHY适配子状态：Receiver Detect在P1完成后，MAC先请求P0，
    // 并等待一次独立PhyStatus完成脉冲，之后才进入PCIe Polling.Active发TS1。
    localparam [5:0] PHY_POWERUP           = 6'd15;
    localparam [5:0] WAIT_REMOTE_DETECT    = 6'd16;
    localparam [5:0] G9_DETECT_TIMEOUT     = 6'd17;
    localparam [5:0] RECOVERY_SPEED        = 6'd18;

    localparam [31:0] DETECT_QUIET_LIMIT   = DETECT_QUIET_CYCLES - 1;
    localparam [31:0] DETECT_TIMEOUT_LIMIT = DETECT_TIMEOUT_CYCLES - 1;
    localparam [31:0] TRAIN_TIMEOUT_LIMIT  = TRAIN_TIMEOUT_CYCLES - 1;
    localparam [31:0] HOT_RESET_LIMIT      = HOT_RESET_CYCLES - 1;
    localparam [31:0] G9_WAIT_REMOTE_DETECT_LIMIT =
        G9_WAIT_REMOTE_DETECT_CYCLES - 1;
    localparam [4:0]  TS_REQUIRED          = 5'd8;
    localparam [4:0]  TS_ACCEPT_REQUIRED   = 5'd2;
    // Gen1 16-bit PHY 每个 TS 占 8 个 pclk。Configuration 的 Accept/Complete
    // 子状态即使已满足接收条件，也必须先发送至少 16 个对应 TS。
    localparam [31:0] MIN_CONFIG_TX_CYCLES = 32'd128;
    localparam [31:0] MIN_CONFIG_TX_LIMIT  = MIN_CONFIG_TX_CYCLES - 1'b1;
    localparam [7:0]  K_PAD                = 8'hf7;

    reg [31:0] state_timer;
    // G9结果锁存：用于在25 ms级等待结束后，通过ILA触发取证。
    reg        g9_rxelecidle_low_seen;
    reg        g9_timeout_seen;
    // G10 CFG_COMPLETE取证计数器：统计收到的TS2及字段匹配结果。
    reg [15:0] dbg_cfg_ts2_any_count;
    reg [15:0] dbg_cfg_ts2_match_count;
    reg [15:0] dbg_cfg_ts2_mismatch_count;
    reg [15:0] dbg_cfg_ts2_link_pad_count;
    reg [15:0] dbg_cfg_ts2_lane_pad_count;
    reg [15:0] dbg_cfg_ts2_link_mismatch_count;
    reg [15:0] dbg_cfg_ts2_lane_mismatch_count;
    reg        dbg_cfg_complete_seen;
    reg        dbg_cfg_idle_seen;
    reg        dbg_l0_seen;
    // G12-B：CFG_LANENUM_ACCEPT满足接收/时序条件后，等待当前TS1完整结束。
    reg        cfg_complete_pending;
    // 一次Recovery内只允许执行一次速率切换；PhyStatus完成后重新经过
    // RcvrLock/RcvrCfg，再进入Recovery.Idle/EQ。
    reg        recovery_speed_changed;
    // A later retrain after Gen1 fallback starts a new Recovery transaction;
    // clear the one-speed-per-recovery guard only on a new semantic request.
    reg        speed_retrain_active_q;
    // standalone PHY的RxElecIdle可能在L0出现很短的瞬态。连续8个pclk才
    // 认定对端进入Electrical Idle，避免本端单方面误入Recovery。
    reg [2:0] rxelecidle_count;
    // standalone pcie_phy在真实板上可能在RxElecIdle置位后继续把最后一拍
    // 标记为RxValid。只有没有有效接收字时，Electrical Idle才可用于L0退出。
    // 这样既过滤PHY状态的重叠窗口，又保留真正RxValid=0的Electrical Idle检测。
    wire rxelecidle_sample = phy_rxelecidle && !phy_rxvalid;
    wire rxelecidle_qualified = &rxelecidle_count;

    wire       os_raw_idle_pair_valid;
    wire       os_link_is_pad;
    wire       os_lane_is_pad;
    wire [7:0] os_n_fts;
    wire       gen3_mode = active_phy_rate == 2'b10;
    wire       gen1_os_ts1_valid, gen1_os_ts2_valid, gen1_os_malformed;
    wire [7:0] gen1_os_link_number, gen1_os_lane_number;
    wire [7:0] gen1_os_n_fts, gen1_os_rate_id, gen1_os_training_control;
    wire       gen1_os_link_is_pad, gen1_os_lane_is_pad;
    wire       gen3_os_ts1_valid, gen3_os_ts2_valid, gen3_os_malformed;
    wire [7:0] gen3_os_link_number, gen3_os_lane_number;
    wire [7:0] gen3_os_n_fts, gen3_os_rate_id, gen3_os_training_control;
    wire [7:0] gen3_os_eq_control;
    wire [23:0] gen3_os_eq_data;
    wire       gen3_os_link_is_pad, gen3_os_lane_is_pad;

    // PIPE/standalone PHY 的 RxDataValid 只用于 Gen3 128b/130b 数据块；
    // Gen1/2 的 8b/10b Symbol 有效性由 RxValid 指示。K03 固定 Gen1，因此不能
    // 用 phy_rxdata_valid 门控 Ordered Set，否则真实 PHY 会丢弃全部 TS1/TS2。
    wire        rx_phy_word_valid = phy_rxvalid;
    wire        rx_raw_aligned_valid;
    wire [15:0] rx_raw_aligned_data;
    wire [1:0]  rx_raw_aligned_datak;
    wire        rx_descrambled_valid;
    wire [15:0] rx_descrambled_data;
    wire [1:0]  rx_descrambled_datak;
    wire        rx_aligned_valid;
    wire [15:0] rx_aligned_data;
    wire [1:0]  rx_aligned_datak;
    wire        os_idle_pair_valid = rx_aligned_valid &&
                                     (rx_aligned_datak == 2'b00) &&
                                     (rx_aligned_data == 16'h0000);

    reg  [1:0] tx_os_mode;
    reg  [7:0] tx_os_link;
    reg        tx_os_link_pad;
    reg  [7:0] tx_os_lane;
    reg        tx_os_lane_pad;
    reg        tx_os_enable;
    reg  [7:0] tx_os_training_control;
    // Keep initial Gen1 Polling TS capability at TX_RATE_ID (02).  During a
    // directed Recovery speed change, advertise the higher-rate capability
    // together with the speed-change indication; advertising 0e from reset
    // makes the Xilinx Root Port model reject the initial Gen1 exchange.
    wire       advertise_gen3_rate = speed_retrain_active &&
                                     (recovery_target_rate == 2'b10);
    wire [7:0] tx_os_rate_id = TX_RATE_ID |
        (advertise_gen3_rate ? 8'h0c : 8'h00) |
        ((advertise_gen3_rate && (active_phy_rate != 2'b10) &&
          ((ltssm_state == RECOVERY_RCVRLOCK) ||
           (ltssm_state == RECOVERY_RCVRCFG))) ? 8'h80 : 8'h00);
    wire [31:0] os_tx_data;
    wire [1:0]  os_tx_datak;
    wire        os_tx_valid;
    wire        gen1_os_tx_complete;
    wire [2:0]  tx_os_word_index;
    wire [2:0]  tx_os_active_word_index;
    wire [31:0] gen3_os_tx_data;
    wire        gen3_os_tx_valid, gen3_os_tx_start_block;
    wire [1:0]  gen3_os_tx_sync_header;
    wire        gen3_os_tx_complete;
    wire [1:0]  gen3_os_tx_word_index;
    // Polling.Active中的TX只发送TS1；该事件对应一个完整的8拍TS1。
    wire        os_tx_ts1_complete = os_tx_complete && (tx_os_mode == 2'd1);
    reg  [10:0] polling_tx_ts1_count;
    wire        polling_rx_os_valid = (os_ts1_valid || os_ts2_valid) &&
                                      os_link_is_pad && os_lane_is_pad;
    // 允许最后一个RX Ordered Set与最后一个TX TS1完成事件在同一拍汇合。
    wire        polling_rx_ts_done = (rx_ts_count >= TS_REQUIRED) ||
                                     (polling_rx_os_valid &&
                                      (rx_ts_count >= TS_REQUIRED-1'b1));
    wire        polling_tx_ts1_done = (polling_tx_ts1_count >= 11'd1024) ||
                                      (os_tx_ts1_complete &&
                                       (polling_tx_ts1_count >= 11'd1023));

    generate if (K11B2_ILA_DEBUG != 0) begin : g_ila_debug_ltssm
        // PIPE域原始PHY、Ordered Set解析及LTSSM上下文，专用于链路退出取证。
        (* mark_debug = "true", keep = "true" *)
        wire [10:0] dbg_polling_tx_ts1_count = polling_tx_ts1_count;
        (* mark_debug = "true", keep = "true" *)
        wire [255:0] dbg_ltssm_detail = {
            61'd0, polling_tx_ts1_count, os_tx_ts1_complete,
            polling_tx_ts1_done, polling_rx_ts_done,
            link_disable, hot_reset_req, force_recovery,
            tx_os_mode, tx_os_link, tx_os_link_pad, tx_os_lane,
            tx_os_lane_pad, tx_os_training_control, os_tx_valid,
            ltssm_state, state_timer[15:0], rxelecidle_count,
            rxelecidle_qualified, os_ts1_valid, os_ts2_valid,
            os_malformed, os_raw_idle_pair_valid, os_link_number,
            os_link_is_pad, os_lane_number, os_lane_is_pad, os_n_fts,
            os_rate_id, os_training_control,
            phy_rxdata, phy_rxdatak, phy_rxvalid, phy_rxdata_valid,
            phy_rxelecidle, phy_rxstatus, phy_phystatus,
            phy_txdata, phy_txdatak, phy_txdata_valid, phy_txelecidle
        };
        (* mark_debug = "true", keep = "true" *)
        wire dbg_g9_active = (ltssm_state == WAIT_REMOTE_DETECT);
        (* mark_debug = "true", keep = "true" *)
        wire dbg_g9_rxelecidle_low_seen = g9_rxelecidle_low_seen;
        (* mark_debug = "true", keep = "true" *)
        wire dbg_g9_timeout_seen = g9_timeout_seen;
        // bit0 RXELECIDLE, bit1 RXVALID, bit2 TXELECIDLE, bit3 TXDETECTRX,
        // bit4 AS_MAC_IN_DETECT, bit[6:5] PHY_POWERDOWN, bit7 reserved.
        (* mark_debug = "true", keep = "true" *)
        wire [7:0] dbg_g9_control = {
            1'b0, phy_powerdown, as_mac_in_detect, phy_txdetectrx,
            phy_txelecidle, phy_rxvalid, phy_rxelecidle
        };
        // G10 counts: low-to-high fields are any, match, mismatch, link PAD,
        // lane PAD, link mismatch, lane mismatch, then state-entry latches.
        (* mark_debug = "true", keep = "true" *)
        wire [127:0] dbg_g10_counts = {
            13'd0, dbg_l0_seen, dbg_cfg_idle_seen, dbg_cfg_complete_seen,
            dbg_cfg_ts2_lane_mismatch_count,
            dbg_cfg_ts2_link_mismatch_count,
            dbg_cfg_ts2_lane_pad_count,
            dbg_cfg_ts2_link_pad_count,
            dbg_cfg_ts2_mismatch_count,
            dbg_cfg_ts2_match_count,
            dbg_cfg_ts2_any_count
        };
        // G10 fields: current decoded TS2 fields and the captured link number.
        (* mark_debug = "true", keep = "true" *)
        wire [63:0] dbg_g10_fields = {
            1'b0, phy_rxelecidle, phy_rxvalid, os_idle_pair_valid,
            (ltssm_state == CFG_COMPLETE),
            (os_ts2_valid && !os_link_is_pad && !os_lane_is_pad &&
             (os_link_number == link_number) && (os_lane_number == 0)),
            os_training_control, os_rate_id, os_n_fts,
            os_malformed, os_ts1_valid, os_ts2_valid,
            rx_ts_count, link_number, os_lane_is_pad, os_lane_number,
            os_link_is_pad, os_link_number
        };
        (* mark_debug = "true", keep = "true" *)
        wire [31:0] dbg_g10_state = {
            2'd0, dbg_l0_seen, dbg_cfg_idle_seen, dbg_cfg_complete_seen,
            ltssm_state, rx_ts_count, state_timer[15:0]
        };
        // G12-A：Ordered Set发送边界取证。
        // 低位到高位依次为LTSSM、TX mode、完成脉冲、原始/实际word index、TX valid。
        (* mark_debug = "true", keep = "true" *)
        wire [31:0] dbg_g12_tx = gen3_mode ?
            // Gen3复用为Root Port TS的EQ字段：高24位eq_data，低8位eq_control。
            // 该字段此前虽已解析，但生产K13尚未消费；实板取证后用于接线。
            {gen3_os_eq_data, gen3_os_eq_control} :
            {16'd0, os_tx_valid, tx_os_active_word_index, tx_os_word_index,
             os_tx_complete, tx_os_mode, ltssm_state};
        // G11：从PHY原始输入到Ordered Set解析器的逐级数据链路。
        // 低位到高位依次为OS脉冲、最终aligned、descrambled、raw aligned和PHY原始值。
        (* mark_debug = "true", keep = "true" *)
        wire [127:0] dbg_g11_rx = {
            28'd0,
            phy_rxdata,
            phy_rxdatak,
            phy_rxvalid,
            phy_rxdata_valid,
            phy_rxstatus,
            rx_raw_aligned_valid,
            rx_raw_aligned_data,
            rx_raw_aligned_datak,
            rx_descrambled_valid,
            rx_descrambled_data,
            rx_descrambled_datak,
            rx_aligned_valid,
            rx_aligned_data,
            rx_aligned_datak,
            os_ts1_valid,
            os_ts2_valid,
            os_malformed,
            os_raw_idle_pair_valid
        };
    end endgenerate

    wire [31:0] frame_tx_data;
    wire [1:0]  frame_tx_datak;
    wire        frame_tx_valid;
    wire        framer_error;
    wire        framer_enable = (ltssm_state == STATE_L0);
    wire [15:0] tx_plain_data = framer_enable ? frame_tx_data[15:0] :
                                                os_tx_data[15:0];
    wire [1:0]  tx_plain_datak = framer_enable ? frame_tx_datak : os_tx_datak;
    wire        tx_plain_valid = framer_enable ? frame_tx_valid : os_tx_valid;
    wire        tx_scramble_disable = !((ltssm_state == CFG_IDLE) ||
                                        (ltssm_state == STATE_L0) ||
                                        (ltssm_state == RECOVERY_IDLE));
    wire        tx_scrambled_valid;
    wire [15:0] tx_scrambled_data;
    wire [1:0]  tx_scrambled_datak;
    wire [15:0] tx_scrambler_state;
    wire [15:0] rx_scrambler_state;

    function automatic [31:0] sat_inc32(input [31:0] value);
        begin
            sat_inc32 = (&value) ? value : value + 1'b1;
        end
    endfunction

    function automatic [15:0] sat_inc16(input [15:0] value);
        begin
            sat_inc16 = (&value) ? value : value + 1'b1;
        end
    endfunction

    pcie_gen1_rx_symbol_aligner u_rx_symbol_aligner (
        .clk       (phy_pclk),
        .rst_n     (pipe_rst_n),
        .in_valid  (rx_phy_word_valid),
        .in_data   (phy_rxdata[15:0]),
        .in_datak  (phy_rxdatak),
        .out_valid (rx_raw_aligned_valid),
        .out_data  (rx_raw_aligned_data),
        .out_datak (rx_raw_aligned_datak)
    );

    pcie_gen12_scrambler u_rx_descrambler (
        .clk              (phy_pclk),
        .rst_n            (pipe_rst_n),
        .in_valid         (rx_phy_word_valid),
        .scramble_disable (tx_scramble_disable),
        .in_data          (phy_rxdata[15:0]),
        .in_datak         (phy_rxdatak),
        .out_valid        (rx_descrambled_valid),
        .out_data         (rx_descrambled_data),
        .out_datak        (rx_descrambled_datak),
        .lfsr_state       (rx_scrambler_state)
    );

    pcie_gen1_rx_symbol_aligner u_rx_descrambled_symbol_aligner (
        .clk       (phy_pclk),
        .rst_n     (pipe_rst_n),
        .in_valid  (rx_descrambled_valid),
        .in_data   (rx_descrambled_data),
        .in_datak  (rx_descrambled_datak),
        .out_valid (rx_aligned_valid),
        .out_data  (rx_aligned_data),
        .out_datak (rx_aligned_datak)
    );

    pcie_gen1_os_rx u_os_rx (
        .clk              (phy_pclk),
        .rst_n            (pipe_rst_n),
        .enable           (1'b1),
        .in_valid         (rx_raw_aligned_valid),
        .in_data          (rx_raw_aligned_data),
        .in_datak         (rx_raw_aligned_datak),
        .ts1_valid        (gen1_os_ts1_valid),
        .ts2_valid        (gen1_os_ts2_valid),
        .malformed        (gen1_os_malformed),
        .idle_pair_valid  (os_raw_idle_pair_valid),
        .link_number      (gen1_os_link_number),
        .link_is_pad      (gen1_os_link_is_pad),
        .lane_number      (gen1_os_lane_number),
        .lane_is_pad      (gen1_os_lane_is_pad),
        .n_fts            (gen1_os_n_fts),
        .rate_id          (gen1_os_rate_id),
        .training_control (gen1_os_training_control)
    );

    pcie_gen3_os_rx u_gen3_os_rx (
        .clk(phy_pclk), .rst_n(pipe_rst_n), .enable(gen3_mode),
        .in_valid(phy_rxdata_valid), .start_block(phy_rxstart_block),
        .sync_header(phy_rxsync_header), .in_data(phy_rxdata),
        .ts1_valid(gen3_os_ts1_valid), .ts2_valid(gen3_os_ts2_valid),
        .malformed(gen3_os_malformed),
        .link_number(gen3_os_link_number), .link_is_pad(gen3_os_link_is_pad),
        .lane_number(gen3_os_lane_number), .lane_is_pad(gen3_os_lane_is_pad),
        .n_fts(gen3_os_n_fts), .rate_id(gen3_os_rate_id),
        .training_control(gen3_os_training_control),
        .eq_control(gen3_os_eq_control), .eq_data(gen3_os_eq_data)
    );

    assign os_ts1_valid = gen3_mode ? gen3_os_ts1_valid : gen1_os_ts1_valid;
    assign os_ts2_valid = gen3_mode ? gen3_os_ts2_valid : gen1_os_ts2_valid;
    assign os_malformed = gen3_mode ? gen3_os_malformed : gen1_os_malformed;
    assign os_link_number = gen3_mode ? gen3_os_link_number : gen1_os_link_number;
    assign os_link_is_pad = gen3_mode ? gen3_os_link_is_pad : gen1_os_link_is_pad;
    assign os_lane_number = gen3_mode ? gen3_os_lane_number : gen1_os_lane_number;
    assign os_lane_is_pad = gen3_mode ? gen3_os_lane_is_pad : gen1_os_lane_is_pad;
    assign os_n_fts = gen3_mode ? gen3_os_n_fts : gen1_os_n_fts;
    assign os_rate_id = gen3_mode ? gen3_os_rate_id : gen1_os_rate_id;
    assign os_training_control = gen3_mode ? gen3_os_training_control :
                                             gen1_os_training_control;
    assign os_eq_control = gen3_mode ? gen3_os_eq_control : 8'd0;
    assign os_eq_data = gen3_mode ? gen3_os_eq_data : 24'd0;

    pcie_gen1_os_tx u_os_tx (
        .clk              (phy_pclk),
        .rst_n            (pipe_rst_n),
        .enable           (tx_os_enable),
        .mode             (tx_os_mode),
        .link_number      (tx_os_link),
        .link_is_pad      (tx_os_link_pad),
        .lane_number      (tx_os_lane),
        .lane_is_pad      (tx_os_lane_pad),
        .n_fts            (8'hff),
        // TX_RATE_ID是能力位图；Recovery速率切换期间bit7必须置位，
        // 否则对端只执行同速率Recovery，不会改变PIPE Rate。
        .rate_id          (tx_os_rate_id),
        .training_control (tx_os_training_control),
        .out_data         (os_tx_data),
        .out_datak        (os_tx_datak),
        .out_valid        (os_tx_valid),
        .os_complete      (gen1_os_tx_complete),
        .word_index_debug (tx_os_word_index),
        .active_word_index_debug(tx_os_active_word_index)
    );

    pcie_gen3_os_tx u_gen3_os_tx (
        .clk(phy_pclk), .rst_n(pipe_rst_n),
        .enable(gen3_mode && tx_os_enable), .mode(tx_os_mode),
        .link_number(tx_os_link), .link_is_pad(tx_os_link_pad),
        .lane_number(tx_os_lane), .lane_is_pad(tx_os_lane_pad),
        .n_fts(8'hff), .rate_id(tx_os_rate_id),
        .training_control(tx_os_training_control),
        .out_data(gen3_os_tx_data), .out_valid(gen3_os_tx_valid),
        .start_block(gen3_os_tx_start_block),
        .sync_header(gen3_os_tx_sync_header),
        .os_complete(gen3_os_tx_complete),
        .word_index_debug(gen3_os_tx_word_index)
    );

    assign os_tx_complete = gen3_mode ? gen3_os_tx_complete :
                                            gen1_os_tx_complete;

    pcie_gen12_scrambler u_tx_scrambler (
        .clk              (phy_pclk),
        .rst_n            (pipe_rst_n),
        .in_valid         (tx_plain_valid),
        .scramble_disable (tx_scramble_disable),
        .in_data          (tx_plain_data),
        .in_datak         (tx_plain_datak),
        .out_valid        (tx_scrambled_valid),
        .out_data         (tx_scrambled_data),
        .out_datak        (tx_scrambled_datak),
        .lfsr_state       (tx_scrambler_state)
    );

    pcie_gen1_framer #(
        .TX_BUFFER_BYTES (TX_BUFFER_BYTES)
    ) u_framer (
        .clk              (phy_pclk),
        .rst_n            (pipe_rst_n),
        .enable           (framer_enable),
        .tx_pkt_valid     (tx_pkt_valid),
        .tx_pkt_ready     (tx_pkt_ready),
        .tx_pkt_data      (tx_pkt_data),
        .tx_pkt_keep      (tx_pkt_keep),
        .tx_pkt_sop       (tx_pkt_sop),
        .tx_pkt_eop       (tx_pkt_eop),
        .tx_pkt_is_dllp   (tx_pkt_is_dllp),
        .tx_pkt_bad       (tx_pkt_bad),
        .rx_phy_valid     (rx_aligned_valid && framer_enable),
        .rx_phy_data      (rx_aligned_data),
        .rx_phy_datak     (rx_aligned_datak),
        .tx_phy_data      (frame_tx_data),
        .tx_phy_datak     (frame_tx_datak),
        .tx_phy_valid     (frame_tx_valid),
        .rx_pkt_valid     (rx_pkt_valid),
        .rx_pkt_data      (rx_pkt_data),
        .rx_pkt_keep      (rx_pkt_keep),
        .rx_pkt_sop       (rx_pkt_sop),
        .rx_pkt_eop       (rx_pkt_eop),
        .rx_pkt_is_dllp   (rx_pkt_is_dllp),
        .rx_pkt_error     (rx_pkt_error),
        .frame_error_pulse(framer_error)
    );

    always @* begin
        tx_os_mode     = 2'd0;
        tx_os_link     = link_number;
        tx_os_link_pad = 1'b0;
        tx_os_lane     = 8'd0;
        tx_os_lane_pad = 1'b0;
        tx_os_enable   = 1'b1;
        tx_os_training_control = 8'h00;
        case (ltssm_state)
            DETECT_QUIET, DETECT_ACTIVE, PHY_POWERUP,
            WAIT_REMOTE_DETECT, G9_DETECT_TIMEOUT: begin
                tx_os_enable   = 1'b0;
                tx_os_link_pad = 1'b1;
                tx_os_lane_pad = 1'b1;
            end
            HOT_RESET: begin
                // Upstream Component在Hot Reset保持期回送带Hot Reset位的TS1。
                tx_os_mode             = 2'd1;
                tx_os_training_control = 8'h01;
            end
            POLLING_ACTIVE, CFG_LINKWIDTH_START: begin
                tx_os_mode     = 2'd1;
                tx_os_link_pad = 1'b1;
                tx_os_lane_pad = 1'b1;
            end
            POLLING_CONFIG: begin
                tx_os_mode     = 2'd2;
                tx_os_link_pad = 1'b1;
                tx_os_lane_pad = 1'b1;
            end
            CFG_LINKWIDTH_ACCEPT, CFG_LANENUM_WAIT: begin
                tx_os_mode     = 2'd1;
                tx_os_link_pad = 1'b0;
                tx_os_lane_pad = 1'b1;
            end
            CFG_LANENUM_ACCEPT, RECOVERY_RCVRLOCK: tx_os_mode = 2'd1;
            CFG_COMPLETE, RECOVERY_RCVRCFG:       tx_os_mode = 2'd2;
            RECOVERY_SPEED: begin
                tx_os_enable = 1'b0;
            end
            default:                              tx_os_mode = 2'd0;
        endcase
    end

    assign phy_txdata         = gen3_mode ? gen3_os_tx_data :
                                             {16'd0, tx_scrambled_data};
    assign phy_txdatak        = tx_scrambled_datak;
    assign phy_txdata_valid   = gen3_mode ? gen3_os_tx_valid :
                                             tx_scrambled_valid;
    assign phy_txstart_block  = gen3_mode && gen3_os_tx_start_block;
    assign phy_txsync_header  = gen3_mode ? gen3_os_tx_sync_header : 2'b00;
    assign phy_txdetectrx     = (ltssm_state == DETECT_ACTIVE);
    assign phy_txelecidle     = (ltssm_state == DETECT_QUIET) ||
                                (ltssm_state == DETECT_ACTIVE) ||
                                (ltssm_state == PHY_POWERUP) ||
                                (ltssm_state == WAIT_REMOTE_DETECT) ||
                                (ltssm_state == G9_DETECT_TIMEOUT);
    assign phy_txcompliance   = 1'b0;
    assign phy_rxpolarity     = 1'b0;
    // Receiver Detect必须在P1执行；Detect成功后的PHY_POWERUP已请求P0，
    // 但在第二个PhyStatus到达前仍保持TX Electrical Idle且不提交数据。
    assign phy_powerdown      = (ltssm_state == DETECT_ACTIVE) ? 2'b10 :
                                ((ltssm_state == DETECT_QUIET) &&
                                 (G7_RX_P0_QUIET == 0)) ? 2'b10 : 2'b00;
    assign phy_rate           = 2'b00;
    assign phy_txmargin       = 3'b000;
    assign phy_txswing        = 1'b0;
    assign phy_txdeemph       = 1'b0;
    assign phy_txeq_ctrl      = 2'b00;
    assign phy_txeq_preset    = 4'd0;
    assign phy_txeq_coeff     = 6'd0;
    assign phy_rxeq_ctrl      = 2'b00;
    assign phy_rxeq_txpreset  = 4'd0;
    assign as_mac_in_detect   = (ltssm_state == DETECT_QUIET) ||
                                (ltssm_state == DETECT_ACTIVE) ||
                                (ltssm_state == WAIT_REMOTE_DETECT) ||
                                (ltssm_state == G9_DETECT_TIMEOUT);
    // PG239 PHY assist contract: hold the RX CDR while the LTSSM is
    // changing rate in Recovery.Speed.  The current MAC does not yet
    // implement the L1/Loopback states, so Recovery.Speed is the only
    // applicable state in this integration.
    assign as_cdr_hold_req    = (ltssm_state == RECOVERY_SPEED);
    assign link_up            = (ltssm_state == STATE_L0);
    assign negotiated_width   = ((ltssm_state >= STATE_L0 &&
                                  ltssm_state <= RECOVERY_IDLE) ||
                                 (ltssm_state == RECOVERY_SPEED)) ? 3'd1 : 3'd0;
    assign negotiated_speed   = 2'b00;
    assign recovery_speed_ready = (ltssm_state == RECOVERY_SPEED);

    always @(posedge phy_pclk or negedge pipe_rst_n) begin
        if (!pipe_rst_n) begin
            ltssm_state         <= DETECT_QUIET;
            state_timer         <= 32'd0;
            rx_ts_count         <= 5'd0;
            polling_tx_ts1_count <= 11'd0;
            link_number         <= K_PAD;
            training_error_count <= 32'd0;
            timeout_count       <= 32'd0;
            frame_error_count   <= 32'd0;
            hot_reset_seen      <= 1'b0;
            rxelecidle_count    <= 3'd0;
            g9_rxelecidle_low_seen <= 1'b0;
            g9_timeout_seen        <= 1'b0;
            dbg_cfg_ts2_any_count <= 16'd0;
            dbg_cfg_ts2_match_count <= 16'd0;
            dbg_cfg_ts2_mismatch_count <= 16'd0;
            dbg_cfg_ts2_link_pad_count <= 16'd0;
            dbg_cfg_ts2_lane_pad_count <= 16'd0;
            dbg_cfg_ts2_link_mismatch_count <= 16'd0;
            dbg_cfg_ts2_lane_mismatch_count <= 16'd0;
            dbg_cfg_complete_seen <= 1'b0;
            dbg_cfg_idle_seen <= 1'b0;
            dbg_l0_seen <= 1'b0;
            cfg_complete_pending <= 1'b0;
            recovery_speed_changed <= 1'b0;
            speed_retrain_active_q <= 1'b0;
        end else begin
            hot_reset_seen <= 1'b0;
            if (speed_retrain_active && !speed_retrain_active_q)
                recovery_speed_changed <= 1'b0;
            speed_retrain_active_q <= speed_retrain_active;
            if (ltssm_state == CFG_COMPLETE)
                dbg_cfg_complete_seen <= 1'b1;
            if (ltssm_state == CFG_IDLE)
                dbg_cfg_idle_seen <= 1'b1;
            if (ltssm_state == STATE_L0)
                dbg_l0_seen <= 1'b1;
            if ((ltssm_state != STATE_L0) || !rxelecidle_sample)
                rxelecidle_count <= 3'd0;
            else if (!rxelecidle_qualified)
                rxelecidle_count <= rxelecidle_count + 1'b1;
            if (framer_error)
                frame_error_count <= sat_inc32(frame_error_count);
            if (os_malformed)
                training_error_count <= sat_inc32(training_error_count);

            if ((ltssm_state == WAIT_REMOTE_DETECT) && !phy_rxelecidle)
                g9_rxelecidle_low_seen <= 1'b1;

            if (link_disable) begin
                ltssm_state <= DETECT_QUIET;
                state_timer <= 32'd0;
                rx_ts_count <= 5'd0;
                polling_tx_ts1_count <= 11'd0;
                link_number <= K_PAD;
                g9_rxelecidle_low_seen <= 1'b0;
                g9_timeout_seen <= 1'b0;
                dbg_cfg_ts2_any_count <= 16'd0;
                dbg_cfg_ts2_match_count <= 16'd0;
                dbg_cfg_ts2_mismatch_count <= 16'd0;
                dbg_cfg_ts2_link_pad_count <= 16'd0;
                dbg_cfg_ts2_lane_pad_count <= 16'd0;
                dbg_cfg_ts2_link_mismatch_count <= 16'd0;
                dbg_cfg_ts2_lane_mismatch_count <= 16'd0;
                dbg_cfg_complete_seen <= 1'b0;
                dbg_cfg_idle_seen <= 1'b0;
                dbg_l0_seen <= 1'b0;
                recovery_speed_changed <= 1'b0;
                speed_retrain_active_q <= 1'b0;
            end else begin
                case (ltssm_state)
                    DETECT_QUIET: begin
                        rx_ts_count <= 5'd0;
                        polling_tx_ts1_count <= 11'd0;
                        if (state_timer >= DETECT_QUIET_LIMIT) begin
                            ltssm_state <= DETECT_ACTIVE;
                            state_timer <= 32'd0;
                        end else begin
                            state_timer <= state_timer + 1'b1;
                        end
                    end
                    DETECT_ACTIVE: begin
                        polling_tx_ts1_count <= 11'd0;
                        if (phy_phystatus) begin
                            state_timer <= 32'd0;
                            rx_ts_count <= 5'd0;
                            if (phy_rxstatus == 3'b011) begin
                                ltssm_state <= PHY_POWERUP;
                            end else begin
                                ltssm_state <= DETECT_QUIET;
                                training_error_count <= sat_inc32(training_error_count);
                            end
                        end else if (state_timer >= DETECT_TIMEOUT_LIMIT) begin
                            ltssm_state <= DETECT_QUIET;
                            state_timer <= 32'd0;
                            timeout_count <= sat_inc32(timeout_count);
                        end else begin
                            state_timer <= state_timer + 1'b1;
                        end
                    end
                    PHY_POWERUP: begin
                        rx_ts_count <= 5'd0;
                        polling_tx_ts1_count <= 11'd0;
                        if (phy_phystatus) begin
                            ltssm_state <= (G9_WAIT_REMOTE_DETECT != 0) ?
                                            WAIT_REMOTE_DETECT : POLLING_ACTIVE;
                            state_timer <= 32'd0;
                        end else if (state_timer >= DETECT_TIMEOUT_LIMIT) begin
                            ltssm_state <= DETECT_QUIET;
                            state_timer <= 32'd0;
                            timeout_count <= sat_inc32(timeout_count);
                        end else begin
                            state_timer <= state_timer + 1'b1;
                        end
                    end
                    WAIT_REMOTE_DETECT: begin
                        // G9诊断窗口：P0 + TX Electrical Idle + Detect assist，
                        // 不执行本端Receiver Detect，也不发送TS1。
                        rx_ts_count <= 5'd0;
                        polling_tx_ts1_count <= 11'd0;
                        if (!phy_rxelecidle) begin
                            ltssm_state <= POLLING_ACTIVE;
                            state_timer <= 32'd0;
                        end else if (state_timer >= G9_WAIT_REMOTE_DETECT_LIMIT) begin
                            ltssm_state <= G9_DETECT_TIMEOUT;
                            state_timer <= 32'd0;
                            g9_timeout_seen <= 1'b1;
                            timeout_count <= sat_inc32(timeout_count);
                        end else begin
                            state_timer <= state_timer + 1'b1;
                        end
                    end
                    G9_DETECT_TIMEOUT: begin
                        // 诊断失败后停留，保持控制信号可被ILA观察；等待外部复位。
                        rx_ts_count <= 5'd0;
                        polling_tx_ts1_count <= 11'd0;
                        state_timer <= state_timer;
                    end
                    POLLING_ACTIVE: begin
                        state_timer <= state_timer + 1'b1;
                        if (os_tx_ts1_complete && (polling_tx_ts1_count < 11'd1024))
                            polling_tx_ts1_count <= polling_tx_ts1_count + 1'b1;

                        if (polling_rx_os_valid) begin
                            // Polling.Active要求连续8个TS1或TS2；计数饱和，
                            // 使RX条件一旦满足即可等待TX条件，不必碰巧同拍汇合。
                            if (rx_ts_count < TS_REQUIRED)
                                rx_ts_count <= rx_ts_count + 1'b1;
                            if (polling_rx_ts_done && polling_tx_ts1_done) begin
                                ltssm_state <= POLLING_CONFIG;
                                state_timer <= 32'd0;
                                rx_ts_count <= 5'd0;
                            end
                        end else if (os_ts1_valid || os_ts2_valid || os_malformed) begin
                            rx_ts_count <= 5'd0;
                            if (os_ts1_valid || os_ts2_valid)
                                training_error_count <= sat_inc32(training_error_count);
                        end
                        if (state_timer >= TRAIN_TIMEOUT_LIMIT) begin
                            ltssm_state <= DETECT_QUIET;
                            state_timer <= 32'd0;
                            rx_ts_count <= 5'd0;
                            polling_tx_ts1_count <= 11'd0;
                            timeout_count <= sat_inc32(timeout_count);
                        end
                    end
                    POLLING_CONFIG: begin
                        state_timer <= state_timer + 1'b1;
                        if (os_ts2_valid && os_link_is_pad && os_lane_is_pad) begin
                            if (rx_ts_count == TS_REQUIRED-1'b1) begin
                                ltssm_state <= CFG_LINKWIDTH_START;
                                state_timer <= 32'd0;
                                rx_ts_count <= 5'd0;
                            end else rx_ts_count <= rx_ts_count + 1'b1;
                        end else if (os_ts2_valid) begin
                            rx_ts_count <= 5'd0;
                            training_error_count <= sat_inc32(training_error_count);
                        end else if (os_ts1_valid) begin
                            // 对端允许在状态交接期间继续发送上一状态的合法TS1。
                            // 它只打断连续TS2计数，不属于训练错误。
                            rx_ts_count <= 5'd0;
                        end
                        if (state_timer >= TRAIN_TIMEOUT_LIMIT) begin
                            ltssm_state <= DETECT_QUIET;
                            state_timer <= 32'd0;
                            rx_ts_count <= 5'd0;
                            timeout_count <= sat_inc32(timeout_count);
                        end
                    end
                    CFG_LINKWIDTH_START: begin
                        state_timer <= state_timer + 1'b1;
                        if (os_ts1_valid && !os_link_is_pad && os_lane_is_pad) begin
                            link_number <= os_link_number;
                            ltssm_state <= CFG_LINKWIDTH_ACCEPT;
                            state_timer <= 32'd0;
                            rx_ts_count <= 5'd0;
                        end else if (os_ts1_valid || os_ts2_valid) begin
                            training_error_count <= sat_inc32(training_error_count);
                        end
                        if (state_timer >= TRAIN_TIMEOUT_LIMIT) begin
                            ltssm_state <= DETECT_QUIET;
                            state_timer <= 32'd0;
                            timeout_count <= sat_inc32(timeout_count);
                        end
                    end
                    CFG_LINKWIDTH_ACCEPT: begin
                        state_timer <= state_timer + 1'b1;
                        if (os_ts1_valid && !os_link_is_pad && os_lane_is_pad &&
                            (os_link_number == link_number)) begin
                            if (rx_ts_count < TS_ACCEPT_REQUIRED)
                                rx_ts_count <= rx_ts_count + 1'b1;
                        end else if ((os_ts1_valid || os_ts2_valid) &&
                                     (rx_ts_count < TS_ACCEPT_REQUIRED)) begin
                            // 接收门槛满足后锁存结果。对端可能先进入下一子状态，
                            // 此时仍需把本端规定的16个TS1发送完，不能清零条件。
                            rx_ts_count <= 5'd0;
                            training_error_count <= sat_inc32(training_error_count);
                        end
                        if ((rx_ts_count >= TS_ACCEPT_REQUIRED) &&
                            (state_timer >= MIN_CONFIG_TX_LIMIT)) begin
                            ltssm_state <= CFG_LANENUM_WAIT;
                            state_timer <= 32'd0;
                            rx_ts_count <= 5'd0;
                            cfg_complete_pending <= 1'b0;
                        end else if (state_timer >= TRAIN_TIMEOUT_LIMIT) begin
                            ltssm_state <= DETECT_QUIET;
                            state_timer <= 32'd0;
                            rx_ts_count <= 5'd0;
                            timeout_count <= sat_inc32(timeout_count);
                        end
                    end
                    CFG_LANENUM_WAIT: begin
                        state_timer <= state_timer + 1'b1;
                        if (os_ts1_valid && !os_link_is_pad && !os_lane_is_pad &&
                            (os_link_number == link_number) && (os_lane_number == 0)) begin
                            ltssm_state <= CFG_LANENUM_ACCEPT;
                            state_timer <= 32'd0;
                            rx_ts_count <= 5'd0;
                            cfg_complete_pending <= 1'b0;
                        end else if (os_ts1_valid || os_ts2_valid) begin
                            training_error_count <= sat_inc32(training_error_count);
                        end
                        if (state_timer >= TRAIN_TIMEOUT_LIMIT) begin
                            ltssm_state <= DETECT_QUIET;
                            state_timer <= 32'd0;
                            timeout_count <= sat_inc32(timeout_count);
                        end
                    end
                    CFG_LANENUM_ACCEPT: begin
                        state_timer <= state_timer + 1'b1;
                        if (os_ts1_valid && !os_link_is_pad && !os_lane_is_pad &&
                            (os_link_number == link_number) && (os_lane_number == 0)) begin
                            if (rx_ts_count < TS_ACCEPT_REQUIRED)
                                rx_ts_count <= rx_ts_count + 1'b1;
                        end else if ((os_ts1_valid || os_ts2_valid) &&
                                     (rx_ts_count < TS_ACCEPT_REQUIRED)) begin
                            // 与 Linkwidth.Accept 相同：接收条件满足后保持，直到
                            // 本端16个TS1发送门槛同时满足。
                            rx_ts_count <= 5'd0;
                            training_error_count <= sat_inc32(training_error_count);
                        end
                        // 接收门槛和最小时序满足后，不立即切换TX mode；先等待
                        // 当前TS1的最后一个word，避免TS1/TS2在Ordered Set中间拼接。
                        if ((rx_ts_count >= TS_ACCEPT_REQUIRED) &&
                            (state_timer >= MIN_CONFIG_TX_LIMIT)) begin
                            cfg_complete_pending <= 1'b1;
                        end
                        if ((cfg_complete_pending ||
                             ((rx_ts_count >= TS_ACCEPT_REQUIRED) &&
                              (state_timer >= MIN_CONFIG_TX_LIMIT))) &&
                            os_tx_complete) begin
                            ltssm_state <= CFG_COMPLETE;
                            state_timer <= 32'd0;
                            rx_ts_count <= 5'd0;
                            cfg_complete_pending <= 1'b0;
                        end else if (state_timer >= TRAIN_TIMEOUT_LIMIT) begin
                            ltssm_state <= DETECT_QUIET;
                            state_timer <= 32'd0;
                            rx_ts_count <= 5'd0;
                            timeout_count <= sat_inc32(timeout_count);
                            cfg_complete_pending <= 1'b0;
                        end
                    end
                    CFG_COMPLETE: begin
                        cfg_complete_pending <= 1'b0;
                        state_timer <= state_timer + 1'b1;
                        if (os_ts2_valid) begin
                            dbg_cfg_ts2_any_count <= sat_inc16(dbg_cfg_ts2_any_count);
                            if (os_link_is_pad)
                                dbg_cfg_ts2_link_pad_count <= sat_inc16(dbg_cfg_ts2_link_pad_count);
                            if (os_lane_is_pad)
                                dbg_cfg_ts2_lane_pad_count <= sat_inc16(dbg_cfg_ts2_lane_pad_count);
                            if (os_link_number != link_number)
                                dbg_cfg_ts2_link_mismatch_count <= sat_inc16(dbg_cfg_ts2_link_mismatch_count);
                            if (os_lane_number != 0)
                                dbg_cfg_ts2_lane_mismatch_count <= sat_inc16(dbg_cfg_ts2_lane_mismatch_count);
                        end
                        if (os_ts2_valid && !os_link_is_pad && !os_lane_is_pad &&
                            (os_link_number == link_number) && (os_lane_number == 0)) begin
                            dbg_cfg_ts2_match_count <= sat_inc16(dbg_cfg_ts2_match_count);
                            if (rx_ts_count < TS_REQUIRED)
                                rx_ts_count <= rx_ts_count + 1'b1;
                        end else if (os_ts1_valid || os_ts2_valid) begin
                            if (os_ts2_valid)
                                dbg_cfg_ts2_mismatch_count <= sat_inc16(dbg_cfg_ts2_mismatch_count);
                            rx_ts_count <= 5'd0;
                            training_error_count <= sat_inc32(training_error_count);
                        end
                        if ((rx_ts_count >= TS_REQUIRED) &&
                            (state_timer >= MIN_CONFIG_TX_LIMIT)) begin
                            ltssm_state <= CFG_IDLE;
                            state_timer <= 32'd0;
                            rx_ts_count <= 5'd0;
                        end else if (state_timer >= TRAIN_TIMEOUT_LIMIT) begin
                            ltssm_state <= DETECT_QUIET;
                            state_timer <= 32'd0;
                            rx_ts_count <= 5'd0;
                            timeout_count <= sat_inc32(timeout_count);
                        end
                    end
                    CFG_IDLE: begin
                        state_timer <= state_timer + 1'b1;
                        if (os_idle_pair_valid) begin
                            if (rx_ts_count == TS_REQUIRED-1'b1) begin
                                ltssm_state <= STATE_L0;
                                state_timer <= 32'd0;
                                rx_ts_count <= 5'd0;
                            end else rx_ts_count <= rx_ts_count + 1'b1;
                        end
                        if (state_timer >= TRAIN_TIMEOUT_LIMIT) begin
                            ltssm_state <= DETECT_QUIET;
                            state_timer <= 32'd0;
                            rx_ts_count <= 5'd0;
                            timeout_count <= sat_inc32(timeout_count);
                        end
                    end
                    STATE_L0: begin
                        state_timer <= 32'd0;
                        rx_ts_count <= 5'd0;
                        recovery_speed_changed <= 1'b0;
                        if (hot_reset_req ||
                            ((os_ts1_valid || os_ts2_valid) &&
                             os_training_control[0])) begin
                            ltssm_state <= HOT_RESET;
                            hot_reset_seen <= 1'b1;
                        end else if (force_recovery || os_ts1_valid ||
                                     os_ts2_valid ||
                                     rxelecidle_qualified) begin
                            ltssm_state <= RECOVERY_RCVRLOCK;
                        end
                    end
                    RECOVERY_RCVRLOCK: begin
                        state_timer <= state_timer + 1'b1;
                        // An EQ/peer failure can be reported after the
                        // original Gen3 Recovery.Speed has already returned
                        // to RcvrLock.  Re-enter Speed for the explicit Gen1
                        // fallback while active_phy_rate is still Gen3, so
                        // the Root Port observes the fallback PhyStatus in
                        // the same Recovery transaction.
                        if (recovery_fallback_active &&
                            (active_phy_rate != 2'b00)) begin
                            ltssm_state <= RECOVERY_SPEED;
                            state_timer <= 32'd0;
                            rx_ts_count <= 5'd0;
                        end else if (os_ts1_valid && !os_link_is_pad && !os_lane_is_pad &&
                            (os_link_number == link_number) && (os_lane_number == 0)) begin
                            if (rx_ts_count == TS_REQUIRED-1'b1) begin
                                ltssm_state <= RECOVERY_RCVRCFG;
                                state_timer <= 32'd0;
                                rx_ts_count <= 5'd0;
                            end else rx_ts_count <= rx_ts_count + 1'b1;
                        end
                        if (state_timer >= TRAIN_TIMEOUT_LIMIT) begin
                            ltssm_state <= DETECT_QUIET;
                            state_timer <= 32'd0;
                            rx_ts_count <= 5'd0;
                            timeout_count <= sat_inc32(timeout_count);
                        end
                    end
                    RECOVERY_RCVRCFG: begin
                        state_timer <= state_timer + 1'b1;
                        if (os_ts2_valid && !os_link_is_pad && !os_lane_is_pad &&
                            (os_link_number == link_number) && (os_lane_number == 0)) begin
                            if (rx_ts_count == TS_REQUIRED-1'b1) begin
                                if (speed_retrain_active &&
                                    (!recovery_speed_changed ||
                                     recovery_fallback_active))
                                    ltssm_state <= RECOVERY_SPEED;
                                else
                                    ltssm_state <= RECOVERY_IDLE;
                                state_timer <= 32'd0;
                                rx_ts_count <= 5'd0;
                            end else rx_ts_count <= rx_ts_count + 1'b1;
                        end
                        if (state_timer >= TRAIN_TIMEOUT_LIMIT) begin
                            ltssm_state <= DETECT_QUIET;
                            state_timer <= 32'd0;
                            rx_ts_count <= 5'd0;
                            timeout_count <= sat_inc32(timeout_count);
                        end
                    end
                    RECOVERY_SPEED: begin
                        state_timer <= state_timer + 1'b1;
                        rx_ts_count <= 5'd0;
                        if (recovery_speed_done) begin
                            recovery_speed_changed <= 1'b1;
                            ltssm_state <= RECOVERY_RCVRLOCK;
                            state_timer <= 32'd0;
                        end else if (state_timer >= TRAIN_TIMEOUT_LIMIT) begin
                            ltssm_state <= DETECT_QUIET;
                            state_timer <= 32'd0;
                            timeout_count <= sat_inc32(timeout_count);
                        end
                    end
                    RECOVERY_IDLE: begin
                        state_timer <= state_timer + 1'b1;
                        // K13 Speed/EQ控制未释放前保持Recovery，避免PHY已切速而
                        // 生产LTSSM提前回L0并恢复Gen1事务。
                        if (!force_recovery && os_idle_pair_valid) begin
                            if (rx_ts_count == TS_REQUIRED-1'b1) begin
                                ltssm_state <= STATE_L0;
                                state_timer <= 32'd0;
                                rx_ts_count <= 5'd0;
                            end else rx_ts_count <= rx_ts_count + 1'b1;
                        end
                        if (state_timer >= TRAIN_TIMEOUT_LIMIT) begin
                            ltssm_state <= DETECT_QUIET;
                            state_timer <= 32'd0;
                            rx_ts_count <= 5'd0;
                            timeout_count <= sat_inc32(timeout_count);
                        end
                    end
                    HOT_RESET: begin
                        rx_ts_count <= 5'd0;
                        polling_tx_ts1_count <= 11'd0;
                        if (state_timer >= HOT_RESET_LIMIT) begin
                            ltssm_state <= DETECT_QUIET;
                            state_timer <= 32'd0;
                            link_number <= K_PAD;
                        end else begin
                            state_timer <= state_timer + 1'b1;
                        end
                    end
                    default: begin
                        ltssm_state <= DETECT_QUIET;
                        state_timer <= 32'd0;
                        rx_ts_count <= 5'd0;
                        polling_tx_ts1_count <= 11'd0;
                        link_number <= K_PAD;
                        training_error_count <= sat_inc32(training_error_count);
                    end
                endcase
            end
        end
    end

    wire _unused_rx_fields = &{1'b0, phy_rxdata[31:16], phy_rxdata_valid,
                               os_n_fts, os_rate_id, os_training_control[7:1],
                               os_raw_idle_pair_valid, tx_scrambler_state,
                               rx_scrambler_state, os_tx_data[31:16],
                               frame_tx_data[31:16]};
endmodule

`default_nettype wire
