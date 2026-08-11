`timescale 1ns/1ps
`default_nettype none

// 调试专用链路退出检测器。
// 只有在同一复位周期内曾经同时观察到Link Up和DLL Active后，
// 第一次离开该工作状态才产生一个脉冲；训练阶段的中间状态变化被忽略。
module pcie_link_loss_trigger (
    input  wire clk,
    input  wire rst_n,
    input  wire link_up,
    input  wire dll_active,
    output reg  operational_seen,
    output reg  link_loss_seen,
    output reg  link_loss_pulse
);
    wire operational_now = link_up && dll_active;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            operational_seen <= 1'b0;
            link_loss_seen   <= 1'b0;
            link_loss_pulse  <= 1'b0;
        end else begin
            link_loss_pulse <= 1'b0;
            if (operational_now)
                operational_seen <= 1'b1;
            if (operational_seen && !link_loss_seen && !operational_now) begin
                link_loss_seen  <= 1'b1;
                link_loss_pulse <= 1'b1;
            end
        end
    end
endmodule

`default_nettype wire
