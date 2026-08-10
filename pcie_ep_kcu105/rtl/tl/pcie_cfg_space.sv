`timescale 1ns/1ps
`default_nettype none

// K08：单Function Type-0 Endpoint配置空间。
//
// 本模块只实现配置寄存器、BDF捕获和一个响应寄存器，不解析或编码TLP。
// 配置读忽略Byte Enable；配置写先按Byte Enable合并，再应用寄存器写掩码。
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
    output reg  [31:0] bar0_base,
    output reg         bar0_probe_active,
    output wire        memory_space_enable,
    output wire        bus_master_enable,
    output wire [2:0]  max_payload_size,
    output wire [2:0]  max_read_request_size,
    output wire        rcb_128b,
    output wire        link_disable,
    output reg         retrain_link_pulse,
    output reg  [1:0]  target_link_speed
);
    localparam [2:0] CFG_STATUS_SC = 3'b000;
    localparam [2:0] CFG_STATUS_UR = 3'b001;

    localparam [15:0] COMMAND_RW_MASK        = 16'h0547;
    localparam [15:0] DEVICE_CONTROL_RW_MASK = 16'h701f;
    localparam [15:0] LINK_CONTROL_RW_MASK   = 16'h02d8;

    reg [15:0] command_reg;
    reg [15:0] device_control_reg;
    reg [15:0] link_control_reg;

    wire [31:0] cfg_be_mask = {
        {8{cfg_req_be[3]}}, {8{cfg_req_be[2]}},
        {8{cfg_req_be[1]}}, {8{cfg_req_be[0]}}
    };

    wire [15:0] command_merged =
        (command_reg & ~cfg_be_mask[15:0]) |
        (cfg_req_wdata[15:0] & cfg_be_mask[15:0]);
    wire [15:0] command_write_value = command_merged & COMMAND_RW_MASK;

    wire [15:0] device_control_merged =
        (device_control_reg & ~cfg_be_mask[15:0]) |
        (cfg_req_wdata[15:0] & cfg_be_mask[15:0]);
    wire [15:0] device_control_candidate =
        device_control_merged & DEVICE_CONTROL_RW_MASK;
    wire mrrs_candidate_valid =
        (device_control_candidate[14:12] <= 3'd5);
    wire [15:0] device_control_write_value = mrrs_candidate_valid ?
        device_control_candidate :
        ((device_control_candidate & 16'h8fff) |
         (device_control_reg & 16'h7000));

    wire [15:0] link_control_merged =
        (link_control_reg & ~cfg_be_mask[15:0]) |
        (cfg_req_wdata[15:0] & cfg_be_mask[15:0]);
    wire [15:0] link_control_write_value =
        link_control_merged & LINK_CONTROL_RW_MASK;

    wire [31:0] bar0_merged =
        (bar0_base & ~cfg_be_mask) | (cfg_req_wdata & cfg_be_mask);
    wire bar0_probe_write =
        (cfg_req_be == 4'hf) && (cfg_req_wdata == 32'hffff_ffff);

    wire [3:0] target_speed_wire_value =
        {2'b00, target_link_speed} + 4'd1;
    wire [3:0] target_speed_merged = cfg_req_be[0] ?
        cfg_req_wdata[3:0] : target_speed_wire_value;
    wire target_speed_candidate_valid =
        (target_speed_merged >= 4'd1) &&
        (target_speed_merged <= 4'd3);

    wire [3:0] current_link_speed =
        (link_speed == 2'd0) ? 4'd1 :
        (link_speed == 2'd1) ? 4'd2 :
        (link_speed == 2'd2) ? 4'd3 : 4'd1;
    wire [5:0] negotiated_link_width =
        (link_up && (link_width == 3'd1)) ? 6'd1 : 6'd0;
    wire [15:0] link_status_value = {
        2'b00,
        dll_active,
        1'b0,
        link_training,
        1'b0,
        negotiated_link_width,
        current_link_speed
    };

    reg [31:0] cfg_read_data;
    always @* begin
        cfg_read_data = 32'd0;
        case (cfg_req_dw_addr)
            10'd0:  cfg_read_data = 32'he001_1234;
            10'd1:  cfg_read_data = 32'h0010_0000 |
                                           {16'd0, command_reg};
            10'd2:  cfg_read_data = 32'hff00_0001;
            10'd3:  cfg_read_data = 32'h0000_0000;
            10'd4:  cfg_read_data = bar0_probe_active ?
                                           32'hffff_f000 : bar0_base;
            10'd11: cfg_read_data = 32'he001_1234;
            10'd13: cfg_read_data = 32'h0000_0040;
            10'd16: cfg_read_data = 32'h0002_0010;
            10'd17: cfg_read_data = 32'h0000_0000;
            10'd18: cfg_read_data = {16'd0, device_control_reg};
            10'd19: cfg_read_data = 32'h0010_0013;
            10'd20: cfg_read_data = {link_status_value, link_control_reg};
            10'd25: cfg_read_data = 32'h0000_0000;
            10'd26: cfg_read_data = 32'h0000_0000;
            10'd27: cfg_read_data = 32'h0000_000e;
            10'd28: cfg_read_data = {28'd0, target_speed_wire_value};
            default: cfg_read_data = 32'd0;
        endcase
    end

    // 单Function Endpoint只要求Function Number为0；Device Number由Root Port分配，
    // 不能假定为0。固件和OS可能先后为同一Device分配不同Bus Number，因此首次
    // 命中后只锁定Device Number，接受的每次请求都更新完整BDF。
    wire target_function_zero =
        (cfg_req_target_bdf[2:0] == 3'd0);
    wire target_device_matches =
        !bdf_valid ||
        (cfg_req_target_bdf[7:3] == captured_bdf[7:3]);
    wire request_hits_function =
        target_function_zero && target_device_matches;
    wire cfg_req_fire = cfg_req_valid && cfg_req_ready;

    assign cfg_req_ready = rst_n && !hot_reset && !cfg_rsp_valid;

    assign local_completer_id = bdf_valid ? captured_bdf : 16'd0;
    assign memory_space_enable = command_reg[1];
    assign bus_master_enable = command_reg[2];
    assign max_payload_size = 3'd0;
    assign max_read_request_size = device_control_reg[14:12];
    assign rcb_128b = link_control_reg[3];
    assign link_disable = link_control_reg[4];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cfg_rsp_valid <= 1'b0;
            cfg_rsp_status <= CFG_STATUS_SC;
            cfg_rsp_rdata <= 32'd0;
            cfg_rsp_completer_id <= 16'd0;

            captured_bdf <= 16'd0;
            bdf_valid <= 1'b0;
            command_reg <= 16'd0;
            bar0_base <= 32'd0;
            bar0_probe_active <= 1'b0;
            device_control_reg <= 16'h2000;
            link_control_reg <= 16'd0;
            retrain_link_pulse <= 1'b0;
            target_link_speed <= 2'd2;
        end else begin
            retrain_link_pulse <= 1'b0;

            // 一个既有响应即使与Hot Reset同拍也按正常握手完成。
            if (cfg_rsp_valid && cfg_rsp_ready)
                cfg_rsp_valid <= 1'b0;

            if (hot_reset) begin
                captured_bdf <= 16'd0;
                bdf_valid <= 1'b0;
                command_reg <= 16'd0;
                bar0_base <= 32'd0;
                bar0_probe_active <= 1'b0;
                device_control_reg <= 16'h2000;
                link_control_reg <= 16'd0;
                target_link_speed <= 2'd2;
                // 响应槽有意不复位：反压响应必须跨Hot Reset保持。
            end else if (cfg_req_fire) begin
                cfg_rsp_valid <= 1'b1;
                cfg_rsp_rdata <= 32'd0;

                if (!request_hits_function) begin
                    cfg_rsp_status <= CFG_STATUS_UR;
                    cfg_rsp_completer_id <= bdf_valid ?
                                                captured_bdf : 16'd0;
                end else begin
                    cfg_rsp_status <= CFG_STATUS_SC;
                    // Completion必须回显当前请求所使用的Bus Number；不能使用
                    // 上一次固件枚举阶段捕获的临时Bus Number。
                    cfg_rsp_completer_id <= cfg_req_target_bdf;

                    if (!bdf_valid ||
                        (cfg_req_target_bdf != captured_bdf)) begin
                        captured_bdf <= cfg_req_target_bdf;
                        bdf_valid <= 1'b1;
                    end

                    if (cfg_req_write) begin
                        case (cfg_req_dw_addr)
                            10'd1: command_reg <= command_write_value;

                            10'd4: begin
                                if (bar0_probe_write) begin
                                    bar0_probe_active <= 1'b1;
                                end else begin
                                    bar0_base <= bar0_merged &
                                                 32'hffff_f000;
                                    bar0_probe_active <= 1'b0;
                                end
                            end

                            10'd18: device_control_reg <=
                                                    device_control_write_value;

                            10'd20: begin
                                link_control_reg <= link_control_write_value;
                                retrain_link_pulse <= cfg_req_be[0] &&
                                                     cfg_req_wdata[5];
                            end

                            10'd28: begin
                                if (target_speed_candidate_valid)
                                    target_link_speed <=
                                        target_speed_merged[1:0] - 2'd1;
                            end

                            default: begin
                            end
                        endcase
                    end else begin
                        cfg_rsp_rdata <= cfg_read_data;
                    end
                end
            end
        end
    end

    // 请求者ID和Tag由K07保存用于Completion，K08只保留端口作为诊断契约。
    wire _unused = &{1'b0, cfg_req_requester_id, cfg_req_tag};
endmodule

`default_nettype wire
