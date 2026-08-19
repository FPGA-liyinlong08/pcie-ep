`timescale 1ns/1ps
`default_nettype none

// K02 专用上板顶层：执行一次 Receiver Detect，并可在成功后进入受控
// Gen3 PHY/GT 诊断模式；不包含任何 LTSSM、TS1/TS2 或链路训练功能。
// DIRECT_GEN3_MODE 用于独立验证 Gen3 steady-state：复位释放后直接请求
// P0/Gen3，不执行 Receiver Detect 和 Gen1->Gen3 dynamic rate transition。
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
    parameter integer DYNAMIC_SKIP_TXEQ_MODE        = 0
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

    logic       phy_txdetectrx;
    logic [1:0] phy_powerdown;
    logic [1:0] phy_rate_cmd;
    logic       phy_txelecidle_cmd;
    logic [1:0] phy_txeq_ctrl_cmd;
    logic [3:0] phy_txeq_preset_cmd;
    logic       as_cdr_hold_cmd;
    logic       as_mac_in_detect_cmd;
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
    endgenerate

    always_comb begin
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

    assign led[0] = pipe_rst_n && !phy_phystatus_rst;
    assign led[1] = receiver_present;
    assign led[2] = detect_done;
    assign led[3] = pipe_rst_n;
    assign led[4] = core_rst_n;
    assign led[5] = detect_timeout;
    assign led[6] = unexpected_status;
    assign led[7] = heartbeat_count[24];

    kcu105_pcie_phy_wrapper u_phy_wrapper (
        .pcie_refclk_p          (pcie_refclk_p),
        .pcie_refclk_n          (pcie_refclk_n),
        .pcie_perst_n           (pcie_perst_n),
        .pcie_rxp               (pcie_rxp),
        .pcie_rxn               (pcie_rxn),
        .pcie_txp               (pcie_txp),
        .pcie_txn               (pcie_txn),
        .phy_txdata             (32'b0),
        .phy_txdatak            (2'b0),
        .phy_txdata_valid       (1'b0),
        .phy_txstart_block      (1'b0),
        .phy_txsync_header      (2'b0),
        .phy_txdetectrx         (phy_txdetectrx),
        .phy_txelecidle         (phy_txelecidle_cmd),
        .phy_txcompliance       (1'b0),
        .phy_rxpolarity         (1'b0),
        .phy_powerdown          (phy_powerdown),
        .phy_rate               (phy_rate_cmd),
        .phy_txmargin           (3'b0),
        .phy_txswing            (1'b0),
        .phy_txdeemph           (1'b0),
        .phy_txeq_ctrl          (phy_txeq_ctrl_cmd),
        .phy_txeq_preset        (phy_txeq_preset_cmd),
        .phy_txeq_coeff         (6'b0),
        .phy_rxeq_ctrl          (2'b0),
        .phy_rxeq_txpreset      (4'b0),
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
