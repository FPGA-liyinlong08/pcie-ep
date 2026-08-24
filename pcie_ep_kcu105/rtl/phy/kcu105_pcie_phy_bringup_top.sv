`timescale 1ns/1ps
`default_nettype none

// K02 专用上板顶层：实例化 Xilinx 7-series `phy_ctrl.v` + `phy_bringup_seq`
// 作为 K02 `pcie_phy_x1_gen3` 的 Golden 控制器，独立完成 Gen1→Gen3 切换。
// 不含 K02 自有 FSM；不实现 LTSSM/TS1/TS2。
//
// 设计目的：替代 commit 7d39d60 之前的 `K02_USE_PHY_CTRL=0` 路径
//（`dynamic_rate_*` FSM + A/B 3 变量），该路径在 2×2 cell #3 验证中
// 被确认无法让 QPLL1 relock / phy_phystatus pulse，根因为 FSM 在
// `DYN_GEN3_WAIT` 期间没给 PHY 正确控制序列。Golden 控制器的
// `phy_ctrl.v` + `phy_bringup_seq` 自带完整的速率切换状态机。
//
// 实板 ILA 验证：2026-08-19（commit 82db3cd） seq_state 走到 S_DONE、
// debug_state==8'h04 出现、QPLL1LOCK 1→0→1 切换、K02 Gen1→Gen3 闭环。
module kcu105_pcie_phy_bringup_top #(
    // 5 个参数对齐 `pcie_phy_0_ex/board_kcu105/phy_bringup_seq.sv` 的
    // 250 MHz 计数器预算，phy_bringup_seq 内部按 ns 折算。
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

    wire        phy_coreclk;
    wire        phy_userclk;
    wire        phy_mcapclk;
    wire        phy_pclk;
    wire        pipe_rst_n;
    wire        core_rst_n;
    wire        phy_phystatus_rst;

    // Wrapper PHY 命令 - 由 Golden `phy_ctrl.v` 直接驱动。
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

    // Wrapper 端口驱动信号 - 由 Golden `phy_ctrl.v` 的 ctrl_* 输出驱动。
    // 在 always_comb 中被赋值，因此声明为 logic 而非 wire。
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

    // phy_ctrl.v 输出。
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

    // phy_bringup_seq 输出。
    wire        seq_tx_elec_idle;
    wire        seq_phy_ready_en;
    wire        seq_gen1_en;
    wire        seq_gen2_en;
    wire        seq_gen3_en;
    wire        seq_gen4_en;
    wire [3:0]  seq_seq_state;
    wire        seq_gen3_request;

    // pcie_perst_n 是 PERST# 输入（异步、低有效），并非 phy_pclk 域信号。
    // 直接接到 phy_bringup_seq.rst 会被 report_cdc 判为 1-bit unknown CDC
    // （seq_state + delay_count 共 36 bit）。这里在 phy_pclk 域做两级同步
    // （异步置位、同步释放）后再驱动 phy_bringup_seq.rst，与 Golden
    // 控制器在 pcie_phy_0_ex 中的 reset 同步策略保持一致。
    wire pcie_perst_n_sync;
    pcie_reset_sync #(
        .STAGES (2)
    ) u_perst_sync (
        .clk           (phy_pclk),
        .async_release_n (pcie_perst_n),
        .sync_reset_n  (pcie_perst_n_sync)
    );

    // ILA 诊断信号 - 直接接 Golden 控制器输出。
    (* mark_debug = "true" *) wire [7:0]  phy_ctrl_debug_state_w = ctrl_debug_state;
    (* mark_debug = "true" *) wire [3:0]  seq_state_w           = seq_seq_state;
    (* mark_debug = "true" *) wire        gen3_request_w        = seq_gen3_request;
    (* mark_debug = "true" *) wire        gen1_en_w             = seq_gen1_en;
    (* mark_debug = "true" *) wire        gen2_en_w             = seq_gen2_en;
    (* mark_debug = "true" *) wire        gen3_en_w             = seq_gen3_en;
    (* mark_debug = "true" *) wire        gen4_en_w             = seq_gen4_en;
    (* mark_debug = "true" *) wire        tx_elec_idle_w        = seq_tx_elec_idle;
    (* mark_debug = "true" *) wire        phy_ready_en_w        = seq_phy_ready_en;

    // The implementation Tcl connects these recorder inputs to the actual
    // GTHE3_COMMON QPLL1LOCK/QPLL1RESET primitive nets after synthesis.
    // These are deliberately left as synthesizable tap nets.  The K02
    // implementation Tcl retargets them to the GTHE3_COMMON primitive pins
    // after synthesis; DONT_TOUCH here would prevent that retargeting.
    (* KEEP = "TRUE" *) wire        qpll1lock_record_in;
    (* KEEP = "TRUE" *) wire        qpll1reset_record_in;
    (* mark_debug = "true" *) wire [117:0] k02_event_record_w;

    // 最小 bring-up 计数器：仅给 LED[7] 提供慢闪信号。
    logic [24:0] heartbeat_count;

    // Synthesizable equivalent of `pcie_phy_0_ex/board.v`'s bring-up stimulus.
    phy_bringup_seq #(
        .SEQ_CLK_HZ                  (250_000_000),
        .WAIT_AFTER_READY_NS         (K02_PHY_CTRL_WAIT_AFTER_READY_NS),
        .WAIT_AFTER_GEN1_ON_NS       (K02_PHY_CTRL_WAIT_AFTER_GEN1_ON_NS),
        .GEN1_HOLD_NS                (K02_PHY_CTRL_GEN1_HOLD_NS),
        .WAIT_AFTER_GEN1_OFF_NS      (K02_PHY_CTRL_WAIT_AFTER_GEN1_OFF_NS),
        .GEN3_HOLD_NS                (K02_PHY_CTRL_GEN3_HOLD_NS)
    ) u_phy_bringup_seq (
        .clk                  (phy_pclk),
        .rst                  (!pcie_perst_n_sync),
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

    // Unmodified Xilinx reference controller from `pcie_phy_0_ex/imports/`.
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

    // Golden 控制器直接驱动 wrapper 输入与 PHY 命令。
    always_comb begin
        phy_powerdown        = ctrl_phy_powerdown;
        phy_txdetectrx       = ctrl_txdetectrx;
        phy_rate_cmd         = ctrl_phy_rate[1:0];
        phy_txelecidle_cmd   = ctrl_txelecidle;
        phy_txeq_ctrl_cmd    = ctrl_txeq_ctrl;
        phy_txeq_preset_cmd  = ctrl_txeq_preset;
        as_cdr_hold_cmd      = ctrl_as_cdr_hold_req;
        as_mac_in_detect_cmd = ctrl_as_mac_in_detect;

        phy_txdata_w         = ctrl_txdata;
        phy_txdatak_w        = ctrl_txdatak;
        phy_txdata_valid_w   = ctrl_txdata_valid;
        phy_txstart_block_w  = ctrl_txstart_block;
        phy_txsync_header_w  = ctrl_txsync_header;
        phy_txcompliance_w   = ctrl_txcompliance;
        phy_rxpolarity_w     = ctrl_rxpolarity;
        phy_txmargin_w       = ctrl_txmargin;
        phy_txswing_w        = ctrl_txswing;
        phy_txdeemph_w       = ctrl_txdeemph;
        phy_txeq_coeff_w     = ctrl_txeq_coeff;
        phy_rxeq_ctrl_w      = ctrl_rxeq_ctrl;
        phy_rxeq_txpreset_w  = ctrl_rxeq_txpreset;
    end

    // 最小 bring-up heartbeat：LED[7] 慢闪（0.55 Hz @ 250 MHz pclk）。
    always_ff @(posedge phy_pclk or negedge pipe_rst_n) begin
        if (!pipe_rst_n) begin
            heartbeat_count <= '0;
        end else begin
            heartbeat_count <= heartbeat_count + 1'b1;
        end
    end

    k02_phy_event_recorder u_k02_event_recorder (
        .clk            (phy_pclk),
        .rst            (phy_phystatus_rst),
        .qpll1lock      (qpll1lock_record_in),
        .qpll1reset     (qpll1reset_record_in),
        .phy_rate       (phy_rate_cmd),
        .phy_phystatus  (phy_phystatus),
        .seq_state      (seq_state_w),
        .record_bus     (k02_event_record_w)
    );

    // LED 映射：phy_bringup_seq 进度 + heartbeat。
    assign led[0] = pipe_rst_n && !phy_phystatus_rst;
    assign led[1] = gen3_request_w;
    assign led[2] = (phy_ctrl_debug_state_w == 8'h04);
    assign led[3] = pipe_rst_n;
    assign led[4] = core_rst_n;
    assign led[5] = (seq_state_w == 4'd8);  // S_DONE
    assign led[6] = ctrl_as_cdr_hold_req;
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
