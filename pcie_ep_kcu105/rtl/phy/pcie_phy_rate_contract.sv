`timescale 1ns/1ps
`default_nettype none

//-----------------------------------------------------------------------------
// K13：PHY Rate-Change Contract
//
// 本模块是 K13 LTSSM/Recovery 控制器与 raw PHY 命令之间的唯一生产化握手边界。
// 语义来自 Xilinx Golden phy_ctrl.v 的 RDY 握手，但剥除：
//   1. phy_ctrl_pat_gen*      (TX pattern generator，与生产 MAC/OS 路径冲突)
//   2. ltssm_mimic_cnt        (替代 LTSSM，与真实 LTSSM 冲突)
//   3. 50 us / 10 us / 80 us  (example-design stimulus，不是生产时序)
//
// K13 已通过 K11 闭环 Receiver Detect / P1->P0 / PHY_POWERUP。
// 本模块接管 K11 之后的稳态 (active_rate=Gen1) 以及
// K13 控制器发起的任何语义层 retrain / speed-change 请求。
//
// 状态编码直接映射 Golden PHY_BUP_* 编号 (低 4 bit)：
//   RC_DISABLED       = 4'h0
//   RC_RDY2_STABLE    = 4'h4   // 稳态，可接受 request
//   RC_RELEASE_RDY3   = 4'h5   // 准备切速：force TXEI
//   RC_RDY0_GAP       = 4'h2   // 保守 10 us gap (Golden stimulus)
//   RC_APPLY_RDY1     = 4'h3   // 驱动 phy_rate_cmd=target
//   RC_WAIT_PHYSTATUS = 4'hA   // 等待 PHY_PHYSTATUS 上升沿
//   RC_COMMIT_RDY2    = 4'hB   // 提交 active_rate，rate_done pulse
//   RC_FALLBACK_WAIT  = 4'hC   // 预留：fast-fallback (Gen3->Gen1)
//   RC_ERROR          = 4'hF   // sticky 错误，仅 rst_n 清零
//
// 不变量 (ILA + SVA 共同证明)：
//   1. active_rate 只能在 RC_COMMIT_RDY2 -> RC_RDY2_STABLE 跳转时更新
//   2. phy_rate_cmd 可以在 transition 中提前到 target
//   3. rate_done 是单周期 pulse，仅在 active_rate 实际更新时产生
//   4. rate_failed 是 sticky，由 timeout 触发，rst_n 清零
//   5. raw phy_rate 的唯一 owner 是本模块
//-----------------------------------------------------------------------------
module pcie_phy_rate_contract #(
    parameter integer RATE_TIMEOUT_CYCLES     = 1_000_000,  // ~4 ms @ 250 MHz
    parameter integer GEN1_RELEASE_GAP_CYCLES = 2500         // 10 us @ 250 MHz
) (
    input  wire       clk,
    input  wire       rst_n,

    // K11 闭环后的 link_up 信号；=1 时本模块同步到 RC_RDY2_STABLE
    input  wire       link_ready,

    // 来自 K13 recovery_speed_ctrl 的语义层 rate-change 请求
    input  wire       rate_req_valid,
    input  wire [1:0] rate_req_target,
    output wire       rate_req_ready,

    // 来自 PHY (单 lane 单 bit)
    input  wire       phy_phystatus,

    // raw PHY 命令 (本模块是 phy_rate_cmd 唯一 owner)
    output wire [1:0] phy_rate_cmd,
    output wire       force_txelecidle,

    // 协议层使用的"活动速率"——只能在 completion 后改变
    output wire [1:0] active_rate,
    output wire       rate_busy,
    output wire       rate_done,
    output wire       rate_failed,

    // 调试
    output wire [3:0] dbg_state,
    output wire       phystatus_seen,
    output wire       timeout_sticky
);

    // ------------------------------------------------------------------
    // 速率编码 (与 pcie_phy_x1_gen3 PHY_RATE[2:0] 兼容)
    // ------------------------------------------------------------------
    /* verilator lint_off UNUSEDPARAM */
    localparam [1:0] RATE_GEN1     = 2'b00;
    localparam [1:0] RATE_GEN2     = 2'b01;
    localparam [1:0] RATE_GEN3     = 2'b10;
    localparam [1:0] RATE_RESERVED = 2'b11;   // 非法，触发 sticky error
    /* verilator lint_on UNUSEDPARAM */

    // ------------------------------------------------------------------
    // 状态编码——直接映射 Golden PHY_BUP_* 编号 (低 4 bit)
    // ------------------------------------------------------------------
    localparam [3:0] RC_DISABLED       = 4'h0;
    localparam [3:0] RC_RDY2_STABLE    = 4'h4;   // 稳态
    localparam [3:0] RC_RELEASE_RDY3   = 4'h5;   // force TXEI 准备切速
    localparam [3:0] RC_RDY0_GAP       = 4'h2;   // 保守 10 us gap
    localparam [3:0] RC_APPLY_RDY1     = 4'h3;   // 驱动 phy_rate_cmd
    localparam [3:0] RC_WAIT_PHYSTATUS = 4'hA;   // 等待 PHY_PHYSTATUS
    localparam [3:0] RC_COMMIT_RDY2    = 4'hB;   // 提交 active_rate
    localparam [3:0] RC_FALLBACK_WAIT  = 4'hC;   // 预留：fast-fallback
    localparam [3:0] RC_ERROR          = 4'hF;   // sticky 错误

    localparam integer TIMEOUT_LIMIT     = (RATE_TIMEOUT_CYCLES     < 1) ? 1 : RATE_TIMEOUT_CYCLES;
    localparam integer RELEASE_GAP_LIMIT = (GEN1_RELEASE_GAP_CYCLES < 1) ? 1 : GEN1_RELEASE_GAP_CYCLES;

    // ------------------------------------------------------------------
    // 状态 / 数据寄存器
    // ------------------------------------------------------------------
    reg [3:0]  state_r;
    reg [1:0]  active_rate_r;
    reg [1:0]  target_rate_r;
    reg [31:0] gap_count_r;
    reg [31:0] timeout_count_r;

    reg        phystatus_seen_r;          // 1-cycle 延迟线 (1)
    reg        phystatus_seen_prev_r;     // 1-cycle 延迟线 (0)
    reg        phystatus_seen_pulse_r;    // ILA debug pulse

    reg        rate_done_pulse_r;         // 1-cycle completion pulse
    reg        rate_failed_r;             // sticky 失败
    reg        timeout_sticky_r;          // sticky timeout

    // ------------------------------------------------------------------
    // 组合输出
    // ------------------------------------------------------------------
    reg [1:0] phy_rate_cmd_r;
    reg       force_txelecidle_r;

    wire legal_target     = (rate_req_target != RATE_RESERVED);
    wire same_rate        = (rate_req_target == active_rate_r);
    wire timeout_expired  = (timeout_count_r >= (TIMEOUT_LIMIT - 1));
    wire gap_expired      = (gap_count_r     >= (RELEASE_GAP_LIMIT - 1));
    wire phystatus_rising = phy_phystatus & ~phystatus_seen_prev_r;

    // 唯一接受 request 的状态：RDY2_STABLE + link_up
    assign rate_req_ready = (state_r == RC_RDY2_STABLE) && link_ready;

    // raw phy_rate_cmd：transition 期间 = target，稳态 = active_rate
    always @* begin
        case (state_r)
            RC_DISABLED,
            RC_RDY2_STABLE,
            RC_RELEASE_RDY3,
            RC_RDY0_GAP:      phy_rate_cmd_r = active_rate_r;
            RC_APPLY_RDY1,
            RC_WAIT_PHYSTATUS,
            RC_COMMIT_RDY2,
            RC_FALLBACK_WAIT: phy_rate_cmd_r = target_rate_r;
            RC_ERROR:         phy_rate_cmd_r = active_rate_r;
            default:          phy_rate_cmd_r = active_rate_r;
        endcase
    end
    assign phy_rate_cmd = phy_rate_cmd_r;

    // force_txelecidle：transition 期间强制 TXEI；稳态不强制
    // top-level 应 OR-arbitrate：
    //   phy_txelecidle = ltssm_phy_txelecidle
    //                  | rate_contract_force_txelecidle
    //                  | k13_eq_force_txelecidle
    always @* begin
        case (state_r)
            RC_DISABLED,
            RC_RDY2_STABLE:  force_txelecidle_r = 1'b0;
            RC_RELEASE_RDY3,
            RC_RDY0_GAP,
            RC_APPLY_RDY1,
            RC_WAIT_PHYSTATUS,
            RC_COMMIT_RDY2,
            RC_FALLBACK_WAIT,
            RC_ERROR:        force_txelecidle_r = 1'b1;
            default:         force_txelecidle_r = 1'b0;
        endcase
    end
    assign force_txelecidle = force_txelecidle_r;

    // rate_busy：transition 期间为 1
    assign rate_busy = (state_r != RC_DISABLED) &&
                       (state_r != RC_RDY2_STABLE) &&
                       (state_r != RC_ERROR);

    assign active_rate    = active_rate_r;
    assign rate_done      = rate_done_pulse_r;
    assign rate_failed    = rate_failed_r;
    assign dbg_state      = state_r;
    assign phystatus_seen = phystatus_seen_pulse_r | phystatus_rising;
    assign timeout_sticky = timeout_sticky_r;

    // ------------------------------------------------------------------
    // 同步时序 (异步复位)
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_r               <= RC_DISABLED;
            active_rate_r         <= RATE_GEN1;
            target_rate_r         <= RATE_GEN1;
            gap_count_r           <= 32'd0;
            timeout_count_r       <= 32'd0;
            phystatus_seen_r      <= 1'b0;
            phystatus_seen_prev_r <= 1'b0;
            phystatus_seen_pulse_r <= 1'b0;
            rate_done_pulse_r     <= 1'b0;
            rate_failed_r         <= 1'b0;
            timeout_sticky_r      <= 1'b0;
        end else begin
            // 默认 pulse 归零
            rate_done_pulse_r      <= 1'b0;
            phystatus_seen_pulse_r <= 1'b0;

            // phystatus 1-cycle 延迟线，用于上升沿检测
            phystatus_seen_prev_r <= phystatus_seen_r;
            phystatus_seen_r      <= phy_phystatus;

            case (state_r)
                // ------------------------------------------------------------
                // 初始 / link 失联：停在 Gen1，等待 K11 link_up
                // ------------------------------------------------------------
                RC_DISABLED: begin
                    timeout_count_r <= 32'd0;
                    gap_count_r     <= 32'd0;
                    if (link_ready) begin
                        state_r <= RC_RDY2_STABLE;
                    end
                end

                // ------------------------------------------------------------
                // 稳态：active_rate == phy_rate_cmd
                // 唯一接受 semantic request 的状态
                // ------------------------------------------------------------
                RC_RDY2_STABLE: begin
                    timeout_count_r <= 32'd0;
                    gap_count_r     <= 32'd0;

                    if (rate_req_valid && rate_req_ready && legal_target && !same_rate) begin
                        target_rate_r <= rate_req_target;
                        state_r       <= RC_RELEASE_RDY3;
                    end else if (rate_req_valid && !legal_target) begin
                        // 非法 target：sticky 错误
                        rate_failed_r <= 1'b1;
                        state_r       <= RC_ERROR;
                    end
                end

                // ------------------------------------------------------------
                // 切速准备：force TXEI，PHY 进入 all-rate-enable-off
                // 对应 Golden PHY_BUP_PHY_RDY3 进入语义
                // ------------------------------------------------------------
                RC_RELEASE_RDY3: begin
                    timeout_count_r <= 32'd0;
                    gap_count_r     <= 32'd0;
                    state_r         <= RC_RDY0_GAP;
                end

                // ------------------------------------------------------------
                // 保守 10 us gap (2500 pclk @ 250 MHz)
                // 仅因 KCU105 实板目前唯一有硬件闭环的 Golden stimulus
                // K13 实板闭环后可缩短
                // ------------------------------------------------------------
                RC_RDY0_GAP: begin
                    if (gap_expired) begin
                        gap_count_r <= 32'd0;
                        state_r     <= RC_APPLY_RDY1;
                    end else begin
                        gap_count_r <= gap_count_r + 1'b1;
                    end
                end

                // ------------------------------------------------------------
                // 驱动 phy_rate_cmd = target；active_rate 保持旧值
                // 1 cycle 后进入 WAIT_PHYSTATUS，便于 ILA 区分"已驱动"vs"已观测"
                // ------------------------------------------------------------
                RC_APPLY_RDY1: begin
                    timeout_count_r <= 32'd0;
                    state_r         <= RC_WAIT_PHYSTATUS;
                end

                // ------------------------------------------------------------
                // 等待 PHY_PHYSTATUS 上升沿
                // timeout -> RC_ERROR
                // ------------------------------------------------------------
                RC_WAIT_PHYSTATUS: begin
                    if (phystatus_rising) begin
                        phystatus_seen_pulse_r <= 1'b1;
                        state_r                <= RC_COMMIT_RDY2;
                    end else if (timeout_expired) begin
                        timeout_sticky_r <= 1'b1;
                        rate_failed_r    <= 1'b1;
                        state_r          <= RC_ERROR;
                    end else begin
                        timeout_count_r  <= timeout_count_r + 1'b1;
                    end
                end

                // ------------------------------------------------------------
                // 提交：active_rate <- target，rate_done 单周期 pulse
                // ------------------------------------------------------------
                RC_COMMIT_RDY2: begin
                    active_rate_r     <= target_rate_r;
                    rate_done_pulse_r <= 1'b1;
                    state_r           <= RC_RDY2_STABLE;
                end

                // ------------------------------------------------------------
                // 预留 fast-fallback (Gen3->Gen1 单状态路径，跳过 10us gap)
                // 第一版未启用；K13 实板闭环后由 K13 控制器通过专用 request
                // 触发。本状态保留 localparam 编号 4'hC 以匹配设计文档
                // ----------------------------------------------------------------
                RC_FALLBACK_WAIT: begin
                    if (phystatus_rising) begin
                        phystatus_seen_pulse_r <= 1'b1;
                        active_rate_r          <= target_rate_r;
                        rate_done_pulse_r      <= 1'b1;
                        state_r                <= RC_RDY2_STABLE;
                    end else if (timeout_expired) begin
                        timeout_sticky_r <= 1'b1;
                        rate_failed_r    <= 1'b1;
                        state_r          <= RC_ERROR;
                    end else begin
                        timeout_count_r  <= timeout_count_r + 1'b1;
                    end
                end

                // ------------------------------------------------------------
                // Sticky 错误：phy_rate_cmd 保持 active_rate，force TXEI=1
                // 仅 link_ready=0 (K11 重新进 link-up 流程) 才回到 DISABLED
                // ------------------------------------------------------------
                RC_ERROR: begin
                    if (!link_ready) begin
                        state_r <= RC_DISABLED;
                    end
                end

                default: begin
                    state_r <= RC_DISABLED;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
