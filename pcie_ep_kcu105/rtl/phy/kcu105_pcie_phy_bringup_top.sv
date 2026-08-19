`timescale 1ns/1ps
`default_nettype none

// K02 专用上板顶层：执行一次 Receiver Detect，并可在成功后进入受控
// Gen3 PHY/GT 诊断模式；不包含任何 LTSSM、TS1/TS2 或链路训练功能。
// DIRECT_GEN3_MODE 用于独立验证 Gen3 steady-state：复位释放后直接请求
// P0/Gen3，不执行 Receiver Detect 和 Gen1->Gen3 dynamic rate transition。
//
// K02_USE_PHY_CTRL=1：把 Xilinx 7-series `phy_ctrl.v` + `phy_bringup_seq`
// 实例化到顶层。phy_ctrl 内部产生 PHY_RATE/PHY_POWERDOWN/TXEQ/
// as_mac_in_detect/as_cdr_hold_req 完整控制序列，原 K02 FSM 被旁路
// (`if (K02_USE_PHY_CTRL == 0)` 包裹）。K02 顶层仍持有 32+ 控制信号
// 端口，因此 K01 共用同一 wrapper 的实板接口不变；K02 自身
// `DYN_*` 节奏/状态保留作 8'h04 触发器的 fallback 诊断项。
module kcu105_pcie_phy_bringup_top #(
    parameter integer DETECT_TIMEOUT_CYCLES = 16_000_000,
    parameter integer GEN3_TEST_MODE        = 1,
    parameter integer DYNAMIC_RATE_TEST_MODE = 0,
    parameter integer DYNAMIC_COEFF_QUERY_MODE = 0,
    parameter integer DYNAMIC_GEN1_OFF_GAP_MODE = 0,
    parameter integer DIRECT_GEN3_MODE      = 0,
    parameter integer DYNAMIC_START_DELAY_CYCLES = 1024,
    parameter integer DYNAMIC_GEN1_STABLE_CYCLES = 1024,
    // 250 MHz phy_pclk下，2500个周期约等于10 us；这是Golden
    // Gen1 OFF GAP的等价诊断窗口。K02没有board.v的rate enable，
    // 因此窗口内保持Gen1/P0/Electrical Idle并撤销TXEQ命令。
    parameter integer DYNAMIC_GEN1_OFF_GAP_CYCLES = 2500,
    parameter integer DYNAMIC_TXEQ_TIMEOUT_CYCLES = 8192,
    parameter integer DYNAMIC_GEN3_TIMEOUT_CYCLES = 32768,
    // Golden-vs-K02 A/B Test 独立开关 (claude_code_k02_golden_ab_modify.md)。
    // 默认全部为 0，保持当前 K02 行为不变；打开任意一个都只改变对应变量。
    parameter integer DYNAMIC_MAC_IN_DETECT_LOW_MODE = 0,
    parameter integer DYNAMIC_CDR_HOLD_LOW_MODE      = 0,
    parameter integer DYNAMIC_SKIP_TXEQ_MODE        = 0,
    // 1：实例化 Golden `phy_ctrl.v` + `phy_bringup_seq` 旁路 K02 FSM，
    //    6 个使能由 `phy_bringup_seq` 提供；PHY 控制由 `phy_ctrl.v` 输出。
    // 0（默认）：保持原 K02 FSM 行为（与 K01/历史 build 兼容）。
    // 当 K02_USE_PHY_CTRL=1 时，下列 3 个 A/B 变量被旁路，无效果：
    //   DYNAMIC_MAC_IN_DETECT_LOW_MODE / CDR_HOLD_LOW_MODE / SKIP_TXEQ_MODE。
    parameter integer K02_USE_PHY_CTRL = 0,
    // 以下 6 个参数只用于 K02_USE_PHY_CTRL=1，对齐 imports/board.v 的
    // 250 MHz 计数器预算。默认值与 board_kcu105/phy_bringup_seq.sv 完全一致。
    parameter integer K02_PHY_CTRL_WAIT_AFTER_READY_NS    = 10_000,
    parameter integer K02_PHY_CTRL_WAIT_AFTER_GEN1_ON_NS  =  5_000,
    parameter integer K02_PHY_CTRL_GEN1_HOLD_NS           = 50_000,
    parameter integer K02_PHY_CTRL_WAIT_AFTER_GEN1_OFF_NS = 10_000,
    parameter integer K02_PHY_CTRL_GEN3_HOLD_NS           = 80_000
) (
    input  wire       pcie_refclk_p,
    input  wire       pcie_refclk_n,
    input  wire       pcie_perst_n,
    input  wire       pcie_rxp,
    input  wire       pcie_rxn,
    output wire       pcie_txp,
    output wire       pcie_txn,
    output wire [7:0] led
);

    localparam logic [2:0] BUP_RESET       = 3'd0;
    localparam logic [2:0] BUP_SETTLE      = 3'd1;
    localparam logic [2:0] BUP_DETECT      = 3'd2;
    localparam logic [2:0] BUP_WAIT_STATUS = 3'd3;
    localparam logic [2:0] BUP_DONE        = 3'd4;
    localparam logic [2:0] BUP_TIMEOUT     = 3'd5;
    localparam logic [3:0] DYN_IDLE        = 4'd0;
    localparam logic [3:0] DYN_GEN1_STABLE = 4'd1;
    localparam logic [3:0] DYN_TXEQ        = 4'd2;
    localparam logic [3:0] DYN_GEN3_WAIT   = 4'd3;
    localparam logic [3:0] DYN_PASS        = 4'd4;
    localparam logic [3:0] DYN_FAIL        = 4'd5;
    localparam logic [3:0] DYN_TXEQ_GAP    = 4'd6;
    localparam logic [3:0] DYN_QUERY       = 4'd7;
    localparam logic [3:0] DYN_QUERY_GAP   = 4'd8;
    localparam logic [3:0] DYN_GEN1_OFF_GAP = 4'd9;
    localparam logic [23:0] DETECT_TIMEOUT_LIMIT =
        DETECT_TIMEOUT_CYCLES[23:0] - 24'd1;

    wire        phy_coreclk;
    wire        phy_userclk;
    wire        phy_mcapclk;
    wire        phy_pclk;
    wire        pipe_rst_n;
    wire        core_rst_n;
    wire        phy_phystatus_rst;

    // Original K02 FSM signals - only meaningful when K02_USE_PHY_CTRL=0.
    (* mark_debug = "true" *) logic       phy_txdetectrx;
    (* mark_debug = "true" *) logic [1:0] phy_powerdown;
    (* mark_debug = "true" *) logic [1:0] phy_rate_cmd;
    (* mark_debug = "true" *) logic       phy_txelecidle_cmd;
    (* mark_debug = "true" *) logic [1:0] phy_txeq_ctrl_cmd;
    (* mark_debug = "true" *) logic [3:0] phy_txeq_preset_cmd;
    (* mark_debug = "true" *) logic       as_cdr_hold_cmd;
    (* mark_debug = "true" *) logic       as_mac_in_detect_cmd;
    wire        phy_phystatus;
    wire [2:0]  phy_rxstatus;

    wire [31:0] phy_rxdata;
    wire [1:0]  phy_rxdatak;
    wire        phy_rxdata_valid;
    wire        phy_rxstart_block;
    wire [1:0]  phy_rxsync_header;
    wire        phy_rxvalid;
    wire        phy_rxelecidle;
    wire [5:0]  phy_txeq_fs;
    wire [5:0]  phy_txeq_lf;
    wire [17:0] phy_txeq_new_coeff;
    wire        phy_txeq_done;
    wire        phy_rxeq_preset_sel;
    wire [17:0] phy_rxeq_new_txcoeff;
    wire        phy_rxeq_adapt_done;
    wire        phy_rxeq_done;

    // Wrapper 端口驱动信号 - K02_USE_PHY_CTRL=0 时用 FSM 输出/常数，
    // K02_USE_PHY_CTRL=1 时用 Golden `phy_ctrl.v` 的 ctrl_* 输出。
    // 这些信号在 always_comb 中被赋值，因此声明为 logic 而非 wire。
    logic [31:0] phy_txdata_w;
    logic [1:0]  phy_txdatak_w;
    logic        phy_txdata_valid_w;
    logic        phy_txstart_block_w;
    logic [1:0]  phy_txsync_header_w;
    logic        phy_txcompliance_w;
    logic        phy_rxpolarity_w;
    logic [2:0]  phy_txmargin_w;
    logic        phy_txswing_w;
    logic        phy_txdeemph_w;
    logic [5:0]  phy_txeq_coeff_w;
    logic [1:0]  phy_rxeq_ctrl_w;
    logic [3:0]  phy_rxeq_txpreset_w;
    // 与 K02 FSM 共享名字（已在上面声明），仅在 PHY_CTRL=0 时被 FSM 驱动。
    // PHY_CTRL=1 时 always_comb 的 if 分支会重新赋值。

    // phy_ctrl.v 输出（当 K02_USE_PHY_CTRL=1 时使用）.
    wire [31:0] ctrl_txdata;
    wire [1:0]  ctrl_txdatak;
    wire        ctrl_txdata_valid;
    wire        ctrl_txstart_block;
    wire [1:0]  ctrl_txsync_header;
    wire        ctrl_txdetectrx;
    wire        ctrl_txelecidle;
    wire        ctrl_txcompliance;
    wire        ctrl_rxpolarity;
    wire [1:0]  ctrl_phy_powerdown;
    wire [2:0]  ctrl_phy_rate;
    wire [2:0]  ctrl_txmargin;
    wire        ctrl_txswing;
    wire        ctrl_txdeemph;
    wire [1:0]  ctrl_txeq_ctrl;
    wire [3:0]  ctrl_txeq_preset;
    wire [5:0]  ctrl_txeq_coeff;
    wire [1:0]  ctrl_rxeq_ctrl;
    wire [3:0]  ctrl_rxeq_txpreset;
    wire        ctrl_as_mac_in_detect;
    wire        ctrl_as_cdr_hold_req;
    wire [7:0]  ctrl_debug_state;

    // phy_bringup_seq 输出（仅 K02_USE_PHY_CTRL=1 时非零）.
    wire        seq_tx_elec_idle;
    wire        seq_phy_ready_en;
    wire        seq_gen1_en;
    wire        seq_gen2_en;
    wire        seq_gen3_en;
    wire        seq_gen4_en;
    wire [3:0]  seq_seq_state;
    wire        seq_gen3_request;

    (* mark_debug = "true" *) logic [2:0] bup_state;
    (* mark_debug = "true" *) logic [2:0] detected_rxstatus;
    (* mark_debug = "true" *) logic       detect_done;
    (* mark_debug = "true" *) logic       receiver_present;
    (* mark_debug = "true" *) logic       detect_timeout;
    (* mark_debug = "true" *) logic       unexpected_status;
    (* mark_debug = "true" *) logic       gen3_test_active;
    (* mark_debug = "true" *) logic [1:0] phy_rate_debug;
    (* mark_debug = "true" *) logic [1:0] phy_powerdown_debug;
    (* mark_debug = "true" *) logic       phy_txelecidle_debug;
    (* mark_debug = "true" *) logic [1:0] phy_txeq_ctrl_debug;
    (* mark_debug = "true" *) logic [3:0] phy_txeq_preset_debug;
    (* mark_debug = "true" *) logic [17:0] phy_txeq_new_coeff_debug;
    (* mark_debug = "true" *) logic       as_cdr_hold_debug;
    (* mark_debug = "true" *) logic       as_mac_in_detect_debug;
    (* mark_debug = "true" *) logic       phy_txeq_done_debug;
    (* mark_debug = "true" *) logic [3:0] dynamic_rate_state;
    (* mark_debug = "true" *) logic       dynamic_rate_txeq_active;
    (* mark_debug = "true" *) logic       dynamic_rate_txeq_query_active;
    // PHY_PHYSTATUS is a completion pulse, not a level that remains high
    // after the rate change.  Keep a sticky copy for the dynamic checker and
    // ILA so a later sample cannot hide an earlier completion event.
    (* mark_debug = "true" *) logic       dynamic_rate_phystatus_seen;
    (* mark_debug = "true" *) logic       dynamic_rate_pass;
    (* mark_debug = "true" *) logic       dynamic_rate_fail;
    // K02_USE_PHY_CTRL=1 时的诊断信号。
    (* mark_debug = "true" *) wire [7:0]  phy_ctrl_debug_state_w =
        (K02_USE_PHY_CTRL != 0) ? ctrl_debug_state : 8'h00;
    (* mark_debug = "true" *) wire [3:0]  seq_state_w =
        (K02_USE_PHY_CTRL != 0) ? seq_seq_state    : 4'h0;
    (* mark_debug = "true" *) wire        gen3_request_w =
        (K02_USE_PHY_CTRL != 0) ? seq_gen3_request : 1'b0;
    (* mark_debug = "true" *) wire        gen1_en_w =
        (K02_USE_PHY_CTRL != 0) ? seq_gen1_en      : 1'b0;
    (* mark_debug = "true" *) wire        gen2_en_w =
        (K02_USE_PHY_CTRL != 0) ? seq_gen2_en      : 1'b0;
    (* mark_debug = "true" *) wire        gen3_en_w =
        (K02_USE_PHY_CTRL != 0) ? seq_gen3_en      : 1'b0;
    (* mark_debug = "true" *) wire        gen4_en_w =
        (K02_USE_PHY_CTRL != 0) ? seq_gen4_en      : 1'b0;
    (* mark_debug = "true" *) wire        tx_elec_idle_w =
        (K02_USE_PHY_CTRL != 0) ? seq_tx_elec_idle : 1'b0;
    (* mark_debug = "true" *) wire        phy_ready_en_w =
        (K02_USE_PHY_CTRL != 0) ? seq_phy_ready_en : 1'b0;
    logic [31:0] dynamic_rate_count;
    logic [4:0]  settle_count;
    logic [23:0] timeout_count;
    logic [24:0] heartbeat_count;

    generate
        if ((DETECT_TIMEOUT_CYCLES < 1) ||
            (DETECT_TIMEOUT_CYCLES > 16_777_216)) begin : g_invalid_timeout
            initial $error("DETECT_TIMEOUT_CYCLES must be in [1, 16777216]");
        end
        if ((DYNAMIC_GEN1_OFF_GAP_MODE != 0) &&
            (DYNAMIC_GEN1_OFF_GAP_CYCLES < 1)) begin : g_invalid_off_gap
            initial $error("DYNAMIC_GEN1_OFF_GAP_CYCLES must be >= 1 when OFF GAP is enabled");
        end
        if (K02_USE_PHY_CTRL != 0) begin : g_phy_ctrl
            // Synthesizable equivalent of imports/board.v's bring-up stimulus.
            phy_bringup_seq #(
                .SEQ_CLK_HZ                  (250_000_000),
                .WAIT_AFTER_READY_NS         (K02_PHY_CTRL_WAIT_AFTER_READY_NS),
                .WAIT_AFTER_GEN1_ON_NS       (K02_PHY_CTRL_WAIT_AFTER_GEN1_ON_NS),
                .GEN1_HOLD_NS                (K02_PHY_CTRL_GEN1_HOLD_NS),
                .WAIT_AFTER_GEN1_OFF_NS      (K02_PHY_CTRL_WAIT_AFTER_GEN1_OFF_NS),
                .GEN3_HOLD_NS                (K02_PHY_CTRL_GEN3_HOLD_NS)
            ) u_phy_bringup_seq (
                .clk                  (phy_pclk),
                .rst                  (!pcie_perst_n),
                .phy_status_ready     (!phy_phystatus_rst),
                .phy_ctrl_debug_state (ctrl_debug_state),
                .tx_elec_idle         (seq_tx_elec_idle),
                .phy_ready_en         (seq_phy_ready_en),
                .gen1_en              (seq_gen1_en),
                .gen2_en              (seq_gen2_en),
                .gen3_en              (seq_gen3_en),
                .gen4_en              (seq_gen4_en),
                .seq_state            (seq_seq_state),
                .gen3_request         (seq_gen3_request)
            );

            // Unmodified Xilinx reference controller from imports/.
            phy_ctrl #(
                .PHY_LANE (1),
                .DW       (32),
                .TCQ      (1)
            ) u_phy_ctrl (
                .CLK                 (phy_pclk),
                .RST                 (phy_phystatus_rst),
                .PHY_TXDATA          (ctrl_txdata),
                .PHY_TXDATAK         (ctrl_txdatak),
                .PHY_TXDATA_VALID    (ctrl_txdata_valid),
                .PHY_TXSTART_BLOCK   (ctrl_txstart_block),
                .PHY_TXSYNC_HEADER   (ctrl_txsync_header),
                .PHY_RXDATA          (phy_rxdata),
                .PHY_RXDATAK         (phy_rxdatak),
                .PHY_RXDATA_VALID    (phy_rxdata_valid),
                .PHY_RXSTART_BLOCK   (phy_rxstart_block),
                .PHY_RXSYNC_HEADER   (phy_rxsync_header),
                .PHY_TXDETECTRX      (ctrl_txdetectrx),
                .PHY_TXELECIDLE      (ctrl_txelecidle),
                .PHY_TXCOMPLIANCE    (ctrl_txcompliance),
                .PHY_RXPOLARITY      (ctrl_rxpolarity),
                .PHY_POWERDOWN       (ctrl_phy_powerdown),
                .PHY_RATE            (ctrl_phy_rate),
                .PHY_RXVALID         (phy_rxvalid),
                .PHY_PHYSTATUS       (phy_phystatus),
                .PHY_PHYSTATUS_RST   (phy_phystatus_rst),
                .PHY_RXELECIDLE      (phy_rxelecidle),
                .PHY_RXSTATUS        (phy_rxstatus),
                .PHY_TXMARGIN        (ctrl_txmargin),
                .PHY_TXSWING         (ctrl_txswing),
                .PHY_TXDEEMPH        (ctrl_txdeemph),
                .PHY_TXEQ_CTRL       (ctrl_txeq_ctrl),
                .PHY_TXEQ_PRESET     (ctrl_txeq_preset),
                .PHY_TXEQ_COEFF      (ctrl_txeq_coeff),
                .PHY_RXEQ_CTRL       (ctrl_rxeq_ctrl),
                .PHY_RXEQ_TXPRESET   (ctrl_rxeq_txpreset),
                .PHY_TXEQ_FS         (phy_txeq_fs),
                .PHY_TXEQ_LF         (phy_txeq_lf),
                .PHY_TXEQ_NEW_COEFF  (phy_txeq_new_coeff),
                .PHY_TXEQ_DONE       (phy_txeq_done),
                .PHY_RXEQ_PRESET_SEL (phy_rxeq_preset_sel),
                .PHY_RXEQ_NEW_TXCOEFF(phy_rxeq_new_txcoeff),
                .PHY_RXEQ_ADAPT_DONE (phy_rxeq_adapt_done),
                .PHY_RXEQ_DONE       (phy_rxeq_done),
                .as_mac_in_detect    (ctrl_as_mac_in_detect),
                .as_cdr_hold_req     (ctrl_as_cdr_hold_req),
                .debug_state         (ctrl_debug_state),
                .tx_elec_idle        (seq_tx_elec_idle),
                .phy_ready_en        (seq_phy_ready_en),
                .gen1_en             (seq_gen1_en),
                .gen2_en             (seq_gen2_en),
                .gen3_en             (seq_gen3_en),
                .gen4_en             (seq_gen4_en)
            );
        end
    endgenerate

    always_comb begin
        if (K02_USE_PHY_CTRL != 0) begin
            // Golden `phy_ctrl.v` 直接驱动 wrapper；FSM 输出被旁路。
            phy_powerdown       = ctrl_phy_powerdown;
            phy_txdetectrx      = ctrl_txdetectrx;
            phy_rate_cmd        = ctrl_phy_rate[1:0];
            phy_txelecidle_cmd  = ctrl_txelecidle;
            phy_txeq_ctrl_cmd   = ctrl_txeq_ctrl;
            phy_txeq_preset_cmd = ctrl_txeq_preset;
            as_cdr_hold_cmd     = ctrl_as_cdr_hold_req;
            as_mac_in_detect_cmd = ctrl_as_mac_in_detect;

            phy_txdata_w        = ctrl_txdata;
            phy_txdatak_w       = ctrl_txdatak;
            phy_txdata_valid_w  = ctrl_txdata_valid;
            phy_txstart_block_w = ctrl_txstart_block;
            phy_txsync_header_w = ctrl_txsync_header;
            phy_txcompliance_w  = ctrl_txcompliance;
            phy_rxpolarity_w    = ctrl_rxpolarity;
            phy_txmargin_w      = ctrl_txmargin;
            phy_txswing_w       = ctrl_txswing;
            phy_txdeemph_w      = ctrl_txdeemph;
            phy_txeq_coeff_w    = ctrl_txeq_coeff;
            phy_rxeq_ctrl_w     = ctrl_rxeq_ctrl;
            phy_rxeq_txpreset_w = ctrl_rxeq_txpreset;
        end else begin
        phy_powerdown      = 2'b10;
        phy_txdetectrx     = 1'b0;
        phy_rate_cmd       = 2'b00;
        phy_txelecidle_cmd = 1'b1;
        phy_txeq_ctrl_cmd  = 2'b00;
        phy_txeq_preset_cmd = 4'd0;
        as_cdr_hold_cmd    = 1'b0;
        // 默认行为：K02 顶层把 as_mac_in_detect 永久拉 1（与之前 .as_mac_in_detect(1'b1)
        // 一致）。A/B Test 1 (DYNAMIC_MAC_IN_DETECT_LOW_MODE=1) 时，在 dynamic
        // rate-change 流程内把它拉 0，对齐 Golden phy_ctrl.v 在 Detect.Quiet/
        // Detect.Active 之外的状态（参考 imports/phy_ctrl.v:209）。
        as_mac_in_detect_cmd = 1'b1;
        if ((DIRECT_GEN3_MODE == 0) &&
            ((bup_state == BUP_DETECT) ||
             (bup_state == BUP_WAIT_STATUS))) begin
            phy_txdetectrx = 1'b1;
        end
        if ((DIRECT_GEN3_MODE != 0) && pipe_rst_n) begin
            // 直接进入 Gen3 steady-state。TX 保持 Electrical Idle，避免在
            // 没有 TS/Ordered Set 发送器时把零数据误认为协议流量。
            phy_powerdown      = 2'b00;
            phy_rate_cmd       = 2'b10;
            phy_txelecidle_cmd = 1'b1;
        end else if ((GEN3_TEST_MODE != 0) && gen3_test_active) begin
            // K02 不实现 LTSSM/TS1/TS2；这里只把 standalone PHY 置于
            // P0 并执行稳态 Gen3 或受控 Gen1->Gen3 rate-change 诊断。
            phy_powerdown      = 2'b00;
            phy_txelecidle_cmd = 1'b1;
            // A/B Test 1：dynamic 流程内释放 mac_in_detect。
            if (DYNAMIC_MAC_IN_DETECT_LOW_MODE != 0) begin
                as_mac_in_detect_cmd = 1'b0;
            end
            if (DYNAMIC_RATE_TEST_MODE != 0) begin
                case (dynamic_rate_state)
                    DYN_TXEQ: begin
                        // A/B Test 3 (DYNAMIC_SKIP_TXEQ_MODE=1)：保留进入此状态
                        // 的可能性，但强制 TXEQ_CTRL=Idle / preset=0，
                        // 并把 as_cdr_hold_cmd 也拉 0，避免空跑 TXEQ 期间
                        // CDR 被错误地 hold 住。
                        phy_rate_cmd        = 2'b00;
                        phy_txeq_ctrl_cmd   = (DYNAMIC_SKIP_TXEQ_MODE != 0) ?
                                               2'b00 : 2'b01;
                        phy_txeq_preset_cmd = (DYNAMIC_SKIP_TXEQ_MODE != 0) ?
                                               4'd0 : 4'd4;
                        as_cdr_hold_cmd     = (DYNAMIC_SKIP_TXEQ_MODE != 0) ?
                                               1'b0 : 1'b1;
                    end
                    DYN_TXEQ_GAP: begin
                        // PG239 requires TXEQ_CTRL to return to Idle after
                        // TXEQ_DONE.  Keep one complete pclk gap before the
                        // optional query so the two PHY commands cannot
                        // merge at the interface.
                        phy_rate_cmd    = 2'b00;
                        as_cdr_hold_cmd = (DYNAMIC_SKIP_TXEQ_MODE != 0) ?
                                           1'b0 : 1'b1;
                    end
                    DYN_QUERY: begin
                        phy_rate_cmd     = 2'b00;
                        phy_txeq_ctrl_cmd = (DYNAMIC_SKIP_TXEQ_MODE != 0) ?
                                               2'b00 : 2'b11;
                        as_cdr_hold_cmd  = (DYNAMIC_SKIP_TXEQ_MODE != 0) ?
                                               1'b0 : 1'b1;
                    end
                    DYN_QUERY_GAP: begin
                        phy_rate_cmd    = 2'b00;
                        as_cdr_hold_cmd = (DYNAMIC_SKIP_TXEQ_MODE != 0) ?
                                           1'b0 : 1'b1;
                    end
                    DYN_GEN1_OFF_GAP: begin
                        // Direct K02 has no board.v rate-enable input. The
                        // closest equivalent to Golden's all-rate-disabled
                        // interval is Gen1/P0 with TXEQ idle and TxElecIdle
                        // asserted.  A/B Test 2 (DYNAMIC_CDR_HOLD_LOW_MODE=1)
                        // 在此状态强制 as_cdr_hold_cmd=0，对齐 Golden。
                        phy_rate_cmd      = 2'b00;
                        phy_txeq_ctrl_cmd = 2'b00;
                        as_cdr_hold_cmd    = (DYNAMIC_CDR_HOLD_LOW_MODE != 0) ?
                                              1'b0 : 1'b1;
                    end
                    DYN_GEN3_WAIT: begin
                        // A/B Test 2 (DYNAMIC_CDR_HOLD_LOW_MODE=1) 在此状态
                        // 强制 as_cdr_hold_cmd=0，让 GTHE3 CDR 重新锁定到
                        // Gen3；否则 Golden 风格下 QPLL1 不会在 PHY_RATE=2
                        // 保持期间重新 relock，phy_phystatus 也不会 pulse。
                        phy_rate_cmd      = 2'b10;
                        phy_txeq_ctrl_cmd = 2'b00;
                        as_cdr_hold_cmd   = (DYNAMIC_CDR_HOLD_LOW_MODE != 0) ?
                                              1'b0 : 1'b0;
                    end
                    DYN_PASS: begin
                        phy_rate_cmd = 2'b10;
                    end
                    default: begin
                        phy_rate_cmd = 2'b00;
                    end
                endcase
            end else begin
                phy_rate_cmd = 2'b10;
            end
        end

        // K02_USE_PHY_CTRL=0 时，wrapper 的常量端口保持默认零/低。
        phy_txdata_w        = 32'b0;
        phy_txdatak_w       = 2'b0;
        phy_txdata_valid_w  = 1'b0;
        phy_txstart_block_w = 1'b0;
        phy_txsync_header_w = 2'b0;
        phy_txcompliance_w  = 1'b0;
        phy_rxpolarity_w    = 1'b0;
        phy_txmargin_w      = 3'b0;
        phy_txswing_w       = 1'b0;
        phy_txdeemph_w      = 1'b0;
        phy_txeq_coeff_w    = 6'b0;
        phy_rxeq_ctrl_w     = 2'b0;
        phy_rxeq_txpreset_w = 4'b0;
        end
    end

    assign phy_rate_debug       = phy_rate_cmd;
    assign phy_powerdown_debug  = phy_powerdown;
    assign phy_txelecidle_debug = phy_txelecidle_cmd;
    assign phy_txeq_ctrl_debug  = phy_txeq_ctrl_cmd;
    assign phy_txeq_preset_debug = phy_txeq_preset_cmd;
    assign phy_txeq_new_coeff_debug = phy_txeq_new_coeff;
    assign as_cdr_hold_debug    = as_cdr_hold_cmd;
    assign as_mac_in_detect_debug = as_mac_in_detect_cmd;
    assign phy_txeq_done_debug  = phy_txeq_done;
    assign dynamic_rate_txeq_active =
        (dynamic_rate_state == DYN_TXEQ);
    assign dynamic_rate_txeq_query_active =
        (dynamic_rate_state == DYN_QUERY);

    always_ff @(posedge phy_pclk or negedge pipe_rst_n) begin
        if (!pipe_rst_n) begin
            bup_state          <= BUP_RESET;
            settle_count       <= '0;
            timeout_count      <= '0;
            detected_rxstatus  <= '0;
            detect_done        <= 1'b0;
            receiver_present   <= 1'b0;
            detect_timeout     <= 1'b0;
            unexpected_status  <= 1'b0;
            gen3_test_active   <= 1'b0;
            dynamic_rate_state <= DYN_IDLE;
            dynamic_rate_count <= '0;
            dynamic_rate_phystatus_seen <= 1'b0;
            dynamic_rate_pass  <= 1'b0;
            dynamic_rate_fail  <= 1'b0;
            heartbeat_count    <= '0;
        end else begin
            heartbeat_count <= heartbeat_count + 1'b1;

            // K02_USE_PHY_CTRL=1 时 FSM 旁路；保留 heartbeat 与 BUP/DYN
            // 复位状态作为对照变量。
            if (K02_USE_PHY_CTRL == 0) begin
            if (DYNAMIC_RATE_TEST_MODE == 0 || DIRECT_GEN3_MODE != 0) begin
                dynamic_rate_state <= DYN_PASS;
                dynamic_rate_count <= '0;
                dynamic_rate_phystatus_seen <= 1'b0;
                dynamic_rate_pass  <= 1'b0;
                dynamic_rate_fail  <= 1'b0;
            end else if (!gen3_test_active) begin
                dynamic_rate_state <= DYN_IDLE;
                dynamic_rate_count <= '0;
                dynamic_rate_phystatus_seen <= 1'b0;
                dynamic_rate_pass  <= 1'b0;
                dynamic_rate_fail  <= 1'b0;
            end else begin
                case (dynamic_rate_state)
                    DYN_IDLE: begin
                        dynamic_rate_phystatus_seen <= 1'b0;
                        if ((DYNAMIC_START_DELAY_CYCLES <= 1) ||
                            (dynamic_rate_count >= DYNAMIC_START_DELAY_CYCLES - 1)) begin
                            dynamic_rate_state <= DYN_GEN1_STABLE;
                            dynamic_rate_count <= '0;
                        end else begin
                            dynamic_rate_count <= dynamic_rate_count + 1'b1;
                        end
                    end
                    DYN_GEN1_STABLE: begin
                        if ((DYNAMIC_GEN1_STABLE_CYCLES <= 1) ||
                            (dynamic_rate_count >= DYNAMIC_GEN1_STABLE_CYCLES - 1)) begin
                            // A/B Test 3 (DYNAMIC_SKIP_TXEQ_MODE=1)：
                            // 跳过 DYN_TXEQ / TXEQ_GAP / QUERY / QUERY_GAP，
                            // 直接进入 DYN_GEN1_OFF_GAP（如果启用）或 DYN_GEN3_WAIT。
                            if (DYNAMIC_SKIP_TXEQ_MODE != 0) begin
                                dynamic_rate_state <=
                                    (DYNAMIC_GEN1_OFF_GAP_MODE != 0) ?
                                    DYN_GEN1_OFF_GAP : DYN_GEN3_WAIT;
                                if (DYNAMIC_GEN1_OFF_GAP_MODE == 0)
                                    dynamic_rate_phystatus_seen <= 1'b0;
                            end else begin
                                dynamic_rate_state <= DYN_TXEQ;
                            end
                            dynamic_rate_count <= '0;
                        end else begin
                            dynamic_rate_count <= dynamic_rate_count + 1'b1;
                        end
                    end
                    DYN_TXEQ: begin
                        // A/B Test 3 (DYNAMIC_SKIP_TXEQ_MODE=1)：
                        // 若 SKIP_TXEQ 模式下误入 DYN_TXEQ，1 cycle 内透传，
                        // 等价于空跑一次 TXEQ。
                        if (DYNAMIC_SKIP_TXEQ_MODE != 0) begin
                            dynamic_rate_state <=
                                ((DYNAMIC_GEN1_OFF_GAP_MODE != 0) ?
                                 DYN_GEN1_OFF_GAP : DYN_GEN3_WAIT);
                            if (DYNAMIC_GEN1_OFF_GAP_MODE == 0)
                                dynamic_rate_phystatus_seen <= 1'b0;
                            dynamic_rate_count <= '0;
                        end else if (phy_txeq_done) begin
                            dynamic_rate_state <=
                                (DYNAMIC_COEFF_QUERY_MODE != 0) ?
                                DYN_TXEQ_GAP :
                                ((DYNAMIC_GEN1_OFF_GAP_MODE != 0) ?
                                 DYN_GEN1_OFF_GAP : DYN_GEN3_WAIT);
                            dynamic_rate_count <= '0;
                        end else if ((DYNAMIC_TXEQ_TIMEOUT_CYCLES <= 1) ||
                                     (dynamic_rate_count >= DYNAMIC_TXEQ_TIMEOUT_CYCLES - 1)) begin
                            dynamic_rate_state <= DYN_FAIL;
                            dynamic_rate_count <= '0;
                            dynamic_rate_fail  <= 1'b1;
                        end else begin
                            dynamic_rate_count <= dynamic_rate_count + 1'b1;
                        end
                    end
                    DYN_TXEQ_GAP: begin
                        dynamic_rate_state <= DYN_QUERY;
                        dynamic_rate_count <= '0;
                    end
                    DYN_QUERY: begin
                        if (phy_txeq_done) begin
                            dynamic_rate_state <= DYN_QUERY_GAP;
                            dynamic_rate_count <= '0;
                        end else if ((DYNAMIC_TXEQ_TIMEOUT_CYCLES <= 1) ||
                                     (dynamic_rate_count >= DYNAMIC_TXEQ_TIMEOUT_CYCLES - 1)) begin
                            dynamic_rate_state <= DYN_FAIL;
                            dynamic_rate_count <= '0;
                            dynamic_rate_fail  <= 1'b1;
                        end else begin
                            dynamic_rate_count <= dynamic_rate_count + 1'b1;
                        end
                    end
                    DYN_QUERY_GAP: begin
                        dynamic_rate_state <=
                            (DYNAMIC_GEN1_OFF_GAP_MODE != 0) ?
                            DYN_GEN1_OFF_GAP : DYN_GEN3_WAIT;
                        dynamic_rate_count <= '0;
                        if (DYNAMIC_GEN1_OFF_GAP_MODE == 0)
                            dynamic_rate_phystatus_seen <= 1'b0;
                    end
                    DYN_GEN1_OFF_GAP: begin
                        if ((DYNAMIC_GEN1_OFF_GAP_CYCLES <= 1) ||
                            (dynamic_rate_count >= DYNAMIC_GEN1_OFF_GAP_CYCLES - 1)) begin
                            dynamic_rate_state <= DYN_GEN3_WAIT;
                            dynamic_rate_count <= '0;
                            dynamic_rate_phystatus_seen <= 1'b0;
                        end else begin
                            dynamic_rate_count <= dynamic_rate_count + 1'b1;
                        end
                    end
                    DYN_GEN3_WAIT: begin
                        if (phy_phystatus)
                            dynamic_rate_phystatus_seen <= 1'b1;
                        if (phy_phystatus || dynamic_rate_phystatus_seen) begin
                            dynamic_rate_state <= DYN_PASS;
                            dynamic_rate_count <= '0;
                            dynamic_rate_pass  <= 1'b1;
                        end else if ((DYNAMIC_GEN3_TIMEOUT_CYCLES <= 1) ||
                                     (dynamic_rate_count >= DYNAMIC_GEN3_TIMEOUT_CYCLES - 1)) begin
                            dynamic_rate_state <= DYN_FAIL;
                            dynamic_rate_count <= '0;
                            dynamic_rate_fail  <= 1'b1;
                        end else begin
                            dynamic_rate_count <= dynamic_rate_count + 1'b1;
                        end
                    end
                    DYN_PASS,
                    DYN_FAIL: begin
                        dynamic_rate_state <= dynamic_rate_state;
                    end
                    default: begin
                        dynamic_rate_state <= DYN_IDLE;
                        dynamic_rate_count <= '0;
                    end
                endcase
            end

            if (DIRECT_GEN3_MODE != 0) begin
                // 该模式不把 Receiver Detect 当作 Gen3 steady-state 的前置
                // 条件；LED 仅表示 PHY/PIPE/Core 已脱离复位，Detect 结果无效。
                bup_state         <= BUP_DONE;
                gen3_test_active  <= 1'b1;
                detect_done       <= 1'b0;
                receiver_present  <= 1'b0;
                detect_timeout    <= 1'b0;
                unexpected_status <= 1'b0;
            end else case (bup_state)
                BUP_RESET: begin
                    settle_count <= '0;
                    bup_state    <= BUP_SETTLE;
                end

                BUP_SETTLE: begin
                    if (settle_count == 5'd15) begin
                        bup_state <= BUP_DETECT;
                    end else begin
                        settle_count <= settle_count + 1'b1;
                    end
                end

                BUP_DETECT: begin
                    timeout_count <= '0;
                    bup_state     <= BUP_WAIT_STATUS;
                end

                BUP_WAIT_STATUS: begin
                    if (phy_phystatus) begin
                        detected_rxstatus <= phy_rxstatus;
                        detect_done       <= 1'b1;
                        receiver_present  <= (phy_rxstatus == 3'b011);
                        unexpected_status <= (phy_rxstatus != 3'b011);
                        bup_state         <= BUP_DONE;
                    end else if (timeout_count == DETECT_TIMEOUT_LIMIT) begin
                        detect_timeout <= 1'b1;
                        bup_state      <= BUP_TIMEOUT;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end

                BUP_DONE: begin
                    if (GEN3_TEST_MODE != 0)
                        gen3_test_active <= 1'b1;
                    bup_state <= BUP_DONE;
                end

                BUP_TIMEOUT: begin
                    bup_state <= BUP_TIMEOUT;
                end

                default: begin
                    bup_state <= BUP_RESET;
                end
            endcase
            end
        end
    end

    // LED 映射：
    //   K02_USE_PHY_CTRL=0：保留原 K02 诊断灯（pipe_rst / receiver_present /
    //     detect_done / detect_timeout / heartbeat）。
    //   K02_USE_PHY_CTRL=1：复用同一组灯显示 phy_bringup_seq 进度：
    //     led[1]=gen3_request, led[2]=phy_ctrl debug_state==8'h04,
    //     led[5]=seq_state==S_DONE, led[6]=ctrl_as_cdr_hold_req。
    assign led[0] = pipe_rst_n && !phy_phystatus_rst;
    assign led[1] = (K02_USE_PHY_CTRL != 0) ? gen3_request_w : receiver_present;
    assign led[2] = (K02_USE_PHY_CTRL != 0) ?
                     (phy_ctrl_debug_state_w == 8'h04) : detect_done;
    assign led[3] = pipe_rst_n;
    assign led[4] = core_rst_n;
    assign led[5] = (K02_USE_PHY_CTRL != 0) ?
                     (seq_state_w == 4'd8) : detect_timeout;
    assign led[6] = (K02_USE_PHY_CTRL != 0) ?
                     ctrl_as_cdr_hold_req : unexpected_status;
    assign led[7] = heartbeat_count[24];

    kcu105_pcie_phy_wrapper u_phy_wrapper (
        .pcie_refclk_p          (pcie_refclk_p),
        .pcie_refclk_n          (pcie_refclk_n),
        .pcie_perst_n           (pcie_perst_n),
        .pcie_rxp               (pcie_rxp),
        .pcie_rxn               (pcie_rxn),
        .pcie_txp               (pcie_txp),
        .pcie_txn               (pcie_txn),
        .phy_txdata             (phy_txdata_w),
        .phy_txdatak            (phy_txdatak_w),
        .phy_txdata_valid       (phy_txdata_valid_w),
        .phy_txstart_block      (phy_txstart_block_w),
        .phy_txsync_header      (phy_txsync_header_w),
        .phy_txdetectrx         (phy_txdetectrx),
        .phy_txelecidle         (phy_txelecidle_cmd),
        .phy_txcompliance       (phy_txcompliance_w),
        .phy_rxpolarity         (phy_rxpolarity_w),
        .phy_powerdown          (phy_powerdown),
        .phy_rate               (phy_rate_cmd),
        .phy_txmargin           (phy_txmargin_w),
        .phy_txswing            (phy_txswing_w),
        .phy_txdeemph           (phy_txdeemph_w),
        .phy_txeq_ctrl          (phy_txeq_ctrl_cmd),
        .phy_txeq_preset        (phy_txeq_preset_cmd),
        .phy_txeq_coeff         (phy_txeq_coeff_w),
        .phy_rxeq_ctrl          (phy_rxeq_ctrl_w),
        .phy_rxeq_txpreset      (phy_rxeq_txpreset_w),
        .as_mac_in_detect       (as_mac_in_detect_cmd),
        .as_cdr_hold_req        (as_cdr_hold_cmd),
        .phy_coreclk            (phy_coreclk),
        .phy_userclk            (phy_userclk),
        .phy_mcapclk            (phy_mcapclk),
        .phy_pclk               (phy_pclk),
        .pipe_rst_n             (pipe_rst_n),
        .core_rst_n             (core_rst_n),
        .phy_rxdata             (phy_rxdata),
        .phy_rxdatak            (phy_rxdatak),
        .phy_rxdata_valid       (phy_rxdata_valid),
        .phy_rxstart_block      (phy_rxstart_block),
        .phy_rxsync_header      (phy_rxsync_header),
        .phy_rxvalid            (phy_rxvalid),
        .phy_phystatus          (phy_phystatus),
        .phy_phystatus_rst      (phy_phystatus_rst),
        .phy_rxelecidle         (phy_rxelecidle),
        .phy_rxstatus           (phy_rxstatus),
        .phy_txeq_fs            (phy_txeq_fs),
        .phy_txeq_lf            (phy_txeq_lf),
        .phy_txeq_new_coeff     (phy_txeq_new_coeff),
        .phy_txeq_done          (phy_txeq_done),
        .phy_rxeq_preset_sel    (phy_rxeq_preset_sel),
        .phy_rxeq_new_txcoeff   (phy_rxeq_new_txcoeff),
        .phy_rxeq_adapt_done    (phy_rxeq_adapt_done),
        .phy_rxeq_done          (phy_rxeq_done)
    );

endmodule

`default_nettype wire
