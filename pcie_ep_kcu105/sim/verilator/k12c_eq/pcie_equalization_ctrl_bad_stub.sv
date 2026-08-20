module pcie_equalization_ctrl #(
    parameter integer EQ_TIMEOUT_CYCLES = 4
) (
    input wire clk, input wire rst_n, input wire eq_start, input wire [1:0] target_speed,
    input wire [3:0] tx_preset, input wire [5:0] tx_coeff, input wire tx_coeff_valid,
    input wire [3:0] rx_txpreset, input wire rx_preset_valid,
    input wire phy_txeq_done, input wire phy_rxeq_adapt_done,
    input wire phy_rxeq_done,
    output reg eq_start_accept, output reg eq_active, output reg eq_done,
    output reg eq_failed, output reg [2:0] phase,
    output reg [1:0] phy_txeq_ctrl, output reg [3:0] phy_txeq_preset,
    output reg [5:0] phy_txeq_coeff, output reg [1:0] phy_rxeq_ctrl,
    output reg [3:0] phy_rxeq_txpreset, output reg illegal_param_sticky,
    output reg phase_timeout_sticky
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= 7; eq_start_accept <= 0;
        end else if (eq_start) begin
            eq_start_accept <= 1; phase <= 2;
        end else begin
            eq_start_accept <= 0; phase <= 2;
        end
    end
    always @* begin
        eq_active = 1; eq_done = 0; eq_failed = 0; phy_txeq_ctrl = 0; phy_txeq_preset = 0;
        phy_txeq_coeff = 0; phy_rxeq_ctrl = 0; phy_rxeq_txpreset = 0;
        illegal_param_sticky = 0; phase_timeout_sticky = 0;
    end
endmodule
