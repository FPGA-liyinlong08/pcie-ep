`timescale 1ns/1ps
`default_nettype none

// K08 Checker自检专用错误实现。
// 它保证请求能够及时完成，但故意返回错误ID、错误BAR尺寸，并忽略Byte Enable。
module pcie_cfg_space (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        hot_reset,
    input  wire        link_up,
    input  wire        link_training,
    input  wire        dll_active,
    input  wire [1:0]  link_speed,
    input  wire [2:0]  link_width,
    input  wire        cfg_req_valid,
    output wire        cfg_req_ready,
    input  wire        cfg_req_write,
    input  wire [9:0]  cfg_req_dw_addr,
    input  wire [3:0]  cfg_req_be,
    input  wire [31:0] cfg_req_wdata,
    input  wire [15:0] cfg_req_requester_id,
    input  wire [7:0]  cfg_req_tag,
    input  wire [15:0] cfg_req_target_bdf,
    output reg         cfg_rsp_valid,
    input  wire        cfg_rsp_ready,
    output reg  [2:0]  cfg_rsp_status,
    output reg  [31:0] cfg_rsp_rdata,
    output reg  [15:0] cfg_rsp_completer_id,
    output reg  [15:0] captured_bdf,
    output reg         bdf_valid,
    output wire [15:0] local_completer_id,
    output wire [31:0] bar0_base,
    output reg         bar0_probe_active,
    output wire        memory_space_enable,
    output wire        bus_master_enable,
    output wire [2:0]  max_payload_size,
    output wire [2:0]  max_read_request_size,
    output wire        rcb_128b,
    output wire        link_disable,
    output reg         retrain_link_pulse,
    output wire [1:0]  target_link_speed
);
    reg [15:0] command_reg;
    reg [31:0] bar0_reg;

    wire target_device_function_zero = (cfg_req_target_bdf[7:0] == 8'h00);
    wire target_matches = !bdf_valid || (cfg_req_target_bdf == captured_bdf);

    assign cfg_req_ready = rst_n && !hot_reset && !cfg_rsp_valid;
    assign local_completer_id = bdf_valid ? captured_bdf : 16'd0;
    assign bar0_base = bar0_reg & 32'hffff_f000;
    assign memory_space_enable = command_reg[1];
    assign bus_master_enable = command_reg[2];
    assign max_payload_size = 3'd0;
    assign max_read_request_size = 3'd2;
    assign rcb_128b = 1'b0;
    assign link_disable = 1'b0;
    assign target_link_speed = 2'd2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cfg_rsp_valid <= 1'b0;
            cfg_rsp_status <= 3'b000;
            cfg_rsp_rdata <= 32'd0;
            cfg_rsp_completer_id <= 16'd0;
            captured_bdf <= 16'd0;
            bdf_valid <= 1'b0;
            command_reg <= 16'd0;
            bar0_reg <= 32'd0;
            bar0_probe_active <= 1'b0;
            retrain_link_pulse <= 1'b0;
        end else begin
            retrain_link_pulse <= 1'b0;

            if (cfg_rsp_valid && cfg_rsp_ready)
                cfg_rsp_valid <= 1'b0;

            if (hot_reset) begin
                captured_bdf <= 16'd0;
                bdf_valid <= 1'b0;
                command_reg <= 16'd0;
                bar0_reg <= 32'd0;
                bar0_probe_active <= 1'b0;
                // 已经产生的响应故意仍遵守冻结契约，不在Hot Reset中撤销。
            end else if (cfg_req_valid && cfg_req_ready) begin
                cfg_rsp_valid <= 1'b1;
                cfg_rsp_rdata <= 32'd0;

                if (!target_device_function_zero || !target_matches) begin
                    cfg_rsp_status <= 3'b001;
                    cfg_rsp_completer_id <= bdf_valid ? captured_bdf : 16'd0;
                end else begin
                    cfg_rsp_status <= 3'b000;
                    cfg_rsp_completer_id <= bdf_valid ? captured_bdf : cfg_req_target_bdf;
                    if (!bdf_valid) begin
                        captured_bdf <= cfg_req_target_bdf;
                        bdf_valid <= 1'b1;
                    end

                    if (cfg_req_write) begin
                        if (cfg_req_dw_addr == 10'd1)
                            command_reg <= cfg_req_wdata[15:0]; // 错误：忽略cfg_req_be和RW mask
                        if (cfg_req_dw_addr == 10'd4) begin
                            bar0_reg <= cfg_req_wdata;          // 错误：保存低位且忽略BE
                            bar0_probe_active <= (cfg_req_wdata == 32'hffff_ffff);
                        end
                    end else begin
                        case (cfg_req_dw_addr)
                            10'd0: cfg_rsp_rdata <= 32'he001_1235; // 错误Vendor ID
                            10'd1: cfg_rsp_rdata <= 32'h0010_0000 |
                                                        {16'd0, command_reg};
                            10'd4: cfg_rsp_rdata <= bar0_reg;      // 错误Probe返回ffffffff
                            default: cfg_rsp_rdata <= 32'd0;
                        endcase
                    end
                end
            end
        end
    end

    // Checker自检只关心可观察协议结果；这些输入仍保留以证明端口完全一致。
    wire _unused = &{1'b0, link_up, link_training, dll_active, link_speed,
                     link_width, cfg_req_be, cfg_req_requester_id, cfg_req_tag};
endmodule

`default_nettype wire
