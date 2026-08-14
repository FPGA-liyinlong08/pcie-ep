// K12-C：Gen3 Equalization Phase 0～3独立控制器。
// 只负责命令保持、参数门禁和done/timeout，不解析TS或接入生产LTSSM。
module pcie_equalization_ctrl #(
    parameter integer EQ_TIMEOUT_CYCLES = 32
) (
    input wire clk, input wire rst_n,
    input wire eq_start, input wire [1:0] target_speed,
    input wire [3:0] tx_preset, input wire [5:0] tx_coeff,
    input wire tx_coeff_valid, input wire [3:0] rx_txpreset,
    input wire rx_preset_valid,
    input wire phy_txeq_done, input wire phy_rxeq_adapt_done,
    input wire phy_rxeq_done,
    output reg eq_start_accept, output reg eq_active,
    output reg eq_done, output reg eq_failed,
    output reg [2:0] phase,
    output reg [1:0] phy_txeq_ctrl,
    output reg [3:0] phy_txeq_preset,
    output reg [5:0] phy_txeq_coeff,
    output reg [1:0] phy_rxeq_ctrl,
    output reg [3:0] phy_rxeq_txpreset,
    output reg illegal_param_sticky,
    output reg phase_timeout_sticky
);
    localparam [2:0] ST_IDLE = 3'd0;
    localparam [2:0] ST_P0_TX = 3'd1;
    localparam [2:0] ST_P1_RX = 3'd2;
    localparam [2:0] ST_P2_TX = 3'd3;
    localparam [2:0] ST_P3_RX = 3'd4;
    localparam [2:0] ST_DONE = 3'd5;
    localparam [2:0] ST_FAIL = 3'd6;
    localparam integer TIMEOUT_LIMIT = (EQ_TIMEOUT_CYCLES < 1) ? 1 : EQ_TIMEOUT_CYCLES;

    reg [2:0] state;
    reg [3:0] saved_tx_preset, saved_rx_txpreset;
    reg [5:0] saved_tx_coeff;
    reg [31:0] timeout_count;
    wire params_legal = (target_speed == 2'b10) &&
                        (tx_preset <= 4'd9) &&
                        (rx_txpreset <= 4'd9) &&
                        tx_coeff_valid && rx_preset_valid;
    wire timeout_expired = timeout_count >= (TIMEOUT_LIMIT - 1);
    // PG239: RXEQ is complete only when both one-cycle indications are high.
    // A done pulse without adaptation must not advance the EQ phase.
    wire phy_rxeq_success = phy_rxeq_done && phy_rxeq_adapt_done;

    always @* begin
        eq_active = (state == ST_P0_TX) || (state == ST_P1_RX) ||
                    (state == ST_P2_TX) || (state == ST_P3_RX);
        eq_done = (state == ST_DONE);
        eq_failed = (state == ST_FAIL);
        phase = 3'd7;
        phy_txeq_ctrl = 2'b00;
        phy_txeq_preset = 4'd0;
        phy_txeq_coeff = 6'd0;
        phy_rxeq_ctrl = 2'b00;
        phy_rxeq_txpreset = 4'd0;
        case (state)
            ST_P0_TX: begin
                phase = 3'd0; phy_txeq_ctrl = 2'b01;
                phy_txeq_preset = saved_tx_preset; phy_txeq_coeff = saved_tx_coeff;
            end
            ST_P1_RX: begin
                // 01 is reserved by PG239; 10 requests RX equalization.
                phase = 3'd1; phy_rxeq_ctrl = 2'b10;
                phy_rxeq_txpreset = saved_rx_txpreset;
            end
            ST_P2_TX: begin
                phase = 3'd2; phy_txeq_ctrl = 2'b10;
                phy_txeq_preset = saved_tx_preset; phy_txeq_coeff = saved_tx_coeff;
            end
            ST_P3_RX: begin
                phase = 3'd3; phy_rxeq_ctrl = 2'b10;
                phy_rxeq_txpreset = saved_rx_txpreset;
            end
            ST_DONE: phase = 3'd4;
            ST_FAIL: phase = 3'd5;
            default: begin end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE; timeout_count <= 32'd0;
            saved_tx_preset <= 4'd0; saved_rx_txpreset <= 4'd0; saved_tx_coeff <= 6'd0;
            eq_start_accept <= 1'b0;
            illegal_param_sticky <= 1'b0; phase_timeout_sticky <= 1'b0;
        end else begin
            eq_start_accept <= 1'b0;
            case (state)
                ST_IDLE: begin
                    timeout_count <= 32'd0;
                    if (eq_start) begin
                        eq_start_accept <= 1'b1;
                        if (!params_legal) begin
                            illegal_param_sticky <= 1'b1;
                            state <= ST_FAIL;
                        end else begin
                            saved_tx_preset <= tx_preset;
                            saved_rx_txpreset <= rx_txpreset;
                            saved_tx_coeff <= tx_coeff;
                            state <= ST_P0_TX;
                            timeout_count <= 32'd0;
                        end
                    end
                end
                ST_P0_TX: begin
                    if (phy_txeq_done) begin
                        timeout_count <= 32'd0; state <= ST_P1_RX;
                    end else if (timeout_expired) begin
                        phase_timeout_sticky <= 1'b1; timeout_count <= 32'd0; state <= ST_FAIL;
                    end else timeout_count <= timeout_count + 1'b1;
                end
                ST_P1_RX: begin
                    if (phy_rxeq_success) begin
                        timeout_count <= 32'd0; state <= ST_P2_TX;
                    end else if (phy_rxeq_done) begin
                        // The PHY rejected this adaptation proposal.  Clear
                        // the command by entering the failure state instead
                        // of falsely reporting a completed phase.
                        phase_timeout_sticky <= 1'b1;
                        timeout_count <= 32'd0; state <= ST_FAIL;
                    end else if (timeout_expired) begin
                        phase_timeout_sticky <= 1'b1; timeout_count <= 32'd0; state <= ST_FAIL;
                    end else timeout_count <= timeout_count + 1'b1;
                end
                ST_P2_TX: begin
                    if (phy_txeq_done) begin
                        timeout_count <= 32'd0; state <= ST_P3_RX;
                    end else if (timeout_expired) begin
                        phase_timeout_sticky <= 1'b1; timeout_count <= 32'd0; state <= ST_FAIL;
                    end else timeout_count <= timeout_count + 1'b1;
                end
                ST_P3_RX: begin
                    if (phy_rxeq_success) begin
                        timeout_count <= 32'd0; state <= ST_DONE;
                    end else if (phy_rxeq_done) begin
                        phase_timeout_sticky <= 1'b1;
                        timeout_count <= 32'd0; state <= ST_FAIL;
                    end else if (timeout_expired) begin
                        phase_timeout_sticky <= 1'b1; timeout_count <= 32'd0; state <= ST_FAIL;
                    end else timeout_count <= timeout_count + 1'b1;
                end
                ST_DONE: begin
                    if (eq_start) state <= ST_IDLE;
                end
                ST_FAIL: begin
                    if (eq_start) state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
