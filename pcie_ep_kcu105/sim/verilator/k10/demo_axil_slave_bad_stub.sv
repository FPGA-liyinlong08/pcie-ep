`timescale 1ns/1ps
`default_nettype none

// K10测试平台自检专用：签名错误、忽略WSTRB、非法地址错误返回OKAY。
module demo_axil_slave (
    input  wire clk, input wire rst_n,
    input  wire [31:0] s_axil_awaddr, input wire s_axil_awvalid,
    output wire s_axil_awready,
    input  wire [31:0] s_axil_wdata, input wire [3:0] s_axil_wstrb,
    input  wire s_axil_wvalid, output wire s_axil_wready,
    output reg [1:0] s_axil_bresp, output reg s_axil_bvalid,
    input  wire s_axil_bready,
    input  wire [31:0] s_axil_araddr, input wire s_axil_arvalid,
    output wire s_axil_arready,
    output reg [31:0] s_axil_rdata, output reg [1:0] s_axil_rresp,
    output reg s_axil_rvalid, input wire s_axil_rready,
    input wire link_up, input wire [1:0] link_speed,
    input wire [5:0] ltssm_state, input wire dll_active,
    input wire [3:0] dll_state,
    input wire [31:0] rx_bad_symbol_count,
    input wire [31:0] ltssm_retrain_count,
    input wire [31:0] dll_lcrc_error_count,
    input wire [31:0] dll_nak_count,
    input wire [31:0] dll_replay_count,
    input wire [31:0] dll_replay_timeout_count,
    input wire [31:0] tl_malformed_count,
    input wire [31:0] tl_unsupported_count,
    input wire [31:0] bar_ur_count,
    input wire [31:0] bar_ca_count,
    input wire [31:0] bar_axi_error_count,
    input wire [31:0] bar_payload_error_count
);
    reg [31:0] scratch;
    assign s_axil_awready = !s_axil_bvalid;
    assign s_axil_wready  = !s_axil_bvalid;
    assign s_axil_arready = !s_axil_rvalid;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scratch <= 0; s_axil_bvalid <= 0; s_axil_bresp <= 0;
            s_axil_rvalid <= 0; s_axil_rdata <= 0; s_axil_rresp <= 0;
        end else begin
            if (s_axil_bvalid && s_axil_bready) s_axil_bvalid <= 0;
            if (s_axil_awvalid && s_axil_awready &&
                s_axil_wvalid && s_axil_wready) begin
                if (s_axil_awaddr[11:0] == 12'h040)
                    scratch <= s_axil_wdata; // 故意忽略WSTRB
                s_axil_bvalid <= 1; s_axil_bresp <= 2'b00; // 故意无DECERR
            end
            if (s_axil_rvalid && s_axil_rready) s_axil_rvalid <= 0;
            if (s_axil_arvalid && s_axil_arready) begin
                s_axil_rvalid <= 1; s_axil_rresp <= 2'b00; // 故意无DECERR
                case (s_axil_araddr[11:0])
                    12'h000: s_axil_rdata <= 32'hdead_beef; // 故意错误签名
                    12'h040: s_axil_rdata <= scratch;
                    default: s_axil_rdata <= 0;
                endcase
            end
        end
    end
    wire _unused = &{1'b0, s_axil_wstrb, link_up, link_speed, ltssm_state,
        dll_active, dll_state, rx_bad_symbol_count, ltssm_retrain_count,
        dll_lcrc_error_count, dll_nak_count, dll_replay_count,
        dll_replay_timeout_count, tl_malformed_count, tl_unsupported_count,
        bar_ur_count, bar_ca_count, bar_axi_error_count, bar_payload_error_count};
endmodule

`default_nettype wire
