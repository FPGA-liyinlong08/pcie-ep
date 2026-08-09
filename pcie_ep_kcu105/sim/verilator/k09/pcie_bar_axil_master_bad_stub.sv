`timescale 1ns/1ps
`default_nettype none

// K09错误Stub：仅用于证明checker能检出地址、WSTRB和Posted Completion三项错误。
/* verilator lint_off DECLFILENAME */
module pcie_bar_axil_master (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         hot_reset,
    input  wire [31:0]  bar0_base,
    input  wire         bar0_probe_active,
    input  wire         memory_space_enable,
    input  wire [15:0]  local_completer_id,
    input  wire         mem_req_valid,
    output wire         mem_req_ready,
    input  wire         mem_req_write,
    input  wire         mem_req_64bit,
    input  wire         mem_req_poisoned,
    input  wire [63:0]  mem_req_address,
    input  wire [10:0]  mem_req_length_dw,
    input  wire [3:0]   mem_req_first_be,
    input  wire [3:0]   mem_req_last_be,
    input  wire [15:0]  mem_req_requester_id,
    input  wire [7:0]   mem_req_tag,
    input  wire [2:0]   mem_req_tc,
    input  wire [2:0]   mem_req_attr,
    input  wire         mem_w_valid,
    output wire         mem_w_ready,
    input  wire [127:0] mem_w_data,
    input  wire [15:0]  mem_w_keep,
    input  wire         mem_w_last,
    output reg          cpl_req_valid,
    input  wire         cpl_req_ready,
    output wire         cpl_req_has_data,
    output wire         cpl_req_poisoned,
    output wire [2:0]   cpl_req_status,
    output wire         cpl_req_bcm,
    output wire [12:0]  cpl_req_byte_count,
    output wire [15:0]  cpl_req_completer_id,
    output wire [15:0]  cpl_req_requester_id,
    output wire [7:0]   cpl_req_tag,
    output wire [6:0]   cpl_req_lower_address,
    output wire [5:0]   cpl_req_length_dw,
    output wire [2:0]   cpl_req_tc,
    output wire [2:0]   cpl_req_attr,
    output wire         cpl_data_valid,
    input  wire         cpl_data_ready,
    output wire [127:0] cpl_data,
    output wire [15:0]  cpl_data_keep,
    output wire         cpl_data_last,
    output reg  [31:0]  m_axil_awaddr,
    output reg          m_axil_awvalid,
    input  wire         m_axil_awready,
    output reg  [31:0]  m_axil_wdata,
    output reg  [3:0]   m_axil_wstrb,
    output reg          m_axil_wvalid,
    input  wire         m_axil_wready,
    input  wire [1:0]   m_axil_bresp,
    input  wire         m_axil_bvalid,
    output wire         m_axil_bready,
    output wire [31:0]  m_axil_araddr,
    output wire         m_axil_arvalid,
    input  wire         m_axil_arready,
    input  wire [31:0]  m_axil_rdata,
    input  wire [1:0]   m_axil_rresp,
    input  wire         m_axil_rvalid,
    output wire         m_axil_rready,
    output wire         busy,
    output reg          ur_pulse,
    output reg          ca_pulse,
    output reg          posted_drop_pulse,
    output reg          axi_error_pulse,
    output reg          payload_error_pulse,
    output reg  [31:0]  mem_request_count,
    output reg  [31:0]  mem_read_count,
    output reg  [31:0]  mem_write_count,
    output reg  [31:0]  axi_read_count,
    output reg  [31:0]  axi_write_count,
    output reg  [31:0]  sc_completion_count,
    output reg  [31:0]  ur_completion_count,
    output reg  [31:0]  ca_completion_count,
    output reg  [31:0]  posted_drop_count,
    output reg  [31:0]  poisoned_write_count,
    output reg  [31:0]  axi_read_error_count,
    output reg  [31:0]  axi_write_error_count,
    output reg  [31:0]  payload_protocol_error_count
);
    localparam [2:0] S_IDLE = 0, S_PAYLOAD = 1, S_AXI = 2,
                     S_B = 3, S_CPL = 4;
    reg [2:0] state;
    reg aw_done, w_done;

    assign mem_req_ready = rst_n && !hot_reset && state == S_IDLE;
    assign mem_w_ready = state == S_PAYLOAD;
    assign m_axil_bready = state == S_B;
    assign busy = state != S_IDLE;

    assign cpl_req_has_data = 1'b0;
    assign cpl_req_poisoned = 1'b0;
    assign cpl_req_status = 3'd0;
    assign cpl_req_bcm = 1'b0;
    assign cpl_req_byte_count = 13'd0;
    assign cpl_req_completer_id = local_completer_id;
    assign cpl_req_requester_id = 16'd0;
    assign cpl_req_tag = 8'd0;
    assign cpl_req_lower_address = 7'd0;
    assign cpl_req_length_dw = 6'd0;
    assign cpl_req_tc = 3'd0;
    assign cpl_req_attr = 3'd0;
    assign cpl_data_valid = 1'b0;
    assign cpl_data = 128'd0;
    assign cpl_data_keep = 16'd0;
    assign cpl_data_last = 1'b0;
    assign m_axil_araddr = 32'd0;
    assign m_axil_arvalid = 1'b0;
    assign m_axil_rready = 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            aw_done <= 1'b0;
            w_done <= 1'b0;
            cpl_req_valid <= 1'b0;
            m_axil_awaddr <= 32'd0;
            m_axil_awvalid <= 1'b0;
            m_axil_wdata <= 32'd0;
            m_axil_wstrb <= 4'd0;
            m_axil_wvalid <= 1'b0;
            ur_pulse <= 0; ca_pulse <= 0; posted_drop_pulse <= 0;
            axi_error_pulse <= 0; payload_error_pulse <= 0;
            mem_request_count <= 0; mem_read_count <= 0; mem_write_count <= 0;
            axi_read_count <= 0; axi_write_count <= 0; sc_completion_count <= 0;
            ur_completion_count <= 0; ca_completion_count <= 0;
            posted_drop_count <= 0; poisoned_write_count <= 0;
            axi_read_error_count <= 0; axi_write_error_count <= 0;
            payload_protocol_error_count <= 0;
        end else begin
            ur_pulse <= 0; ca_pulse <= 0; posted_drop_pulse <= 0;
            axi_error_pulse <= 0; payload_error_pulse <= 0;
            case (state)
                S_IDLE: if (mem_req_valid && mem_req_ready) begin
                    mem_request_count <= mem_request_count + 1'b1;
                    mem_write_count <= mem_write_count + 1'b1;
                    // Stub只支持checker的一DW Write，其余字段故意忽略。
                    m_axil_awaddr <= mem_req_address[31:0] - bar0_base + 32'd4;
                    state <= S_PAYLOAD;
                end
                S_PAYLOAD: if (mem_w_valid && mem_w_ready) begin
                    m_axil_wdata <= mem_w_data[31:0];
                    m_axil_wstrb <= 4'hf;
                    m_axil_awvalid <= 1'b1;
                    m_axil_wvalid <= 1'b1;
                    aw_done <= 1'b0;
                    w_done <= 1'b0;
                    state <= S_AXI;
                end
                S_AXI: begin
                    if (m_axil_awvalid && m_axil_awready) begin
                        m_axil_awvalid <= 1'b0;
                        aw_done <= 1'b1;
                    end
                    if (m_axil_wvalid && m_axil_wready) begin
                        m_axil_wvalid <= 1'b0;
                        w_done <= 1'b1;
                    end
                    if ((aw_done || (m_axil_awvalid && m_axil_awready)) &&
                        (w_done || (m_axil_wvalid && m_axil_wready)))
                        state <= S_B;
                end
                S_B: if (m_axil_bvalid && m_axil_bready) begin
                    axi_write_count <= axi_write_count + 1'b1;
                    cpl_req_valid <= 1'b1; // 故意违反Posted语义
                    state <= S_CPL;
                end
                S_CPL: if (cpl_req_valid && cpl_req_ready) begin
                    cpl_req_valid <= 1'b0;
                    sc_completion_count <= sc_completion_count + 1'b1;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

    wire unused_ok = &{1'b0, bar0_probe_active, memory_space_enable,
        mem_req_write, mem_req_64bit, mem_req_poisoned,
        mem_req_length_dw, mem_req_first_be, mem_req_last_be,
        mem_req_requester_id, mem_req_tag, mem_req_tc, mem_req_attr,
        mem_w_keep, mem_w_last, m_axil_bresp, cpl_data_ready,
        m_axil_arready, m_axil_rdata, m_axil_rresp, m_axil_rvalid};
endmodule

`default_nettype wire
